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
use EBox::MailFilter::Amavis::DBEngine;

sub new
{
    my $class = shift @_;
    my $self = {};
    bless($self,$class);

    $self->{dbengine} =  EBox::MailFilter::Amavis::DBEngine->new();

    return $self;
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
}

sub removeWBList
{
    my ($self, $account, $email) = @_;
    my $accountId = $self->_accountMustExist($account);
    my $emailId = $self->_mailaddrId($email);
    if (not $emailId) {
        throw EBox::Exceptions::Internal("No id for mail address $email");
    }
    $self->{dbengine}->delete('wblist', ["rid=$accountId", "sid=$emailId"]);


    $self->_removeMailaddrIfNotUsed($emailId);
}

sub removeAccount
{
    my ($self, $account) = @_;
    my $id = $self->_accountMustExist($account);
    $self->{dbengine}->delete('users', ["email='$account'"]);

    $self->_cleanAccountWblist($id);

}

sub _cleanAccountWblist
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
