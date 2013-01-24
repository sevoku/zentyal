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

package EBox::MailFilter::Amavis::ExternalAccounts;

use EBox::Exceptions::MissingArgument;

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

#NT
sub WBListForRID
{
    my ($self, $rid) = @_;
    my $selectSQL = "SELECT sid FROM wblist WHERE rid=$rid";
    my $res = $self->{dbengine}->query($selectSQL);
    my @list = map {
        [$rid, $_->{sid}]
    } @{ $res };
    return \@list;
}

#NT
sub getWBList
{
    my ($self, $rid, $sid) = @_;
    my $selectSQL = "SELECT wb FROM wblist WHERE rid=$rid AND sid=$sid";
    my $res = $self->{dbengine}->query($selectSQL);
    if (@{ $res }) {
        return $res->[0]->{wb};
    }
    return undef;
}

sub setWBList
{
    my ($self, $account, $email, $type) = @_;
    if (($type ne 'W') and ($type ne 'B')) {
        throw EBox::Exceptions::Internal("Type argument must be 'W' or 'B' (was $type)");
    }

    my $rid = $self->_accountMustExist($account);
    my $sid = $self->_mailaddrId($email);
    if (not $sid) {
        # not exists, create it
        $sid = $self->_addMailaddr($email);
    }

    my $res = $self->{dbengine}->query(
                     "SELECT wb FROM wblist WHERE rid='$rid' AND sid='$sid'"
                    );
    if (@{ $res } > 0) {
        if ($res->[0]->{wb} ne $type) {
            # update rule
            $self->{dbengine}->update('wblist',
                                      { wb => "'$type'"  },
                                      ["rid='$rid' AND sid='$sid'"]
                                     );
        }
    } else {
        # add new rule
        $self->{dbengine}->unbufferedInsert('wblist', {
            rid => $rid,
            sid => $sid,
            wb => $type
           });
    }

    return [$rid => $sid];
}

# NY
sub removeWBList
{
    my ($self, $account, $email) = @_;
    my $accountId = $self->_accountMustExist($account);
    my $emailId = $self->_mailaddrId($email);
    if (not $emailId) {
        throw EBox::Exceptions::Internal("No id for mail address $email");
    }
    $self->removeWBListByID($accountId, $emailId);
}

# NT
sub removeWBListByID
{
    my ($self, $rid, $sid) = @_;
    $self->{dbengine}->delete('wblist', ["rid=$rid", "sid=$sid"]);
    $self->_removeMailaddrIfNotUsed($sid);
}

sub removeAccount
{
    my ($self, $account) = @_;
    my $id = $self->_accountMustExist($account);
    $self->{dbengine}->delete('users', ["email='$account'"]);

    $self->_cleanAccountWBList($id);
}

#NT
sub mailaddrById
{
    my ($self, $id) = @_;
    my $sql = "SELECT email FROM mailaddr WHERE id=$id LIMIT 1";
    my $res = $self->{dbengine}->query($sql);
    if (@{$res}) {
        return $res->[0]->{email}
    }
    return undef;
}

sub _cleanAccountWBList
{
    my ($self, $rid) = @_;
    my %suspectedSids;
    my $res = $self->{dbengine}->query("select sid from wblist where rid=$rid");
    if (not @{ $res }) {
        # no associated list, nothing to do
        return;
    }

    foreach my $row (@{ $res }) {
        $suspectedSids{$row->{sid}} = 1;
    }

    $self->{dbengine}->delete('wblist', ["rid=$rid"]);

    foreach my $sid (keys %suspectedSids) {
        $self->_removeMailaddrIfNotUsed($sid);
    }
}


sub addAccount
{
    my ($self, $account, $fullname) = @_;
    $fullname or $fullname = $account;

    if ($self->_accountId($account)) {
        throw EBox::Exceptions::Internal("Account already exists: $account");
    }

    $self->{dbengine}->unbufferedInsert('users', {
           email => $account,
           fullname => $fullname,
           local    => 'N', # only external accounts managed for now
       });
}

sub _accountId
{
    my ($self, $email) = @_;
    my $res = $self->{dbengine}->query("select id from users where email='$email'");
    if (@{ $res }) {
        return $res->[0]->{id};
    } else {
        return undef;
    }
}

sub _accountMustExist
{
    my ($self, $email) = @_;
    my $id = $self->_accountId($email);
    if (not $id) {
        throw EBox::Exceptions::Internal("Account does not exists: $email");
    }
    return $id;
}

sub _mailaddrId
{
    my ($self, $email) = @_;
    my $res = $self->{dbengine}->query("select id from mailaddr where email='$email'");
    if (@{$res} == 0) {
        return undef;
    } else {
        return $res->[0]->{'id'};
    }
}

sub _addMailaddr
{
    my ($self, $email) = @_;
    $self->{dbengine}->unbufferedInsert('mailaddr', { email => $email});

    return $self->_mailaddrId($email);
}

sub _removeMailaddrIfNotUsed
{
    my ($self, $id) = @_;
    my $res = $self->{dbengine}->query("select sid from wblist where sid=$id");
    if (@{ $res }) {
        # used, dont remove
        return;
    }

    $self->{dbengine}->delete('mailaddr', ["id='$id'"]);
}

1;
