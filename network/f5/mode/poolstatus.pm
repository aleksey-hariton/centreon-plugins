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

package network::f5::mode::poolstatus;

use base qw(centreon::plugins::mode);

use strict;
use warnings;

my $oid_ltmPoolStatusName = '.1.3.6.1.4.1.3375.2.2.5.5.2.1.1';
my $oid_ltmPoolStatusAvailState = '.1.3.6.1.4.1.3375.2.2.5.5.2.1.2';
my $oid_ltmPoolStatusDetailReason = '.1.3.6.1.4.1.3375.2.2.5.5.2.1.5';

my $thresholds = {
    pool => [
        ['none', 'CRITICAL'],
        ['green', 'OK'],
        ['yellow', 'WARNING'],
        ['critical', 'CRITICAL'],
        ['blue', 'UNKNOWN'],
        ['gray', 'UNKNOWN'],
    ],
};

my %map_pool_status = (
    0 => 'none',
    1 => 'green',
    2 => 'yellow',
    3 => 'red',
    4 => 'blue', # unknown
    5 => 'gray',
);

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                  "name:s"                => { name => 'name' },
                                  "regexp"                => { name => 'use_regexp' },
                                  "threshold-overload:s@"   => { name => 'threshold_overload' },
                                });
    $self->{pool_id_selected} = [];

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    $self->{overload_th} = {};
    foreach my $val (@{$self->{option_results}->{threshold_overload}}) {
        if ($val !~ /^(.*?),(.*)$/) {
            $self->{output}->add_option_msg(short_msg => "Wrong treshold-overload option '" . $val . "'.");
            $self->{output}->option_exit();
        }
        my ($section, $status, $filter) = ('pool', $1, $2);
        if ($self->{output}->is_litteral_status(status => $status) == 0) {
            $self->{output}->add_option_msg(short_msg => "Wrong treshold-overload status '" . $val . "'.");
            $self->{output}->option_exit();
        }
        $self->{overload_th}->{$section} = [] if (!defined($self->{overload_th}->{$section}));
        push @{$self->{overload_th}->{$section}}, {filter => $filter, status => $status};
    }
}

sub manage_selection {
    my ($self, %options) = @_;

    foreach my $oid ($self->{snmp}->oid_lex_sort(keys %{$self->{results}->{$oid_ltmPoolStatusName}})) {
        next if ($oid !~ /^$oid_ltmPoolStatusName\.(.*)$/);
        my $instance = $1;
        
        # Get all without a name
        if (!defined($self->{option_results}->{name})) {
            push @{$self->{pool_id_selected}}, $instance; 
            next;
        }
        
        $self->{results}->{$oid_ltmPoolStatusName}->{$oid} = $self->{results}->{$oid_ltmPoolStatusName}->{$oid};
        if (!defined($self->{option_results}->{use_regexp}) && $self->{results}->{$oid_ltmPoolStatusName}->{$oid} eq $self->{option_results}->{name}) {
            push @{$self->{pool_id_selected}}, $instance; 
        }
        if (defined($self->{option_results}->{use_regexp}) && $self->{results}->{$oid_ltmPoolStatusName}->{$oid} =~ /$self->{option_results}->{name}/) {
            push @{$self->{pool_id_selected}}, $instance;
        }
    }

    if (scalar(@{$self->{pool_id_selected}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No pool found for name '" . $self->{option_results}->{name} . "'.");
        $self->{output}->option_exit();
    }
}

sub run {
    my ($self, %options) = @_;
    # $options{snmp} = snmp object
    $self->{snmp} = $options{snmp};
    
    $self->{results} = $self->{snmp}->get_multiple_table(oids => [
                                                            { oid => $oid_ltmPoolStatusName },
                                                            { oid => $oid_ltmPoolStatusAvailState },
                                                            { oid => $oid_ltmPoolStatusDetailReason },
                                                            ],
                                                         nothing_quit => 1);
    $self->manage_selection();
    
    my $multiple = 1;
    if (scalar(@{$self->{pool_id_selected}}) == 1) {
        $multiple = 0;
    }
    if ($multiple == 1) {
        $self->{output}->output_add(severity => 'OK',
                                    short_msg => 'All Pools are ok.');
    }
    
    foreach my $instance (sort @{$self->{pool_id_selected}}) {
        my $name = $self->{results}->{$oid_ltmPoolStatusName}->{$oid_ltmPoolStatusName . '.' . $instance};
        my $status = defined($self->{results}->{$oid_ltmPoolStatusAvailState}->{$oid_ltmPoolStatusAvailState . '.' . $instance}) ? 
                            $self->{results}->{$oid_ltmPoolStatusAvailState}->{$oid_ltmPoolStatusAvailState . '.' . $instance} : 4;
        my $reason = defined($self->{results}->{$oid_ltmPoolStatusDetailReason}->{$oid_ltmPoolStatusDetailReason . '.' . $instance}) ? 
                            $self->{results}->{$oid_ltmPoolStatusDetailReason}->{$oid_ltmPoolStatusDetailReason . '.' . $instance} : 'unknown';
        
        $self->{output}->output_add(long_msg => sprintf("Pool '%s' status is %s [reason = %s]",
                                                        $name, $map_pool_status{$status}, $reason));
        my $exit = $self->get_severity(section => 'pool', value => $map_pool_status{$status});
        if (!$self->{output}->is_status(value => $exit, compare => 'ok', litteral => 1) || $multiple == 0) {
            $self->{output}->output_add(severity => $exit,
                                        short_msg => sprintf("Pool '%s' status is %s",
                                                        $name, $map_pool_status{$status}));
        }
    }
    
    $self->{output}->display();
    $self->{output}->exit();
}

sub get_severity {
    my ($self, %options) = @_;
    my $status = 'UNKNOWN'; # default 
    
    if (defined($self->{overload_th}->{$options{section}})) {
        foreach (@{$self->{overload_th}->{$options{section}}}) {            
            if ($options{value} =~ /$_->{filter}/i) {
                $status = $_->{status};
                return $status;
            }
        }
    }
    foreach (@{$thresholds->{$options{section}}}) {           
        if ($options{value} =~ /$$_[0]/i) {
            $status = $$_[1];
            return $status;
        }
    }
    
    return $status;
}

1;

__END__

=head1 MODE

Check Pool status.

=over 8

=item B<--name>

Set the pool name.

=item B<--regexp>

Allows to use regexp to filter pool name (with option --name).

=item B<--threshold-overload>

Set to overload default threshold values (syntax: status,regexp)
It used before default thresholds (order stays).
Example: --threshold-overload='CRITICAL,^(?!(green)$)'

=back

=cut
    