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
# NOTSRVC: AURORA service to manage notifications (repetition, user-feedback, escalation etc.)
#
use strict;
use lib qw(/usr/local/lib/aurora);
use POSIX;
use Settings;
use AuroraDB;
use Log;
use SysSchema;
use SystemLogger;
use Notification;
use NotificationHandler;
use NotificationParser;
use Notice::Email;
use AckHandler;
use MetadataCollection;
use Time::HiRes qw(time);
use Sys::Hostname;
use AuroraVersion;

# version constant
my $VERSION=$AuroraVersion::VERSION;

# auto-reap children
$SIG{CHLD}="IGNORE";
# handle HUP signal myself
$SIG{HUP}=\&signalHandler;

# set base name
my $BASENAME="$0 AURORA Notification-Service";
# set parent name
$0=$BASENAME." Daemon";
# set short name
my $SHORTNAME="NOTSRVC";

# set debug level
my $DEBUG="WARNING";

# get command line options (key=>value)
my %OPT=@ARGV;
%OPT=map {uc($_) => $OPT{$_}} keys %OPT;
# see if user has overridden debug setting
if (exists $OPT{"-D"}) { 
   my $d=$OPT{"-D"} || "WARNING";
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

# get folder path, start with defaults and env
my $FOLDER=($ENV{"AURORA_PATH"} ? $ENV{"AURORA_PATH"}."/notification" : "/local/app/aurora/notification");
# if we have a setting for location in config-files, use that instead.
$FOLDER=($CFG->value("system.notification.location") ? $CFG->value("system.notification.location") : $FOLDER);

# notification parsing structure
my %PARSE = ();

# database instance
my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

my $dbi=$db->getDBI();

if (!$db->connected()) {
   $L->log ("Unable to connect to database: ".$db->error(),"CRIT");
   exit (1);
}

## CONSTANTS
my $WAIT;
my $DATASET;
my $USER;
my @NOTICECLASSES;
my %NOTICETYPES;

# fill constants with the right information
doSetup();

# create ack-handler
my $ack=AckHandler->new(folder=>"$FOLDER/Ack");

# loop until killed
my $nots=NotificationHandler->new(folder=>$FOLDER);
while (1) {
   # database instance
   my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                        pw=>$CFG->value("system.database.pw"));

   # attempt connecting to db
   $db->getDBI();

   # update db-connection
   if (!$db->connected()) {
      $L->log ("Unable to connect to database: ".$db->error().". Will sleep a little and try again.","ERR");
      # wait a little bit
      sleep (10);
      # then try again
      next;
   } 

   my %nottypes=%{$CFG->value("system.notification.types")};

   # read all notifications present
   $nots->update();
   $nots->resetNext();
   while (my $not=$nots->getNext()) {
      my $id=$not->id() || 0;
      $L->log ("ID $id","INFO");
           
      # check if disabled or not
      if ((exists $PARSE{$id}) && ($PARSE{$id}{disabled})) { next; } # just in memory
      if ((exists $PARSE{$id}) && ($PARSE{$id}{fin})) { next; } # written to event

      # create notification parser instance
      my $parser=NotificationParser->new(nottypes=>\%nottypes, db=>$db);

      # parse latest from notification
      my $state=$PARSE{$id};
      $state=$parser->parse($not,$state);

      if (!defined $state) { next; } # something failed.

      # we have a new state, also get last event data
      my %event=%{$parser->lastEvent()};

      # update our parse-HASH
      $PARSE{$id}=$state;

      # check if disabled during last loop, then go to next notification
      if ($PARSE{$id}{disabled}) { next; } # just in memory
      if ($PARSE{$id}{fin}) { next; } # written to event

      # check parse state and what was the last event
      my $type=$event{event};
      my $timestamp=$event{timestamp};

      # get any threadids
      my $threadids;
      if ((exists $state->{threadids}) && (defined $state->{threadids})) {
         $threadids=$state->{threadids};
      }

      # check if we are in a lame duck situation, if so write a FIN-event
      if ($state->{lameduck}) {
         $state->{disabled}=1;
         $state->{fin}=1;
         # create a FIN-event hash
         my %nev;
         $nev{event}=$Notification::FIN;
         $nev{cancel}=0;
         $nev{lameduck}=1;
         if (defined $threadids) { $nev{threadids}=$threadids; }
         # if this is a dataset.remove-notification, we need to check if 
         # expire-date have been met
         if (lc($state->{type}) eq "dataset.remove") {
            # get dataset metadata
            my $about=$state->{about} || 0;
            my $md=$db->getEntityMetadata($about,$SysSchema::MD{"dataset.expire"});
            my $curexpire;
            if (!defined $md) {
               # failed to get metadata - we will default to remove notification to avoid any data loss
               $curexpire=time()+86400;
            } else { $curexpire=$md->{$SysSchema::MD{"dataset.expire"}}; }
            # check if expiretime has been reached/passed or not
            if (time() < $curexpire) {
               # expire time has not been reached, so we are not allowed to remove it
               $nev{cancel}=1;
            }
         }
         
         # write a FIN-event and let the maintenance-service deal with it
         if (!$not->add(\%nev)) {
            $L->log ("Unable to add fin-event to notification $id: ".$not->error,"ERR");
         }
         # next
         next;
      }

      if ((keys %event > 0) && (($type == $Notification::MESSAGE) || ($type == $Notification::ESCALATION))) {
         # this was a message or escalation event - generate notice-events.
         $L->log ("Sending notices","INFO");
         # only log to dataset log if the about type is a dataset
         my $about=$state->{about};
         my $abouttype=$db->getEntityType($about) || "";
         # we cannot continue if we lack the type, log error, force a re-parsing and move to next
         if ($abouttype eq "") {
            $L->log ("Failed to get entity type of $about in notification $id: ".$db->error().". Forcing a re-parsing of notification.","ERR");
            # remove info from PARSE structure to force a complete re-parsing
            delete ($PARSE{$id});
            # reset event reading from notification
            $not->resetNext();
            # move on to next notification
            next;
         }
         my $level=$state->{level};
         if (($abouttype == $DATASET) && ($type == $Notification::ESCALATION)) {
            dbLogger($about,"Notification $id has been escalated to level $level.","DEBUG");
         }

         send_notice(\%PARSE,$not,$ack,$db);
         next;
      }

      # check touching of ack-files, if touched - ack...
      foreach (keys %{$PARSE{$id}{notice}{rid}}) {
         my $rid=$_;

         my $time=$PARSE{$id}{notice}{rid}{$rid}{timestamp}; # sending time of the notice in question
         my $mtime=$ack->mtime($id,$rid) || 0;
         if ($mtime > $time) {
            $L->log ("An ack has occured on notification $id with RID $rid. Writing ack-event","DEBUG");
            # an ack has occured - write ack-event and remove ack-file
            my %aec;
            $aec{event}=$Notification::ACK;
            $aec{timestamp}=$mtime;
            $aec{rid}=$rid;
            # attempt to add event
            if (!$not->add(\%aec)) {
               # failed to add ack - do not remove ack-file
               $L->log ("Unable to add ack-event to notification $id: ".$not->error(),"ERR");
               # SOME ERROR HANDLING
               next;
            }         
            # remove ack-file
            $ack->remove($id,$rid);
            # no update of parse-structure is done here. It is done above
         }
      }

      # check if votes have passed or reached needed or no votes needed
      # if so, this notification is finished
      if ((defined $PARSE{$id}{cast}) && ($PARSE{$id}{cast} <= 0)) {
         my $votes=$PARSE{$id}{cast};
         my $needed=$PARSE{$id}{votes};
         my $about=$PARSE{$id}{about};
         $L->log ("Enough votes have been cast or no votes needed on notification $id. Removing it.","INFO");
         # we have reached the required votes - log it
         # provided needed is not 0, which means no votes needed.
         if ($needed != 0) {
            dbLogger($about,"Enough votes (needed: $needed) have been cast to end the process in notification $id. Ending the notification.","INFO");
         }
         # add a end event - there is no more to do here.
         my %fev;
         $fev{event}=$Notification::FIN;
         $fev{cancel}=0;
         if (defined $threadids) { $fev{threadids}=$threadids; }
         if (!$not->add(\%fev)) {
            # failed to add fin-event
            $L->log("Failed to add fin-event on notification $id: ".$not->error(),"ERR");
         }
          
         # remove ack-files - we have ended this notification
         foreach (keys %{$PARSE{$id}{notice}{rid}}) {
            my $rid=$_;

            $ack->remove($id,$rid);
         }

         # remove notification from parse structure
#         delete ($PARSE{$id});

         # remove notification
#         $nots->delete($not);
         # disable this notification
         $state->{disabled}=1;
         $state->{fin}=1;
         # go to next notification in line
         next;
      }

      # check if escalation wait time has passed, if so escalate
      my $lastnotice=(exists $PARSE{$id}{notice} ? $PARSE{$id}{notice}{timestamp} || 0 : 0);
      if ((exists $PARSE{$id}{notice}) && (time() > $lastnotice+$WAIT)) {
         # wait time exceeeded for confirmation/enough votes - escalate or remove message
         my $type=$PARSE{$id}{type};
         if (($type eq "dataset.close") || 
             ($type eq "dataset.remove")) {
            # these are message to close or remove dataset, check if expire date has changed
            my $about=$PARSE{$id}{about};
            my $expire=$PARSE{$id}{expire};
            my $md=$db->getEntityMetadata($about,$SysSchema::MD{"dataset.expire"});
            my $curexpire;
            if (!defined $md) {
               # failed to get metadata - we will default to remove notification to avoid any data loss
               $curexpire=time()+86400;
            } else { $curexpire=$md->{$SysSchema::MD{"dataset.expire"}}; }
            # check if expire has changed
            if ($curexpire != $expire) {
               # expire has changed/increased - tag notification as finished
               my %fev;
               $fev{event}=$Notification::FIN;
               $fev{cancel}=1;
               if (defined $threadids) { $fev{threadids}=$threadids; }
               if (!$not->add(\%fev)) {
                  # failed to add fin-event
                  $L->log("Failed to add fin-event on notification $id: ".$not->error(),"ERR");
               }
          
               # remove ack-files - we have ended this notification
               foreach (keys %{$PARSE{$id}{notice}{rid}}) {
                  my $rid=$_;

                  $ack->remove($id,$rid);
               }

               # remove notification from parse structure
     #         delete ($PARSE{$id});

               # remove notification
     #         $nots->delete($not);
               # disable this notification
               $state->{disabled}=1;
               $state->{fin}=1;
               # go to next notification in line
               next;
            }
         }
         # escalate
         $L->log ("Escalation wait time ($WAIT) has been exceeded without any acknowledgements. Escalating notification $id","INFO");
         my %nev;
         $nev{event}=$Notification::ESCALATION;
         $nev{level}=$PARSE{$id}{level}; # escalate from current level
         $nev{who}=$SysSchema::FROM_NOTIFICATION; # it is I who escalate
         if (defined $threadids) { $nev{threadids}=$threadids; } # include previous threadids when escalating
         if (!$not->add(\%nev)) {
            # failed to add escalation-event
            $L->log("Failed to add escalation-event on notification $id: ".$not->error(),"ERR");
         }
         # remove ack-files here, since we have in effect escalated
         # but, importantly, do *not* remove rid-structure yet.
         foreach (keys %{$PARSE{$id}{notice}{rid}}) {
            my $rid=$_;

            # attempt to remove ack-file
            $ack->remove($id,$rid);
         }

         # we do not update the PARSE-structure, that is the next loop-turns job to do
         $L->log ("Successfully added escalation-event to notification $id","INFO");
      }
   }

   # add a disconnect here
   $db->disconnect(); # disconnect DB in a controlled fashion.

   sleep (5);
}

