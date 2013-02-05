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

package EBox::MailFilterUI::SanitizeHTML;

use HTML::StripScripts::Parser;

my $subjectParser;
my $msgParser;

sub sanitizeSubject
{
    my ($subj) = @_;

    if (not $subjectParser) {
        $subjectParser = _newSubjectParser();
    }
    return $subjectParser->filter_html($subj);
}

sub sanitizeMsg
{
    my ($msg) = @_;

    if (not $msgParser) {
        $msgParser = _newMsgParser();
    }

    return $msgParser->filter_html($msg);

}

sub _newSubjectParser
{
    my $tableTags = _tableTags();
    return _newParser($tableTags);
}

sub _newMsgParser
{
    return _newParser();
}

sub _tableTags
{
    return [
        '<table>', '<th>', '<tr>', '<td>',
        '<caption>', '<col>', '<colgroup>',
        '<tbody>', '<thead>', '<tfoot>',
       ];
}


sub _newParser
{
    my ($banList) = @_;
    $banList or $banList = [];

    my $parser = HTML::StripScripts::Parser->new(

       {
           Context => 'Flow',       ## HTML::StripScripts configuration
           BanList => $banList,
           AllowSrc => 0,
           AllowHref => 0,
           AllowRelURL => 0,
           AllowMailto => 0
       },

       strict_comment => 1,             ## HTML::Parser options
       strict_names   => 1,
      );

    return $parser;
}

1;
