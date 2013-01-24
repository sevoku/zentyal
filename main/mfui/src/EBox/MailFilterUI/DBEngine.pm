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

package EBox::MailFilterUI::DBEngine;
use base 'EBox::MailFilter::Amavis::DBEngine';

use EBox::Sudo;

sub _dbpassFile
{
    my $user = _user();
    my ($name,$passwd,$uid,$gid,$quota,$comment,$gcos,$dir,$shell,$expire) = getpwnam($user);
    return $dir . '.amavis-db.passwd';
}

sub _user
{
    return 'zentyal-mfui';
}

sub _group
{
    return 'zentyal-mfui';
}

sub _dbpass
{
    my ($self) = @_;
    unless ($self->{dbpass}) {
        my $cmd = "/bin/cat '" . $self->_dbpassFile() . "'";
        my $pass = `$cmd`;
        if ($? != 0) {
            throw EBox::Exceptions::Internal('Error getting DB password');
        }
        $self->{dbpass} = $pass;
    }

    return $self->{dbpass};
}


# give to zentyal-mfui a copy of this file
sub setupDBPassFile
{
    my ($class) = @_;
    my $user = $class->_user();
    my $group = $class->_group();
    my $orig = $class->SUPER::_dbpassFile();
    my $dest = $class->_dbpassFile();
    EBox::Sudo::root("rm -rf '$dest'",
                     "cp '$orig' '$dest'",
                     "chmod 0600 '$dest'",
                     "chown '$user'.'$group' '$dest'",
                    );

}


1;
