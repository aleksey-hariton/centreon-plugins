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

package os::aix::local::mode::lvsync;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::misc;

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                  "hostname:s"        => { name => 'hostname' },
                                  "remote"            => { name => 'remote' },
                                  "ssh-option:s@"     => { name => 'ssh_option' },
                                  "ssh-path:s"        => { name => 'ssh_path' },
                                  "ssh-command:s"     => { name => 'ssh_command', default => 'ssh' },
                                  "timeout:s"         => { name => 'timeout', default => 30 },
                                  "sudo"              => { name => 'sudo' },
                                  "command:s"         => { name => 'command', default => 'lsvg' },
                                  "command-path:s"    => { name => 'command_path' },
                                  "command-options:s" => { name => 'command_options', default => '-o | lsvg -i -l 2>&1' },
                                  "filter-state:s"    => { name => 'filter_state', default => 'stale' },
                                  "filter-type:s"     => { name => 'filter_type', },
                                  "name:s"            => { name => 'name' },
                                  "regexp"              => { name => 'use_regexp' },
                                  "regexp-isensitive"   => { name => 'use_regexpi' },
                                });
    $self->{result} = {};
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);
}

sub manage_selection {
    my ($self, %options) = @_;

    my $stdout = centreon::plugins::misc::execute(output => $self->{output},
                                                  options => $self->{option_results},
                                                  sudo => $self->{option_results}->{sudo},
                                                  command => $self->{option_results}->{command},
                                                  command_path => $self->{option_results}->{command_path},
                                                  command_options => $self->{option_results}->{command_options});
    my @lines = split /\n/, $stdout;
    # Header not needed
    shift @lines;
    if (scalar @lines != 0){
        foreach my $line (@lines) {
            next if ($line !~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*)/);
            my ($lv, $type, $lp, $pp, $pv, $lvstate, $mount) = ($1, $2, $3, $4, $5, $6, $7);
            
            next if (defined($self->{option_results}->{filter_state}) && $self->{option_results}->{filter_state} ne '' &&
                     $lvstate !~ /$self->{option_results}->{filter_state}/);
            next if (defined($self->{option_results}->{filter_type}) && $self->{option_results}->{filter_type} ne '' &&
                     $type !~ /$self->{option_results}->{filter_type}/);

            next if (defined($self->{option_results}->{name}) && defined($self->{option_results}->{use_regexp}) && defined($self->{option_results}->{use_regexpi}) 
                && $mount !~ /$self->{option_results}->{name}/i);
            next if (defined($self->{option_results}->{name}) && defined($self->{option_results}->{use_regexp}) && !defined($self->{option_results}->{use_regexpi}) 
                && $mount !~ /$self->{option_results}->{name}/);
            next if (defined($self->{option_results}->{name}) && !defined($self->{option_results}->{use_regexp}) && !defined($self->{option_results}->{use_regexpi})
                && $mount ne $self->{option_results}->{name});
            
            $self->{result}->{$mount} = {lv => $lv, type => $type, lp => $lp, pp => $pp, pv => $pv, lvstate => $lvstate};
        }
    }
    
}

sub run {
    my ($self, %options) = @_;
    
    $self->manage_selection();
    
    if (scalar(keys %{$self->{result}}) <= 0) {
        $self->{output}->output_add(long_msg => 'All LV are ok.');
        $self->{output}->output_add(severity => 'OK',
                                    short_msg => 'All LV are ok.');
    } else {
        my $num_disk_check = 0;
        foreach my $name (sort(keys %{$self->{result}})) {
            $num_disk_check++;
            my $lv = $self->{result}->{$name}->{lv};
            my $type = $self->{result}->{$name}->{type};
            my $lp = $self->{result}->{$name}->{lp};
            my $pp = $self->{result}->{$name}->{pp};
            my $pv = $self->{result}->{$name}->{pv};
            my $lvstate = $self->{result}->{$name}->{lvstate};
            my $mount = $name;
            
            $self->{output}->output_add(long_msg => sprintf("LV '%s' MountPoint: '%s' State: '%s' [LP: %s  PP: %s  PV: %s]", $lv,
                                             $mount, $lvstate,
                                             $lp, $pp, $pv));
            $self->{output}->output_add(severity => 'critical',
                                        short_msg => sprintf("LV '%s' MountPoint: '%s' State: '%s' [LP: %s  PP: %s  PV: %s]", $lv,
                                            $mount, $lvstate,
                                            $lp, $pp, $pv));
        }
    
        if ($num_disk_check == 0) {
            $self->{output}->add_option_msg(short_msg => "No lv checked.");
            $self->{output}->option_exit();
        }
    }
    
    $self->{output}->display();
    $self->{output}->exit();
}

1;

__END__

=head1 MODE

Check vg mirroring.

=over 8

=item B<--remote>

Execute command remotely in 'ssh'.

=item B<--hostname>

Hostname to query (need --remote).

=item B<--ssh-option>

Specify multiple options like the user (example: --ssh-option='-l=centreon-engine' --ssh-option='-p=52').

=item B<--ssh-path>

Specify ssh command path (default: none)

=item B<--ssh-command>

Specify ssh command (default: 'ssh'). Useful to use 'plink'.

=item B<--timeout>

Timeout in seconds for the command (Default: 30).

=item B<--sudo>

Use 'sudo' to execute the command.

=item B<--command>

Command to get information (Default: 'lsvg').
Can be changed if you have output in a file.

=item B<--command-path>

Command path (Default: none).

=item B<--command-options>

Command options (Default: '-o | lsvg -i -l 2>&1').

=item B<--name>

Set the storage mount point (empty means 'check all storages')

=item B<--regexp>

Allows to use regexp to filter storage mount point (with option --name).

=item B<--regexp-isensitive>

Allows to use regexp non case-sensitive (with --regexp).

=item B<--filter-state>

Filter filesystem state (Default: stale) (regexp can be used).

=item B<--filter-type>

Filter filesystem type (regexp can be used).

=back

=cut
