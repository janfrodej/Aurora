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
# DistributionQueue: A module to handle an AURORA REST-server distribution queue
#
package DistributionQueue;
use strict;
use Schema;
use SysSchema;
use sectools;
use Time::HiRes qw(time);

sub new {
   my $class=shift;
   my $self={};
   bless ($self,$class);

   my %pars=@_;
   if (!exists $pars{folder}) { $pars{folder}="/local/app/aurora/distributions"; }
   if (!exists $pars{delimiter}) { $pars{delimiter}=","; }

   $self->{pars}=\%pars;

   return $self;
}

sub addTask {
   my $self=shift;
   my $userid=shift;
   my $datasetid=shift;
   my $data=shift;
   my %tags=@_; # optional tag->value pairs to method

   my $method=(caller(0))[3];

   my $folder=$self->folder();
   my $delim=$self->delimiter();

   if ((!defined $userid) || ($userid !~ /\d+/)) {
      # missing or invalid userid
      $self->{error}="$method: Missing or invalid userid specified.";
      return undef;
   }

   if ((!defined $datasetid) || ($datasetid !~ /\d+/)) {
      # missing or invalid datasetid
      $self->{error}="$method: Missing or invalid dataset id specified.";
      return undef;
   }

   if (!defined $data) {
      $self->{error}="$method: No data for task defined. Unable to continue.";
      return undef;
   }

   # create random id of task
   my $random=sectools::randstr(32);

   # put together userid, datasetid and random string
   my $task=$userid.$delim.$datasetid.$delim.$random;

   # create task folder in a temp state
   if (mkdir("$folder/.$task")) {
      # successfully created folder for task - populate files
      if (open(FH,">","$folder/.$task/DATA")) {
         # successful - write data
         print FH $data;
         # close file
         close (FH);
         # make symlink in init folder
         mkdir ("$folder/".$SysSchema::C{"phase.init"}); # quick and dirty
         if (!symlink ("$folder/$task","$folder/".$SysSchema::C{"phase.init"}."/$task")) {
            # failed to symlink - fail the task and remove file
            $self->{error}="$method: Unable to symlink file to ".$SysSchema::C{"phase.init"}."-folder: $!";
            # cleanup in tmp-mode
            $self->removeTask($task,1);
            return undef;
         }
         # make phase tag
         if (!$self->taskTag($task,"phase",$SysSchema::C{"phase.init"},1)) {
            # unable to set phase tag 
            $self->{error}="$method: Unable to set phase tag file: $!";
            # cleanup in tmp-mode
            $self->removeTask($task,1);
            return undef;
         }
         # make status tag
         if (!$self->taskTag($task,"status",$SysSchema::C{"phase.init"},1)) {   
            # unable to set status tag 
            $self->{error}="$method: Unable to create status tag file: $!";
            # cleanup in tmp-mode
            $self->removeTask($task,1);
            return undef;
         }
         # add other optional tags
         foreach (keys %tags) {
            my $tag=$_;

            # attempt to add tag
            if (!defined $self->taskTag($task,$tag,$tags{$tag},1)) {
               # some error - it affects the result of all. Error already set.
               # cleanup
               $self->removeTask($task,1);
               return undef;
            }
         }
         # move folder into place
         if (!rename ("$folder/.$task","$folder/$task")) {
            # we failed at moving folder into place
            $self->{error}="$method: Unable to move temporary task folder into production: $!";
            # cleanup in tmp-mode
            $self->removeTask($task,1);
            return undef;
         }
         # we are successful - return task id
         return $task;
      } else {
         # unable to create file
         $self->{error}="$method: Unable to create task data file: $!";
         # cleanup in tmp-mode
         $self->removeTask($task,1);
         return undef;
      }
   } else {
      # unable to create task folder
      $self->{error}="$method: Unable to create temporary task folder $folder/.$task: $!";
      return undef;
   }
}

