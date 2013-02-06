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

package EBox::MailFilterUI;
use base qw(EBox::Module::Service);

use EBox::Config;
use EBox::Gettext;
use EBox::Global;
use EBox::Menu::Root;
use EBox::MailFilterUI::DBEngine;


use constant MFUI_USER  => 'zentyal-mfui';
use constant MFUI_GROUP => 'zentyal-mfui';
use constant MFUI_APACHE => EBox::Config->conf() . '/mfui-apache2.conf';
use constant MFUI_REDIS => '/var/lib/zentyal-mfui/conf/redis.conf';
use constant MFUI_REDIS_PASS => '/var/lib/zentyal-mfui/conf/redis.passwd';
use constant LDAP_CONF => '/var/lib/zentyal-mfui/ldap.conf';
use constant AMAVIS_HOME => '/var/lib/amavis';
use constant AMAVIS_SOCKET =>  AMAVIS_HOME .  '/amavisd.sock';
use constant CRON_FILE    => '/etc/cron.d/zentyal-mfui';

sub _create
{
    my $class = shift;
    my $self = $class->SUPER::_create(name => 'mfui',
                                      printableName => __('Mailfilter UI'),
                                      @_);

    bless($self, $class);
    return $self;
}

# Method: mfuiDir
#
#      Get the path to the mfui directory
#
# Returns:
#
#      String - the path to that directory
sub mfuiDir
{
    return EBox::Config->var() . 'lib/zentyal-mfui/';
}

# Method: usersessiondir
#
#      Get the path where user Web session identifiers are stored
#
# Returns:
#
#      String - the path to that directory
sub usersessiondir
{
    return mfuiDir() . 'sids/';
}

# Method: actions
#
#       Override EBox::Module::Service::actions
#
sub actions
{
    my ($self) = @_;

    my @actions;
    # XXX database creation?
    return \@actions;
}

# Method: initialSetup
#
# Overrides:
#   EBox::Module::Base::initialSetup
#
sub initialSetup
{
    my ($self, $version) = @_;

    # Create default rules and services
    # only if installing the first time
    unless ($version) {
        my $fw = EBox::Global->modInstance('firewall');

        my $port = 9999;
        $fw->addInternalService(
                'name'            => 'mailfilter_ui',
                'printableName'   => __('Mail Filter UI'),
                'description'     => __('Mail Filter UI Web Server'),
                'protocol'        => 'tcp',
                'sourcePort'      => 'any',
                'destinationPort' => $port,
                );
        $fw->saveConfigRecursive();

        $self->setPort($port);
    }

    # Execute initial-setup script
    $self->SUPER::initialSetup($version);
}

# Method: enableActions
#
#       Override EBox::Module::Service::enableActions
#
sub enableActions
{
    my ($self) = @_;

}

# Method: _daemons
#
#  Override <EBox::Module::Service::_daemons>
#
sub _daemons
{
    my ($self) = @_;
    my $authConfCompleteSub = sub {
        return defined $self->authSettings();
    };

    return [
        {
            'name' => 'zentyal.apache2-mfui',
            'precondition' => $authConfCompleteSub,
        },
        {
            'name' => 'zentyal.redis-mfui'
        }
    ];
}

sub authSettings
{
    my ($self) = @_;
    my $settings = $self->model('Settings');
    return $settings->authSettings();
}

# Method: _setConf
#
#  Override <EBox::Module::Service::_setConf>
#
sub _setConf
{
    my ($self) = @_;

    # We can assume the listening port is ready available
    my $settings = $self->model('Settings');

    # Overwrite the listening port conf file
    EBox::Module::Base::writeConfFileNoCheck(MFUI_APACHE,
        "mfui/mfui-apache2.conf.mas",
        [ port => $settings->portValue() ],
    );

    #  Write mfui corner redis file
    my $redisPort =  EBox::Config::configkey('redis_port_mfui');
    $self->{redis}->writeConfigFile(MFUI_USER, port => $redisPort);

    # Setup DB password file
    EBox::MailFilterUI::DBEngine->setupDBPassFile();

    # Setup LDAP auth conf file
    my $authSettings =   $self->authSettings();
    if (defined $authSettings) {
        EBox::Module::Base::writeConfFileNoCheck(LDAP_CONF,
                                                 "mfui/ldap.conf.mas",
                                                 [auth => $authSettings]
                                                );
    } else {
        EBox::Sudo::root("rm -f '" . LDAP_CONF . "'");
    }

    # Make release socket available to zentyal-mfui user
    EBox::Sudo::root(
        'setfacl -m u:' . MFUI_USER .':rx '. AMAVIS_HOME,
        'setfacl -m u:' . MFUI_USER .':rw '. AMAVIS_SOCKET
       );

    # Create cron file
    my $adminEmail = $settings->value('adminEmail');
    EBox::Module::Base::writeConfFileNoCheck(CRON_FILE,
                                             "mfui/zentyal-mfui.cron.mas",
                                             [fromAddr => $adminEmail]
                                                );
}

# Method: menu
#
#        Show the mfui menu entry
#
# Overrides:
#
#        <EBox::Module::menu>
#
sub menu
{
    my ($self, $root) = @_;

    my $folder = new EBox::Menu::Folder(
                                        'name' => 'MailFilter',
                                        'text' => __('Mail Filter'),
                                        'separator' => 'Communications',
                                        'order' =>  615   );

    my $item = new EBox::Menu::Item(text => __('Web UI'),
                                    url => 'MailFilter/MailFilterUI',
                                    order => 1000);
    $folder->add($item);
    $root->add($folder);
}

# Method: port
#
#       Returns the port the mfui webserver is on
#
sub port
{
    my ($self) = @_;
    my $settings = $self->model('Settings');
    return $settings->portValue();
}

# Method: setPort
#
#       Sets the port the mfui webserver is on
#
sub setPort
{
    my ($self, $port) = @_;

    my $settingsModel = $self->model('Settings');
    $settingsModel->set(port => $port);
}

sub certificates
{
    my ($self) = @_;

    return [
            {
             serviceId =>  q{Mail Filter UI web server},
             service =>  __(q{Mail Filter UI web server}),
             path    =>  '/var/lib/zentyal-mfui/ssl/ssl.pem',
             user => MFUI_USER,
             group => MFUI_GROUP,
             mode => '0400',
            },
           ];
}

1;
