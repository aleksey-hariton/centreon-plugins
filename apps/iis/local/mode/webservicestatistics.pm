################################################################################
# Copyright 2005-2014 MERETHIS
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

package apps::iis::local::mode::webservicestatistics;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use Win32::OLE;
use File::Spec;
use centreon::plugins::statefile;
use Digest::MD5 qw(md5_hex);

# 1 means by default
my $counters = {
    TotalAnonymousUsers => { selected => 1, unit => 'users/s'},
    TotalConnectionAttemptsAllInstances => { selected => 1, unit => 'con/s'},
    TotalGetRequests => { selected => 1, unit => 'requests/s'},
    TotalPostRequests => { selected => 1, unit => 'requests/s'},
    TotalBytesReceived => { selected => 0, unit => 'b/s'},
    TotalBytesSent => { selected => 0, unit => 'b/s'},
    TotalFilesReceived => { selected => 0, unit => 'files/s'},
    TotalFilesSent => { selected => 0, unit => 'files/s'}
};

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    foreach my $name (keys %$counters) {
        $options{options}->add_options(arguments =>
                                { 
                                  "warning-" . $name . ":s" => { name => 'warning_' . $name, },
                                  "critical-" . $name . ":s" => { name => 'critical_' . $name, },
                                });
    }
    $options{options}->add_options(arguments =>
                                { 
                                  "name:s"              => { name => 'name', },
                                  "regexp"              => { name => 'use_regexp' },
                                  "add-counters:s"      => { name => 'add_counters', },
                                });
    $self->{result} = {};
    $self->{new_datas} = {};
    $self->{wql_names} = '';
    $self->{statefile_value} = centreon::plugins::statefile->new(%options);
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    foreach my $name (keys %$counters) {
        if (($self->{perfdata}->threshold_validate(label => 'warning_' . $name, value => $self->{option_results}->{'warning_' . $name})) == 0) {
            $self->{output}->add_option_msg(short_msg => "Wrong warning-$name threshold '" . $self->{option_results}->{'warning_' . $name} . "'.");
            $self->{output}->option_exit();
        }
        if (($self->{perfdata}->threshold_validate(label => 'critical_' . $name, value => $self->{option_results}->{'critical_' . $name})) == 0) {
            $self->{output}->add_option_msg(short_msg => "Wrong critical-$name threshold '" . $self->{option_results}->{'critical_' . $name} . "'.");
            $self->{output}->option_exit();
        }
    }
    
    if (defined($self->{option_results}->{add_counters})) {
        foreach my $counter (split /,/, $self->{option_results}->{add_counters}) {
            next if ($counter eq '');
            if (!defined($counters->{$counter})) {
                $self->{output}->add_option_msg(short_msg => "Counter '$counter' unknown.");
                $self->{output}->option_exit();
            }
            $counters->{$counter}->{selected} = 1;
        }
    }
    
    $self->{wql_names} = 'Name';
    foreach my $name (keys %$counters) {
        $self->{wql_names} .= ', ' . $name;
    }
    
    $self->{statefile_value}->check_options(%options);
}