sub removeTask {
   my $self=shift;
   my $task=shift;
   my $tmp=shift || 0; # sets if the task folder is in a tmp mode - only internal use!

   my $method=(caller(0))[3];

   my $folder=$self->folder();
   my $delim=$self->delimiter();
   my $qdelim=qq($delim);

   if ((!defined $task) || ($task !~ /^\d+$qdelim\d+$qdelim[A-Za-z0-9]{32}$/)) {
      $self->{error}="$method: Task parameter not defined or wrong format.";
      return undef;
   }

   # get task files 
   my $files=$self->getTaskFiles($task,$tmp);
   if (!defined $files) {
      # something failed - error already set
      return 0;
   }

   # put task into tmp state
   if ((!$tmp) && (!rename("$folder/$task","$folder/.$task"))) {
      # unable to rename folder
      $self->{error}="$method: Unable to move task $task into temporary state for removal: $!";
      return undef;
   }

   # found files - lets get phase, so we can remove symlink there first
   my @phasefile=grep { $_ =~ /^phase\_.*$/ } @{$files};
 
   if (defined $phasefile[0]) {
      # remove phase symlink
      my $phase=$phasefile[0]; 
      $phase=~s/^phase\_(.*)$/$1/;
      unlink ("$folder/$phase/$task");
   } else { 
      # could not locate phase, attempt to check all phase folders
      if (opendir (DH,"$folder/")) {
         # get all existing phases
         my @phases=grep { $_ =~ /^[A-Z]+$/ && -d "$folder/$_" } readdir DH;
         closedir DH;
         # go through each phase and remove the task from all that have it
         foreach (@phases) {
            my $phase=$_;

            if (-l "$folder/$phase/$task") { unlink ("$folder/$phase/$task"); }
         }
      }
   }

   # remove the rest of the files
   foreach (@{$files}) {
      my $file=$_;

      unlink ("$folder/.$task/$file");
   }

   # attempt to remove the folder
   if (!rmdir("$folder/.$task")) {
      # unable to remove folder - the whole methodf fails
      $self->{error}="$method: Unable to remove task $task folder $folder/$task: $!";
      return 0;
   }

   # if here, we are successful
   return 1;
}

sub getTaskData {
   my $self=shift;
   my $task=shift;
   
   my $method=(caller(0))[3];

   my $folder=$self->folder();
   my $delim=$self->delimiter();
   my $qdelim=qq($delim);

   if ((!defined $task) || ($task !~ /^\d+$qdelim\d+$qdelim[A-Za-z0-9]{32}$/)) {
      $self->{error}="$method: Task parameter not defined or wrong format.";
      return undef;
   }
   
   # attempt to open and read the data
   if (open (FH,"<","$folder/$task/DATA")) {
      # read the data contents
      my @data=<FH>;
      eval { close(FH); };
      # return the data
      return join("",@data);
   } else {
      # failure
      $self->{error}="$method: Unable to open task $task DATA-file for reading: $!";
      return undef;
   }
}

sub taskTag {
   my $self=shift;
   my $task=shift;
   my $tag=shift;

   my $method=(caller(0))[3];

   if (defined $tag) { $tag=lc($tag); }

   my $folder=$self->folder();
   my $delim=$self->delimiter();
   my $qdelim=qq($delim);

   if ((!defined $task) || ($task !~ /^\d+$qdelim\d+$qdelim[A-Za-z0-9]{32}$/)) {
      $self->{error}="$method: Task parameter not defined or wrong format.";
      return undef;
   }

   if ((!defined $tag) || ($tag !~ /^[a-z]+$/)) {
      $self->{error}="$method: Tag parameter not defined or wrong format.";
      return undef;
   }

   if (@_) {
      # this is a set/update - get value
      my $value=shift;
      my $tmp=shift || 0; # optionally handle tmp-folder. Internal use


      my $dot=($tmp ? "." : "");
      
      if ($value =~ //) {
         $self->{error}="$method: Value-parameter is of wrong format.";
         return undef;
      }

      # get task files
      my $files=$self->getTaskFiles($task,$tmp);
      if (!defined $files) {
         # some error - already set
         return undef;
      } 

      # quoted tag
      my $qtag=qq($tag);

      # check if tag file is there
      my @efile=grep { $_ =~ /$qtag\_.*$/ } @{$files};
      my $evalue;
      if (defined $efile[0]) {      
         $evalue=$efile[0];
         $evalue=~s/$qtag\_(.*)$/$1/;
      }

      my $change=(defined $efile[0] ? ($evalue eq $value ? 0 : 1) : 0);

      if ($change) {
         # rename file to new value
         if (!rename("$folder/$dot$task/$efile[0]","$folder/$dot$task/${tag}_$value")) {
            # update of existing tag file failed
            $self->{error}="$method: Unable to update tag $tag: $!";
            return undef;
         }
         # successfully updated
         return $value;
      } elsif ((!$change) && (!defined $efile[0])) {
         # create file
         if (open (FH,">","$folder/$dot$task/${tag}_$value")) {
            # success - close file
            eval { close (FH); };
            return $value;
         } else {
            # unable to create file
            $self->{error}="$method: Unable to create tag $tag: $!";
            return undef;
         }
      }
      # we have no set, since the value has not changed
      return $value;
   } else {
      # this is a get - get task files
      my $files=$self->getTaskFiles($task);
      if (!defined $files) {
         # some error - already set
         return undef;
      } 
      # quoted tag
      my $qtag=qq($tag);

      # check if tag file is there
      my @tagfile=grep { $_ =~ /$qtag\_.*$/ } @{$files};

      if (defined $tagfile[0]) {
         # tag found - return its value
         my $tagvalue=$tagfile[0];
         $tagvalue=~s/^$qtag\_(.*)$/$1/;

         return $tagvalue || "";
      } else {
         # tag does not exist
         $self->{error}="$method: Task tag $tag does not exist for task $task.";
         return undef; 
      }
   }
}

