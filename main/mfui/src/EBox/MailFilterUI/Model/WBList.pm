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

package EBox::MailFilterUI::Model::WBList;
use base 'EBox::Model::DataTable';

use EBox::Gettext;
use EBox::Validate qw(:all);
use EBox::MailFilter::Types::AmavisSender;
use EBox::::Types::Select;

use EBox::MailFilterUI::DBEngine;
use EBox::MailFilter::Amavis::ExternalAccounts;

use Apache2::RequestUtil;
use File::Temp qw/tempfile/;

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    my $dbengine = EBox::MailFilterUI::DBEngine->new();
    $self->{externalAccounts}  =
        EBox::MailFilter::Amavis::ExternalAccounts->new(dbengine => $dbengine);

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
        new EBox::MailFilter::Types::AmavisSender(
            'fieldName' => 'sender',
            'printableName' => __('Sender'),
            'help' => __('Domain or email address'),
            'unique' => 1,
            'editable' => 1
        ),
     new EBox::Types::Select(
         fieldName     => 'policy',
         printableName => __('Policy'),
         populate      => \&_populatePolicy,
         editable      => 1,
        ),
    );
    my $dataTable =
    {
        'tableName' => 'WBList',
        'printableTableName' => __('Spam policy by sender'),
        'modelDomain' => 'mfui',
        'defaultActions' => ['add', 'del', 'editField', 'changeView' ],
        'tableDescription' => \@tableHead,
        'printableRowName' => __('sender policy'),
        'help' => '', # FIXME
    };

    return $dataTable;
}

sub _populatePolicy
{
    return [
            { value => 'W', printableValue => __('whitelist') },
            { value => 'B', printableValue => __('blacklist') },
           ]
}

sub ids
{
    my ($self) = @_;
    my $rid = $self->_rid();
    my $list = $self->{externalAccounts}->WBListForRID($rid);
    my @ids = map {
        ($_->[0] . 'S' . $_->[1])
    } @{ $list };
    use EBox;
    EBox::debug("IDS @ids");
    return \@ids;
}

sub row
{
    my ($self, $id) = @_;
    my ($rid, $sid) = split 'S', $id, 2;
    EBox::debug("$id -> $rid, $sid");
    my $wb = $self->{externalAccounts}->getWBList($rid, $sid);
    if (not $wb) {
        # row does nto exists
        return undef;
    }
    my $sender = $self->{externalAccounts}->mailaddrById($sid);

    my $row = $self->_setValueRow(sender => $sender, policy => $wb);
    $row->setId($id);
    return $row;
}

sub addTypedRow
{
    my ($self, $paramsRef, %optParams) = @_;
    my $sender = $paramsRef->{sender}->value();
    my $policy = $paramsRef->{policy}->value();
    my $rcpt = $self->_userEmail();
    my $ret = $self->{externalAccounts}->setWBList($rcpt, $sender, $policy);
    $self->setMessage(__('Sender policy added') );
    return $ret->[0] . 'S' . $ret->[1];
}

sub setTypedRow
{
    my ($self, $id, $paramsRef, %optParams) = @_;
    my $sender = $paramsRef->{sender}->value();
    my $policy = $paramsRef->{policy}->value();
    my $rcpt = $self->_userEmail();
    $self->{externalAccounts}->setWBList($rcpt, $sender, $policy);
    # return id?
    $self->setMessage(__('Sender policy modified') );
}

sub removeRow
{
    my ($self, $id, $force) = @_;

    unless (defined($id)) {
        throw EBox::Exceptions::MissingArgument(
                "Missing row identifier to remove")
    }

    my $row = $self->row($id);
    if (not defined $row) {
        throw EBox::Exceptions::Internal(
           "Row with id $id does not exist, so it cannot be removed"
          );
    }

    my ($rid, $sid) = split 'S', $id, 2;
    $self->{externalAccounts}->removeBWListByID($rid, $sid);
    $self->setMessage(__('Sender policy removed') );
}

# TODO get somehow the users email
sub _userEmail
{
    my ($self, $returnId) = @_;
    my $user = $self->_user();

    # DDD
    my $email =  $user . '@pipo.com';
    if (not $self->{externalAccounts}->_accountId($email)) {
        # add user to table if not exists
        $self->{externalAccounts}->addAccount($email, $user);
    }

    return $email;
}

sub _rid
{
    my ($self) = @_;
    my $rcpt = $self->_userMail(); # _userMail will create records if rid not in db
    return $self->{externalAccounts}->_accountId($rcpt);
}

sub _user
{
    my $r = Apache2::RequestUtil->request;
    my $user = $r->user;
    return $user;
}

1;
