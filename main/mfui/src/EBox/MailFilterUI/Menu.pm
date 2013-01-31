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

package EBox::MailFilterUI::Menu;

use EBox::Config;
use EBox::Global;
use EBox::Menu;
use EBox::Menu::Root;
use EBox::Menu::Item;
use EBox::Gettext;
use Storable qw(store);

sub menu
{
    my ($current) = @_;

    my $global = EBox::Global->getInstance();

    my $root = new EBox::Menu::Root('current' => $current);
    $root->add(
                 new EBox::Menu::Item(
                                      'url' => '"mfui/View/WBList',
                                      'text' => __('Policy by sender')
                 )
    );

    return $root;
}

sub cacheFile
{
    return EBox::Config::var . 'lib/zentyal-mfui/menucache';
}

sub regenCache
{
    my $keywords = {};

    my $root = menu();

    EBox::Menu::getKeywords($keywords, $root);

    my $file = cacheFile();
    store($keywords, $file);
}

1;
