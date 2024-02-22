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
# STORESRVC: AURORA service to handle running StoreCollections of Store-classes on datasets
#
use strict;
use lib qw(/usr/local/lib/aurora);
use AuroraVersion;
use Schema;
use SysSchema;
use POSIX;
use AuroraDB;
use Settings;
use SystemLogger;
use Log;
use Not;
use Time::HiRes qw(time);
use StoreCollection;
use DistributionQueue;
use FileInterface;
use Store::RSyncSSH;
use Store::FTP;
use Store::SFTP;
use Store::SCP;
use Store::SMB;
use DistLog;
use fiEval;
use Sys::Hostname;
use RestTools;
use MetadataCollection;
use DBD::SQLite::Constants ':dbd_sqlite_string_mode';
use Data::Dumper;

our %CHILDS;

# version constant
my $VERSION=$AuroraVersion::VERSION;

# to be used with setsid
require "syscall.ph"; 

$SIG{HUP}=\&signalHandler;

# get hostname
my $HOSTNAME=uc(hostname());

# set base name
my $BASENAME="$0 AURORA Store-Service";
# set parent name
$0=$BASENAME." Daemon";
# set short name
my $SHORTNAME="STORESRVC $HOSTNAME";

# set debug level
my $DEBUG="INFO";

# set loglevels
my %LEV = (
   "DEBUG" => 0,
   "INFO"  => 1,
   "WARN"  => 2,
   "ERROR" => 3,
   "FATAL" => 4,
);

# get command line options (key=>value)
my %OPT=@ARGV;
%OPT=map {uc($_) => $OPT{$_}} keys %OPT;
# see if user has overridden debug setting
if (exists $OPT{"-D"}) { 
   my $d=$OPT{"-D"} || "INFO";
   $DEBUG=$d;
}

# instantiate syslog logger
my $L=SystemLogger->new(ident=>$BASENAME,priority=>$DEBUG);
if (!$L->open()) { die "Unable to open SystemLogger: ".$L->error(); }

# settings instance
my $CFG=Settings->new();
$CFG->load();

print "$BASENAME, version $VERSION, Copyright(C) 2019 NTNU\n\n";

# turn off buffering on stdout because of sleep
$| = 1; 