sub get_counters {
    my ($self, %options) = @_;
    
    my $wmi = Win32::OLE->GetObject('winmgmts:root\cimv2');
    if (!defined($wmi)) {
        $self->{output}->add_option_msg(short_msg => "Cant create server object:" . Win32::OLE->LastError());
        $self->{output}->option_exit();
    }
    my $query = 'Select ' . $self->{wql_names} . ' From Win32_PerfRawData_W3SVC_WebService';
    my $resultset = $wmi->ExecQuery($query);
    foreach my $obj (in $resultset) {
        my $site_name = $obj->{Name};
        
        if (defined($self->{option_results}->{name})) {
            next if (defined($self->{option_results}->{use_regexp}) && $site_name !~ /$self->{option_results}->{name}/);
            next if (!defined($self->{option_results}->{use_regexp}) && $site_name ne $self->{option_results}->{name});
        }
        
        $self->{result}->{$site_name} = {};
        foreach my $name (keys %$counters) {
            next if ($counters->{$name}->{selected} == 0);
            $self->{new_datas}->{$site_name . '_' . $name} = $obj->{$name};
            $self->{result}->{$site_name}->{$name} = { old_value => undef, current_value => $obj->{$name} };
        }
    }
 
    if (scalar(keys %{$self->{result}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No site found");
        $self->{output}->option_exit();
    }
}

sub check {
    my ($self, %options) = @_;
    
    $self->{statefile_value}->read(statefile => "iis_" . $self->{mode} . '_' . (defined($self->{option_results}->{name}) ? md5_hex($self->{option_results}->{name}) : md5_hex('all')));
    $self->{new_datas}->{last_timestamp} = time();
    my $old_timestamp;
    $old_timestamp = $self->{statefile_value}->get(name => 'last_timestamp');

    if (!defined($self->{option_results}->{name}) || defined($self->{option_results}->{use_regexp})) {
        $self->{output}->output_add(severity => 'OK',
                                    short_msg => 'All sites are ok');
    }
    
    foreach my $site_name (keys %{$self->{result}}) {
        
        next if (!defined($old_timestamp));
        
        my $time_delta = $self->{new_datas}->{last_timestamp} - $old_timestamp;
        if ($time_delta <= 0) {
            # At least one second. two fast calls ;)
            $time_delta = 1;
        }
        
        my $exits = [];
        my $str_display = "Site '" . $site_name . "': ";
        my $str_display_append = '';
        
        foreach my $name (keys %$counters) {
            next if ($counters->{$name}->{selected} == 0);
            $self->{result}->{$site_name}->{$name}->{old_value} = $self->{statefile_value}->get(name => $site_name . '_' . $name);
            if (!defined($self->{result}->{$site_name}->{$name}->{old_value})) {
                next;
            }
            if ($self->{result}->{$site_name}->{$name}->{current_value} < $self->{result}->{$site_name}->{$name}->{old_value}) {
                # We set 0. Has reboot.
                $self->{result}->{$site_name}->{$name}->{old_value} = 0;
            }
            
            my $value_per_seconds = ($self->{result}->{$site_name}->{$name}->{current_value} - $self->{result}->{$site_name}->{$name}->{old_value}) / $time_delta;
            push @$exits, $self->{perfdata}->threshold_check(value => $value_per_seconds, 
                                                             threshold => [ { label => 'critical_' . $name, exit_litteral => 'critical' }, 
                                                                            { label => 'warning_' . $name, exit_litteral => 'warning' } ]);
            my $value_display;
            if (defined($counters->{$name}->{unit}) && $counters->{$name}->{unit} eq 'b/s') {
                my ($trans_value, $trans_unit) = $self->{perfdata}->change_bytes(value => $value_per_seconds, network => 1);
                $value_display = $trans_value . ' ' . $trans_unit;
            } else {
                $value_display = sprintf("%.2f", $value_per_seconds);
            }
            $str_display .= $str_display_append . sprintf("%s %s /sec", $name, $value_display);
            $str_display_append = ', ';
            
            my $extra_label = '';
            $extra_label = '_' . $site_name if (!defined($self->{option_results}->{name}) || defined($self->{option_results}->{use_regexp}));
            $self->{output}->perfdata_add(label => $name . $extra_label, unit => $counters->{$name}->{unit},
                                          value => sprintf("%.2f", $value_per_seconds),
                                          warning => $self->{perfdata}->get_perfdata_for_output(label => 'warning_' . $name),
                                          critical => $self->{perfdata}->get_perfdata_for_output(label => 'critical_' . $name),
                                          min => 0);
        }
        
        # No values computing.
        next if (scalar(@$exits) == 0);
        
        my $exit = $self->{output}->get_most_critical(status => $exits);
        $self->{output}->output_add(long_msg => $str_display);
        if (!$self->{output}->is_status(value => $exit, compare => 'ok', litteral => 1) || (defined($self->{option_results}->{name}) && !defined($self->{option_results}->{use_regexp}))) {
            $self->{output}->output_add(severity => $exit,
                                        short_msg => $str_display);
        }
    }
    
    $self->{statefile_value}->write(data => $self->{new_datas});    
    if (!defined($old_timestamp)) {
        $self->{output}->output_add(severity => 'OK',
                                    short_msg => "Buffer creation...");
    }
}

sub run {
    my ($self, %options) = @_;

    $self->get_counters();
    $self->check();
   
    $self->{output}->display();
    $self->{output}->exit();
}

1;

__END__

=head1 MODE

Check IIS Site Statistics.
Available counters are: TotalAnonymousUsers, TotalConnectionAttemptsAllInstances, TotalGetRequests, TotalPostRequests, TotalBytesReceived, TotalBytesSent, TotalFilesReceived, TotalFilesSent

Counters are per seconds.

=over 8

=item B<--warning-COUNTER>

Warning threshold for counters.

=item B<--critical-COUNTER>

Critical threshold for counters.

=item B<--name>

Set the site name.

=item B<--regexp>

Allows to use regexp to filter site name (with option --name).

=item B<--add-counters>

Can add the following counters (not by default): TotalBytesReceived, TotalBytesSent, TotalFilesReceived, TotalFilesSent

Counters are separated by comas.

=back

=cut