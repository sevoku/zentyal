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
use base qw(EBox::Model::DataTable EBox::MailFilterUI::UserAccount);

use EBox::Gettext;
use EBox::Validate qw(:all);
use EBox::Types::Text;
use EBox::Types::Float;
use EBox::Types::Action;

use EBox::MailFilterUI::DBEngine;
use EBox::MailFilterUI::SanitizeHTML;
use EBox::MailFilter::Amavis::ExternalAccounts;
use EBox::MailFilter::Amavis::Quarantine;
use File::Temp qw/tempfile/;
use Time::Piece;

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

    return $self;
}

sub pageTitle
{
    return __('Quarantined mail');
}

sub _table
{
    my ($self) = @_;

    my @tableHead =
    (
        new EBox::Types::Text(
            'fieldName' => 'type',
            'printableName' => __('Type'),
            'unique' => 0,
            'editable' => 0,
            'filter' => \&_typeFilter,
        ),
        new EBox::Types::Text(
            'fieldName' => 'from',
            'printableName' => __('Sender'),
            'help' => __('Domain or email address'),
            'unique' => 0,
            'editable' => 0,
            'allowUnsafeChars' => 1,
        ),
        new EBox::Types::Text(
            'fieldName' => 'subject',
            'printableName' => __('Subject'),
            'unique' => 0,
            'editable' => 0,
            'allowUnsafeChars' => 1,
            'filter' => \&_htmlSubjectFilter,
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
            'filter' => \&_isoDateFilter,
        ),
    );

    my $customActions = [
        new EBox::Types::Action(
            model => $self,
            name => 'release',
            printableValue => __('Release from qurantine'),
            handler => \&_releaseAction,
            image => '/data/images/show.gif',
        ),
        new EBox::Types::Action(
            model => $self,
            name => 'remove',
            printableValue => __('Remove'),
            handler => \&_removeAction,
            image => '/data/images/delete.gif',
        ),
        new EBox::Types::Action(
            model => $self,
            name => 'show',
            printableValue => __('Show'),
            onclick => \&_showClicked,
            image => '/data/images/search.gif',
        ),
       ];

    my $dataTable =
    {
        'tableName' => 'Quarantine',
        'printableTableName' => __('Messages'),
        'modelDomain' => 'mfui',
        'defaultActions' => ['changeView' ],
        'tableDescription' => \@tableHead,
        'printableRowName' => __('message'),
        customActions      => $customActions,
        'help' => '', # FIXME
        'sortedBy' => 'date',
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
        type => $msgInfo->{content},
        from => $msgInfo->{email},
        subject => $msgInfo->{subject},
        spamScore => $rcptInfo->{bspam_level},
        date =>  $msgInfo->{time_iso},
       );
    $row->setId($id);
    return $row;
}

sub _isoDateFilter
{
    my ($dateElement) = @_;
    my $isoDate = $dateElement->value();
    my $date = Time::Piece->strptime($isoDate, '%Y%m%dT%H%M%SZ%z');
    return  $date->strftime('%a, %d %b %Y %T' ),
}

my %printableTypes = (
    V => __('Virus'),
    B => __('Banned file'),
    U => __('Unchecked'),
    S => __('Spam'),
    Y => __('Spam'),
    M => __('Bad MIME type'),
    H => __('Bad header'),
    O => __('Oversized'),
    T => __('MTA error'),
    C => __('Clean'),
);

sub _typeFilter
{
    my ($typeElement) = @_;
    my $value = $typeElement->value();
    defined $value or return '';
    return $printableTypes{$value};
}

sub _htmlSubjectFilter
{
    my ($element) = @_;
    my $subj = $element->value();
    defined $subj or return '';
    return EBox::MailFilterUI::SanitizeHTML::sanitizeSubject($subj);
}

sub _releaseAction
{
    my ($self, $type, $id) = @_;
    my $key = $self->_idToKey($id);
    $self->_userAllowedMailKey($key);

    my $addr = $self->_userEmail();

    $self->{quarantine}->release($id, $addr);
}

sub _removeAction
{
    my ($self, $type, $id) = @_;
    my $key = $self->_idToKey($id);
    $self->_userAllowedMailKey($key);
    $self->{quarantine}->remove($key);
}

sub _showClicked
{
    my ($self, $id) = @_;
    my $key = $self->_idToKey($id);
    my $title = __('Message contents');
    return "Modalbox.show('/ViewMail?key=$key', {title: '$title',  wideWindow : true,}); return false",
}

sub _idToKey
{
    my ($self, $id) = @_;
    my $key = $id;
    $key =~ s{\s}{\+}g;
    return $key;
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