# loop until killed
while (1) {
   # dist queue instance
   my $dq=DistributionQueue->new(folder=>$CFG->value("system.dist.location"));

   # get datasets to work on
   my $timeout=$CFG->value("system.dist.timeout") || 86400;
   my $maxretry=$CFG->value("system.dist.maxretry") || 2;

   # get distributions that are inits, timed out or failed in status tag (not phase-tag).
   my $inits=$dq->enumTasks(undef,undef,$SysSchema::C{"phase.init"});
   my $atimeouts=$dq->enumTasks(undef,undef,$SysSchema::C{"phase.acquire"},undef,$timeout);
   my $dtimeouts=$dq->enumTasks(undef,undef,$SysSchema::C{"phase.dist"},undef,$timeout);
   my $deltimeouts=$dq->enumTasks(undef,undef,$SysSchema::C{"phase.delete"},undef,$timeout);
   my $failed=$dq->enumTasks(undef,undef,$SysSchema::C{"status.failed"},$maxretry,$timeout);

   # combine the three and start fork'in
   my %dists=(%{$inits},%{$atimeouts},%{$dtimeouts},%{$deltimeouts},%{$failed});
#print "TASKS: ".Dumper(\%dists)."\n\n";
   foreach (keys %dists) {
      my $task=$_;

      # get dataset id
      my $did=$dists{$task}{datasetid} || undef;

      # get random task id
      my $taskid=$dq->getTaskRandomID($task);

      my $pid=fork();
      if ($pid == 0) {
         # inside child - set fork anme
         $0=$BASENAME." FORK TASK: $task";
         %CHILDS=();
         # do some checks and cleanup. If task is still in dist- or acquire-phase, something
         # has gone wrong and child has not cleaned up and timed out. First we attempt to clean away child
         my $cpid=$dists{$task}{tags}{pid} || 0;
         my $cctime=$dists{$task}{tags}{ctime} || 0;
         my $retry=$dists{$task}{tags}{retry} || -1;
         my $ccmd=$dists{$task}{tags}{cmdline} || "";

         if ($cpid != 0) {
            # this is a task that has timed out or not cleaned itself up properly, do some house-cleaning
            # set alive tag to avoid multiple forks
            $dq->taskTag($task,"alive",time());
            my $running=1;
            my $ccctime=(stat "/proc/$cpid/stat")[10] || 0; # get current possible change time of pid
            my $cccmd=getFileData("/proc/$cpid/cmdline") || "";
            if (($ccctime == 0) || ($cccmd ne $ccmd)) { $running=0; } # this process has already been stopped
            if ($running) {
               # process is still running, but we want to stop it
               my $killed=0;
               # attempt soft-kill group
               my $arg=kill("-TERM",$cpid);
               # wait for soft kill
               my $ttimeout=time()+($CFG->value("system.dist.killwait") || 10); # get killwait setting or use 10 sec
               while (1) {
                  my $ctime=(stat "/proc/$cpid/stat")[10] || 0;
                  my $cmd=getFileData("/proc/$cpid/cmdline") || "";
                 
                  if ((!defined $cmd) || (time() > $ttimeout)) { last; } # killed or timed out wait
               }  
               # check if it is gone - if not hard kill
               $ccctime=(stat "/proc/$cpid/stat")[10] || 0;
               $cccmd=getFileData("/proc/$cpid/cmdline") || "";
               if ($cccmd eq $ccmd) { # matches what we know from before, hard-kill group
                  my $arg=kill("-KILL",$cpid);
               } else { $killed=1; }

               if (!$killed) {
                  # wait for kill
                  while (1) {
                     my $ctime=(stat "/proc/$cpid/stat")[10] || 0;
                     my $cmd=getFileData("/proc/$cpid/cmdline") || "";

                     if ((!defined $cmd) || (time() > $ttimeout)) { last; } # killed or timed out wait
                  } 
                  # check if process is killed or not
                  $ccctime=(stat "/proc/$cpid/stat")[10] || 0;
                  $cccmd=getFileData("/proc/$cpid/cmdline") || "";
                  if ($cccmd eq $ccmd) {
                     # unable to kill or still waiting - skipping this task for the moment
                     dbLogger ($did,"Unable to kill process $cpid for task $taskid. Skipping rerunning task for this iteration.","ERROR");
                     exit(0); # skip this one
                  } 
               }
               # process is killed, we can proceed
               dbLogger ($did,"Process $cpid for task $taskid was killed succesfully due to timeout. Will attempt to rerun task.","INFO");
            }  
         } 
         # check if retry has been exhausted
         if ($retry >= $maxretry) {
            # we have exhausted the retries - change to failed
            $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
            # message user about failed distribution task
            my $not=Not->new();
            $not->send(type=>"distribution.acquire.failed",about=>$did,from=>$SysSchema::FROM_STORE,
                       message=>"Hi,\n\nDistribution task $taskid has failed for the last time (retry=$maxretry) on dataset with id $did.".
                                "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                                "\n\nBest regards,\n\n   Aurora System");
            dbLogger ($did,"Distribution task $taskid failed for the last time (retry=$maxretry) on dataset with id $did and has been moved to FAILED-phase. Manual intervention needed. Notification sent.","FAILED");
            exit(0); # skip this one...
         }

         # new process - set it as session leader
         my $ret=syscall (SYS_setsid());
         if ($ret == -1) { exit(0); } # failed to set group=pid, so skip

         # get the todo tag
         my @todo=split(",",$dists{$task}{tags}{todo});
         if (@todo > 0) { # we must have something todo, or we end it for this task
            if ($todo[0] eq $SysSchema::C{"phase.acquire"}) {
               do_acquire($task,$dists{$task});
            } elsif ($todo[0] eq $SysSchema::C{"phase.dist"}) {
               do_dist($task,$dists{$task});
            } elsif ($todo[0] eq $SysSchema::C{"phase.delete"}) {
               do_delete($task,$dists{$task});
            } 
         } else {
            # no more todos - remove task
            $dq->removeTask($task);
         }
         # child finished
         exit(0);
      } elsif (defined $pid) {
         # cleanup parent side of fork
         # save pid to list
         $CHILDS{$pid}=undef;
         # reap children
         $SIG{CHLD}=sub { foreach (keys %CHILDS) { my $p=$_; next if defined $CHILDS{$p}; if (waitpid($p,WNOHANG) > 0) { $CHILDS{$p}=$? >> 8; } } };
      } else {
         # some fork'in failure
         dbLogger ($did,"Failed to fork a child for handling task $taskid: $!","ERROR");
      }
   }

   sleep (120); 
}

sub getFileData {
   my $name=shift||"/tmp/dummy";

   if (open FH,"$name") {
      # file opened successfully - read its content
      my $content = join("",<FH>);
      # clean away newline and carriage return
      # and \000 as well as slash
      $content =~ s/[\r\n\/\000]//g;
      # close the file
      eval { close (FH); };
      # return result
      return $content;
   } else {
      return undef;
   }
}

sub do_acquire {
   my $task=shift; # get task id
   my $info=shift; # get task info

   # set subprocess name
   $0=$BASENAME." ACQ TASK: $task";

   # get dataset id
   my $id=$info->{datasetid} || 0;

   # dist queue instance
   my $dq=DistributionQueue->new(folder=>$CFG->value("system.dist.location"));

   # get task random id or id.
   my $taskid=$dq->getTaskRandomID($task);

   dbLogger ($id,"In acquire-fork on task $taskid","DEBUG");

   # get user name that owns the task
   my $uid=$info->{userid} || 0;

   # attempt to change phase to ensure that we have the acquire - we do not accept change to same
   # phase name and thereby we stop other processes from running.
   if (!$dq->changeTaskPhase($task,$SysSchema::C{"phase.acquire"},undef,0)) {
      # we do not have the acquire - exit
      dbLogger($id,"Unable to change phase for task $taskid to ".$SysSchema::C{"phase.acquire"}.": ".$dq->error(),"FATAL");
      return 0;
   }

   # we have the acquire phase

   # set alive tag
   $dq->taskTag($task,"alive",time());

   # get own pid and ctime
   my $pid=$$;
   my $ctime=(stat "/proc/$pid/stat")[10] || 0;
   # save it on the task
   $dq->taskTag($task,"pid",$pid);
   $dq->taskTag($task,"ctime",$ctime);
   my $ccmd=getFileData("/proc/$pid/cmdline") || "";
   $dq->taskTag($task,"cmdline",$ccmd);   

   # update retry counter right away - this is a valid attempt
   my $retry=$dq->taskTag($task,"retry");
   $retry=(defined $retry ? $retry : -1);
   $retry++;
   $dq->taskTag($task,"retry",$retry);

   # get maxretry setting
   my $maxretry=$CFG->value("system.dist.maxretry") || 2;

   # notify log
   dbLogger ($id,"Performing acquire on task $taskid.");

   # connect to database
   # database instance
   my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                        pw=>$CFG->value("system.database.pw"));

   # abort if no database connection
   if (!$db->getDBI()) {
      dbLogger ($id,"Database connection error while acquiring on task $taskid: ".$db->error(),"FATAL");
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its acquire-phase for the last time (retry=$maxretry) on dataset with id $id. We are unable to connect to database: ".$db->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});
      }
      return 0;
   }

   # get metadata of dataset
   my $dataset=$db->getEntityMetadata($id);
   if (!defined $dataset) {
      # some failure
      dbLogger ($id,"Unable to get metadata for dataset while acquiring on task $taskid: ".$db->error(),"FATAL");
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its acquire-phase for the last time (retry=$maxretry) on dataset with id $id. We are unable to get dataset metadata: ".$db->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }
      return 0;
   }

   # check that dataset status is not closed
   if ($dataset->{$SysSchema::MD{"dataset.status"}} eq $SysSchema::C{"status.closed"}) {
      # dataset is already closed. Not allowed to get more data on it
      dbLogger ($id,"Unable to store more data on dataset in task $taskid. It is already closed. Moving task to FAILED.","FATAL");
      # this is a complete fatal event, move task to failed
      $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});

      # message user about failed distribution task
      my $not=Not->new();
      $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                 message=>"Hi,\n\nDistribution task $taskid has failed fatally its acquire-phase on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")." because dataset is already closed and cannot store more data.".
                          "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                          "\n\nBest regards,\n\n   Aurora System");
      return 0;
   }

   # get user metadata
   my $umd=$db->getEntityMetadata($uid);
   # check that we got the user metadata, or else fail
   if (!defined $umd) {
      # Something failed getting user metadata
      dbLogger ($id,"Unable to get user metadata for user $uid: ".$db->error().". Moving task $taskid to FAILED.","FATAL");
      # this is a complete fatal event, move task to failed
      $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});

      # message user about failed distribution task
      my $not=Not->new();
      $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                 message=>"Hi,\n\nDistribution task $taskid has failed fatally its acquire-phase on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")." because it were unable to get metadata of executing user: $uid.".
                          "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                          "\n\nBest regards,\n\n   Aurora System");
      return 0;
   }

   # get task data
   my $yaml=$dq->getTaskData($task);

   # convert to hash
   my $c=Content::YAML->new();

   if (!defined $c->decode($yaml)) {
      # something failed
      dbLogger ($id,"Unable to decode task data while acquiring on task $taskid: ".$c->error(),"FATAL");
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A").". Unable to decode task data while acquiring: ".$c->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }

      return 0;
   }

   # successfully decoded - get decoded hash
   my $data=$c->get();

   # we have the task data...start to prepare the get-operation and create data area

   # create fiEval-instance
   my $ev=fiEval->new();
   if (!$ev->success()) {
      # unable to instantiate
      dbLogger ($id,"Unable to instantiate fiEval: ".$ev->error(),"FATAL");
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). We are unable to instantiate fiEval: ".$ev->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }

      return 0;     
   }

   dbLogger ($id,"Opening storage area for dataset while acquiring in task $taskid.","DEBUG");

   # check if data area is already created
   if (!$ev->evaluate("datapath",$id)) {
      # data area does not exist - create
      my $parent=$dataset->{$SysSchema::MD{"entity.parent"}}||0;
      if ((!$ev->evaluate("create",$id,$uid,$parent)) || ($ev->evaluate("mode",$id) ne "rw")) {
         my $err=": ".$ev->error();
         dbLogger ($id,"Unable to create storage area in RW-mode for dataset while acquiring on task $taskid$err.","FATAL");
# attempt cleanup storage
# dbLogger ($id,"Flagging dataset $id for removal due to error in task $taskid.","DEBUG");
# $ev->evaluate("remove",$id); 
         # check retry
         if ($retry >= $maxretry) {
            # exhausted our retries - move to failed.
            $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
            # message user about failed distribution task
            my $not=Not->new();
            $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                       message=>"Hi,\n\nDistribution task $taskid has failed for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). We are unable to open storage area in RW-mode: $err".
                                "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                                "\n\nBest regards,\n\n   Aurora System");

         } else {
            # we will try again - move to init
            $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});
         }

         return 0;
      }
   }

   # we have a rw storage area - get path
   my $spath=$ev->evaluate("datapath",$id);
   # ensure we have a spath with a ending slash, many Store-classes are picky on this
   if ($spath !~ /^.*\/$/) { $spath .= "/"; }

   # enumerate Store-classes
   my $ids=$db->enumEntitiesByType (\@{[($db->getEntityTypeIdByName("STORE"))[0]]});

   if (!defined $ids) {
      # something failed enumerating STORE-entities - we have to abort acquire
      dbLogger ($id,"Unable to enumerate STORE-entities: ".$db->error(),"FATAL");
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). We are unable to enumerate Store-entities: ".$db->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }

      return 0;      
   }

   my %stores;
   foreach (@{$ids}) {
      my $s=$_;

      # get store metadata
      my $smd=$db->getEntityMetadata($s);

      if (!defined $smd) {
         # failed to get metadata for Store - must abort
         dbLogger ($id,"Unable to get metadata for STORE $s: ".$db->error(),"FATAL");
         # check retry
         if ($retry >= $maxretry) {
            # exhausted our retries - move to failed.
            $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
            # message user about failed distribution task
            my $not=Not->new();
            $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                       message=>"Hi,\n\nDistribution task $taskid has failed for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). We are unable to get metadata for STORE $s: ".$db->error().
                                "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                                "\n\nBest regards,\n\n   Aurora System");

         } else {
            # we will try again - move to init
            $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});
         }

         return 0;
      }

      # success - get relevant details
      $stores{$s}{id}=$s;
      $stores{$s}{class}=$smd->{$SysSchema::MD{"store.class"}};
   }

   # must have 1 or more get-operations
   if (keys %{$data->{get}} == 0) {
      dbLogger ($id,"Task $taskid does not have any acquire-operations defined. Unable to proceed.","FATAL");
# attempt to remove dataset
# $ev->evaluate("remove",$id);
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its acquire-phase for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). No acquire-operations have been defined. ".
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});
      } 
      return 0;
   }

   # go through each get-operation and input necessary 
   # data before attempting to run them...
   my $ok=1;
   foreach (sort {$a <=> $b} keys %{$data->{get}}) {
      my $no=$_;

      # get computer id, if any
      my $computer=$data->{get}{$no}{computer} || 0;
      # get computer description, if any
      my $computername=$data->{get}{$no}{computername} || "";
      # get user path
      my $userpath=$data->{get}{$no}{param}{remote} || "/";

      # check if user has COMPUTER_READ on computer in question
      if (!hasPerm($db,$uid,$computer,["COMPUTER_READ"],"ALL","ANY",1,1,undef,1)) {
         # user does not have the necessary permissions on this computer, we have to abort.
         dbLogger ($id,"User $uid does not have the COMPUTER_READ permission on computer $computer. Unable to continue acquire operation $taskid.","ERROR");
         $ok=0;
         last;
      }

      # get template of computer
      my $templ=$db->getEntityTemplate(($db->getEntityTypeIdByName("COMPUTER"))[0],$db->getEntityPath($computer));
      if (!defined $templ) {
         dbLogger ($id,"Unable to get template of computer $computer. Unable to continue acquire operation $taskid.","ERROR");
         $ok=0;
         last;
      }

      # ensure that host-info comes from computer in question
      my $cmd=$db->getEntityMetadata($computer);
      if (!defined $cmd) {
         dbLogger ($id,"Unable to get metadata on computer $computer. Unable to continue acquire operation $taskid.","ERROR");
         $ok=0;
         last;
      }

      # merge template and computer for raw use
      my %tc=(%{$templ},%{$cmd});

      # get metadatacollection data from template and computer
      my $mc=MetadataCollection->new(base=>$SysSchema::MD{"computer.task.base"});
      # make store collection hash from template
      my $thash=$mc->template2Hash($templ);
      # make store collection hash from computer metadata
      my $chash=$mc->metadata2Hash($cmd);
      # merge template and computer metadata hashes, computer having precedence
      my $mdcoll=$mc->mergeHash($thash,$chash);

      # merge metdata into data
      foreach (keys %{$mdcoll->{param}}) {
         my $name=$_;
         my $value=$mdcoll->{param}{$name};
         $data->{get}{$no}{param}{$name}=$value;
      }

      # merge metadata classparam into data
      foreach (keys %{$mdcoll->{classparam}}) {
         my $name=$_;
         my $value=$mdcoll->{classparam}{$name};
         $data->{get}{$no}{classparam}{$name}=$value;
      }

      # ensure sensible values on host and remote
      my $host=$mdcoll->{param}{host}||"0.0.0.0";
      my $cpath=$tc{$SysSchema::MD{"computer.path"}};
      my $user=($tc{$SysSchema::MD{"computer.useusername"}} ? $umd->{$SysSchema::MD{"username"}}."/" : "");

      # overwrite any value in host
      $data->{get}{$no}{param}{host}=$host;
      # ensure correct value in remote
      $data->{get}{$no}{param}{remote}=$SysSchema::CLEAN{pathsquash}->($cpath."/$user".$userpath);
   }

   if (!$ok) {
      # we failed to setup the get-operations, abort...
      dbLogger ($id,"Unable to successfully setup all acquire-operations in task $taskid.","FATAL");

      # $ev->evaluate("remove",$id);

      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its acquire-phase for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). We are unable to successfully setup all acquire-operations. Please check the dataset-log for more information on the failure.".
                             "\n\nYour dataset-log can be viewed by going to the AURORA web site here:".
                             "\n\n".$CFG->value("system.www.base").
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      } 
#      dbLogger ($id,"Finished cleaning up after failed acquire-operations for task $taskid.","DEBUG");

      return 0;
   }

   # disconnect database to avoid timeout issues
   $db=undef;

   dbLogger ($id,"Executing acquire-operations for dataset in task $taskid.","DEBUG");

   # iterate over get stores
   my $success=1;
   my $log;
   my $failmsg="";
   my $totalsize=0;
   foreach (sort {$a <=> $b} keys %{$data->{get}}) {
      my $no=$_;

      # get computer id, if any
      my $computer=$data->{get}{$no}{computer} || 0;
      # get computer description, if any
      my $computername=$data->{get}{$no}{computername} || "";
      # get storecollection
      my $sc=$data->{get}{$no}{sc} || 0;

      # get store id
      my $sid=$data->{get}{$no}{store} || 0;

      dbLogger ($id,"Attempting to use store $sid while executing acquire operation $no in task $taskid.","DEBUG");

      # check if it exists
      if (!exists $stores{$sid}) {
         # invalid store - log it and end execution
         dbLogger ($id,"Store $sid does not exist. Unable to execute acquire-operation $no in task $taskid.","ERROR");
         $failmsg="Store $sid does not exist. Unable to execute acquire-operation $no in task $taskid.";
         $success=0;
         last; 
      }

      # get class params
      my %cparams;
      foreach (keys %{$data->{get}{$no}{classparam}}) {
         my $par=$_;
 
         $cparams{$par}=$data->{get}{$no}{classparam}{$par};
      }

      # get store class name
      my $sclass=$stores{$sid}{class} || "";

      # try to instantiate class, add dataset metadata, sandbox location, and use class params
      my $sandbox=$CFG->value("system.sandbox.location") || "/nonexistant";
      my $store=$sclass->new(%cparams,metadata=>$dataset,sandbox=>$sandbox) || undef;

      if (!defined $store) {
         # failed to get an instantiated store class
         dbLogger ($id,"Unable to instantiate store-class $sclass while executing acquire operation $no on task $taskid","ERROR");
         $failmsg="Unable to instantiate store-class $sclass while executing acquire operation $no on task $taskid.";
         $success=0;
         last; 
      }

      # put params in place
      my %params;
      foreach (keys %{$data->{get}{$no}{param}}) {
         my $param=$_;

         # get the param
         $params{$param}=$data->{get}{$no}{param}{$param};
      }

      # put local parameter in place by setting the storage location
      $params{"local"}=$spath;

      # attempt to open store
      if (!$store->open(%params)) {
         # something failed
         dbLogger ($id,"Unable to open store $no ($sclass) while executing acquire operation $no in task $taskid: ".$store->error(),"ERROR");
         $failmsg="Unable to open store $no ($sclass) while executing acquire operation $no in task $taskid: ".$store->error();
         $success=0;
         last; 
      }

      # we probe store without checking result
      $store->probe();

      dbLogger ($id,"Checking size of data in the acquire-operation $no with store $sclass ($sid) in task $taskid.","DEBUG");

      my $rsize=$store->remoteSize();
      # get store log
      $log=$store->getLog();
      if (!defined $rsize) {
         # unable to get remote size
         dbLogger ($id,"Unable to calculate size of data in acquire-operation $no with store $sclass ($sid) in task $taskid: ".$store->error(),"ERROR");
         $store->close();
         $failmsg="Unable to calculate size of data in acquire-operation $no with store $sclass ($sid) in task $taskid: ".$store->error();
         $success=0;
         last;
      }

      dbLogger ($id,"Size of data in acquire-operation $no with store $sclass ($sid) in task $taskid: ".size($rsize)." ($rsize Byte(s))","DEBUG");

      # we are ready to run store by invoking get-method
      dbLogger ($id,"Executing acquire-operation $no with store $sclass ($sid) in task $taskid.","DEBUG");

      # execute get
      if (!$store->get()) {
         # get store-log
         $log=$store->getLog();
         # get the last 5 log entries as a string
         my $errmsg=$log->getLastAsString(5,"%t: %m ");
         $errmsg=$errmsg || "Unknown reason";
         dbLogger ($id,"Failed to execute acquire-operation $no with store $sclass ($sid) in task $taskid: $errmsg","ERROR");
         $store->close();
         $failmsg="Failed to execute acquire-operation $no with store $sclass ($sid) in task $taskid: $errmsg";
         $success=0;
         last;
      }
      # wait for it to complete and update alive status
      $log=$store->getLog();
      while ($store->isRunning()) { my $alive=$store->alive(); if ((defined $alive) && ($alive > 0)) { $dq->taskTag ($task,"alive",$alive); } sleep(10); }
      # writing the entire transfer log to the AURORA log
      $log->resetNext();
      while (my $entry=$log->getNext()) { dbLogger($id,$entry->[0],"DEBUG","TRANSFER",$entry->[1]); }
      # check success of last store-operation. If not successful - abort the rest.
      if (!$store->success()) {
         # get store-log
#         my $log=$store->getLog();
         # get the last 3 log entries as a string
         my $errmsg=$log->getLastAsString(5,"%t: %m ");
         $errmsg=$errmsg || "Unknown reason";
         dbLogger ($id,"Acquire operation $no with store $sclass ($sid) in task $taskid failed: ".$errmsg,"ERROR"); 
         $store->close();
         $failmsg="Acquire operation $no with store $sclass ($sid) in task $taskid failed: $errmsg";
         # write entire error log to file, for possible inspection
         my $data=$log->getFirstAsString($log->count(),"%t: %m\n");
         # add the store-command that was run
         my $get=$store->getParams();
         $data="COMMAND: ".$get->toString()."\nCLASS-PARAMS: ".Dumper(\%cparams)."\nPARAMS: ".Dumper(\%params)."\n".$data;
         $data=$data."\nFAILURE REASON: $failmsg\n";
         $dq->taskFile($task,"ERROR",$data);
         $success=0;
         last;
      } else {
         dbLogger ($id,"Completed transferring data successfully in acquire operation $no with store $sclass ($sid) in task $taskid. Will attempt to calculate size on local data area.","DEBUG");
         # get local size and compare
         my $lsize=$store->localSize();
         if (!defined $lsize) {
            # failed to get local size
            dbLogger ($id,"Unable to calculate size of local data in acquire-operation $no with store $sclass ($sid) in task $taskid ".$store->error(),"ERROR");
       
            $store->close();
            $failmsg="Unable to calculate size of local data in acquire-operation $no with store $sclass ($sid) in task $taskid ".$store->error();
            $success=0;
            last;
         } 

         dbLogger ($id,"Size of local data in acquire-operation $no with store $sclass ($sid) in task $taskid: ".size($lsize)." ($lsize Byte(s))","DEBUG");

         # check that the two sizes match
         if ($rsize != $lsize) {
            dbLogger ($id,"Sizes of data for acquire-operation $no with store $sclass ($sid) in task $taskid are mismatched between remote ($rsize) and local ($lsize) area.","ERROR");
   
            $store->close();
            $failmsg="Sizes of data for acquire-operation $no with store $sclass ($sid) in task $taskid are mismatched between remote ($rsize) and local ($lsize) area.";
            $success=0;
            last;
         }
         # always close store
         $store->close();
         # add localsize to totalsize
         $totalsize=$lsize;
         # successfullt completed this acquiry operation
         dbLogger ($id,"Successfully executed acquire-operation $no with store $sclass in task $taskid.","DEBUG"); 
         # make distribution log entry
         my $entry=createDistLogEntry(
                                       event=>"TRANSFER",
                                       sc=>$sc,
                                       from=>$sclass,
                                       fromid=>$sid,
                                       fromhost=>$params{"host"},
                                       fromhostid=>$computer,
                                       fromhostname=>$computername,
                                       fromloc=>$params{"remote"},
                                       toloc=>$id,
                                       uid=>$uid
                                     );

         dbLogger($id,$entry,"DEBUG","DISTLOG");
      }
   }

   if (!$success) {
      # not successful - clean up
      dbLogger ($id,"Unable to successfully complete all acquire-operations in task $taskid.","FATAL");


      # check retry
      if ($retry >= $maxretry) {
# $ev->evaluate("remove",$id);
# dbLogger ($id,"We have retried this task $retry time(s). Cleaning up.","DEBUG");

         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its acquire-phase for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). We are unable to successfully complete all acquire-operation. Please check the dataset-log for more information on the failure.".
                             "\n\nYour dataset-log can be viewed by going to the AURORA web site here:".
                             "\n\n".$CFG->value("system.www.base").
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
         # write entire error log to file, for possible inspection
         my $data="";
         if ($log) { $data=$log->getFirstAsString($log->count(),"%t: %m\n"); }
         $data=$data."\nFAILURE REASON: $failmsg\n";
         $dq->taskFile($task,"ERROR",$data);
         # dbLogger ($id,"Finished cleaning up after failed acquire-operations for task $taskid.","DEBUG");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      } 

      return 0;
   }

   dbLogger ($id,"All acquire-operations executed successfully in task $taskid.");

   # connect to database again
   $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

   # abort if no database connection  
   if (!$db->getDBI()) {
      dbLogger ($id,"Database connection error while acquiring in task $taskid: ".$db->error(),"FATAL");
      # remove dataset
# $ev->evaluate("remove",$id);
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its acquire-phase for the last time (retry=$maxretry) on on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). Database connection error: ".$db->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
         # write entire error log to file, for possible inspection
         my $data="";
         if ($log) { $data=$log->getFirstAsString($log->count(),"%t: %m\n"); }
         $data=$data."\nFAILURE REASON: Database connection error while acquiring in task $taskid: ".$db->error()."\n";
         $dq->taskFile($task,"ERROR",$data);
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});
      } 
      return 0;
   }

   # close storage dataset
   if (!$ev->evaluate("close",$id)) {
      my $err=$ev->error();
      dbLogger ($id,"Unable to close storage while acquiring in task $taskid: $err.","FATAL");
# failed to close - remove
# $ev->evaluate("remove",$id);
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its acquire-phase for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). Unable to close storage while acquiring: $err.: ".
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
         # write entire error log to file, for possible inspection
         my $data="";
         if ($log) { $data=$log->getFirstAsString($log->count(),"%t: %m\n"); }
         $data=$data."\nFAILURE REASON: Unable to close storage while acquiring in task $taskid: $err\n";
         $dq->taskFile($task,"ERROR",$data);
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      } 
#      dbLogger ($id,"Finished cleaning up after failed attempt to close storage while acquiring in task $taskid.","DEBUG");
      return 0;
   }

   # success - purge links etc., do not check result
   $ev->evaluate("purge",$id);

   #get template for parent
   my $parent=$db->getEntityParent($id);
   my @tmplpath=$db->getEntityPath($parent);
   my $tmplparent=$db->getEntityTemplate($db->getEntityTypeIdByName("DATASET"),@tmplpath);
   # decide the lifespan based on template from praent
   my $lifespan=(86400*7); # default it to a week to ensure it doesnt just disappear
   my $extendmax=(86400*3); # default maximum to extend per time is 3 days.
   my $extendlimit=(86400*30); # default limit of extension is a month.
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}{default})) {
      $lifespan=$tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}{default};
   }
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.close.extendmax"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.close.extendmax"}}{default})) {
      $extendmax=$tmplparent->{$SysSchema::MD{"dataset.close.extendmax"}}{default};
   }
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.close.extendlimit"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.close.extendlimit"}}{default})) {
      $extendlimit=$tmplparent->{$SysSchema::MD{"dataset.close.extendlimit"}}{default};
   }

   # storage area closed, we have the size - store it and set status to closed
   my $time=time();
   my %md;
   $md{$SysSchema::MD{"dataset.status"}}=$SysSchema::C{"status.closed"};
   $md{$SysSchema::MD{"dataset.closed"}}=time();
   $md{$SysSchema::MD{"dataset.size"}}=$totalsize;

   # also set its expire date upon closing
   $md{$SysSchema::MD{"dataset.expire"}}=$time+$lifespan;
   $md{$SysSchema::MD{"dataset.extendmax"}}=$extendmax;
   $md{$SysSchema::MD{"dataset.extendlimit"}}=$time+$extendlimit;

   # update system metadata here and override template to ensure update
   if (!$db->setEntityMetadata($id,\%md,undef,undef,1)) {
      # some failure - abort
      dbLogger ($id,"Unable to set metadata for dataset while acquiring on task $taskid: ".$db->error(),"FATAL");
# remove dataset
# $ev->evaluate("remove",$id);
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its acquire-phase for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). Unable to set metadata for dataset: ".$db->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
         # write entire error log to file, for possible inspection        
         my $data="";
         if ($log) { $data=$log->getFirstAsString($log->count(),"%t: %m\n"); }
         $data=$data."\nFAILURE REASON: Unable to set metadata for dataset while acquiring on task $taskid: ".$db->error()."\n";
         $dq->taskFile($task,"ERROR",$data);
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});
      }
      return 0;
   }

   # success - update todo-entries
   my @todo=split(",",$dq->taskTag($task,"todo"));
   # remove first entry which we have now run
   shift (@todo);
   # update tag
   my $td=join(",",@todo);
   # update tag
   $dq->taskTag($task,"todo",$td);
   # update retry
   $dq->taskTag($task,"retry",-1);
   # ready for next possible phase - move to init
   $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"});

   # successfully completed.
   dbLogger ($id,"Successfully completed ".$SysSchema::C{"phase.acquire"}."-phase for task $taskid");

   # message user about failed distribution task
   my $not=Not->new();
   $not->send(type=>"distribution.acquire.success",about=>$id,from=>$SysSchema::FROM_STORE,
              message=>"Hi,\n\nDistribution task $taskid has successfully completed its acquire-phase on dataset with id $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A").")".
                       "\n\nYour dataset can be managed and downloaded by going to the AURORA web site here:".
                       "\n\n".$CFG->value("system.www.base").
                       "\n\nPlease be aware that it might still be pending distribute-phase(s) on the dataset.".
                       "\n\nBest regards,\n\n   Aurora System");

   # consummatum est
   return 1;
}

