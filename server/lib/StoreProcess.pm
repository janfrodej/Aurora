#!/usr/bin/perl -w
#
# Copyright (C) 2018 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
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
# StoreProcess: class for a Store Process (get, put etc of some type)
#
package StoreProcess;

use strict;
use POSIX;
use SmartLog;
use sectools;
use Parameter::Group;
use Time::HiRes qw(time);

our %CHILDS;

# constructor
sub new {
   # instantiate   
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # set defaults if not specified 
   my $cmd=Parameter::Group->new();
   my $size=Parameter::Group->new();
   if ((!exists $pars{pars}) || (ref($pars{pars}) ne "Parameter::Group")) { $pars{pars}=$cmd; }
   if ((!exists $pars{size}) || (ref($pars{size}) ne "Parameter::Group")) { $pars{size}=$size; }
   # timeout in seconds, 0=never
   if (!exists $pars{timeout}) { $pars{timeout}=0; }
   # wait for n seconds before aborting, 0=forever
   if (!exists $pars{wait}) { $pars{wait}=0; }
   # decode or mark incoming content as utf8
   if (!exists $pars{decode}) { $pars{decode}=1; }
   # ensure sensible setting...
   $pars{decode}=($pars{decode} =~ /[01]{1}/ ? $pars{decode} : 1);

   # save parameters
   $self->{pars}=\%pars;
 
   $self->{error}="";

   # create log
   $self->{log}=SmartLog->new();

   # process status
   $self->{running}=0;

   # read handle has been emptied
   # when process was not running
   # anymore. It is true to begin with
   # since no process has started yet
   $self->{reademptied}=1;

   # end-success of the process
   $self->{success}=0;

   return $self;
}

