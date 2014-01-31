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
# Authors : Quentin Garnier <qgarnier@merethis.com>
#
####################################################################################

package network::fortinet::fortigate::common::mode::hardware;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::misc;

my %alarm_map = (
    0 => 'off',
    1 => 'on',
);

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                { 
                                });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);
}

sub run {
    my ($self, %options) = @_;
    # $options{snmp} = snmp object
    $self->{snmp} = $options{snmp};
    
    my $oid_sysDescr = '.1.3.6.1.2.1.1.1.0';
    my $oid_fgSysVersion = '.1.3.6.1.4.1.12356.101.4.1.1.0';
    my $oid_fgHwSensorCount = '.1.3.6.1.4.1.12356.101.4.3.1.0';
    my $result = $self->{snmp}->get_leef(oids => [$oid_sysDescr, $oid_fgSysVersion, $oid_fgHwSensorCount], nothing_quit => 1);
    
    $self->{output}->output_add(long_msg => sprintf("[System: %s] [Firmware: %s]", $result->{$oid_sysDescr}, $result->{$oid_fgSysVersion});
    if ($result->{$oid_fgHwSensorCount} == 0) {
        $self->{output}->add_option_msg(short_msg => "No hardware sensors available.");
        $self->{output}->option_exit();
    }
    
    $self->{output}->output_add(severity => 'OK', 
                                short_msg => "All sensors are ok.");
    
    my $oid_fgHwSensorEntry = '.1.3.6.1.4.1.12356.101.4.3.2.1';
    my $oid_fgHwSensorEntAlarmStatus = '.1.3.6.1.4.1.12356.101.4.3.2.1.4';
    my $oid_fgHwSensorEntName = '.1.3.6.1.4.1.12356.101.4.3.2.1.2';
    my $oid_fgHwSensorEntValue = '.1.3.6.1.4.1.12356.101.4.3.2.1.3';
    $result = $self->{snmp}->get_table(oid => $oid_fgHwSensorEntry);
    
    foreach my $key ($self->{snmp}->oid_lex_sort(keys %$result)) {
        next if ($key !~ /^$oid_fgHwSensorEntName\.(\d+)/);
        my $index = $1;
        my $name = centreon::plugins::misc::trim($result->{$oid_fgHwSensorEntName . '.' . $index});
        my $value = $result->{$oid_fgHwSensorEntValue . '.' . $index};
        my $alarm_status = centreon::plugins::misc::trim($result->{$oid_fgHwSensorEntAlarmStatus . '.' . $index});
        
        $self->{output}->output_add(long_msg => sprintf("Sensor %s alarm status is %s [value: %s]", 
                                                        $name, $alarm_map{$alarm_status}, $value));
        if ($alarm_map{$alarm_status} eq 'on') {
            $self->{output}->output_add(severity => 'CRITICAL',
                                        short_msg => sprintf("Sensor %s alarm status is %s [value: %s]", 
                                                             $name, $alarm_map{$alarm_status}, $value));
        }
    }
    
    $self->{output}->display();
    $self->{output}->exit();
}

1;

__END__

=head1 MODE

Check fortigate hardware sensors (FORTINET-FORTIGATE-MIB).

=over 8

=back

=cut