sub do_dist {
   my $task=shift; # get distribution task to work on
   my $info=shift; # get task info

   # set subprocess name
   $0=$BASENAME." DIST TASK: $task";

   # get dataset id
   my $id=$info->{datasetid} || 0;

   # dist queue instance
   my $dq=DistributionQueue->new(folder=>$CFG->value("system.dist.location"));

   # get task random id or id.
   my $taskid=$dq->getTaskRandomID($task);

   # get user name that owns the task
   my $uid=$info->{userid} || 0;

   # attempt to change phase to ensure that we have the dist
   # do not accept same phase change in order to be atomic and stop other processes from running.
   if (!$dq->changeTaskPhase($task,$SysSchema::C{"phase.dist"},undef,0)) {
      # we do not have the acquire - exit
      dbLogger($id,"Unable to change phase for task $taskid to ".$SysSchema::C{"phase.dist"}.": ".$dq->error(),"FATAL");
      return 0;
   }

   # we have the dist

   # set alive tag
   $dq->taskTag($task,"alive",time());

   # get own pid and ctime
   my $pid=$$;
   my $ctime=(stat "/proc/$pid/stat")[10] || 0;
   # save it on the task
   $dq->taskTag($task,"pid",$pid);
   $dq->taskTag($task,"ctime",$ctime);
   my $ccmd=getFileData("/proc/$pid/cmdline") || "";
   $dq->taskTag($task,"cmdline",$ccmd);   

   # update retry counter right away - this is a valid attempt
   my $retry=$dq->taskTag($task,"retry");
   $retry=(defined $retry ? $retry : -1);
   $retry++;
   $dq->taskTag($task,"retry",$retry);

   # get maxretry setting
   my $maxretry=$CFG->value("system.dist.maxretry") || 2;

   # connect to database
   # database instance
   my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                        pw=>$CFG->value("system.database.pw"));

   # abort if no database connection
   if (!$db->getDBI()) {
      dbLogger ($id,"Database connection error while distributing in task $taskid: ".$db->error(),"FATAL");
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.distribute.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its distribute-phase for the last time (retry=$maxretry) of dataset with id $id. Unable to connect to database: ".$db->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }
      return 0;
   }

   # get metadata of dataset
   my $dataset=$db->getEntityMetadata($id);
   if (!defined $dataset) {
      # some failure
      dbLogger ($id,"Unable to get metadata for dataset while distributing in task $taskid: ".$db->error(),"FATAL");
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.distribute.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its distribute-phase for the last time (retry=$maxretry) of dataset with id $id. Unable to get metadata for dataset: ".$db->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }
      return 0;
   }

   # check that dataset status *is* closed - we cannot distribute an open dataset
   if ($dataset->{$SysSchema::MD{"dataset.status"}} ne $SysSchema::C{"status.closed"}) {
      # dataset is not closed. Not allowed to attempt distribution, we will have to wait. Reset task

      # decrease retry count from earlier
      my $retry=$dq->taskTag($task,"retry");
      $retry=(defined $retry ? $retry : 1);
      $retry--;
      $dq->taskTag($task,"retry",$retry);

      # we move the task back into init
      $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"phase.init"});

      return 0;
   }

   # notify dataset log of distribution task start
   dbLogger ($id,"Starting distribution on task $taskid");

   # get computer
   my $computer=$dataset->{$SysSchema::MD{"dataset.computer"}} || 0; # default to an invalid entity id

   # get user metadata
   my $umd=$db->getEntityMetadata($uid);
   # check that we got the user metadata, or else fail
   if (!defined $umd) {
      # Something failed getting user metadata
      dbLogger ($id,"Unable to get user metadata for user $uid: ".$db->error().". Moving task $taskid to FAILED.","FATAL");
      # this is a complete fatal event, move task to failed
      $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});

      # message user about failed distribution task
      my $not=Not->new();
      $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                 message=>"Hi,\n\nDistribution task $taskid has failed fatally its distribute-phase on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")." because it were unable to get metadata of executing user: $uid.".
                          "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                          "\n\nBest regards,\n\n   Aurora System");
      return 0;
   }

   # get task data
   my $yaml=$dq->getTaskData($task);

   # convert to hash
   my $c=Content::YAML->new();

   if (!defined $c->decode($yaml)) {
      # something failed
      dbLogger ($id,"Unable to decode task queue data while distributing in task $taskid: ".$c->error(),"FATAL");
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.distribute.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its distribute-phase for the last time (retry=$maxretry). Unable to decode task queue data for dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."): ".$c->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }

      return 0;
   }

   # successfully decoded - get decoded hash
   my $data=$c->get();

   # we have the task data...start to prepare the put-operation by getting the storage area of the data

   # create fiEval-instance
   my $ev=fiEval->new();
   if (!$ev->success()) {
      # unable to instantiate
      dbLogger ($id,"Unable to instantiate fiEval: ".$ev->error(),"FATAL");
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.distribute.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). We are unable to instantiate fiEval: ".$ev->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }

      return 0;     
   }

   dbLogger ($id,"Opening storage area for dataset while distributing in task $taskid.","DEBUG");

   if ($ev->evaluate("mode",$id) ne "ro") {
      my $err=": ".$ev->error();
      dbLogger ($id,"Unable to open storage area in RO-mode while distributing in task $taskid$err.","FATAL");
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.distribute.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its distribute-phase for the last time (retry=$maxretry). Unable to open storage area in RO mode on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."): $err.".
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }

      return 0;
   }

   # we have a rw storage area - get path
   my $spath=$ev->evaluate("datapath",$id);

   # enumerate Store-classes
   my $ids=$db->enumEntitiesByType (\@{[($db->getEntityTypeIdByName("STORE"))[0]]});

   if (!defined $ids) {
      # something failed enumerating STORE-entities - we have to abort acquire
      dbLogger ($id,"Unable to enumerate STORE-entities: ".$db->error(),"FATAL");
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.distribute.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). We are unable to enumerate Store-entities: ".$db->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});
      }

      return 0;
   }

   my %stores;
   foreach (@{$ids}) {
      my $s=$_;

      # get store metadata
      my $smd=$db->getEntityMetadata($s);

      if (!defined $smd) {
         # failed to get metadata for Store - must abort
         dbLogger ($id,"Unable to get metadata for STORE $s: ".$db->error(),"FATAL");
         # check retry
         if ($retry >= $maxretry) {
            # exhausted our retries - move to failed.
            $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
            # message user about failed distribution task
            my $not=Not->new();
            $not->send(type=>"distribution.distribute.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                       message=>"Hi,\n\nDistribution task $taskid has failed for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). We are unable to get metadata for STORE $s: ".$db->error().
                                "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                                "\n\nBest regards,\n\n   Aurora System");

         } else {
            # we will try again - move to init
            $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});
         }

         return 0;
      }

      # success - get relevant details
      $stores{$s}{id}=$s;
      $stores{$s}{class}=$smd->{$SysSchema::MD{"store.class"}};
   }

   # must have 1 or more put-operations
   if (keys %{$data->{put}} == 0) {
      dbLogger ($id,"Distribution task $taskid does not have any put-operations defined. Unable to proceed.","FATAL");
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.distribute.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its distribute-phase for the last time (retry=$maxretry). No put-operations defined on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). Unable to proceed.".
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      } 
      return 0;
   }

   # go through each put-operation and input necessary 
   # data before attempting to run them...
   my $ok=1;
   foreach (sort {$a <=> $b} keys %{$data->{put}}) {
      my $no=$_;

      # get computer id, if any
      my $computer=$data->{put}{$no}{computer} || 0;
      # get computer description, if any
      my $computername=$data->{put}{$no}{computername} || "";
      # get user path
      my $userpath=$data->{put}{$no}{param}{remote} || "/";

      # check if user has COMPUTER_WRITE on computer in question
      if (!hasPerm($db,$uid,$computer,["COMPUTER_WRITE"],"ALL","ANY",1,1,undef,1)) {
         # user does not have the necessary permissions on this computer, we have to abort.
         dbLogger ($id,"User $uid does not have the COMPUTER_WRITE permission on computer $computer. Unable to continue distribute operation in task $taskid.","ERROR");
         $ok=0;
         last;
      }

      # get template of computer
      my $templ=$db->getEntityTemplate(($db->getEntityTypeIdByName("COMPUTER"))[0],$db->getEntityPath($computer));
      if (!defined $templ) {
         dbLogger ($id,"Unable to get template of computer $computer. Unable to continue distribute operation in task $taskid.","ERROR");
         $ok=0;
         last;
      }

      # ensure that host-info comes from computer in question
      my $cmd=$db->getEntityMetadata($computer);
      if (!defined $cmd) {
         dbLogger ($id,"Unable to get metadata on computer $computer. Unable to continue distribute operation in task $taskid.","ERROR");
         $ok=0;
         last;
      }

      # merge template and computer for raw use
      my %tc=(%{$templ},%{$cmd});

      # get metadatacollection data from template and computer
      my $mc=MetadataCollection->new(base=>$SysSchema::MD{"computer.task.base"});
      # make store collection hash from template
      my $thash=$mc->template2Hash($templ);
      # make store collection hash from computer metadata
      my $chash=$mc->metadata2Hash($cmd);
      # merge template and computer metadata hashes, computer having precedence
      my $mdcoll=$mc->mergeHash($thash,$chash);
 
      # merge metdata into data
      foreach (keys %{$mdcoll->{param}}) {
         my $name=$_;
         my $value=$mdcoll->{param}{$name};
         $data->{put}{$no}{param}{$name}=$value;
      }

      # merge metadata classparam into data
      foreach (keys %{$mdcoll->{classparam}}) {
         my $name=$_;
         my $value=$mdcoll->{classparam}{$name};
         $data->{put}{$no}{classparam}{$name}=$value;
      }

      # ensure sensible values on host and remote
      my $host=$mdcoll->{param}{host}||"0.0.0.0";
      my $cpath=$tc{$SysSchema::MD{"computer.path"}};
      my $user=($tc{$SysSchema::MD{"computer.useusername"}} ? $umd->{$SysSchema::MD{"username"}}."/" : "");

      # overwrite any value in host
      $data->{put}{$no}{param}{host}=$host;
      # ensure correct value in remote
      $data->{put}{$no}{param}{remote}=$SysSchema::CLEAN{pathsquash}->($cpath."/$user".$userpath);
   }

   if (!$ok) {
      # we failed to setup the get-operations, abort...
      dbLogger ($id,"Unable to successfully setup all distribute-operations in task $taskid.","FATAL");

      # $ev->evaluate("remove",$id);

      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.acquire.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its distribute-phase for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A").". We are unable to successfully setup all distribute-operations. Please check the dataset-log for more information on the failure.".
                             "\n\nYour dataset-log can be viewed by going to the AURORA web site here:".
                             "\n\n".$CFG->value("system.www.base").
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      } 
#      dbLogger ($id,"Finished cleaning up after failed distribute-operations for task $taskid.","DEBUG");

      return 0;
   }

   # disconnect database to avoid timeout issues
   $db=undef;

   dbLogger ($id,"Executing distribution-operations for dataset in task $taskid.");

   # iterate over put stores
   my $success=1;
   my $log;
   foreach (sort {$a <=> $b} keys %{$data->{put}}) {
      my $no=$_;

      # get computer id, if any
      my $computer=$data->{put}{$no}{computer} || 0;
      # get computer description, if any
      my $computername=$data->{put}{$no}{computername} || "";
      # get storecollection
      my $sc=$data->{put}{$no}{sc} || 0;

      # get store id
      my $sid=$data->{put}{$no}{store} || 0;

      dbLogger ($id,"Attempting to use store $sid while executing distribution operation $no in task $taskid.","DEBUG");

      # check if it exists
      if (!exists $stores{$sid}) {
         # invalid store - log it and end execution
         dbLogger ($id,"Store $sid does not exist. Unable to execute distribution-operation $no in task $taskid.","ERROR");
         $success=0;
         last; 
      }

      # get class params
      my %cparams;
      foreach (keys %{$data->{put}{$no}{classparam}}) {
         my $par=$_;
 
         $cparams{$par}=$data->{put}{$no}{classparam}{$par};
      }

      # get store class name
      my $sclass=$stores{$sid}{class} || "";

      # try to instantiate class, add dataset metadata, sandbox and use class params
      my $sandbox=$CFG->value("system.sandbox.location") || "/nonexistant";
      my $store=$sclass->new(%cparams,metadata=>$dataset,sandbox=>$sandbox) || undef;

      if (!defined $store) {
         # failed to get an instantiated store class
         dbLogger ($id,"Unable to instantiate store-class $sclass while executing distribute-operation $no in task $taskid","ERROR");
         $success=0;
         last; 
      }

      # put params in place
      my %params;
      foreach (keys %{$data->{put}{$no}{param}}) {
         my $param=$_;

         # get the param
         $params{$param}=$data->{put}{$no}{param}{$param};
      }

      # put local parameter in place by setting the storage location
      $params{"local"}=$spath;

      # modify remote parameter and add dataset id if defined, if not leave untouched (brace for errors)
      $params{"remote"}=(defined $params{"remote"} ? $params{"remote"}."/$id/" : undef);

      # attempt to open store
      if (!$store->open(%params)) {
         # something failed
         dbLogger ($id,"Unable to open store $no ($sclass) while executing distribute-operation $no in task $taskid: ".$store->error(),"ERROR");
         $success=0;
         last; 
      }

      # we probe store without checking result
      $store->probe();

      dbLogger ($id,"Checking size of data in the distribution-operation $no with store $sclass ($sid) in task $taskid.","DEBUG");

      my $lsize=$store->localSize();
      # get store log
      $log=$store->getLog();
      if (!defined $lsize) {
         # unable to get local size
         dbLogger ($id,"Unable to calculate size of data in distribution-operation $no with store $sclass ($sid) in task $taskid: ".$store->error(),"ERROR");
         $store->close();
         $success=0;
         last;
      }

      dbLogger ($id,"Size of data in distribution-operation $no with store $sclass ($sid) in task $taskid: ".size($lsize)." ($lsize Byte(s))","DEBUG");

      # we are ready to run store by invoking put-method
      dbLogger ($id,"Executing distribution-operation $no with store $sclass ($sid) in task $taskid.","DEBUG");

      # execute put
      if (!$store->put()) {
         # get store-log
         $log=$store->getLog();
         # get the last 3 log entries as a string
         my $errmsg=$log->getLastAsString(5,"%t: %m ");
         $errmsg=$errmsg || "Unknown reason";
         dbLogger ($id,"Failed to execute distribution-operation $no with store $sclass ($sid) in task $taskid: ".$errmsg,"ERROR");
         $store->close();
         $success=0;
         last;
      }

      # wait for it to complete and update alive status
      $log=$store->getLog();
      while ($store->isRunning()) { my $alive=$store->alive(); if ((defined $alive) && ($alive > 0)) { $dq->taskTag ($task,"alive",$alive); } sleep(10); }
      # write entire transfer log to the AURORA log
      $log->resetNext();
      while (my $entry=$log->getNext()) { dbLogger($id,$entry->[0],"DEBUG","TRANSFER",$entry->[1]); }
      # check success of last store-operation. If not successful - abort the rest.
      if (!$store->success()) {
         # get store-log
         $log=$store->getLog();
         # get the last 3 log entries as a string
         my $errmsg=$log->getLastAsString(5,"%t: %m ");
         $errmsg=$errmsg || "Unknown reason"; 
         dbLogger ($id,"Distribution operation $no with store $sclass ($sid) in task $taskid failed: ".$errmsg,"ERROR");
         $store->close(); 
         $success=0;
         # write entire error log to file, for possible inspection
         my $data=$log->getFirstAsString($log->count(),"%t: %m\n");
         # add the store-command that was run
         my $put=$store->putParams();
         $data="COMMAND: ".$put->toString()."\nCLASS-PARAMS: ".Dumper(\%cparams)."\nPARAMS: ".Dumper(\%params)."\n".$data;
         $dq->taskFile($task,"ERROR",$data);
         last; 
      } else {
         # get local size and compare
         my $rsize=$store->remoteSize();
         if (!defined $rsize) {
            # failed to get remote size
            dbLogger ($id,"Unable to calculate size of remote data in distribution-operation $no with store $sclass ($sid) in task $taskid: ".$store->error(),"ERROR");
            $store->close();
            $success=0;
            last;
         } 

         dbLogger ($id,"Size of remote data in distribution-operation $no with store $sclass ($sid) in task $taskid: ".size($rsize)." ($rsize Byte(s))","DEBUG");

         # check that the two sizes match
         if ($rsize != $lsize) {
            dbLogger ($id,"Sizes of data for distribution-operation $no with store $sclass ($sid) in task $taskid are mismatched between remote ($rsize) and local ($lsize) area.","ERROR");
            $store->close();
            $success=0;
            last;
         }
         # always close store
         $store->close();
         dbLogger ($id,"Successfully executed distribution-operation $no with store $sclass in task $taskid.","DEBUG"); 
         # make distribution log entry
         my $entry=createDistLogEntry(
                                       event=>"TRANSFER",
                                       sc=>$sc,
                                       fromloc=>$id,
                                       to=>$sclass,
                                       toid=>$sid,
                                       tohost=>$params{"host"},
                                       tohostid=>$computer,
                                       tohostname=>$computername,
                                       toloc=>$params{"remote"},
                                       uid=>$uid
                                     );

         dbLogger($id,$entry,"DEBUG","DISTLOG");
      }
   }

   if (!$success) {
      # not successful
      dbLogger ($id,"Unable to successfully complete all distribution-operations in task $taskid.","FATAL");
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.distribute.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its distribute-phase for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). Please check the dataset-log for more information on failure.".
                             "\n\nYour dataset-log can be viewed by going to the AURORA web site here:".
                             "\n\n".$CFG->value("system.www.base").
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      } 
#      dbLogger ($id,"Finished cleaning up after failed distribution-operations for task $taskid.","DEBUG");
      return 0;
   }

   dbLogger ($id,"All distribution-operations executed successfully in task $taskid.");

   # success - update todo-entries
   my @todo=split(",",$dq->taskTag($task,"todo"));
   # remove first entry which we have now run
   shift (@todo);
   # update tag
   my $td=join(",",@todo);
   # update tag
   $dq->taskTag($task,"todo",$td);
   # update retry
   $dq->taskTag($task,"retry",-1);
   # ready for next possible phase - move to init
   $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"});

   # successfully completed.
   dbLogger ($id,"Successfully completed ".$SysSchema::C{"phase.dist"}."-phase for task $taskid");

   # message user about failed distribution task
   my $not=Not->new();
   $not->send(type=>"distribution.distribute.success",about=>$id,from=>$SysSchema::FROM_STORE,
              message=>"Hi,\n\nDistribution task $taskid has successfully completed its distribute-phase on dataset with id $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A").")".
                       "\n\nYour dataset can be managed by going to the AURORA web site here:".
                       "\n\n".$CFG->value("system.www.base").
                       "\n\nBest regards,\n\n   Aurora System");

   # consummatum est
   return 1;
}