# execute the Store Process...
sub execute {
   my $self = shift;

   $self->{error}="";

   if (!$self->isrunning()) {
      # new run - set success flag to 0
      $self->{success}=0;
      # process exitcode
      $self->{execute_exitcode}=undef;
      # create an endmarker that notifies the 
      # parent process that the storeprocess has ended

      $self->{execute_endmarker}=sectools::randstr(64);
      $self->{message_marker}=sectools::randstr(64);

      # reset cputime structure
      my %ct=();
      $self->{cputimes}=\%ct;

      # get endmarker
      my $rstring=$self->{execute_endmarker};
      my $qrstring=qq($rstring);

      # create a one-way pipe
      pipe (my $read, my $write); 
      # save read handle          
      $self->{execute_read}=$read;
      # fork a child to handle reading the file handle
      my $pid=fork();
      if ($pid == 0) {
         # child
         %CHILDS=();
         close ($read);
         # update last alive
         $self->{alive}=time();
         # set new name
         $0="$0 StoreProcess collectdata";
         # start the background storeprocess
         if ($self->execute_startprocess()) {
            # only do all of this if process started successfully
            # continue this loop as long as file handle/pipe exists
            my $stime=time();
            # set running to true
            $self->{running}=1;
            # when was the last update written from the pipe
            my $lupdated=time();
            my $aread=$self->{execute_fh};

            my $rin='';
            vec($rin,fileno($aread),1) = 1;
            my $rbuf="";
            my $ended=0;
            # notify parent of execute pid of sub-process
            syswrite ($write,"EXECUTEPID ".$self->{execute_pid}." ".$self->{message_marker}."\n");
            while (1) {
               my $nfound=select (my $rout=$rin,undef,my $rfail=$rin,0.25);
               if ($nfound) {
                  # check if there was anything on STDOUT/STDERR
                  if (vec($rout, fileno($aread), 1)) {
                     # read 
                     my $data;
                     my $no=sysread ($aread,$data,2048);
                     if (!defined $no) {
                        # error sysread
                        syswrite ($write,"Unable to read STDOUT/STDERR from StoreProcess: $!\|".time()."\n");
                        $ended=1;
                     } elsif ($no > 0) {
                        # we have some data
                        # update read-buffer
                        $rbuf.=$data;
                     } else {
                        # EOF - finished with all reading
                        $ended=1;
                     }
                  }
                  # check for new lines from STDOUT/STDERR
                  while ($rbuf =~ /^([^\n]*\n)(.*)$/s) {
                     # we have a new line
                     my $line=$1;
                     $rbuf=$2;
                     $line=~s/[\n]//g;
                     if (!defined $rbuf) { $rbuf=""; }
                     # print to the parent process, including time stamp
                     # use eval to avoid sub-process crashing upon anything (like wide characters)
                     my $err;
                     local $@;
                     eval { syswrite ($write,"$line\|".time()."\n"); };
                     $@ =~ /nefarious/;
                     $err=$@;
                     if ($err ne "") { 
                        # also eval this syswrite to ensure it doesnt kill off the sub-process
                        eval { syswrite ($write,"Unable to syswrite logged StoreProcess line to pipe: $err\|".time()."\n"); };
                     }
                     # update last update time
                     $lupdated=time();
                  }
               }
               if (($ended) || ($nfound == -1)) {
                  # finished reading/something failed....wait for child-process and harvest exitcode
                  my $exitcode=0;
                  my $child=$self->{execute_pid};
                  my $r=0;
                  while ($r >= 0) { # wait for child-process (in StoreProcess::XYZ)
                     $r=waitpid($child,WNOHANG);
                     if ($r > 0) { $exitcode=$? >> 8; }  
                  }
                  eval { close ($aread); };
                  # print info about exitcode to parent
                  syswrite ($write,"EXITCODE $exitcode $rstring\|".time()."\n");
                  last;
               }

               # check to see if timeout has been reached
               # and no activity has been generated by the command
               if (($self->{pars}{timeout} > 0) &&
                   (time() > $lupdated + $self->{pars}{timeout})) {
                  # timeout reached and no new output from command - terminating...
                  syswrite ($write,"TIMEOUT $rstring\|".time()."\n");
                  last;
               } elsif (($self->{pars}{wait} > 0) && (time() > ($stime+$self->{pars}{wait}))) {
                  # execution wait is over - terminating even if activity is running
                  syswrite ($write,"WAITOUT $rstring\|".time()."\n");
                  last;
               } 
            }
         } else {
            # something failed
            syswrite ($write,"Unable to start process propely: ".$self->error()."\|".time()."\n");
            syswrite ($write,"EXITCODE 1 $rstring\|".time()."\n");
         }
         # do cleanup
         $self->execute_cleanup();
         # child is finished
         exit(0);      
      } elsif (defined $pid) {
         # parent
         # save pid to list
         $CHILDS{$pid}=$pid;
         # reap children
         $SIG{CHLD}=sub { foreach (keys %CHILDS) { my $p=$_; next if defined $CHILDS{$p}; if (waitpid($p,WNOHANG) > 0) { $CHILDS{$p}=$? >> 8; } } };
         # close write handle in this process
         close ($write);
         # set running state
         $self->{running}=1;
         # set reademptied to false
         $self->{reademptied}=0;
         # set line remainder to blank
         $self->{line}="";
         # save child pid of process reading filehandler
         $self->{read_pid}=$pid;
         # get its creation time
         my $ctime=(stat "/proc/$pid/stat")[10] || 0;
         # save it
         $self->{read_ctime}=$ctime;
         return 1;
      } else {
         # failed to fork
         $self->{error}="Unable to fork a process to execute command: $!";
         return 0;
      }
   } else {
      $self->{error}="A process is running already.";
      return 0;
   }
}

# this sub is to be 
# overridden by the inheriting
# child and does the necessary
# setup and start of the process
# in question. Set error and
# return 0 if it fails.
sub execute_startprocess {
   my $self = shift;

   return 1;
}

# this sub is to be overridden
# by the inheriting child and does
# the cleanup of the process
# after the child monitor exits
# always return 1
sub execute_cleanup {
   my $self = shift;

   return 1;
}

