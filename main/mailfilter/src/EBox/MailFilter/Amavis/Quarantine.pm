# Copyright (C) 2013 Zentyal S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
use strict;
use warnings;

package EBox::MailFilter::Amavis::Quarantine;

use EBox::Exceptions::MissingArgument;
use EBox::Exceptions::DataNotFound;
use EBox::Exceptions::External;
use EBox::Gettext;

sub new
{
    my ($class, %params) = @_;

    my $self = {};
    bless($self,$class);

    if ($params{dbengine}) {
        $self->{dbengine} = $params{dbengine};
    } else {
        throw EBox::Exceptions::MissingArgument('dbengine');
    }

    return $self;
}

sub msgKeys
{
    my ($self, @addresses) = @_;
    my $sql = qq{select msgrcpt.mail_id, msgrcpt.rseqnum from msgrcpt, msgs, quarantine,maddr where quarantine.mail_id=msgrcpt.mail_id and msgrcpt.rid = maddr.id and msgrcpt.mail_id = msgs.mail_id and };
    # check release status
    $sql.= qq{(msgrcpt.rs = ' ') and (};
    my $addrWhere = join ' OR ', map {
        "(maddr.email = '$_' )"
    } @addresses;
    $sql .= $addrWhere . ') ORDER BY msgs.time_num DESC';

    my $res = $self->{dbengine}->query($sql);
    my @ids = map { $_->{mail_id} .':' . $_->{rseqnum} } @{ $res };
    return \@ids;
}

# TODO move to another class
sub msgRcptInfo
{
    my ($self, $mailKey) = @_;
    my ($mailId, $rseqnum) = split ':', $mailKey, 2;
    my $sql = qq{select * from msgrcpt WHERE mail_id='$mailId' AND rseqnum='$rseqnum'};
    my $res = $self->{dbengine}->query($sql);
    if (@{ $res }) {
        return $res->[0];
    }

    return undef;
}

# TODO move to another class
sub msgInfo
{
    my ($self, $mailKey) = @_;
    my ($mailId, $rseqnum) = split ':', $mailKey, 2;
    my $sql = qq{select msgs.*, maddr.email from msgs, maddr WHERE msgs.mail_id='$mailId' AND msgs.sid = maddr.id};
    my $res = $self->{dbengine}->query($sql);
    if (@{ $res }) {
        return $res->[0];
    }

    return undef;
}

# TODO move to another class
sub rcptAddresses
{
    my ($self, $mailKey) = @_;
    my ($mail_id, $rseqnum) = split ':', $mailKey, 2;
    my $sql = qq{SELECT maddr.email FROM msgrcpt, maddr WHERE msgrcpt.mail_id='$mail_id' AND };
    $sql   .= qq{msgrcpt.rseqnum=$rseqnum AND maddr.id=msgrcpt.rid};

    my $res = $self->{dbengine}->query($sql);
    my @addr = map {
        $_->{email}
    } @{$res};
    return \@addr;
}

# must have permission to use the amavis socket
sub release
{
    my ($self, $key, $addr) = @_;
    $addr  or throw EBox::Exceptions::MissingArgument('address');
    $key or throw EBox::Exceptions::MissingArgument('message key');
    my ($mailId, $rseqnum) = split ':', $key, 2;
    $self->_checkMsgIsQuarantined($mailId, $rseqnum);

    # get secret_id to do the release
    my $sql =  qq{select secret_id from msgs where mail_id='$mailId'};
    my $res = $self->{dbengine}->query($sql);
    if (not @{ $res }) {
        throw EBox::Exceptions::DataNotFound(
              data => __('Mail message'),
              value => $key,
           );
    }

    my $secretId = $res->[0]->{secret_id};
    my $releaseCmd = qq{/usr/sbin/amavisd-release '$mailId' '$secretId' '$addr' 2>&1};
    my @output = `$releaseCmd`;
    if ($? != 0) {
        EBox::error("$releaseCmd : @output");
        throw EBox::Exceptions::External(
             __('Release for quarantine faile')
           );
    }

    # update release info
    my $upSql = qq{UPDATE msgrcpt SET rs='R' where mail_id='$mailId' and rseqnum='$rseqnum'};
    $self->{dbengine}->do($upSql);
}

sub remove
{
    my ($self, $key) = @_;
    $key or throw EBox::Exceptions::MissingArgument('message key');
    my ($mailId, $rseqnum) = split ':', $key, 2;
    my $upSql = qq{UPDATE msgrcpt SET rs='D' where mail_id='$mailId' and rseqnum='$rseqnum'};
    $self->{dbengine}->do($upSql);
}

sub mailText
{
    my ($self, $key) = @_;
    $key or throw EBox::Exceptions::MissingArgument('message key');
    my ($mailId, $rseqnum) = split ':', $key, 2;
    $self->_checkMsgIsQuarantined($mailId, $rseqnum);

    my $sql = qq{SELECT mail_text FROM quarantine WHERE mail_id='$mailId'};
    my $res = $self->{dbengine}->query($sql);
    if (@{ $res }) {
        return $res->[0]->{mail_text};
    } else {
        return '';
    }
}

sub _checkMsgIsQuarantined
{
    my ($self, $mailId, $rseqnum) = @_;
    my $sql = qq{SELECT rs FROM msgrcpt where mail_id='$mailId' and rseqnum='$rseqnum'};
    my $res = $self->{dbengine}->query($sql);
    if (@{ $res }) {
        my $rs = $res->[0]->{rs};
        if ($rs eq 'R') {
            throw EBox::Exceptions::External(__('Message already released'));
        } elsif ($rs eq 'D') {
            throw EBox::Exceptions::External(__('Message was deleted'));
        }
    } else {
        throw EBox::Exceptions::DataNotFound(
              data => __('Mail message'),
              value => "$mailId:$rseqnum",
           );
    }
}

sub cleanByTime
{
    my ($self, $weeksTTL) = @_;
    ($weeksTTL < 1) and
        throw EBox::Exceptions::Internal("Week ttls mut be greater than one");
    ($weeksTTL > 50) and
        throw EBox::Exceptions::Internal("Week ttls too big");
    my $ourWeek = _iso8601_week(time());
    my $where;
    if ($ourWeek > $weeksTTL) {
        my $leTarget = $ourWeek - $weeksTTL;
        $where = "((partition_tag <= $leTarget) AND (partition_tag > $ourWeek))";
    } elsif ($ourWeek == $weeksTTL) {
        my $geTarget = $ourWeek + 1;
        $where = "partition_tag >= $geTarget";
    } else {
        my $gtTarget = $ourWeek;
        my $leTarget = 54 + $ourWeek - $weeksTTL; # 54 - max number of weeks
        $where = "(partition_tag > $gtTarget) AND (partition_tag <= $leTarget)";
    }

    my @partitionTagTables = qw(maddr msgs msgrcpt quarantine);
    foreach my $table (@partitionTagTables) {
        my $sqlDelete = qq{DELETE FROM $table WHERE $where};
        $self->{dbengine}->do($sqlDelete);
    }

}

sub cleanDeletedMessages
{
    my ($self) = @_;
    my $sql = qq{DELETE FROM msgrcpt where rs='D'};
    my $res = $self->{dbengine}->do($sql);
    # TODO delete for msgs table if needed?
}

sub _iso8601_week
{
  my($unix_time) = @_;
  my($y,$dowm0,$doy0) = (localtime($unix_time))[5,6,7];
  $y += 1900; $dowm0--; $dowm0=6 if $dowm0<0;  # normalize, Monday==0
  my($dow0101) = ($dowm0 - $doy0 + 53*7) % 7;  # dow Jan 1
  my($wn) = int(($doy0 + $dow0101) / 7);
  if ($dow0101 < 4) { $wn++ }
  if ($wn == 0) { $wn = iso8601_year_is_long($y-1) ? 53 : 52 }
  elsif ($wn == 53 && !iso8601_year_is_long($y)) { $wn = 1 }
  $wn;
}
1;
