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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
use strict;
use warnings;

package EBox::MailFilterUI::Model::Quarantine;
use base 'EBox::Model::DataTable';

use EBox::Gettext;
use EBox::Validate qw(:all);
use EBox::Types::Text;
use EBox::Types::Float;

use EBox::MailFilterUI::DBEngine;
use EBox::MailFilter::Amavis::Quarantine;
use EBox::MailFilterUI::Auth;

use Apache2::RequestUtil;
use File::Temp qw/tempfile/;

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    my $dbengine = EBox::MailFilterUI::DBEngine->new();
    $self->{quarantine}  =
        EBox::MailFilter::Amavis::Quarantine->new(dbengine => $dbengine);

    return $self;
}

sub pageTitle
{
    return __('Sender policy');
}

sub _table
{
    my @tableHead =
    (
        new EBox::Types::Text(
            'fieldName' => 'type',
            'printableName' => __('Type'),
            'unique' => 0,
            'editable' => 0,
        ),
        new EBox::Types::Text(
            'fieldName' => 'from',
            'printableName' => __('Sender'),
            'help' => __('Domain or email address'),
            'unique' => 0,
            'editable' => 0,
        ),
        new EBox::Types::Text(
            'fieldName' => 'subject',
            'printableName' => __('Subject'),
            'unique' => 0,
            'editable' => 0,
        ),
        new EBox::Types::Float(
            'fieldName' => 'spamScore',
            'printableName' => __('Spam score'),
            'unique' => 0,
            'editable' => 0,
        ),
        new EBox::Types::Text(
            'fieldName' => 'date',
            'printableName' => __('Date'),
            'unique' => 0,
            'editable' => 0,
        ),

    );
    my $dataTable =
    {
        'tableName' => 'Quarantine',
        'printableTableName' => __('Quarantined messages'),
        'modelDomain' => 'mfui',
        'defaultActions' => ['changeView' ],
        'tableDescription' => \@tableHead,
        'printableRowName' => __('message'),
        'help' => '', # FIXME
    };

    return $dataTable;
}



sub ids
{
    my ($self) = @_;
    my $email = $self->_userEmail();
    my $ids = $self->{quarantine}->msgKeys($email);
    return $ids;
}

sub row
{
    my ($self, $id) = @_;
    my $rcptInfo = $self->{quarantine}->msgRcptInfo($id);
    my $msgInfo  = $self->{quarantine}->msgInfo($id);


    my $row = $self->_setValueRow(
        type => $rcptInfo->{content},
        from => $msgInfo->{email},
        subject => $msgInfo->{subject},
        spamScore => $rcptInfo->{bspam_level},
        date => $msgInfo->{time_iso},
       );
    $row->setId($id);
    return $row;
}





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
    # TODO add accoutn here if does not exists

    return $mail;
}



sub _user
{
    my $r = Apache2::RequestUtil->request;
    my $user = $r->user;
    return $user;
}

# Method: _checkRowExist
#
#   Override <EBox::Model::DataTable::_checkRowExist> as DataTable try to check
#   if a row exists checking the existance of the conf directory
sub _checkRowExist
{
    my ($self, $id) = @_;
    return 1;
}

1;
