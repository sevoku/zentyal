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
    my ($self, $includeAlias) = @_;

    my $user = $self->_user();
    my $sessionFile = EBox::MailFilterUI::usersessiondir() . $user;
    my $sessionKey = `cat '$sessionFile'`;
    if ($? != 0) {
       throw EBox::Exceptions::Internal('Error getting user session info');
    }
    EBox::info("skey $sessionKey");
    my ($sid, $key, $time, $mail, @aliases) = split '\t', $sessionKey;
#    EBox::info("mail $mail");
#    EBox::info("aliases @aliases");
    if (not $self->{externalAccounts}->_accountId($mail)) {
        # add user to table if not exists
        $self->{externalAccounts}->addAccount($mail, "$user, mail");
    }

    # add accounts for aliases
    foreach my $alias (@aliases) {
        if (not $self->{externalAccounts}->_accountId($alias)) {
            $self->{externalAccounts}->addAccount($alias, "$user, alias");
        }
    }

    if ($includeAlias) {
        return [$mail, @aliases];
    } else {
        return $mail;
    }

}

sub _userAllAddresses
{
    my ($self) = @_;
    return $self->_userEmail(1);
}

sub _rid
{
    my ($self) = @_;
    my ($rid) = @{ $self->_userAllRids() };
    return $rid;
}

sub _userAllRids
{
    my ($self) = @_;
    my @rids;
    my @accounts = @{ $self->_userAllAddresses() };
    foreach my $acc (@accounts) {
        push @rids, $self->{externalAccounts}->_accountId($acc);
    }
    return \@rids;
}

sub _user
{
    my $r = Apache2::RequestUtil->request;
    my $user = $r->user;
    return $user;
}

sub _userAllowedMailKey
{
    my ($self, $mailKey) = @_;
    my @rcptAddresses = @{ $self->{quarantine}->rcptAddresses($mailKey) };

    my $allowed = 0;
    if (@rcptAddresses) {
        my @userAddresses = @{ $self->_userAllAddresses() };
        foreach my $rcptAddr (@rcptAddresses) {
            # remove '+' portion.
            $rcptAddr =~ s/\+(.*?)@//;  # XXX check if amavis does this itself
            foreach my $userAddr (@userAddresses) {
                if ($rcptAddr eq $userAddr) {
                    $allowed = 1;
                }
            }
        }
    }

    if (not $allowed) {
        throw EBox::Exceptions::Internal('User has not permission to access requested message');
    }

}

1;