sub taskFile {
   my $self=shift;
   my $task=shift;
   my $name=shift || "dummy";
   my $data=shift || "";
   my $tmp=shift || 0; # task folder in tmp-mode. Only internal use!

   my $folder=$self->folder();
   my $delim=$self->delimiter();
   my $qdelim=qq($delim);

   my $method=(caller(0))[3];

   if ((!defined $task) || ($task !~ /^\d+$qdelim\d+$qdelim[A-Za-z0-9]{32}$/)) {
      $self->{error}="$method: Task parameter not defined or wrong format.";
      return 0;
   }

   if ((!defined $name) || ($name !~ /^[A-Z]+$/)) {
      $self->{error}="$method: Name parameter not defined or wrong format.";
      return 0;
   }

   my $dot=($tmp ? "." : "");

   # attempt to open file
   if (open (FH,">","$folder/$dot$task/$name")) {
      # success - write content to file
      print FH $data;
      close (FH);
      return 1;
   } else {
      # unable to open file for writing
      $self->{error}="$method: Unable to open file for writing: $!\n";
      return 0;
   }
}

sub changeTaskPhase {
   my $self=shift;
   my $task=shift;
   my $phase=shift; # new phase
   my $status=shift; # potential differing status tag, optional
   my $sphase=shift; # set if we accept same phase or not when changing
   if (!defined $sphase) { $sphase=1; } # default setting - accept same phase
   $sphase = ($sphase ? 1 : 0);

   my $method=(caller(0))[3];

   my $folder=$self->folder();
   my $delim=$self->delimiter();
   my $qdelim=qq($delim);

   if ((!defined $task) || ($task !~ /^\d+$qdelim\d+$qdelim[A-Za-z0-9]{32}$/)) {
      $self->{error}="$method: Task parameter not defined or wrong format.";
      return 0;
   }

   if ((!defined $phase) || ($phase !~ /^[A-Z]+/)) {
      $self->{error}="$method: Phase parameter is not defined or wrong format.";
      return 0;
   }

   # status tag is always uppercase
   $phase=uc($phase);

   # get current phase tag
   my $cphase=$self->taskTag($task,"phase");
   
   if (!defined $cphase) {
      # some problem - error already set
      return 0;
   }

   if (($cphase eq $phase) && ($sphase)) { 
      # we accept that old and new phase is the same, default behaviour
      $status=(defined $status ? $status : $phase);
      $self->taskTag($task,"status",$status);

      return 1; 
   } elsif (($cphase eq $phase) && (!$sphase)) {
      # we do not accept that old and new phase is the same - abort
      $self->{error}="$method: current and new phase ($phase) cannot be the same";
      return 0;
   }

   # ensure we have the new status folder
   mkdir ("$folder/$phase"); # quick and dirty

   # attempt to move symlink in status-folder
   if (!rename("$folder/$cphase/$task","$folder/$phase/$task")) {
      # unable to move symlink - failure
      $self->{error}="$method: Unable to move symlink in phase-folder: $!";
      return 0;
   }

   # update phase
   if (!$self->taskTag($task,"phase",$phase)) {
      # failed to update task tag - failure of entire operation and move symlink back
      # move symlink back again - no error checking, we fail anyway
      rename ("$folder/$phase/$task","$folder/$cphase/$task"); 
      return 0;
   }

   # success - update success tag
   $status=(defined $status ? $status : $phase);
   $self->taskTag($task,"status",$status);

   # success
   return 1;
}