# send a notice and generate event
sub send_notice {
   my $PARSE=shift; # ref to PARSE-structure
   my $not=shift; # ref to Notification-instance
   my $ack=shift; # ack handler-instance
   my $db=shift; # ref to AurorDB-instance

   my $id=$not->id();
   my $parse=$PARSE{$id};

   # needed no of votes
   my $needed=$parse->{votes} || 0;

   my $message=$parse->{message};
   # get users to send notices to
   my $level=$parse->{level};
   # get voting so far, if any
   my $voting=$parse->{voting};

   # get about-type
   my $about=$parse->{about} || 0;
   my $abouttype=$db->getEntityType($about) || "";

   if ($abouttype eq "") {
      # we cannot continue without type - reset parsing of notification and move on to next
      $L->log ("Failed to get entity type of $about in notification $id: ".$db->error().". Forcing a re-parsing of notification.","ERR");
      # remove info from PARSE structure to force a complete re-parsing
      delete ($PARSE{$id});
      # reset event reading from notification
      $not->resetNext();
      # move on to next notification
      return;
   }

   # get level type (typically GROUP or DATASET)
   my $leveltype=$db->getEntityType($level) || "";
   if ($leveltype eq "") {
      # cannot continue without leveltype
      $L->log ("Failed to get entity level type of $level in notification $id: ".$db->error().". Forcing a re-parsing of notification.","ERR");
      # remove info from PARSE structure to force a complete re-parsing
      delete ($PARSE{$id});
      # reset event reading from notification
      $not->resetNext();
      # move on to next notification
      return; 
   }
   # get metadata for level
   my $md=$db->getEntityMetadata($level);
   if (!defined $md) {
      # something failed reading metadata
      $L->log ("Failed to get metadata for $level in notification $id: ".$db->error().". Forcing a re-parsing of notification.","ERR");
      # remove info from PARSE structure to force a complete re-parsing
      delete ($PARSE{$id});
      # reset event reading from notification
      $not->resetNext();
      # move on to next notification
      return; 
   }
   # check level type, before proceeding
   if ($leveltype == $DATASET) {
      # we get the user that created the dataset
      my $user=$md->{$SysSchema::MD{"dataset.creator"}};
      # add metadata entries necessary for users subscriptions and votes
      $md->{$SysSchema::MD{"notice.subscribe"}.".$user.0"}=1; # subscribe to all classes
      $md->{$SysSchema::MD{"notice.votes"}.".$user"}=1; # user has 1 vote
   } elsif ($leveltype == $USER) {
      # this is most likely a user-create notification, in any event on a user-level 
      # add metadata entries necessary 
      $md->{$SysSchema::MD{"notice.subscribe"}.".$level.0"}=1; # subscribe to all classes
      $md->{$SysSchema::MD{"notice.votes"}.".$level"}=1; # user has 1 vote      
   }

   # create metadata collection instance
   my $mc=MetadataCollection->new(base=>$SysSchema::MD{"notice.subscribe"});
   # get subscriptions
   my $sub=$mc->metadata2Hash($md);
   # get votes
   $mc->base($SysSchema::MD{"notice.votes"});
   my $votes=$mc->metadata2Hash($md);

   # go throuch each subscription
   my %users;
   foreach (keys %{$sub}) {
      my $user=$_;

      if ((defined $user) && ($user =~ /^\d+$/) && ($user > 0)) {
         # get the users number of votes
         my $vot=-1*$votes->{$user} || 0;
         # add votes
         $users{$user}{votes}=$vot;
         # if global setting exists, skip going through all subscriptions
         if (exists $sub->{$user}{0}) {
            my $value=$sub->{$user}{0};
            $value=(defined $value && $value =~ /\d+/ && $value >= 0 ? $value : 0);
            $users{$user}{subs}{0}=$value;
         } else {          
            # no global setting exists, so go through each subscription
            foreach (keys %{$sub->{$user}}) {
               my $nclass=$_;
               my $lnclass=lc($nclass);
               my $value=$sub->{$user}{$nclass};
               $value=(defined $value && $value =~ /\d+/ && $value >= 0 ? $value : 0);

               if (($nclass !~ /^\d+/) && ($nclass < 1)) { next; } # skip invalid class ids

               # add subscription data
               $users{$user}{subs}{$NOTICETYPES{$lnclass}}=$value; 
            }
         }

         # get users email, if not there already
         if (!exists $users{$user}{email}) {
            my $umd=$db->getEntityMetadata($user);
            if (!defined $umd) {
               # something failed reading metadata
               $L->log ("Failed to get metadata for user $user in notification $id: ".$db->error().". Forcing a re-parsing of notification.","ERR");
               # remove info from PARSE structure to force a complete re-parsing
               delete ($PARSE{$id});
               # reset event reading from notification
               $not->resetNext();
               # move on to next notification
               return; 
            }

            my $email=$umd->{$SysSchema::MD{"email"}};
            my $fullname=$umd->{$SysSchema::MD{"fullname"}};
            $users{$user}{email}=$email;
            $users{$user}{fullname}=$fullname;
         }
      }
   }

   # get all notice-types
   my @classes=@NOTICECLASSES;

   # check if there are any users to send to
   my $votingstr="";
   if (keys %users > 0) {
      if (keys %{$voting} > 0) {
         # we have users to send to and one or more user has cast votes - we include them
         my %v;
         foreach (keys %{$voting}) {
            my $usr=$_;

            my $fullname="";
            if (!exists $users{$usr}) {
               # user is not in users hash - fetch his metadata
               my $umd=$db->getEntityMetadata($usr);
               if (!defined $umd) {
                  # something failed reading metadata
                  $L->log ("Failed to get metadata for user $usr in notification $id: ".$db->error().". Forcing a re-parsing of notification.","ERR");
                  # remove info from PARSE structure to force a complete re-parsing
                  delete ($PARSE{$id});
                  # reset event reading from notification
                  $not->resetNext();
                  # move on to next notification
                  return; 
               }

               $fullname=$umd->{$SysSchema::MD{"fullname"}};
            } else { $fullname=$users{$usr}{fullname}; } # get fullname from users-hash
 
            $v{$fullname}=$voting->{$usr};
         }

         my $str="";
         foreach (sort {$a cmp $b} keys %v) {
            my $name=$_;
            my $vote=$v{$name};
            $str=$str."\n".sprintf ("  %25s%2s",$name,$vote);
         }

         # add str to message
         $votingstr.="\n\nThe following votes have already been cast ($needed needed):\n$str";
      }
   }

   # generate new thread id, combination of notification id and entity tree level
   my $threadid="${id}-${level}\@".hostname();
   if ((!exists $parse->{threadids}) || (!defined $parse->{threadids})) { my @t; $parse->{threadids}=\@t; }

   # send to all users in hash
   my $overall=0;
   foreach (keys %users) {
      my $user=$_;
      $L->log ("Checking notice-class subscriptions for user $user","INFO");
      # create a rid for user on this level
      my $rid=sectools::randstr(32);

      my $msg=$message;

      if ($needed > 0) { # this notice needs acks
         # add ack-message at the bottom of message
         $L->log ("This notification requires acknowledgements, adding extra ack-message","INFO");
         $msg.="\n\nThis message requires voting in order for it to be accepted. We need you to vote on it by clicking on the link below ".
               "(you are not to enter any information on this page): \n\n".$CFG->value("system.www.base").
               "/?route=ack&id=${id}&rid=$rid";
         # include votingstr - it is either empty or contain relevant overview
         $msg.=$votingstr;
      }

      # save current user and group context
      my $uid  = $>;
      my $gid  = $);

      # set correct uid and gid of process
      $) = $CFG->value("system.notification.wwwgroup") || 33; # can never be 0
      $> = $CFG->value("system.notification.wwwuser") || 33; # can never be 0

      # create ack file before any notice-sending
      $ack->add($id,$rid);

      # get mtime
      my $mtime=$ack->mtime($id,$rid);
      if (defined $mtime) {
         $L->log ("Ack-file $rid mtime: $mtime","DEBUG");
      }

      # reset user and group context
      $) = $gid;
      $> = $uid;
  
      # go through each class and send to user   
      my $userok=0;
      foreach (@classes) {
         my $class=$_;
         my $lclass=lc($class);
         my $fullclass="Notice::$class";

         # check if user has subscribed to this
         my $ok=0;
         if ((exists $users{$user}{subs}{0}) && ($users{$user}{subs}{0} == 1)) { $ok=1; }
         elsif ((exists $users{$user}{subs}{$lclass}) && ($users{$user}{subs}{$lclass} == 1)) { $ok=1; }

         if ($ok) {
            $L->log ("User $user subscribes to notices through $fullclass","INFO");
            # get parameters to class
            my %params=%{$CFG->value("system.notification.class.".$lclass.".params")};

            # do en eval when creating instance
            my $n;
            my $err="";
            local $@;
            eval { $n=$fullclass->new(%params) || undef; };
            $@ =~ /nefarious/;
            $err = $@;       

            if (!defined $n) {
               # skip this one
               next;
            }

            # send notice
            my $from=$CFG->value("system.notification.from");
            my $to=$users{$user}{email} || "";
            my %types=%{$CFG->value("system.notification.types")};
            my $subject=$types{$parse->{type}}{subject} || "";
            my $status=1;
            my $errmsg="";
            $L->log ("FROM: $from TO: $to SUBJECT: $subject","DEBUG");
            $L->log ("Attempting to send notice to user $user through $fullclass","INFO");
            if (!$n->send($from,$to,$subject,$msg,$threadid,$parse->{threadids})) {
               $status=0;
               $errmsg=$n->error();
               $L->log ("Failed to send notice to user $user through class $fullclass for notification $id: $errmsg","ERR");
            }
            # only log to dataset log if the type is a dataset
            if ($abouttype == $DATASET) {
               my $result=$n->result();
               # gdpr any email address/user so it doesnt end up in a log
               $result=~s/[^\@\s]+(\@[^\@\s]+)/$1/g;
               dbLogger($about,"Notification $id sent notice to user $user using $class. Result: $result","DEBUG");
            }

            # write notice and if successful, write rid-file
            if ($status) {
               # success - note it as such
               $userok=1;
               $overall=1;
               $L->log ("Successfully sent notice to user $user through class $fullclass.","INFO");
            }
            # create notice event
            my $leftover=$parse->{stragglers}{$user} || 0;
            my %nev;
            $nev{event}=$Notification::NOTICE;
            $nev{class}=$fullclass;
            $nev{rid}=$rid;
            $nev{whom}=$user;
            $nev{votes}=$leftover+$users{$user}{votes};
            $nev{status}=$status;
            $nev{message}=$errmsg;
            $nev{threadid}=$threadid; # save the threadid in each notice, to avoid loss before escalation events
            $L->log ("EVENT: $nev{event} CLASS: $nev{class} RID: $nev{rid} WHOM: $nev{whom} VOTES: $nev{votes} STATUS: $nev{status} MESSAGE: $nev{message}","DEBUG");
            if (!$not->add(\%nev)) {
               # failed to add event, say so
               $L->log ("Failed to add notice-event to notification $id: ".$not->error(),"ERR");
            }
            # we will not add any ack-event in parse-structure here, the parser
            # above will take care of that by reading the event-file
         }
      }
      # check the users overall success, we are satisfied with at least one success
      if (!$userok) {
         # unable to send through any method, remove ack-file
         $ack->remove($id,$rid);
      }
   }

   # escalate if no users notified (or all notice-events failed)
   if (!$overall) {
      # we are not able to send any notices - attempt immediate escalation
      $L->log ("There are no users to send notices to or all notice-events failed on notification $id on level $level. Attemping immediate escalation.","INFO");
      my %nev;
      $nev{event}=$Notification::ESCALATION;
      $nev{level}=$level; # escalate from current level
      $nev{who}=$SysSchema::FROM_NOTIFICATION; # it is I who escalate
      # we do not need to include current threadid, since it was not used
      $nev{threadids}=$parse->{threadids};
      if (!$not->add(\%nev)) {
         # failed to add escalation-event
         $L->log("Failed to add escalation-event on notification $id: ".$not->error(),"ERR");
      } else {
         # we do not update the PARSE-structure, that is the next loop-turns job to do
         $L->log ("Successfully added escalation-event to notification $id","INFO");
      }
   } else {
      # some where notified, so we can accumulate threadids
      my @t=@{$parse->{threadids}};
      # add the last threadid to list
      push @t,$threadid;
      # update
      $parse->{threadids}=\@t;
   }
}

