################################################################################
# Copyright 2005-2013 MERETHIS
# Centreon is developped by : Julien Mathis and Romain Le Merlus under
# GPL Licence 2.0.
# 
# This program is free software; you can redistribute it and/or modify it under 
# the terms of the GNU General Public License as published by the Free Software 
# Foundation ; either version 2 of the License.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along with 
# this program; if not, see <http://www.gnu.org/licenses>.
# 
# Linking this program statically or dynamically with other modules is making a 
# combined work based on this program. Thus, the terms and conditions of the GNU 
# General Public License cover the whole combination.
# 
# As a special exception, the copyright holders of this program give MERETHIS 
# permission to link this program with independent modules to produce an executable, 
# regardless of the license terms of these independent modules, and to copy and 
# distribute the resulting executable under terms of MERETHIS choice, provided that 
# MERETHIS also meet, for each linked independent module, the terms  and conditions 
# of the license of that module. An independent module is a module which is not 
# derived from this program. If you modify this program, you may extend this 
# exception to your version of the program, but you are not obliged to do so. If you
# do not wish to do so, delete this exception statement from your version.
# 
# For more information : contact@centreon.com
# Authors : Stephane Duret <sduret@merethis.com>
#
####################################################################################

package network::checkpoint::mode::components::psu;

use strict;
use warnings;
 
my %map_status = (
    0 => 'OK',
);

sub check {
    my ($self) = @_;

    $self->{components}->{psus} = {name => 'psus', total => 0};
    $self->{output}->output_add(long_msg => "Checking power supplies");
    return if ($self->check_exclude(section => 'psus'));
    
    my $oid_voltageSensorEntry = '.1.3.6.1.4.1.2620.1.6.7.8.3.1';
    my $oid_voltageSensorStatus = '.1.3.6.1.4.1.2620.1.6.7.8.3.1.6';
    my $oid_voltageSensorValue = '.1.3.6.1.4.1.2620.1.6.7.8.3.1.3';
    my $oid_voltageSensorName = '.1.3.6.1.4.1.2620.1.6.7.8.3.1.2';
    
    my $result = $self->{snmp}->get_table(oid => $oid_voltageSensorEntry);
    return if (scalar(keys %$result) <= 0);

    foreach my $key ($self->{snmp}->oid_lex_sort(keys %$result)) {
        next if ($key !~ /^$oid_voltageSensorStatus\.(\d+)$/);
        my $instance = $1;
    
        next if ($self->check_exclude(section => 'psus', instance => $instance));
        my $psu_name = $result->{$oid_voltageSensorName . '.' . $instance}; 
        my $status = $result->{$oid_voltageSensorStatus . '.' . $instance};
     
        $self->{components}->{psus}->{total}++;
        $self->{output}->output_add(long_msg => sprintf("Power Supply '%s' status is %s.", 
                                                        $instance, $map_status{$status}));
        if ($status != 0) {
            $self->{output}->output_add(severity =>  'CRITICAL',
                                        short_msg => sprintf("Power Supply '%s' status is in an error state", 
                                                             $instance));
        }
        $self->{output}->perfdata_add(label => $psu_name , unit => 'V', value => sprintf("%d", $result->{$oid_voltageSensorValue . '.' . $instance})),

    }
}

1;