# update progress of process
sub update {
   my $self = shift;

   # only update status if process is still running or
   # read handle has not been emptied yet.
   if (($self->{running}) || (!$self->{reademptied})) {
      # if process is not running anymore, set reademptied
      if (!$self->{running}) {
         $self->{reademptied}=1;
      }
      # get read pipe
      my $read=$self->{execute_read};
      # get execute pid / pid of process doing the Store-operation
      my $expid=$self->{execute_pid}||0;
      # get endmarker
      my $endmarker=$self->{execute_endmarker} || sectools::randstr(64);
      $endmarker=qq($endmarker);
      my $msgmarker=$self->{message_marker} || sectools::randstr(64);
      $msgmarker=qq($msgmarker);
      if (defined $read) {
         # read all the latest progress, but use select - first create bits
         my $bits;
         vec ($bits,fileno($read),1) = 1;
         my $rbits=$bits;
         my $line=$self->{line} || "";
         while (select($rbits,undef,undef,0.10)) { # short timeout, only 100 ms, nfound will be set if any bits found
            # set bits back to original 
            $rbits=$bits;
            while (sysread($read, my $nextbyte, 1)) { # read one and one character until stop or eol.
               $line .= $nextbyte; 
               last if $nextbyte eq "\n"; 
            }

            if ($line !~ /\n\z/) { next; } # incomplete line - go and wait again

            # complete line if here...add utf8 mark
            utf8::decode($line);
            # split into line and timestamp
            $line=~s/^(.*)\|([\d\.]+)[\n\r]*$/$1/;         
            my $time=$2;
            if (($line !~ /^.*$endmarker$/) && ($line !~ /^.*$msgmarker$/)) {
               # add to log
               my $log=$self->{log};
               $log->add($line,$time);
               $self->{alive}=$time;
            } elsif ($line =~ /^([^\s]+)\s+([^\s+]+)\s+$msgmarker$/) {
               # internal message
               my $type=$1||"NA";
               my $value=$2||"";
               if ($type eq "EXECUTEPID") {
                 # store execute pid
                 $self->{execute_pid}=$value;
                 $expid=$value;
               }
            } else {
               # endmarker seen
               $self->{running}=0;
               $self->{reademptied}=1;
               $self->{alive}=time();
               # check for exitcode
               if ($line =~ /^EXITCODE\s+[\d\.]+\s+$endmarker$/) {
                  # get exitcode
                  my $ecode=$line;
                  $ecode=~s/^EXITCODE\s+([\d\.]+)\s+$endmarker$/$1/;
                  $self->{execute_exitcode}=$ecode;
                  $self->{success}=($ecode != 0? 0 : 1);
                  # update error in case we didnt have success
                  if (!$self->{success}) { 
                     my $log=$self->{log};
                     my $str=$log->getLastAsString(5,"%t: %m "); 
                     $self->{error}=$str; 
                  }
               } elsif ($line =~ /^TIMEOUT $endmarker$/) { # check for potential timeout
                  # command run timed out
                  $self->{error}="Timout has been reached. Process has been aborted.";
                  $self->{success}=0;
               } elsif ($line =~ /^WAITOUT $endmarker$/) { # check potential wait time
                  # commands wait time has been reached
                  $self->{error}="Wait time has been reached. Process has been aborted.";
                  $self->{success}=0;
               }

               # blank the line
               $line="";
 
               last;
            }        
            # set to blank for next line  
            $line="";
         }

         # check stat file to see if process is still alive - utime and stime           
         my $ccputime=0; # existing calculated cpu time
         my $cputime=0;  # cpu time as used up until this instance
         # get pointer to cputimes structure
         my $cputimes=$self->{cputimes};        
         my @pids;
         push @pids,$expid;
         # first get all children of pid
         if (open (FH,"/proc/$expid/task/$expid/children")) {
            # read from file
            my $chl;
            eval { $chl = join("",<FH>); close(FH); };
            my @childs=split(/\s+/,$chl);
            # go through parent and children and sum all cpu-times 
            foreach (@childs) {
               my $pid=$_;
               if (open (FH,"/proc/$pid/stat")) {
                  # read from file
                  my $stat;
                  eval { $stat = join("",<FH>); close(FH); };
                  if (defined $stat) {
                     my @vals=split(/\s+/,$stat);
                     # add utime and stime together with existing values
                     $cputime=$cputime + ($vals[13]+$vals[14]);
                     # do the same addition on the current cputime structure
                     # we only calculate what is there already to keep in mind that processes might
                     # come and go while the parent remains. We are only interested in the 
                     # total of the running processes having changed or not?
                     if (exists $cputimes->{$pid}) { $ccputime=$ccputime + $cputimes->{$pid}; }
                     # update cputimes structure to include potentially new values
                     $cputimes->{$pid}=$vals[13]+$vals[14];
                  }
               }
            }
         }
         if ($cputime > $ccputime) {
            # more cpu resources have been used by process - update alive
            $self->{alive}=time();
         }

         # check if there is remains in the line and set remainder
         if ($line ne "") {
            $self->{line}=$line;
         } else { $self->{line}=""; }
      }

      # return success state
      return $self->{success};
   } else {
      return 0;
   }
}

sub getlog {
   my $self = shift;

   return $self->{log};
}

