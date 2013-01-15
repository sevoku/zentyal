# Copyright (C) 2008-2012 eBox Technologies S.L.
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

package EBox::Mail::Model::RelayDomains;
use base 'EBox::Model::DataTable';

use EBox::Gettext;
use EBox::Exceptions::External;

use EBox::Types::DomainName;
use EBox::Types::Host;

sub _table
{
    my @tableHead =
        (
         new EBox::Types::DomainName(
             'fieldName' => 'domain',
             'printableName' => __('Domain'),
             'size' => '20',
             'editable' => 1,
             'unique' => 1,
         ),
         new EBox::Types::Host(
             fieldName => 'smtp',
             printableName => __('SMTP server to reach the domain'),
             editable => 1
         ),

    );

    my $dataTable =
    {
        'tableName' => 'RelayDomains',
        'printableTableName' => __('Relayed Domains'),
        'pageTitle'         => __('Relay Domains'),
        'defaultController' => '/Mail/Controller/RelayDomains',
        'defaultActions' => ['add', 'del', 'edit', 'changeView'],
        'tableDescription' => \@tableHead,
        'menuNamespace' => 'Mail/RelayDomains',
        'automaticRemove'  => 1,
        'help' => '',
        'printableRowName' => __('mail domain'),
        'sortedBy' => 'domain',
    };

    return $dataTable;
}

sub domains
{
    my ($self) = @_;
    my %domains;
    foreach my $id (@{ $self->ids() }) {
        my $row = $self->row($id);
        my $domain = $row->valueByName('domain');

        my $smtpElement = $row->elementByName('smtp');
        my $smtp = $smtpElement->value();
        if ($smtpElement->isIPAddress()) {
            $smtp = '[' . $smtp . ']'; # escape need for IP address in postfix
        }

        $domains{$domain} = $smtp;
    }

    return \%domains;
}

sub validateTypedRow
{
    my ($self, $action, $changedFields, $allFields) = @_;

    if (exists $changedFields->{domain}) {
        $self->_checkDomain($changedFields->{domain}->value());
    }

    if (exists $changedFields->{domain}) {
        $self->_checkSMTP($changedFields->{smtp});
    }
}


sub existsDomain
{
    my ($self, $domain) = @_;
    my $res = $self->findValue(domain => $domain);
    return defined $res;
}

sub _checkDomain
{
    my ($self, $domain) = @_;
    my $mailMod = $self->parentModule();
    my $mailname = $mailMod->mailname;
    if ($domain eq $mailname) {
            throw EBox::Exceptions::InvalidData(
                               data => __('Relayed mail domain'),
                               value => $domain,
                               advice =>
__('The relayed domain name cannot be equal to the mailname')
                                           );
    }

    my $vdomains = $mailMod->model('VDomains');
    if ($vdomains->existsVDomain($domain)) {
        throw EBox::Exceptions::External( __x(
            '{dom} is a hosted virtual domain. A relayed domain must be a external one.',
             dom => $domain
             )
         );
    } elsif ($vdomains->existsVDomainAlias($domain)) {
        throw EBox::Exceptions::External( __x(
            '{dom} is an alias for a hosted virtual domain. A relayed domain must be a external one.',
             dom => $domain
             )
         );
    }
}

sub _checkSMTP
{
    my ($self, $smtpElement) = @_;
    if ($smtpElement->isIPAddress()) {
        $self->_checkSMTPIP($smtpElement->value());
    } else {
        $self->_checkSMTPHost($smtpElement->value());
    }
}

sub _checkSMTPIP
{
    my ($self, $smtp) = @_;
    # XXX check if it is not a local IP
}

sub _checkSMTPHost
{
    my ($self, $smtp) = @_;
    # XXX check is nto a local name
    if ($smtp eq 'localhost') {
        throw EBox::Exceptions::External(
            __("You cannot set the local host as SMTP gateway")
           );
    }

    my $mailMod = $self->parentModule();
    my $mailname = $mailMod->mailname;
    if ($smtp eq $mailname) {
            throw EBox::Exceptions::InvalidData(
                               data => __('SMTP gateway'),
                               value => $smtp,
                               advice =>
__('The relayed domain gateway cannot be equal to the mailname')
                                           );
    }

    my $global = $self->global();
    if ($smtp eq $global->modInstance('sysinfo')->fqdn()) {
            throw EBox::Exceptions::InvalidData(
                               data => __('SMTP gateway'),
                               value => $smtp,
                               advice =>
__('The relayed domain gateway cannot be equal to the server name')
                                           );
    }
}

1;