sub dbLogger {
   my $entity=shift;
   my $msg=shift;
   my $level=shift || "INFO";
   $level=uc($level);
   my $tag=shift || "";

   my $log;
   if (defined $entity) {
      # log instance
      $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));
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
      # add service name in front of message
      $tag=($tag eq "" ? $SHORTNAME : "$SHORTNAME $tag");
      $log->send(entity=>$entity,logmess=>$msg,loglevel=>$loglevel,logtag=>$tag);
   }
}

sub doSetup {
   # wait time before escalating
   $WAIT=$CFG->value("system.notification.wait") || 86400;
   $L->log ("Globally defined wait-time for escalation is: $WAIT","INFO");
   # get entity type for DATASET and USER
   my $tmpdataset=($db->getEntityTypeIdByName("DATASET"))[0];
   if (!defined $tmpdataset) {
      $L->log ("Failed to get type ID for DATASET from db: ".$db->error(),"CRIT");
      # so critical, we also log to screen
      print "ERROR! Failed to get type ID for DATASET from db: ".$db->error()."\n";
   } else { $DATASET=$tmpdataset; } # only update if we have an answer
   my $tmpuser=($db->getEntityTypeIdByName("USER"))[0];
   if (!defined $tmpuser) {
      $L->log ("Failed to get type ID for USER from db: ".$db->error(),"CRIT");
      # so critical, we also log to screen
      print "ERROR! Failed to get type ID for USER from db: ".$db->error()."\n";
   } else { $USER=$tmpuser; } # only update if we have an answer
   if ((!defined $DATASET) || (!defined $USER)) {
      $L->log ("We do not have any definition of type id for DATASET and/or USER to be using, so we had to abort execution!","CRIT");   
      die "FATAL! We do not have any definition of type id for DATASET and/or USER to be using, so we had to abort execution!";
   }
   @NOTICECLASSES=@{$CFG->value("system.notification.classes")};  
   # get notice-types id to name
   my $notices=$db->enumEntitiesByType([($db->getEntityTypeIdByName("NOTICE"))[0]]);
   if (!defined $notices) {
      # something failed enumerating notices
      $L->log ("Failed to enumerate notice entities: ".$db->error(),"ERR");
      print "ERROR! Failed to enumerate notice entities: ".$db->error()."\n";
   } else {
      if (keys %NOTICETYPES > 0) {
         my @l=keys %NOTICETYPES;
         $notices=\@l;
      }
   }
   if (!defined $notices) {
      # unable to continue
      $L->log ("Cannot find any notices defined, so we had to abort execution!","CRIT");   
      die "FATAL! We do not have any notices defined, so we had to abort execution!";
   }
   foreach (@{$notices}) {
      my $notice=$_;

      my $md=$db->getEntityMetadata($notice);
      if (!defined $md) {
         $L->log ("Unable to get metadata for notice entity $notice: ".$db->errror(),"ERR");   
         print "ERROR! Unable to get metadata for notice entity $notice: ".$db->error(),"ERR\n";;
      } else {
         $NOTICETYPES{$notice}=lc($md->{$SysSchema::MD{"name"}});
      }
      # if not defined already, we have to abort...
      if (!defined $NOTICETYPES{$notice}) {
         $L->log ("Missing any definition of notice $notice, so we have to abort execution!","CRIT");   
         die "FATAL! Missing any definition of notice $notice, so we have to abort execution!"
      }     
   }
}

sub signalHandler {
   my $sig=shift;

   if ($sig eq "HUP") {
      $L->log ("HUP-signal received. Reloading settings-file and updating internal variables","WARNING");
      # handle HUP by reloading config-file
      if ($CFG->load()) {
         # update essential settings
         doSetup();
         $L->log ("Settings-file reloaded successfully and internal variables updated","WARNING");
      } else {
         $L->log ("Unable to reload settings-file: ".$CFG->error(),"ERR");
      }
   }
}

