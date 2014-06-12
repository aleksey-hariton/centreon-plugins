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

package hardware::server::sun::mgmt_cards::mode::showboards;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use hardware::server::sun::mgmt_cards::lib::telnet;
use centreon::plugins::statefile;

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                { 
                                  "hostname:s"       => { name => 'hostname' },
                                  "port:s"           => { name => 'port', default => 23 },
                                  "username:s"       => { name => 'username' },
                                  "password:s"       => { name => 'password' },
                                  "timeout:s"        => { name => 'timeout', default => 30 },
                                  "memory"           => { name => 'memory' },
                                  "command-plink:s"  => { name => 'command_plink', default => 'plink' },
                                  "ssh"              => { name => 'ssh' },
                                });
    $self->{statefile_cache} = centreon::plugins::statefile->new(%options);
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    if (!defined($self->{option_results}->{hostname})) {
       $self->{output}->add_option_msg(short_msg => "Need to specify a hostname.");
       $self->{output}->option_exit(); 
    }
    if (!defined($self->{option_results}->{username})) {
       $self->{output}->add_option_msg(short_msg => "Need to specify a username.");
       $self->{output}->option_exit(); 
    }
    if (!defined($self->{option_results}->{password})) {
       $self->{output}->add_option_msg(short_msg => "Need to specify a password.");
       $self->{output}->option_exit(); 
    }
    
    if (defined($self->{option_results}->{memory})) {
        $self->{statefile_cache}->check_options(%options);
    }
    
    if (!defined($self->{option_results}->{ssh})) {
        require hardware::server::sun::mgmt_cards::lib::telnet;
    }
}

sub telnet_shell_plateform {
    my ($telnet_handle) = @_;
    
    # There are:
    #System Controller 'sf6800':
    #   Type  0  for Platform Shell
    #   Type  1  for domain A console
    #   Type  2  for domain B console
    #   Type  3  for domain C console
    #   Type  4  for domain D console
    #   Input:
    
    $telnet_handle->waitfor(Match => '/Input:/i', Errmode => "return") or telnet_error($telnet_handle->errmsg);
    $telnet_handle->print("0");
}

sub ssh_command {
    my ($self, %options) = @_;
    my $username = '';
    
    if (defined($self->{option_results}->{username}) && $self->{option_results}->{username} ne '') {
        $username = $self->{option_results}->{username} . '\n';
    }
    
    my $cmd_in = "0" . $username . $self->{option_results}->{password} . '\nshowboards\ndisconnect\n';
    my $cmd = "echo -e '$cmd_in' | " . $self->{option_results}->{command_plink} . " -batch " . $self->{option_results}->{hostname} . " 2>&1";
    my ($lerror, $stdout, $exit_code) = centreon::plugins::misc::backtick(
                                                 command => $cmd,
                                                 timeout => $self->{option_results}->{timeout},
                                                 wait_exit => 1
                                                 );
    $stdout =~ s/\r//g;
    if ($lerror <= -1000) {
        $self->{output}->output_add(severity => 'UNKNOWN', 
                                    short_msg => $stdout);
        $self->{output}->display();
        $self->{output}->exit();
    }
    if ($exit_code != 0) {
        $stdout =~ s/\n/ - /g;
        $self->{output}->output_add(severity => 'UNKNOWN', 
                                    short_msg => "Command error: $stdout");
        $self->{output}->display();
        $self->{output}->exit();
    }

    if ($stdout !~ /Slot/mi) {
        $self->{output}->output_add(long_msg => $stdout);
        $self->{output}->output_add(severity => 'UNKNOWN', 
                                    short_msg => "Command 'showboards' problems (see additional info).");
        $self->{output}->display();
        $self->{output}->exit();
    }
    
    return $stdout;
}

sub run {
    my ($self, %options) = @_;
    my ($output, @lines);
    
    if (defined($self->{option_results}->{ssh})) {
        $output = $self->ssh_command();
        @lines = split /\n/, $output;
    } else {
        my $telnet_handle = hardware::server::sun::mgmt_cards::lib::telnet::connect(
                                username => $self->{option_results}->{username},
                                password => $self->{option_results}->{password},
                                hostname => $self->{option_results}->{hostname},
                                port => $self->{option_results}->{port},
                                timeout => $self->{option_results}->{timeout},
                                output => $self->{output},
                                closure => \&telnet_shell_plateform);
        @lines = $telnet_handle->cmd("showboards");
    }
    
    if (defined($self->{option_results}->{memory})) {
        $self->{statefile_cache}->read(statefile => 'cache_sun_mgmtcards_' . $self->{option_results}->{hostname}  . '_' .  $self->{mode});
        $self->{output}->output_add(severity => 'OK', 
                                    short_msg => "No new problems on system.");
    } else {
        $self->{output}->output_add(severity => 'OK', 
                                    short_msg => "No problems on system.");
    }

    my $datas = {};
    foreach (@lines) {
        chomp;
        my $long_msg = $_;
        $long_msg =~ s/\|/~/mg;
        $self->{output}->output_add(long_msg => $long_msg);
        my $id;
        if (/([^\s]+?)\s+/) {
            $id = $1;
        }
        my $status;
        if (/\s+(Degraded|Failed|Not tested|Passed|OK|Under Test)\s+/i) {
            $status = $1;
        }
        if (!defined($status) || $status eq '') {
            next;
        }
        
        if ($status =~ /^(Degraded|Failed)$/i) {
            if (defined($self->{option_results}->{memory})) {
                my $old_status = $self->{statefile_cache}->get(name => "slot_$id");
                if (!defined($old_status) || $old_status ne $status) {
                    $self->{output}->output_add(severity => 'CRITICAL', 
                                                short_msg => "Slot '$id' status is '$status'");
                }
                $datas->{"slot_$id"} = $status;
            } else {
                $self->{output}->output_add(severity => 'CRITICAL', 
                                            short_msg => "Slot '$id' status is '$status'");
            }
        }
    }
    
    if (defined($self->{option_results}->{memory})) {
        $self->{statefile_cache}->write(data => $datas);
    }
 
    $self->{output}->display();
    $self->{output}->exit();
}

1;

__END__

=head1 MODE

Check Sun SFxxxx (sf6900, sf6800, sf3800,...) Hardware (through ScApp).

=over 8

=item B<--hostname>

Hostname to query.

=item B<--port>

telnet port (Default: 23).

=item B<--username>

telnet username.

=item B<--password>

telnet password.

=item B<--memory>

Returns new errors (retention file is used by the following option).

=item B<--timeout>

Timeout in seconds for the command (Default: 30).

=item B<--command-plink>

Plink command (default: plink). Use to set a path.

=item B<--ssh>

Use ssh (with plink) instead of telnet.

=back

=cut