sub do_delete {
   my $task=shift; # get delete task to work on
   my $info=shift; # get task info

   # set subprocess name
   $0=$BASENAME." DIST TASK: $task";

   # get dataset id
   my $id=$info->{datasetid} || 0;

   # dist queue instance
   my $dq=DistributionQueue->new(folder=>$CFG->value("system.dist.location"));

   # get task random id or id.
   my $taskid=$dq->getTaskRandomID($task);

   dbLogger ($id,"Starting deletion on task $taskid");

   # get user name that owns the task
   my $uid=$info->{userid} || 0;

   # attempt to change phase to ensure that we have the deleting-phase
   # do not accept same phase change in order to be atomic and stop other processes from running.
   if (!$dq->changeTaskPhase($task,$SysSchema::C{"phase.delete"},undef,0)) {
      # we do not have the acquire - exit
      dbLogger($id,"Unable to change phase for task $taskid to ".$SysSchema::C{"phase.delete"}.": ".$dq->error(),"FATAL");
      return 0;
   }

   # we have the delete

   # set alive tag
   $dq->taskTag($task,"alive",time());

   # get own pid and ctime
   my $pid=$$;
   my $ctime=(stat "/proc/$pid/stat")[10] || 0;
   # save it on the task
   $dq->taskTag($task,"pid",$pid);
   $dq->taskTag($task,"ctime",$ctime);
   my $ccmd=getFileData("/proc/$pid/cmdline") || "";
   $dq->taskTag($task,"cmdline",$ccmd);   

   # update retry counter right away - this is a valid attempt
   my $retry=$dq->taskTag($task,"retry");
   $retry=(defined $retry ? $retry : -1);
   $retry++;
   $dq->taskTag($task,"retry",$retry);

   # get maxretry setting
   my $maxretry=$CFG->value("system.dist.maxretry") || 2;

   # notify about distribution
   dbLogger($id,"Performing deletion on task $taskid.");

   # connect to database
   # database instance
   my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                        pw=>$CFG->value("system.database.pw"));

   # abort if no database connection
   if (!$db->getDBI()) {
      dbLogger ($id,"Database connection error while deleting in task $taskid: ".$db->error(),"FATAL");
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.delete.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its delete-phase for the last time (retry=$maxretry) of dataset with id $id. Unable to connect to database: ".$db->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }
      return 0;
   }

   # get metadata of dataset
   my $dataset=$db->getEntityMetadata($id);
   if (!defined $dataset) {
      # some failure
      dbLogger ($id,"Unable to get metadata for dataset while deleting in task $taskid: ".$db->error(),"FATAL");
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.delete.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its delete-phase for the last time (retry=$maxretry) of dataset with id $id. Unable to get metadata for dataset: ".$db->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }
      return 0;
   }

   # check that dataset status *is* closed - we cannot delete an open dataset
   if ($dataset->{$SysSchema::MD{"dataset.status"}} ne $SysSchema::C{"status.closed"}) {
      # dataset is not closed. Not allowed to attempt deletion
      dbLogger ($id,"Unable to delete dataset since the dataset is not closed. Task $taskid failed.","FATAL");
      # this is a complete fatal event, move task to failed
      $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
      # message user about failed distribution task
      my $not=Not->new();
      $not->send(type=>"distribution.delete.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                 message=>"Hi,\n\nDistribution task $taskid has failed its delete-phase because the dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A").") is not closed.".
                          "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                          "\n\nBest regards,\n\n   Aurora System");
      return 0;
   }

   # get computer
   my $computer=$dataset->{$SysSchema::MD{"dataset.computer"}} || 0; # default to an invalid entity id

   # get user metadata
   my $umd=$db->getEntityMetadata($uid);
   # check that we got the user metadata, or else fail
   if (!defined $umd) {
      # Something failed getting user metadata
      dbLogger ($id,"Unable to get user metadata for user $uid: ".$db->error().". Moving task $taskid to FAILED.","FATAL");
      # this is a complete fatal event, move task to failed
      $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});

      # message user about failed distribution task
      my $not=Not->new();
      $not->send(type=>"distribution.delete.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                 message=>"Hi,\nDelete operation on task $taskid has failed fatally its delete-phase on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")." because it were unable to get metadata of executing user: $uid.".
                          "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                          "\n\nBest regards,\n\n   Aurora System");
      return 0;
   }

   # get task data
   my $yaml=$dq->getTaskData($task);

   # convert to hash
   my $c=Content::YAML->new();

   if (!defined $c->decode($yaml)) {
      # something failed
      dbLogger ($id,"Unable to decode task queue data while deleting in task $taskid: ".$c->error(),"FATAL");
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.delete.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its delete-phase for the last time (retry=$maxretry). Unable to decode task queue data for dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."): ".$c->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      }

      return 0;
   }

   # successfully decoded - get decoded hash
   my $data=$c->get();

   # enumerate Store-classes
   my $ids=$db->enumEntitiesByType (\@{[($db->getEntityTypeIdByName("STORE"))[0]]});

   if (!defined $ids) {
      # something failed enumerating STORE-entities - we have to abort acquire
      dbLogger ($id,"Unable to enumerate STORE-entities: ".$db->error(),"FATAL");
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.delete.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). We are unable to enumerate Store-entities: ".$db->error().
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});
      }

      return 0;      
   }

   my %stores;
   foreach (@{$ids}) {
      my $s=$_;

      # get store metadata
      my $smd=$db->getEntityMetadata($s);

      if (!defined $smd) {
         # failed to get metadata for Store - must abort
         dbLogger ($id,"Unable to get metadata for STORE $s: ".$db->error(),"FATAL");
         # check retry
         if ($retry >= $maxretry) {
            # exhausted our retries - move to failed.
            $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
            # message user about failed distribution task
            my $not=Not->new();
            $not->send(type=>"distribution.delete.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                       message=>"Hi,\n\nDistribution task $taskid has failed for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). We are unable to get metadata for STORE $s: ".$db->error().
                                "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                                "\n\nBest regards,\n\n   Aurora System");

         } else {
            # we will try again - move to init
            $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});
         }

         return 0;
      }

      # success - get relevant details
      $stores{$s}{id}=$s;
      $stores{$s}{class}=$smd->{$SysSchema::MD{"store.class"}};
   }

   # must have 1 or more del-operations
   if (keys %{$data->{del}} == 0) {
      dbLogger ($id,"Distribution task $taskid does not have any delete-operations defined. Unable to proceed.","FATAL");
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.delete.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its delete-phase for the last time (retry=$maxretry). No del-operations defined on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). Unable to proceed.".
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      } 
      return 0;
   }

   # go through each put-operation and input necessary 
   # data before attempting to run them...
   my $ok=1;
   foreach (sort {$a <=> $b} keys %{$data->{del}}) {
      my $no=$_;

      # get computer id, if any
      my $computer=$data->{del}{$no}{computer} || 0;
      # get computer description, if any
      my $computername=$data->{del}{$no}{computername} || "";
      # get user path
      my $userpath=$data->{del}{$no}{param}{remote} || "/";

      # check if user has COMPUTER_WRITE on computer in question
      if (!hasPerm($db,$uid,$computer,["COMPUTER_WRITE"],"ALL","ANY",1,1,undef,1)) {
         # user does not have the necessary permissions on this computer, we have to abort.
         dbLogger ($id,"User $uid does not have the COMPUTER_WRITE permission on computer $computer. Unable to continue delete operation in task $taskid.","ERROR");
         $ok=0;
         last;
      }

      # get template of computer
      my $templ=$db->getEntityTemplate(($db->getEntityTypeIdByName("COMPUTER"))[0],$db->getEntityPath($computer));
      if (!defined $templ) {
         dbLogger ($id,"Unable to get template of computer $computer. Unable to continue delete operation in task $taskid.","ERROR");
         $ok=0;
         last;
      }

      # ensure that host-info comes from computer in question
      my $cmd=$db->getEntityMetadata($computer);
      if (!defined $cmd) {
         dbLogger ($id,"Unable to get metadata on computer $computer. Unable to continue delete operation in task $taskid.","ERROR");
         $ok=0;
         last;
      }

      # merge template and computer for raw use
      my %tc=(%{$templ},%{$cmd});

      # get metadatacollection data from template and computer
      my $mc=MetadataCollection->new(base=>$SysSchema::MD{"computer.task.base"});
      # make store collection hash from template
      my $thash=$mc->template2Hash($templ);
      # make store collection hash from computer metadata
      my $chash=$mc->metadata2Hash($cmd);
      # merge template and computer metadata hashes, computer having precedence
      my $mdcoll=$mc->mergeHash($thash,$chash);

      # merge metdata into data
      foreach (keys %{$mdcoll->{param}}) {
         my $name=$_;
         my $value=$mdcoll->{param}{$name};
         $data->{del}{$no}{param}{$name}=$value;
      }

      # merge metadata classparam into data
      foreach (keys %{$mdcoll->{classparam}}) {
         my $name=$_;
         my $value=$mdcoll->{classparam}{$name};
         $data->{del}{$no}{classparam}{$name}=$value;
      }

      # ensure sensible values on host and remote
      my $host=$mdcoll->{param}{host}||"0.0.0.0";
      my $cpath=$tc{$SysSchema::MD{"computer.path"}};
      my $user=($tc{$SysSchema::MD{"computer.useusername"}} ? $umd->{$SysSchema::MD{"username"}}."/" : "");

      # overwrite any value in host
      $data->{del}{$no}{param}{host}=$host;
      # ensure correct value in remote
      $data->{del}{$no}{param}{remote}=$SysSchema::CLEAN{pathsquash}->($cpath."/$user".$userpath);
   }

   if (!$ok) {
      # we failed to setup the get-operations, abort...
      dbLogger ($id,"Unable to successfully setup all delete-operations in task $taskid.","FATAL");

      # $ev->evaluate("remove",$id);

      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.delete.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its delete-phase for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A").". We are unable to successfully setup all delete-operations. Please check the dataset-log for more information on the failure.".
                             "\n\nYour dataset-log can be viewed by going to the AURORA web site here:".
                             "\n\n".$CFG->value("system.www.base").
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      } 
#      dbLogger ($id,"Finished cleaning up after failed delete-operations for task $taskid.","DEBUG");

      return 0;
   }

   # disconnect database to avoid timeout issues
   $db=undef;

   dbLogger ($id,"Executing delete-operations for dataset in task $taskid.");

   # iterate over del stores
   my $success=1;
   my $log;
   foreach (sort {$a <=> $b} keys %{$data->{del}}) {
      my $no=$_;

      # get computer id, if any
      my $computer=$data->{del}{$no}{computer} || 0;
      # get computer description, if any
      my $computername=$data->{del}{$no}{computername} || "";
      # get storecollection
      my $sc=$data->{del}{$no}{sc} || 0;

      # get store id
      my $sid=$data->{del}{$no}{store} || 0;

      dbLogger ($id,"Attempting to use store $sid while executing delete-operation $no in task $taskid.","DEBUG");

      # check if it exists
      if (!exists $stores{$sid}) {
         # invalid store - log it and end execution
         dbLogger ($id,"Store $sid does not exist. Unable to execute delete-operation $no in task $taskid.","ERROR");
         $success=0;
         last; 
      }

      # get class params
      my %cparams;
      foreach (keys %{$data->{del}{$no}{classparam}}) {
         my $par=$_;
         $cparams{$par}=$data->{del}{$no}{classparam}{$par};
      }

      # get store class name
      my $sclass=$stores{$sid}{class} || "";

      # try to instantiate class, add dataset metadata, sandbox and use class params
      my $sandbox=$CFG->value("system.sandbox.location") || "/nonexistant";
      my $store=$sclass->new(%cparams,metadata=>$dataset,sandbox=>$sandbox) || undef;

      if (!defined $store) {
         # failed to get an instantiated store class
         dbLogger ($id,"Unable to instantiate store-class $sclass while executing delete-operation $no on task $taskid","ERROR");
         $success=0;
         last; 
      }

      # put params in place
      my %params;
      foreach (keys %{$data->{del}{$no}{param}}) {
         my $param=$_;
         # get the param
         $params{$param}=$data->{del}{$no}{param}{$param};
      }

      # put local parameter in place by just setting it to /tmp. It will not be used.
      $params{"local"}="/tmp";

      # attempt to open store
      if (!$store->open(%params)) {
         # something failed
         dbLogger ($id,"Unable to open store $no ($sclass) while executing delete-operation $no in task $taskid: ".$store->error(),"ERROR");
         $success=0;
         last; 
      }

      # we probe store without checking result
      $store->probe();

      dbLogger ($id,"Checking size of data in the delete-operation $no with store $sclass ($sid) in task $taskid.","DEBUG");

      my $rsize=$store->remoteSize();
      # get store log
      $log=$store->getLog();
      if (!defined $rsize) {
         # unable to get remote size
         dbLogger ($id,"Unable to calculate size of data in delete-operation $no with store $sclass ($sid) in task $taskid: ".$store->error(),"ERROR");
         $store->close();
         $success=0;
         last;
      } elsif ($rsize == 0) {
         # no size on what is to be deleted, suspicious, so we refuse
         dbLogger ($id,"Size of data is 0 in delete-operation $no with store $sclass ($sid) in task $taskid: ".$store->error(),"ERROR");
         $store->close();
         $success=0;
         last;
      }

      dbLogger ($id,"Size of data in delete-operation $no with store $sclass ($sid) in task $taskid: ".size($rsize)." ($rsize Byte(s))","DEBUG");

      # we are ready to run store by invoking del-method
      dbLogger ($id,"Executing delete-operation $no with store $sclass ($sid) in task $taskid.","DEBUG");

      # execute delete
      if (!$store->del()) {
         # get store-log
         $log=$store->getLog();
         # get the last 3 log entries as a string
         my $errmsg=$log->getLastAsString(5,"%t: %m ");
         $errmsg=$errmsg || "Unknown reason";
         dbLogger ($id,"Failed to execute delete-operation $no with store $sclass ($sid) in task $taskid: ".$errmsg,"ERROR");
         $store->close();
         $success=0;
         last;
      }

      # wait for it to complete and update alive status
      $log=$store->getLog();
      while ($store->isRunning()) { my $alive=$store->alive(); if ((defined $alive) && ($alive > 0)) { $dq->taskTag ($task,"alive",$alive); } sleep(10); }
      # write the entire remove-log to the AURORA log
      $log->resetNext();
      while (my $entry=$log->getNext()) { dbLogger($id,$entry->[0],"DEBUG","REMOVE",$entry->[1]); }
      # check success of last store-operation. If not successful - abort the rest.
      if (!$store->success()) {
         # get store-log
         $log=$store->getLog();
         # get the last 3 log entries as a string
         my $errmsg=$log->getLastAsString(5,"%t: %m ");
         $errmsg=$errmsg || "Unknown reason"; 
         dbLogger ($id,"Delete-operation $no with store $sclass ($sid) in task $taskid failed: ".$errmsg,"ERROR");
         $store->close(); 
         $success=0;
         # write entire error log to file, for possible inspection
         my $data=$log->getFirstAsString($log->count(),"%t: %m\n");
         # add the store-command that was run
         my $del=$store->delParams();
         $data="COMMAND: ".$del->toString()."\nCLASS-PARAMS: ".Dumper(\%cparams)."\nPARAMS: ".Dumper(\%params)."\n".$data;
         $dq->taskFile($task,"ERROR",$data);
         last; 
      } else {
         # always close store
         $store->close();
         dbLogger ($id,"Successfully executed delete-operation $no with store $sclass in task $taskid.","DEBUG"); 

         # make distribution log entry
         my $entry=createDistLogEntry(
                                       event=>"REMOVE",
                                       sc=>$sc,
                                       from=>$sclass,
                                       fromid=>$sid,
                                       fromhost=>$params{"host"},
                                       fromhostid=>$computer,
                                       fromhostname=>$computername,
                                       fromloc=>$params{"remote"},
                                       to=>"",
                                       toid=>"",
                                       tohost=>"",
                                       tohostid=>"",
                                       tohostname=>"",
                                       toloc=>"",
                                       uid=>$uid
                                     );

         dbLogger($id,$entry,"DEBUG","DISTLOG");
      }
   }

   if (!$success) {
      # not successful
      dbLogger ($id,"Unable to successfully complete all delete-operations in task $taskid.","FATAL");
      # check retry
      if ($retry >= $maxretry) {
         # exhausted our retries - move to failed.
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.failed"},$SysSchema::C{"status.failed"});
         # message user about failed distribution task
         my $not=Not->new();
         $not->send(type=>"distribution.delete.failed",about=>$id,from=>$SysSchema::FROM_STORE,
                    message=>"Hi,\n\nDistribution task $taskid has failed its delete-phase for the last time (retry=$maxretry) on dataset $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A")."). Please check the dataset-log for more information on failure.".
                             "\n\nYour dataset-log can be viewed by going to the AURORA web site here:".
                             "\n\n".$CFG->value("system.www.base").
                             "\n\nPlease take proper action to restore system operation and ensure that dataset task is executed successfully.".
                             "\n\nBest regards,\n\n   Aurora System");
      } else {
         # we will try again - move to init
         $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"},$SysSchema::C{"status.failed"});        
      } 
