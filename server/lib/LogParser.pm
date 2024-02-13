#!/usr/bin/perl -w
# Copyright (C) 2019-2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
#
# This file is part of AURORA, a system to store and manage science data.
#
# AURORA is free software: you can redistribute it and/or modify it under 
# the terms of the GNU General Public License as published by the Free 
# Software Foundation, either version 3 of the License, or (at your option) 
# any later version.
#
# AURORA is distributed in the hope that it will be useful, but WITHOUT ANY 
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with 
# AURORA. If not, see <https://www.gnu.org/licenses/>. 
#
# LogParser - class to parse a AuroraDB log-hash of a dataset
#
package LogParser;

use strict;
use lib qw(/usr/local/lib/aurora);
use SysSchema;

sub new {
   # instantiate
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # check values, set defaults
   if (!$pars{log}) { my %l=(); $pars{log}=\%l; }

   # save parameters
   $self->{pars}=\%pars;
 
   my %d=();
   $self->{logdata}=\%d;

   # set last error message
   $self->{error}="";

   # return instance
   return $self;
}

# attempt to parse log and fill instance logdata
sub parse {
   my $self = shift;

   # get ref to log
   my $log=$self->{pars}{log};

   # use a blank logdata
   my %logdata = ();
   $logdata{transfer_log}=();
   $logdata{distlog}=();
   # task id
   my $task="";
   my $taskq=qq($task);
   # all transfers completed
   my $tcompleted=0;
   # acquire-phase completed
   my $completed=0;
   # acquire-phase counter in total
   my $acount=0;
   # acquire-phase counter for current run
   my $cacount=0;
   # acquire-phase failure count
   my $afail=0;
   # twin-problem - two or more acquire processes at once
   my $twin=0;
   foreach (sort {$a <=> $b} keys %{$log}) {
      my $no = $_;

      # check for dataset type entry
      if ($log->{$no}{message} =~ /Created\s+([^\s]+)\s+dataset$/) {
         $logdata{dataset_type}=$1;
      }

      # check we if we find log entry for removal
      if ($log->{$no}{message} =~ /Dataset\s+expired\s+and\s+was\s+now\s+removed/) {
         $logdata{removed_time}=$log->{$no}{time};
      }

      # check to see if we can find store-class being used for acquire-operation 1
      if ((!exists $logdata{acquire_phase_store_class}) && ($log->{$no}{message} =~ /Checking\s+size\s+of\s+data\s+in\s+the\s+acquire\-operation\s+1\s+with\s+store\s+([^\s]+)\s+\(\d+\).*$/)) {
         $logdata{acquire_phase_store_class}=$1;
      }

      # check if we have found a distlog entry - save all of them in correct order
      if (($log->{$no}{tag} =~ /^STORESRVC\s+([^\s]+)\s+DISTLOG$/) || ($log->{$no}{tag} =~ /^MAINT\_GEN\s+DISTLOG$/)) {
         # distlog entry located - store it
         my $pos=keys %{$logdata{distlog}};
         $pos++;
         $logdata{distlog}{$pos}=$log->{$no}{message};
      }

      # parse status
      if ($log->{$no}{message} =~ /^Status\s+is\s+OPEN$/) {
         $logdata{status}=$SysSchema::C{"status.open"}
      } elsif ($log->{$no}{message} =~ /Successfully\s+completed\s+ACQUIRING\-phase\s+for\s+task.*$/) {
         $logdata{status}=$SysSchema::C{"status.closed"};
         $logdata{closed_by}=$SysSchema::FROM_MAINTENANCE;
      } elsif ($log->{$no}{message} =~ /Dataset\s+closed\s+by\s+(.*)$/) {
         my $by=$1;
         $logdata{status}=$SysSchema::C{"status.closed"};
         if ($by =~ /the\s+Maintenance\-service.*$/) { $logdata{closed_by}=$SysSchema::FROM_MAINTENANCE; }
         elsif ($by =~ /^user\s+\((\d+)\).*$/) {
            $logdata{closed_by}=$1;
         }
      } elsif ($log->{$no}{message} =~ /has\s+been\s+moved\s+from\s+CLOSED\s+to\s+OPEN\s+state\s+by\s+ manual\s+intervention/) {
         delete($logdata{closed_by});
         $logdata{status}=$SysSchema::C{"status.open"};
      }

      # check if we started another round of the acquire-phase
      if (($log->{$no}{tag} =~ /^STORESRVC.*$/) &&
          ($log->{$no}{message} =~ /In\s+acquire\-fork\s+on\s+task\s+([a-zA-Z0-9]{32}).*$/)) {
         if (!exists $logdata{task_id}) { $logdata{task_id}=$1; $task=$1; $taskq=qq($task); }
         # increment acquire-phase counter
         $acount++;
         # also increment current acquire-phase counter
         $cacount++;
         # check for twin processes at the same time
         if ((!$tcompleted) && ($cacount > 1)) {
            # two or more processes running at the same time
            $twin=1;
         } elsif ((!$tcompleted) && ($cacount <= 1)) { $twin=0; }
      }

      # check if we find transfer log entry - save it
      if ((!$completed) && ($log->{$no}{tag} =~ /^STORESRVC\s+[^\s]+\s+TRANSFER$/)) {
         my $pos = keys %{$logdata{transfer_log}};
         $pos++;
         # if we have a twin problem, check to for double messages and do not save doubles
         if ($twin) {
            # check for double message and only save if not
            # this might end up it becoming random which of the double are being saved or not
            my $found=0;
            foreach (keys %{$logdata{transfer_log}}) {
               my $nno=$_;

               if ($logdata{transfer_log}{$nno} eq $log->{$no}{message}) { $found=1; last; }
            }
            # only save log entry if double not exists already
            if (!$found) { $logdata{transfer_log}{$pos} = $log->{$no}{message}; }
         } else {
            # no twin/double - just save message
            $logdata{transfer_log}{$pos} = $log->{$no}{message};
         }
      }

      # see if we find the remote size of the dataset 
      if ((!$completed) && ($log->{$no}{message} =~ /Size\s+of\s+data\s+in\s+acquire\-operation\s+1\s+with\s+store.*\((\d+)\s+Byte\(s\)\).*$/)) {
         $logdata{remote_size}=$1;
      }

      # check if we find a failure of transfer
      if ((!$tcompleted) && ($log->{$no}{tag} =~ /^STORESRVC.*$/) &&
          (($log->{$no}{message} =~ /Acquire\s+operation\s+\d+\s+with\s+store\s+[a-zA-Z0-9\:]+\s+\(\d+\)\s+in\s+task\s+$taskq\s+failed.*$/) || 
           ($log->{$no}{message} =~ /Unable\s+to\s+successfully\s+complete\s+all\s+acquire\-operations\s+in\s+task/))) {
         # transfer failure - increment counter
         $afail++;
         # substract acquire-phase counter
         if ($cacount > 0) { $cacount--; }
         # check if we need to reset the transfer log
         if (!$twin) {
            # reset the log since we do not have twins and the transfer failed
            $logdata{transfer_log}=();
         }
      }

      # check if we find a successful completion of all transfers
      if ((!$tcompleted) && ($log->{$no}{tag} =~ /^STORESRVC.*$/) &&
          ($log->{$no}{message} =~ /All\s+acquire\-operations\s+executed\s+successfully\s+in\s+task\s+$taskq.*$/)) {
         $tcompleted=1;
      }

      # check if we find a successful completion of the acquire-phase
      if ((!$completed) && ($log->{$no}{tag} =~ /^STORESRVC.*$/) &&
          ($log->{$no}{message} =~ /Successfully\s+completed\s+ACQUIRING\-phase\s+for\s+task\s+$taskq.*$/)) {
         $completed=1;
      }
   }
   # some extra info
   $logdata{transfer_all_completed}=$tcompleted;  # all transfers completed successfully. BOOLEAN 0/1
   $logdata{acquire_phase_completed}=$completed;   # acquire-phase completed successfully. BOOLEAN 0/1
   $logdata{acquire_phase_failure_count}=$afail;  # acquire-phase failure count
   $logdata{acquire_phase_run_count}=$acount;     # acquire-phase run count
   $logdata{acquire_phase_simultaneous}=$twin;    # One or more acquire-phase processes ran at once? BOOLEAN 0/1
   # finished parsing - replace existing logdata of instace
   $self->{logdata}=\%logdata;
   # return the result
   return \%logdata;
}