sub enumTasks {
   my $self=shift;
   my $userid=shift;
   my $datasetid=shift;
   my $status=shift;
   my $retry=shift;
   my $timeout=shift;

   my $method=(caller(0))[3];

   # uppercase status if it is defined
   $status=(defined $status ? uc($status) : $status);

   my $folder=$self->folder();
   my $delim=$self->delimiter();
   my $qdelim=qq($delim);

   # check values
   if ((defined $userid) && ($userid !~ /\d+/)) {
      # invalid userid
      $self->{error}="$method: Invalid userid specified.";
      return undef;
   }

   if ((defined $datasetid) && ($datasetid !~ /\d+/)) {
      # invalid datasetid
      $self->{error}="$method: Invalid dataset id specified.";
      return undef;
   }

   if ((defined $retry) && ($retry !~ /\d+/)) {
      # invalid retry
      $self->{error}="$method: Invalid retry value specified.";
      return undef;
   }

   if ((defined $timeout) && ($timeout !~ /[\d+\.]+/)) {
      # invalid retry
      $self->{error}="$method: Invalid timeout value specified.";
      return undef;
   }

   if (opendir DH,"$folder") {
      # read file content of folder, only get the right file types (userid datasetid random).
      my @tasks=grep { $_ !~ /^(\.|\..)$/ && $_ =~ /^\d+$qdelim\d+$qdelim[A-Za-z0-9]{32}$/ } readdir DH;
      closedir (DH);

      # return task hash
      my %restasks;
 
      # go through each task and pick the ones that are of interest
      foreach (@tasks) {
         my $task=$_;

         # get task files (tags)
         my $files=$self->getTaskFiles($task);

         if (!defined $files) { next; }

         my ($uid,$dsid,$random)=split($delim,$task);

         # attempt to get task tags and set valid values
         my $falive=$self->taskTag($task,"alive") || 0;
         $falive=~s/[^\d\.]//g;
         $falive=$falive || 0;
         my $stat=$self->taskTag($task,"status") || "";
         my $retr=$self->taskTag($task,"retry") || 0;
         $retr=~s/[^\d]//g;
         $retr=$retr || 0;     
        
         my $match=1;
         # the task must match all (AND) criterias specified as input to method
         if ((defined $userid) && ($uid != $userid)) { $match=0; }
         if ((defined $datasetid) && ($dsid != $datasetid)) { $match=0; }
         if ((defined $status) && (defined $stat) && ($stat ne $status)) { $match=0; }
         if ((defined $retry) && (defined $retr) && ($retr >= $retry)) { $match=0; }
         if ((defined $timeout) && (defined $falive) && (($falive+$timeout) > time())) { $match=0; }
         
         # if we have overall match - add it to the LIST
         if ($match) { 
            # save taskid
            $restasks{$task}{random}=$random;            
            $restasks{$task}{userid}=$uid;            
            $restasks{$task}{datasetid}=$dsid;
            # add any tags existing    
            foreach (@{$files}) {
               my $file=$_;

               if ($file =~ /^([a-z]+)\_(.*)$/) {
                  # this is a tag - add it
                  my $tag=$1;
                  my $value=$2;
                  $restasks{$task}{tags}{$tag}=$value;
               }
            }
         }
      }

      return \%restasks;
   } else {
      # failure to read directory
      $self->{error}="$method: Unable to open and read folder $folder: $!";
      return undef;
   }
}

