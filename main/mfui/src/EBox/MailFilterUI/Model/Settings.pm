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

package EBox::MailFilterUI::Model::Settings;
use base 'EBox::Model::DataForm';

use EBox::Gettext;
use EBox::Validate qw(:all);
use EBox::Types::Port;
use EBox::Types::Host;
use EBox::Types::Text;

use constant FW_SERVICE => 'mailfilter_ui';

sub new
{
    my $class = shift;
    my %parms = @_;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    return $self;
}

sub pageTitle
{
    return __('Mailfilter web UI for external accounts');
}


sub _table
{
    my @tableHead =
    (
        new EBox::Types::Port(
            'fieldName' => 'port',
            'printableName' => __('Web interface port'),
            'editable' => 1,
            'defaultValue' => 9999
        ),
        new EBox::Types::Host(
            'fieldName' => 'ldapHost',
            'printableName' => __('External LDAP host'),
            'editable' => 1,
        ),
        new EBox::Types::Port(
            'fieldName' => 'ldapPort',
            'printableName' => __('External LDAP port'),
            'editable' => 1,
            'defaultValue' => 389,
        ),
        new EBox::Types::Text(
            'fieldName' => 'usersDN',
            'printableName' => __('External LDAP users DN'),
            'editable' => 1,
            'allowUnsafeChars' => 1,
        ),
    );

    my $dataTable =
    {
        'tableName' => 'Settings',
        'printableTableName' => __('General configuration'),
        'modelDomain' => 'Mfui',
        'defaultActions' => ['add', 'del', 'editField', 'changeView' ],
        'tableDescription' => \@tableHead,
        'help' => __('This module enables an https webserver to allow external accounts to change their mail fitler settings'),
    };

    return $dataTable;
}

# Method: validateTypedRow
#
# Overrides:
#
#       <EBox::Model::DataTable::ValidateTypedRow>
#
# Exceptions:
#
#       <EBox::Exceptions::DataExists> - if the port number is already
#       in use by any ebox module
#
sub validateTypedRow
{

    my ($self, $action, $changedFields) = @_;

    if ( exists $changedFields->{port} and $action eq 'update') {
        $self->_changedPort($changedFields);
    }

    if (exists $changedFields->{ldapHost} ) {
        my $value = $changedFields->{ldapHost}->value();
        # XXX check iface addresses
        if (($value eq '127.0.0.1') or
            ($value eq 'localhost')
           ) {
            throw EBox::Exceptions::External(__('Must be an external LDAP server address, no a local address'));
        }
    }
}

sub _changedPort
{
    my ($self, $changedFields) = @_;

    my $portNumber = $changedFields->{port}->value();

    my $gl = EBox::Global->getInstance();
    my $firewall = $gl->modInstance('firewall');

    unless ( $firewall->availablePort('tcp', $portNumber) ) {
        throw EBox::Exceptions::DataExists(
            'data'  => __('listening port'),
            'value' => $portNumber,
           );
    }

    my $services = $gl->modInstance('services');
    if (not $services->serviceExists(name => FW_SERVICE)) {
        $services->addService('name' => FW_SERVICE,
                              'protocol' => 'tcp',
                              'sourcePort' => 'any',
                              'destinationPort' => $portNumber,
                              'internal' => 1,
                              'readOnly' => 1
                             );
        my $firewall = $gl->modInstance('firewall');
        $firewall->setInternalService(FW_SERVICE, 'accept');
    } else {
        $services->setService(
            'name'            => FW_SERVICE,
            'printableName'   => __('Mail Filter UI'),
            'description'     => __('Mail Filter UI Web Server'),
            'protocol'        => 'tcp',
            'sourcePort'      => 'any',
            'destinationPort' => $portNumber,
           );
    }

}

sub authSettings
{
    my ($self) = @_;
    my $row = $self->row();
    my $host = $row->valueByName('ldapHost');
    $host or return undef;
    my $port = $row->valueByName('ldapPort');
    $port or return undef;
    my $usersDN = $row->valueByName('usersDN');
    return {
        host => $host,
        port => $port,
        usersDN => $usersDN,
       }
}

1;