#      dbLogger ($id,"Finished cleaning up after failed delete-operations for task $taskid.","DEBUG");
      return 0;
   }

   dbLogger ($id,"All delete-operations executed successfully in task $taskid.");

   # success - update todo-entries
   my @todo=split(",",$dq->taskTag($task,"todo"));
   # remove first entry which we have now run
   shift (@todo);
   # update tag
   my $td=join(",",@todo);
   # update tag
   $dq->taskTag($task,"todo",$td);
   # update retry
   $dq->taskTag($task,"retry",-1);
   # ready for next possible phase - move to init
   $dq->changeTaskPhase($task,$SysSchema::C{"phase.init"});

   # successfully completed.
   dbLogger ($id,"Successfully completed ".$SysSchema::C{"phase.delete"}."-phase for task $taskid");

   # message user about failed distribution task
   my $not=Not->new();
   $not->send(type=>"distribution.delete.success",about=>$id,from=>$SysSchema::FROM_STORE,
              message=>"Hi,\n\nDistribution task $taskid has successfully completed its delete-phase on dataset with id $id (".($dataset->{$SysSchema::MD{"dc.description"}} || "N/A").")".
                       "\n\nYour dataset has been removed from remote store.".
                       "\n\nBest regards,\n\n   Aurora System");

   # consummatum est
   return 1;
}