# task is elevated outside and
# beyond the distribution-queue 
# and is no more reachable by this module
sub raptureTask {
   my $self=shift;
   my $task=shift;

   my $method=(caller(0))[3];

   my $folder=$self->folder();
   my $delim=$self->delimiter();
   my $qdelim=qq($delim);

   my $RAPTURE="._raptured";

   if ((!defined $task) || ($task !~ /^\d+$qdelim\d+$qdelim[A-Za-z0-9]{32}$/)) {
      $self->{error}="$method: Task parameter not defined or wrong format.";
      return 0;
   }

   # get task files 
   my $files=$self->getTaskFiles($task);
   if (!defined $files) {
      # something failed - error already set
      return 0;
   }

   # put task into tmp state
   if (!rename("$folder/$task","$folder/.$task")) {
      # unable to rename folder
      $self->{error}="$method: Unable to move task $task into temporary state for pending rapture: $!";
      return 0;
   }

   # found files - lets get phase, so we can remove symlink there first
   my @phasefile=grep { $_ =~ /^phase\_.*$/ } @{$files};
 
   if (defined $phasefile[0]) {
      # remove phase symlink
      my $phase=$phasefile[0]; 
      $phase=~s/^phase\_(.*)$/$1/;
      unlink ("$folder/$phase/$task");
   } else { 
      # could not locate phase, attempt to check all phase folders
      if (opendir (DH,"$folder/")) {
         # get all existing phases
         my @phases=grep { $_ =~ /^[A-Z]+$/ && -d "$folder/$_" } readdir DH;
         closedir DH;
         # go through each phase and remove the task from all that have it
         foreach (@phases) {
            my $phase=$_;

            if (-l "$folder/$phase/$task") { unlink ("$folder/$phase/$task"); }
         }
      }
   }

   # create the location for the raptured
   # tasks if it is not created already
   mkdir ("$folder/$RAPTURE");

   # we are ready to elevate task outside of the queue
   if (!rename ("$folder/.$task","$folder/$RAPTURE/$task")) {
      $self->{error}="$method: Unable to move task $task for rapture: $!";
      return 0;
   }

   # if here, then success
   return 1;
}

sub getTaskFiles {
   my $self=shift;
   my $task=shift;
   my $tmp=shift || 0; # task folder in tmp-mode. Only internal use!

   my $method=(caller(0))[3];

   my $folder=$self->folder();
   my $delim=$self->delimiter();
   my $qdelim=qq($delim);

   if ((!defined $task) || ($task !~ /^\d+$qdelim\d+$qdelim[A-Za-z0-9]{32}$/)) {
      $self->{error}="$method: Task parameter not defined or wrong format.";
      return undef;
   }

   my $dot=($tmp ? "." : "");

   if (opendir (DH,"$folder/$dot$task")) {
      my @files=grep { $_ !~ /^\.{1,2}$/ } readdir DH;
      closedir (DH); 
      # return the files found
      return \@files;
   } else {
      # failed to open folder
      $self->{error}="$method: Unable to open folder $folder/$dot$task for reading: $!";
      return undef;
   }
}

sub getTaskRandomID {
   my $self=shift;
   my $task=shift;

   my $method=(caller(0))[3];

   my $delim=$self->delimiter();
   my $qdelim=qq($delim);

   if ((!defined $task) || ($task !~ /^\d+$qdelim\d+$qdelim[A-Za-z0-9]{32}$/)) {
      $self->{error}="$method: Task parameter not defined or wrong format.";
      return undef;
   }

   my ($userid,$datasetid,$random)=split($delim,$task);

   return $random;
}

sub getTaskUserID {
   my $self=shift;
   my $task=shift;

   my $method=(caller(0))[3];

   my $delim=$self->delimiter();
   my $qdelim=qq($delim);

   if ((!defined $task) || ($task !~ /^\d+$qdelim\d+$qdelim[A-Za-z0-9]{32}$/)) {
      $self->{error}="$method: Task parameter not defined or wrong format.";
      return undef;
   }

   my ($userid,$datasetid,$random)=split($delim,$task);

   return $userid;
}

sub getTaskDatasetID {
   my $self=shift;
   my $task=shift;

   my $method=(caller(0))[3];

   my $delim=$self->delimiter();
   my $qdelim=qq($delim);

   if ((!defined $task) || ($task !~ /^\d+$qdelim\d+$qdelim[A-Za-z0-9]{32}$/)) {
      $self->{error}="$method: Task parameter not defined or wrong format.";
      return undef;
   }

   my ($userid,$datasetid,$random)=split($delim,$task);

   return $datasetid;
}


sub folder {
   my $self=shift;

   if (@_) {
      # this is a set
      my $folder=shift;
      $self->{pars}{folder}=$folder;
      return $folder;
   } else {
      # this is a get
      return $self->{pars}{folder};
   }
}

sub delimiter {
   my $self=shift;

   if (@_) {
      # this is a set
      my $delim=shift;
      $self->{pars}{delimiter}=$delim;
      return $delim;
   } else {
      # this is a get
      return $self->{pars}{delimiter};
   }
}

