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

package EBox::MailFilterUI::CGI::ViewMail;
use base qw(EBox::CGI::ClientRawBase  EBox::MailFilterUI::UserAccount);

use EBox::Gettext;
use EBox::MailFilterUI::DBEngine;
use EBox::MailFilter::Amavis::ExternalAccounts;
use EBox::MailFilter::Amavis::Quarantine;

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    my $dbengine = EBox::MailFilterUI::DBEngine->new();
    $self->{externalAccounts}  =
        EBox::MailFilter::Amavis::ExternalAccounts->new(dbengine => $dbengine);
    $self->{quarantine}  =
        EBox::MailFilter::Amavis::Quarantine->new(dbengine => $dbengine);
    $self->{template}= '/ajax/simpleModalDialog.mas';

    return $self;
}

sub _process
{
    my ($self) = @_;
    $self->_requireParam('key', 'mail key');
    my $key = $self->param('key');
    $self->_userAllowedMailKey($key);
    my $mailText = $self->{quarantine}->mailText($key);

    $self->{params} = [
        text => $mailText,
        buttonText => __('Close'),
   ];

}

1;