sub dbLogger {
   my $entity=shift;
   my $msg=shift;
   my $level=shift || "INFO";
   $level=uc($level);
   my $tag=shift || "";
   my $time=shift;
   $time=(!defined $time ? time() : $time);

   my $log;
   if (defined $entity) {
      # log instance
      $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),
                    user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));
#                    sqlite_string_mode=>DBD_SQLITE_STRING_MODE_UNICODE_FALLBACK);
      my $loglevel=$Content::Log::LEVEL_INFO;
      if ($level eq "DEBUG") {
         $loglevel=$Content::Log::LEVEL_DEBUG;
      } elsif ($level eq "WARN") {
         $loglevel=$Content::Log::LEVEL_WARN;
      } elsif ($level eq "ERROR") {
         $loglevel=$Content::Log::LEVEL_ERROR;
      } elsif ($level eq "FATAL") {
         $loglevel=$Content::Log::LEVEL_FATAL;
      }
      # add service name to tag in addition to any tag
      $tag=($tag eq "" ? $SHORTNAME : "$SHORTNAME $tag");
      $log->send(entity=>$entity,logmess=>$msg,loglevel=>$loglevel,logtag=>$tag,logtime=>$time);
   }
}

sub signalHandler {
   my $sig=shift;

   if ($sig eq "HUP") {
      # handle HUP by reloading config-file
      my $success=$CFG->load();
      # notify system logger that configuration file has been reloaded (or not)
      if ($success) {
         $L->log ("Reloaded configuration file successfully...","INFO");
      } else {
         $L->log ("Unable to reload configuration file: ".$CFG->error().". Will continue with existing settings.","ERR");
      }
   }
}

sub size {
   my $k = shift() / 1000;
   my $f = int(log($k || 1)/log(1000));
   my $u = (qw(KB MB GB TB EB))[$f];
   return sprintf("%0.1f$u", $k/1000**$f);
}