sub data {
   my $self = shift;

   # return the logdata hash
   return $self->{logdata};
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<LogParser> - Class to parse an AuroraDB log-entries hash returned from method getLogEntries().

=cut

=head1 SYNOPSIS

   use AuroraDB;
   use LogParser;

   my $db = AuroraDB->new(...);
   
   my $id=1234;
   my $log=$db->getLogEntries($id);

   my $parser = LogParser->new(log=>$log);
   my $result = $parser->parse();

=cut

=head1 DESCRIPTION

Class to parse a Log-hash and its content and pick out relevant information from it, including dataset type, status, 
remote size, transfer log and more.

It will parse the log-entries from the beginning to the end and pick out relevant information.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the class.

It takes the following parameters:

=over

=item

B<log> HASH-reference to the AuroraDB log-hash. HASH-reference. Required. See the parse()-method below for the structure.

=cut

=back

Returns a class instance upon success.

=cut

=head1 METHODS

=head2 parse()

Parses an AuroraDB log-hash and returns relevant aggregated information about the life of the dataset in question.

The method does not accept any parameters and returns a hash-reference upon success that are structured accordingly:

  logdata => (
     dataset_type => SCALAR # MANUAL/AUTOMATIC
     removed_time => SCALAR # Unix datetime
     acquire_phase_store_class => SCALAR # Store-class used to perform acquire operation 1
     transfer_log => (
        1 => SCALAR # transfer log entry no 1
        2 => SCALAR # transfer log entry no 2
        .
        .
        n => SCALAR # transfer log entry no n
     )
     status => SCALAR    # OPEN/CLOSED
     closed_by => SCALAR # service id or user id if > 0
     task_id => SCALAR   # Store-service task id used during acquire-phase
     distlog => (
       1 => SCALAR # distlog-entry no 1
       .
       .
       n => SCALAR # distlog-entry no n
     )
     remote_size                 => SCALAR # size of remote data
     transfer_all_completed      => SCALAR # all transfer completed successfully (0/1)
     acquire_phase_completed     => SCALAR # acquire-phase completed successfully (0/1)
     acquire_phase_failure_count => SCALAR # no times the acquire-phase failed
     acquire_phase_run_count     => SCALAR # no of times the acquire-phase ran
     acquire_phase_simultaneous  => SCALAR # did several acquire-phase processes run simultaneously? (0/1)     
  )

Not all values will necessarily be present in the return logdata. That depends on the history of the dataset and what is in its log. Eg. 
"removed_time" will not be there if the dataset was not removed yet. In a similar manner the "closed_by" will not exist if the dataset has not 
been closed yet. Also some values will not be there if the dataset is of MANUAL type. This includes the values remote_size, transfer_all_completed 
and all the acquire_phase ones (they will have 0/false values).

=cut

