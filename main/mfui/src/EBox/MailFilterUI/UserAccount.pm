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

package EBox::MailFilterUI::UserAccount;

use Apache2::RequestUtil;
use EBox::MailFilterUI;

# TODO get somehow the users email
sub _userEmail
{
    my ($self, $returnId) = @_;

    my $user = $self->_user();
    my $sessionFile = EBox::MailFilterUI::usersessiondir() . $user;
    my $sessionKey = `cat '$sessionFile'`;
    if ($? != 0) {
       throw EBox::Exceptions::Internal('Error getting user session info');
    }
    my ($sid, $key, $time, $mail) = split '\t', $sessionKey;
    if (not $self->{externalAccounts}->_accountId($mail)) {
        # add user to table if not exists
        $self->{externalAccounts}->addAccount($mail, $user);
    }

    return $mail;
}

sub _userAllAddresses
{
    my ($self) = @_;
    # TODO this hould resturn usermail and alias
    my $addr = $self->_userEmail();
    my @mockAlias = qw(alias1@mail1.com alias2@domainalias.com);
    return [$addr, @mockAlias];
}

sub _rid
{
    my ($self) = @_;
    my $rcpt = $self->_userEmail(); # _userMail will create records if rid not in db
    return $self->{externalAccounts}->_accountId($rcpt);
}

sub _user
{
    my $r = Apache2::RequestUtil->request;
    my $user = $r->user;
    return $user;
}


1;
