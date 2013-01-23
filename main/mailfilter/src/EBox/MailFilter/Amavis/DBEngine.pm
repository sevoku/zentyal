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

package EBox::MailFilter::Amavis::DBEngine;
use base 'EBox::MyDBEngine';

my $DB_USER     = 'amavisdb';
my $DB_PWD_FILE = '/var/lib/zentyal/conf/amavis-db.passwd';

sub new
{
    my $class = shift,
    my $self = {};
    bless($self,$class);

    $self->_connect();
    # compatibilty  fudge:
    $self->{logs} = EBox::Global->getInstance(1)->modInstance('logs');

    return $self;
}

sub _dbname
{
    return 'amavis';
}

sub _dbuser
{
    return $DB_USER;
}

sub _dbpass
{
    my ($self) = @_;
    unless ($self->{dbpass}) {
        my ($pass) = @{EBox::Sudo::root("/bin/cat $DB_PWD_FILE")};
        $self->{dbpass} = $pass;
    }

    return $self->{dbpass};
}

sub credentials
{
    my ($self) = @_;
    return {
        database => $self->_dbname(),
        host =>'127.0.0.1',
        port => 3306,
        user =>  $self->_dbuser(),
        password => $self->_dbpass(),
       };
}

1;