sub error {
   my $self=shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<DistributionQueue> - Module to handle an AURORA distribution queue.

=cut

=head1 SYNOPSIS

   use DistributionQueue;

   # instantiate
   my $q=$DistributionQueue->new();

   # add a task
   my $userid=3;
   my $datasetid=104;
   my $data="WhatEverWeWant";
   my $task=$q->addTask($userid,$datasetid,$data);

   # add task with optional tags
   my $task=$q->addTask($userid,$datasetid,$data,mytag=>"value",myothertag=>"value");
   
   # show added task id
   if (defined $task) {
      print "New task ID: $task\n";
   }

   # enumerate tasks
   my $tasks=$q->enumTasks();
   if (defined $tasks) {
         print Dumper($tasks);
   }

   # change task phase to DISTRIBUTING
   $q->changeTaskPhase($task,"DISTRIBUTING");

   # get a task tag value
   my $value=$q->taskTag($task,"alive");

   # set a task tag value
   $q->taskTag($task,"alive",time());

   # get task data
   my $data=$q->getTaskData($task);

   # remove a task
   $q->removeTask($task);

=cut

=head1 DESCRIPTION

Module to handle an AURORA distribution queue. It enables to create new tasks, move tasks between various 
phases, read and write task tags, enumerate all tasks or tasks based on userid, datasetid, status, 
retry and/or timeout tags, remove tasks, get task data.

Each added task will create a folder and file hierarchy like thus:

  /distributions/
  /distributions/taskid/
  /distributions/taskid/DATA (the data to operate on)
  /distributions/taskid/phase_VALUE (the phase that the distribution is in)
  /distributions/taskid/status_VALUE (the status the task has)

  /distributions/INITIALIZED/taskid -> ../taskid   (phase folder with symlink to actual task folder)
  /distributions/ACQUIRING/taskid -> ../taskid     (phase folder)
  /distributions/DELETING/taskid -> ../taskid      (phase folder)
  /distributions/DISTRIBUTING/taskid -> ../taskid  (phase folder)
  /distributions/FAILED/taskid -> ../taskid        (phase folder)

The various tags set on a task will be read out when enumerating the tasks. They can also be read or updated by
using the taskTag()-method.

A specific task will only exist in B<one> of the phase folders above at a time and move between them by 
using the changeTaskPhase()-method.

=cut

=head1 CONSTRUCTOR

=head2 new()

Module constructor. Instantiates a DistributionQueue-class.

Possible options are:

=over

=item

B<folder> Folder where the distribution queue is located. Defaults to /local/app/aurora/distributions.

=cut

=item

B<delimiter> Delimiter between the values in task identifier. Defaults to comma ",".

=cut

=back

Returns an instantiated class.

=cut

=head1 METHODS

=head2 addTask()

Adds a task to the distribution queue.

Input parameters are in the following order:

=over

=item

B<userid> Userid of the user that initiated this task. Required.

=cut

=item

B<datasetid> Dataset id of the dataset that this task operates on. Required.

=cut

=item

B<data> Data associated with the task. This is the data used to perform the task. Required.

=cut

=item

<tags> A HASH with optional tag=>value(s) for the task. Will be added at the same time as the other information ensuring 
the tags are there when the task is moved into production.

=cut

=back

It will add the task in the distribution folder and put it into the INITIALIZED status awating to start 
another phase (controlled by the user of the module).

Returns task id upon success, undef upon failure. Please see the error()-method for more information 
upon failure.

=cut

=head2 removeTask()

Removes a task from the distribution queue.

Input is the task id to remove from the distribution queue.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

The method will remove all traces of the task, including its tags, data and so on. It will even attempt to 
locate the phase-symlink if the phase tag does not exist and remove it.

=cut

=head2 getTaskData()

Gets the operational data of the task.

Input is the task id to get the data on.

Return value is the data upon success, undef upon failure. Please check the error()-method for more 
information upon failure.

=cut

=head2 taskTag()

Gets or sets a task tag.

Input is the task id and the tag name. 

Returns the tag value on both get and set, undef upon failure. Please call the error()-method for more 
information upon a failure.

All tag names are lower case and all attempt at adding tags with other cases will be changed to lower case. The 
value can be any allowable character for a POSIX file.

Do not attempt to change the task tag "phase" yourself from this method. It is recommended to instead call the
changeTaskPhase()-method that will handle it in the correct manner. If you do change it yourself, expect possible 
unwanted side-effects.

=cut

=head2 taskFile()

Adds a task file and its information

Input is in the following order: task, name and data.

Task is the id of the task, name is the name of the file to create in the task and data is the content of the newly created file. Any 
existing file is overwritten.

The method return 1 upon success and 0 on failure. Please check the error()-method upon failure...

=cut

=head2 changeTaskPhase()

Changes a tasks phase and status from one phase to another and moving the symlink and updating the phase and status tag.

Input is the task id and the new phase to set on it. Optionally a diverging status can be specified if it 
is different than the phase. Or else the status-tag is set to the same as the phase. In addition the last 
parameter to the method is "samephase". If set to false/0 it will not accept changing a phase from the 
same phase as the current phase and in so doing act as if it is atomic, preventing other processes to 
change the phase at the same time and thereby continue running. Default behaviour is to accept same 
phase change, so if option is to be used it must be set to a value that evaluates to false, eg. 0.

Returns the 1 upon success, 0 upon failure. Please call the error()-method for more information upon a 
failure.

The method moves the symlink file between the phase-folders and updates the phase- and status- tags.

=cut

=head2 enumTasks()

Enumerates either all tasks that exists or moderated by input parameters.

Possible input parameters are in the following order:

=over

=item

B<userid> Only match tasks that have this userid. Can be undefined.

=cut

=item

B<datasetid> Only match tasks that have this datasetid. Can be undefined.

=cut

=item

B<status> Only match tasks that have this current status in the status tag. Can be undefined.

=cut

=item

B<retry> Maximum retry. Only match tasks that have been retried less than this many times. Can be undefined.

=cut

=item

B<timeout> Time before a task times out when not having updated its alive-tag. Only match tasks where 
the alive tag time + timeout-option is less than current time. In other words the alive tag has not been updated 
after the timeout periode expired. The timeout value is specified in seconds. Can be undefined. 

=cut

=back

All these parameters will be and'ed together if specified. Returned datasets will need to match all specified 
parameter settings.

The method will return a HASH-reference upon success, undef upon failure. Please call the error()-method for 
more information upon failure.

The resulting HASH-structure is like this:

   (
      taskid => { userid => ID,
                  datasetid => ID,
                  random => RANDOMSTRING,
                  tags => { phase => INITIALIZED (or whatever other phase the user uses)
                            status => INITIALIZED (or whatever other status the user uses)
                            tagX => VALUE,
                            tagY => VALUE,
                          },
                }
   )

Not all of these parameters are necessarily present at once. The user of the class can add any tag(s) he wants.

This method has a special handling of the alive- (moderated by the timeout-option), status- (moderated by 
the status-option) and retry- (moderated by the retry-option) tags.

=cut

=head2 raptureTask()

Moves a task outside and beyond the distribution queue.

Input is the task id to rapture from the distribution queue.

The tasks phase-link is removed and the task is then moved into the rapture folder "._rapture". 
There it is not visible anymore for the DistributionQueue-module. This is something that can be 
done to tasks that are eg. failed for some reason or other.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

=cut

=head2 getTaskFiles()

Gets a tasks files, including DATA-file and tag-files (not . and ..).

Input is the task id.

Return value is LIST-reference with the filenames upon success, or undef upon failure. Please call the 
error()-method for more information upon failure.

=cut

=head2 getTaskRandomID()

Gets the tasks unique and random ID.

Input is the usual task id.

Returns the random ID upon success, undef upon failure. Please call the error()-method for more information upon failure.

The task random ID is the last 32 characters in the task id. These 32 characters are random and should be unique.

=cut

=head2 getTaskUserID()

Gets the ID of user that owns the task.

Input is the usual task id.

Returns the user ID upon success, undef upon failure. Please call the error()-method for more information upon failure.

=cut

=head2 getTaskDatasetID()

Gets the dataset ID associated with the task.

Input is the usual task id.

Returns the dataset ID upon success, undef upon failure. Please call the error()-method for more information upon failure.

=cut

=head2 folder()

Sets or gets the folder where the distribution queue is.

On get there is no accepted input. On set there is the folder location to set.

Return value is always the folder-value.

=cut

=head2 delimiter()

Sets or gets the delimiter used for the task id.

On get there is no accepted input. On set there is the delimiter to set.

Return value is always the delimiter.

=cut

=head2 error()

Gets the last error string.

No input is accepted.

Returns the last error of the module.

=cut
