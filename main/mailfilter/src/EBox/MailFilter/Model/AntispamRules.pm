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

package EBox::MailFilter::Model::AntispamRules;
use base 'EBox::Model::DataForm';

use EBox::Config;
use EBox::Gettext;
use EBox::MailFilter::Types::AntispamThreshold;
use EBox::Exceptions::External;


# XX TODO:
#  disable autolearnSpamThreshold and autolearnHamThreshold when autolearn is off

sub new
{
    my $class = shift @_ ;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    return $self;
}

sub precondition
{
    return EBox::Config::boolean('show_antispam_rules');
}

# Method:  _table
#
# This method overrides <EBox::Model::DataTable::_table> to return
# a table model description.
#
#
sub _table
{
    my @tableDesc =
        (
         new EBox::MailFilter::Types::AntispamThreshold  (
             fieldName     => 'PYZOR_CHECK',
             printableName => __('Hash listed in Pyzor'),
             positive => 0,
             editable => 1,
             defaultValue => 5,
             help         => __(''),
                               ),
        );

      my $dataForm = {
                      tableName          => __PACKAGE__->nameFromClass(),
                      printableTableName => __('Antispam rules scores'),
                      modelDomain        => 'MailFilter',
                      defaultActions     => [ 'editField', 'changeView' ],
                      tableDescription   => \@tableDesc,

                     };



    return $dataForm;
}

sub scores
{
    my ($self) = @_;
    return {};
}

1;