# reset the log itself
sub resetlog {
   my $self = shift;

   my $log=$self->{log};

   if ((!$self->isrunning()) && ($self->isemptied())) {
      $log->reset();
      return 1;
   } elsif ($self->isrunning()) {
      $self->{error}="Unable to reset log since process is still running.";
      return 0;
   } elsif (!$self->isemptied()) {
      $self->{error}="Unable to reset log since read handle has not been emptied.";
      return 0;
   }
}

# set/get timeout
sub timeout {
   my $self = shift;

   if (@_) {
      my $timeout = shift || 0;

      $timeout=~s/(\d+)/$1/;

      $self->{pars}{timeout}=$timeout;

      return 1;
   } else {
      # read timeout value
      return $self->{pars}{timeout};

   }
}

# set/get wait
sub wait {
   my $self = shift;

   if (@_) {
      my $wait = shift || 0;
   
      $wait=~s/(\d+)/$1/;

      $self->{pars}{wait}=$wait;

      return 1;
   } else {
      # read wait value
      return $self->{pars}{wait};
   }
}

# check if get is running
sub isrunning {
   my $self = shift;

   # get latest progress
   $self->update();

   return $self->{running};
}

# check to see if read handle
# has been emptied. Will be true if
# no process has started to run
sub isemptied {
   my $self = shift;

   return $self->{reademptied} || 0;
}

# get last timestamp
# that process performed
# an update...
sub alive {
   my $self = shift;

   return $self->{alive} || 0;
}

# get exitcode of command
# that was run
sub exitcode {
   my $self=shift;

   if ((!$self->isrunning()) &&
       ($self->isemptied())) {
       return $self->{execute_exitcode};
   } else {
      return undef;
   }
}

# cease process
sub cease {
   my $self = shift;

   # cannot call isrunning because it will run update
   if ($self->{running}) {
      # we do not even risk getting a log update - just end it
      my ($pid,$ctime)=$self->readpid();
      # check that current ctime matches
      my $cctime=(stat "/proc/$pid/stat")[10] || 0;
      my $r=0;
      if ($ctime == $cctime) {
         # its the same process - kill off the child 
         $r=kill ("KILL",$pid);
      }
      # kill off specific processes related to the child that inherits this class
      $self->execute_cease();
      # set some important internal variables
      $self->{running}=0;
      $self->{reademptied}=1;
      $self->{execute_exitcode}=1;
      $self->{success}=0;
      # we signal ok
      return 1;
   } else {
      # no process is running
      $self->{error}="No store process is running. Unable to cease process.";
      return 0;
   }
}

# child specific cease.
# to be overridden
sub execute_cease {
   my $self = shift;

   return 1;
}

# get success of last process
sub success {
   my $self = shift;
   
   # isrunning if process is running
   # including a possible setting of the success flag
   if ((!$self->isrunning()) && ($self->{success})) {
      return 1;
   } else {
      # not successful
      return 0;
   }
}

# get pid and ctime of process reading on the filehandler
sub readpid {
   my $self=shift;

   if ($self->isrunning()) {
      # process is running - return pid and ctime
      return ($self->{read_pid},$self->{read_ctime});
   } else {
      $self->{error}="No process is running, unable to give you any PID.";
      return 0;
   }
}

# get pid and ctime of process executing - this pid is set by the 
# inheriting class.
sub executepid {
   my $self = shift;

   if ($self->isrunning()) {
      # process is running - give pid
       return ($self->{execute_pid},$self->{execute_ctime});
   } else {
      $self->{error}="No process is running, unable to give you any PID.";
      return 0;      
   }
}

# get last error message
sub error {
   my $self = shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<StoreProcess> - Placeholder class for executing a process, manipulating the process and logging its output.

=head1 SYNOPSIS

   use Parameter::Group;
   use SmartLog;
   use StoreProcess;

   # create a Parameter-instance
   my $c=Parameter::Group->new();

   # instantiate
   my $sp=StoreProcess->new(pars=>$c);

   # execute StoreProcess
   $sp->execute();

   # get log instance of the StoreProcess
   my $log=$sp->getlog();

   # reset pointer to where reading log
   $log->resetNext();

   # output log while StoreProcess is running
   while ($sp->isrunning()) {
      print "".$log->getnext()."\n";
   }

=cut

=head1 DESCRIPTION

Placeholder class for executing a process, manipulating the process and logging its output.

It makes it possible to execute a process while the output of that process is being logged. It handles the return exitcode of the 
process, stop or cease the execution of that process and so on.

This class is not meant to be instantiated, but inherited.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the class.

Valid parameters are:

=over

=item 

B<pars> Sets the Parameter::Group-class instance for the StoreProcess. Required. Will default to an empty Parameter::Group-class instance if not specified.

=cut

=item

B<timeout> Sets the timeout of the command being executed by the StoreProcess. It is specified in seconds, where 0 is never. Optional and if not specified will default to 0.

=cut

=item

B<wait> Sets the wait time for the command being executed by the StoreProcess. It is specified in seconds, where 0 is forever. Optional and will default to 0.

=cut

=back

Returns the StoreProcess-instance

=cut

=head1 METHODS

=head2 execute()

Executes the StoreProcess command (see the pars-option in the new()-method).

The method accepts no input.

It will attempt to execute the command that the StoreProcess is meant to run, fork a process to handle logging its output back to 
the parent StoreProcess. It will check timeout- and wait-values (see the new()-methods options).

The method will return 1 upon successful start of execution, 0 upon failure. Please check the error()-method for more information 
upon failure.

=cut

=head2 execute_startprocess()

Setups- and starts the process to be executed.

No input is accepted and it returns 1.

This method is internal and meant to be overridden by the inheriting class. It is not to be called by the user.

=cut

=head2 execute_cleanup()

Performs cleanup if the StoreProcess after the fork'ed child process exits.

It takes no input.

Always returns 1.

This method is internal and meant to be overridden by the inheriting class. It is not to be called by the user.

=cut

=head2 update()

Update the progress of the fork'ed child process in the log.

It reads the output handler from the fork'ed child process and add's the output to the log-instance of the StoreProcess class. It 
also updates the alive-timestamp for when it last saw output from the child process.

It will also harvest the exitcode from the process and it expects it to be 0 upon success and the result of this also marks the 
overall success of the StoreProcess execution itself (see the success()-method).

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

=cut

=head2 getlog()

Gets the log instance of the StoreProcess-class.

No input accepted.

Returns the log-instance of the StoreProcess-class.

=cut

=head2 resetlog()

Resets the log instance of the StoreProcess-class.

It will only accept resetting the log if no StoreProcess is running and the read handle from the fork'ed child process has 
been emptied.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

=cut

=head2 timeout()

Sets or gets the timeout value of the StoreProcess command.

On get, it takes no input. On set, it takes the value of the timeout.

Timeout value is given in seconds to wait on any change/update in the output from the fork'ed child process being run. 0 means it 
will never timeout.

On get the return value is the timeout value. On set, the return value is 1.

Also see the timeout-option in the new()-method for more information.

=cut

=head2 wait()

Sets or gets the wait time value of the StoreProcess command.

On get, it takes no input. On set, it takes the value of the wait time.

Wait value is given in seconds to wait on the fork'ed child process finishing, independant of any timeout or any change/update in 
the output from it. 0 means it will wait forever.

On get the return value is the wait value. On set, the return value is 1.

Also see the wait-option in the new()-method for more information.

=cut

=head2 isrunning()

Checks to see if the store-process is still running and updating the StoreProcess output log at the same time.

Method accepts no input.

Returns 1 if running, 0 if not.

=cut

=head2 isemptied()

Checks to see if the StoreProcess read-handle on the fork'ed child process has been emptied or not.

Method accepts no input.

Returns 1 if emptied, 0 if not.

=cut

=head2 alive()

Returns the last timestamp from getting new output from the StoreProcess command.

=cut

=head2 exitcode()

Returns the exitcode from a finished executed StoreProcess-command.

Returns the exitcode upon success, undef upon failure. Please check the error()-method for more information upon error.

=cut

=head2 cease()

Cease or stop the StoreProcess being executed.

It takes no input.

It does this by killing the fork'ed child process.

Returns 1 upon success, 0 upon failure. Please check the error()-method upon failure.

=cut

=head2 execute_cease()

Placeholder method that performs child specific stopping/ceasing of the StoreProcess being executed.

This method is called by the cease()-method and is internal and not meant to be called by the user.

The method is to be overridden by the inheriting class.

Returns 1 upon success, 0 upon failure. 

=cut

=head2 success()

Returns the success of the last StoreProcess execution.

It requires that a process has been executed and ended.

Returns 1 upon success, 0 upon failure.

=cut

=head2 readpid()

Returns the pid of the process reading the log filehandler of StoreProcess.

No input is accepted.

It returns either the PID upon success, or 0 upon failure (no process running).

=cut

=head2 error()

Returns the last error message of the instance.

Accepts no input.

Returns the last error message as a SCALAR.

=cut
