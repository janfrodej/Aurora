#!/usr/bin/perl -w
#
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
# MAINTENANCESRVC: AURORA service to perform maintenance-operations on the system
#
use strict;
use lib qw(/usr/local/lib/aurora);
use POSIX;
use Settings;
use AuroraDB;
use SysSchema;
use SystemLogger;
use DistributionQueue;
use Notification;
use NotificationHandler;
use NotificationParser;
use Not;
use Log;
use MetadataCollection;
use Time::HiRes qw(time);
use ISO8601;
use fiEval;
use FileInterface;
use DistLog;
use Store;
use sectools;
use AuroraVersion;
use cacheHandler;
use cacheData;
use Content::Log;
use RestTools;
use Data::Dumper;

# version constant
my $VERSION=$AuroraVersion::VERSION;

# Children operations hash
my %CHILDS=();

# auto-reap children
$SIG{CHLD}="IGNORE";
# handle HUP signal myself (reload settings)
$SIG{HUP}=\&signalHandler;
# handle TERM signal myself (graceful exit)
$SIG{TERM}=\&signalHandler;
# handle SIG1 signal myself (status)
$SIG{USR1}=\&signalHandler;

# set base name
my $BASENAME="$0 AURORA MAINT_GEN";
# set parent name
$0=$BASENAME." Daemon";
# set short name
my $SHORTNAME="MAINT_GEN";

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
my $folder=($ENV{"AURORA_PATH"} ? $ENV{"AURORA_PATH"}."/notification" : "/local/app/aurora/notification");
# if we have a setting for location in config-files, use that instead.
$folder=($CFG->value("system.notification.location") ? $CFG->value("system.notification.location") : $folder);

# create notifications handler
my $nots=NotificationHandler->new(folder=>$folder);

# create parsing hash
my %notparse;

# maintenance operations defaults
my ($DEXPIRE,$DEXPIRED,$DNOT,$DDIST,$DINT,$DTOK,$DEMETA,$DDBCLEAN);

# setup operations defaults
doSetup();

# database updates not written yet because of failures.
my $CACHE = cacheHandler->new();
my $C_META = 1; # cache for metadata

# attempt to load cache that might be saved already
$CACHE->load();

# set last time the various
# maintenance operations where run (=never)
my $lexpire=0;
my $lexpired=0;
my $lnot=0;
my $ltok=0;
my $ldist=0;
my $lint=0;
my $lemeta=0;
my $ldbclean=0;

# loop until killed
while (1) {
   # database instance
   my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                        pw=>$CFG->value("system.database.pw"));

   # connect to database
   $db->getDBI();

   # update db-connection
   if (!$db->connected()) {
      $L->log ("Unable to connect to database: ".$db->error().". Will sleep a little and try again.","ERR");
      # wait a little bit
      sleep (10);
      # then try again
      next;
   } else {
      # update database with cache, if any
      cacheSync($db);
   }

   # get time right now
   my $time=time();

   # check if we are due or overdue for a new maintenance operation
   # interval of 0 or less means not to run that operation at all
   if (($DEXPIRE > 0) && ($time >= ($lexpire+$DEXPIRE))) {
      $L->log ("Running pre-expire-operation.","INFO");
      $lexpire=$time;
      maintainExpire($db); # datasets about to expire
   }
   if (($DEXPIRED > 0) && ($time >= ($lexpired+$DEXPIRED))) {
      $L->log ("Running expired-operation.","INFO");
      $lexpired=$time;
      maintainExpired($db); # datasets that have expired
   }
   if (($DNOT > 0) && ($time >= ($lnot+$DNOT))) {
      $L->log ("Running notification-operation.","INFO");
      $lnot=$time;
      maintainNotifications($db,$nots,\%notparse); # Cleanup and Deal with notifications, including deleting datasets
   }
   if (($DDIST > 0) && ($time >= ($ldist+$DDIST))) {
      $L->log ("Running distribution-operation.","INFO");      
      $ldist=$time;
      maintainDistributions($db); # Deal with failed distributions.
   }
   if (($DINT > 0) && ($time >= ($lint+$DINT))) {
      $L->log ("Running interface-operation.","INFO");      
      $lint=$time;
      maintainInterfaces($db); # Clean-up interface-rendered files
   }
   if (($DTOK > 0) && ($time >= ($ltok+$DTOK))) {
      $L->log ("Running token-operation.","INFO");      
      $ltok=$time;
      maintainTokens($db); # Clean-up/deal with timed out tokens.
   }
   if (($DEMETA > 0) && ($time >= ($lemeta+$DEMETA))) {
      $L->log ("Running entity metadata-operation.","INFO");
      $lemeta=$time;
      maintainEntityMetadata($db); # update/maintain entity metadata in METADATA
   }
   if (($DDBCLEAN > 0) && ($time >= ($ldbclean+$DDBCLEAN))) {
      $L->log ("Running DB cleanup-operations.","INFO");
      $ldbclean=$time;
      maintainDBCleanup($db); # clean up database
   }

   # attempt to disconnect database before sleeping
   $db->disconnect();

   # wait a little bit
   sleep (1);
}

# notification of approaching expire-date
sub maintainExpire {
   my $db=shift;

   # create log-instance
   my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));

   # get current time - use this all through this process
   # in order to use a set time for each comparison and dataset
   my $time=time();
   # add a year
   my $year=(86400*365);

   # get all datasets which is not removed (no time stamp and set to zero),
   # which is not still open (we do not send expire warnings on those),
   # and which expire from now and until a year from now
   my @md=("AND"); # all of the basic criteria has to be true
   push @md,{$SysSchema::MD{"dataset.removed"} => { "=" => 0 }}; 
   push @md,{$SysSchema::MD{"dataset.status"} => { "=" => $SysSchema::C{"status.closed"} }}; 
   push @md,{$SysSchema::MD{"dataset.expire"} => { "<=" => ($time+$year), ">=" => $time } }; 
   my $expiring=$db->getEntityByMetadataKeyAndType (\@md,undef,undef,$SysSchema::MD{"dataset.created"},"ASC",undef,[$db->getEntityTypeIdByName("DATASET")]);

   if (!defined $expiring) {
      $L->log ("Unable to query for expiring datasets: ".$db->error(),"ERR");
      return;
   }

   # we have results, within these results, we have to pull metadata to check 
   # notification intervals
   foreach (@{$expiring}) {
      my $id=$_;

      $L->log ("Checking dataset $id for impending expiration.","DEBUG");

      # fetch metadata of this dataset
      my $md=$db->getEntityMetadata($id);
      # fetch template for this dataset to find notification intervals
      my $tmpl=$db->getEntityTemplate($db->getEntityTypeIdByName("DATASET"),$db->getEntityPath($id));

      if (defined $md) {
         # we have metadata - lets pull the intervals
         my @intervals=@{$tmpl->{$SysSchema::MD{"dataset.intervals"}}{default}||[]};
         my %ints=map { $_ => 1 } @intervals;
         # get which intervals have already been notified
         my $n=$md->{$SysSchema::MD{"dataset.notified"}};
         my @notified;
         if ((defined $n) && (ref($n) eq "ARRAY")) {
            @notified=@{$n};
         } elsif (defined $n) { push @notified,$n; }
         my %nots=map { $_ => 1; } @notified;
         # get when the dataset is set to expire
         my $expire=$md->{$SysSchema::MD{"dataset.expire"}} || 0;
         my $closed=$md->{$SysSchema::MD{"dataset.closed"}} || 0;
         # go through each interval and check if they are
         # within time to notify or have already been notified
         foreach (sort { $a <=> $b } @intervals) {
            my $interval=$_;

            $L->log ("Checking notification interval $interval for dataset $id.","DEBUG");
            # check if interval has been notified already, if so skip it
            if (exists $nots{$interval}) { next; }
            if (cacheExists($C_META,$id,$interval,$SysSchema::MD{"dataset.notified"})) { next; } # it exists in cache, so already notified, skip it

            # check that we are within interval and further that the dataset has 
            # an expire-date that is sufficiently long from dataset close-time to
            # warrant a notification.
            if (($time >= ($expire-$interval)) && (($expire-$closed) >= $interval)) {
               # we are within the notification window (we have not notified already) - send notification
               $L->log ("Dataset $id are within notification of interval $interval.","DEBUG");

               my $isoexpire=time2iso($expire);
               my $days=ceil((($expire-$time)/86400)); # do not use interval, to avoid giving wrong info if notificaiton is somehow late
               my $daystr=($days == 1 ? "day" : "days");
               # calculate days in the interval itself
               my $intdays=ceil(($interval/86400));
               my $intdaystr=($intdays == 1 ? "day" : "days");
               my $not=Not->new();
               $L->log ("Creating dataset.expire-notification on dataset $id.","DEBUG");
               my $notid=$not->send(type=>"dataset.expire",about=>$id,from=>$SysSchema::FROM_MAINTENANCE,
                                    message=>"Hi,\n\nPlease be informed that the expiration of dataset with id $id \"".$md->{$SysSchema::MD{"dc.description"}}."\" created by user ".$md->{$SysSchema::MD{"dc.creator"}}." (".$md->{$SysSchema::MD{"dataset.creator"}}.")".
                                   "\nis approaching, which is on the:\n\n".
                                   $isoexpire.
                                   "\n\nin $days $daystr ($intdays $intdaystr pre-notification interval). Please take steps if needed to ensure your data is not lost.".
                                   "\n\nLogin to the AURORA-system from here:".
                                   "\n\n".$CFG->value("system.www.base").
                                   "\n\nBest regards,".
                                   "\n\n   Aurora System") || "";
               # update dataset log of notification
               my $msg="Dataset approaching expiration in $days $daystr on the $isoexpire ($intdays $intdaystr pre-notification interval). Notification $notid created.";
               $L->log ("Sending db log-message: $msg","DEBUG");
               $log->send(entity=>$id,logmess=>$msg,loglevel=>$Content::Log::LEVEL_INFO,logtag=>$SHORTNAME);
               # update dataset metadata on notification created for given interval
               push @notified,$interval;
               $L->log ("Updating dataset $id with notified info: @notified","DEBUG");
               # add notification to cache and let the cache handle the writing in the correct manner
               # all notifications needs to be added - old + new
               my %h;
               $h{$SysSchema::MD{"dataset.notified"}}=\@notified;
               cacheAdd($C_META,$id,\%h);
               # attempt to sync cache
               cacheSync($db);
            }
         }
      }
   }
}

sub maintainExpired {
   my $db=shift;

   # get current time
   my $time=time();

   # create log-instance
   my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));

   # get all datasets which have expired (both open and closed), so we can create a remove or close notification
   my @md=("AND"); # all of the basic criteria has to be true
   push @md,{$SysSchema::MD{"dataset.removed"} => { "=" => 0 }};
   push @md,{$SysSchema::MD{"dataset.expire"} => { "<=" => $time }};
   # do not select datasets that are still open and that are automated ones - they are to be handled
   # by the Store-service primarily. Failed distributions and their datasets are to be handled by
   # the failed distributions algorithm.
   push @md,["NOT",
               ["AND",{$SysSchema::MD{"dataset.status"} => { "=" => $SysSchema::C{"status.open"} }},
                      {$SysSchema::MD{"dataset.type"} => { "=" => $SysSchema::C{"dataset.auto"} }},
               ],
            ];

   my $expired=$db->getEntityByMetadataKeyAndType (\@md,undef,undef,$SysSchema::MD{"dataset.created"},"ASC",undef,[$db->getEntityTypeIdByName("DATASET")]);

   if (!defined $expired) {
      $L->log ("Unable to query for expired datasets: ".$db->error(),"ERR");
      return;
   }

   foreach (@{$expired}) {
      my $id=$_;

      # fetch metadata of this dataset
      my $md=$db->getEntityMetadata($id);
      # check for success
      if (!defined $md) {
         # something failed
         $L->log ("Unable to get metadata for dataset $id: ".$db->error(),"ERR");
         next;
      }
      # get dataset expire date
      my $expire=$md->{$SysSchema::MD{"dataset.expire"}};
      my $isoexpire=time2iso($expire);
      my $status=$md->{$SysSchema::MD{"dataset.status"}};
      # get which intervals have already been notified
      my $n=$md->{$SysSchema::MD{"dataset.notified"}};
      my @notified;
      if ((defined $n) && (ref($n) eq "ARRAY")) {
         @notified=@{$n};
      } elsif (defined $n) { push @notified,$n; }
      my %nots=map { $_ => 1 } @notified;
      if (exists $nots{$expire}) { next; } # already notified
      if (cacheExists ($C_META,$id,$expire,$SysSchema::MD{"dataset.notified"})) { next; } # exists in cache, so skip it
      # not notified, lets do so now
      my $not=Not->new();
      if ($status eq $SysSchema::C{"status.open"}) {
         # dataset is still open, so this is a expiration to close the dataset
         my $notid=$not->send(type=>"dataset.close",about=>$id,from=>$SysSchema::FROM_MAINTENANCE,expire=>$expire,
                              message=>"Hi,\n\nPlease be informed that dataset with id $id \"".$md->{$SysSchema::MD{"dc.description"}}."\" created by user ".$md->{$SysSchema::MD{"dc.creator"}}." (".$md->{$SysSchema::MD{"dataset.creator"}}.") has been open for too long and has expired on the:\n\n".
                             $isoexpire.
                             "\n\nPlease confirm the closure message below by voting or take steps to extend the time the dataset can be open. ".
                             "Failing to do any of these steps will incur penalties and escalation of the close dataset event.".
                             "\n\nLogin to the AURORA-system from here:".
                             "\n\n".$CFG->value("system.www.base").
                             "\n\nBest regards,".
                             "\n\n   Aurora System") || "";

         # update dataset log of notification
         my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));
         my $msg="Dataset has expired on the $isoexpire while still open. A close dataset notification $notid has been created.";
         $log->send(entity=>$id,logmess=>$msg,loglevel=>$Content::Log::LEVEL_INFO,logtag=>$SHORTNAME);
      } else {
         # dataset is already closed, so this is a dataset remove message
         my $notid=$not->send(type=>"dataset.remove",about=>$id,from=>$SysSchema::FROM_MAINTENANCE,expire=>$expire,
                              message=>"Hi,\n\nPlease be informed that dataset with id $id \"".$md->{$SysSchema::MD{"dc.description"}}."\" created by user ".$md->{$SysSchema::MD{"dc.creator"}}." (".$md->{$SysSchema::MD{"dataset.creator"}}.") has expired on the:\n\n".
                             $isoexpire.
                             "\n\nPlease confirm this removal message below or take steps to extend the lifespan of the dataset. ".
                             "Failing to do any of these steps will incur penalties and escalation of the remove dataset event.".
                             "\n\nLogin to the AURORA-system from here:".
                             "\n\n".$CFG->value("system.www.base").
                             "\n\nBest regards,".
                             "\n\n   Aurora System") || "";

         # update dataset log of notification
         my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));
         my $msg="Dataset has expired on the $isoexpire. A remove dataset notification $notid has been created.";
         $log->send(entity=>$id,logmess=>$msg,loglevel=>$Content::Log::LEVEL_INFO,logtag=>$SHORTNAME);
      }

      # add new expired to notifications
      push @notified,$expire;
      # add notification to cache and let the cache handle the writing in the correct manner
      # all notifications needs to be added - old + new
      my %h;
      $h{$SysSchema::MD{"dataset.notified"}}=\@notified;
      cacheAdd($C_META,$id,\%h);
      # attempt to sync cache
      cacheSync($db);
   }
}

sub maintainNotifications {
   my $db=shift;
   my $nots=shift;
   my $PARSE=shift;

   # get notification types
   my %nottypes=%{$CFG->value("system.notification.types")};

   my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));

   # instantiate Not
   my $notif=Not->new();

   # read all notifications present
   $nots->update();
   $nots->resetNext();
   while (my $not=$nots->getNext()) {
      my $id=$not->id() || 0;
      $L->log ("Checking notification $id for FIN-event.","DEBUG");
           
      # check if disabled or not
# disabling fin-marker checking for now. Cleaning up notifications need to ignore
# fin-markers. It needs to repeat attempting to remove until successful
#      if ((exists $PARSE->{$id}) && ($PARSE->{$id}{disabled})) { next; } # just in memory
#      if ((exists $PARSE->{$id}) && ($PARSE->{$id}{fin})) { next; } # written to event

      # create notification parser instance
      my $parser=NotificationParser->new(nottypes=>\%nottypes, db=>$db);

      # parse latest from notification
      my $state=$PARSE->{$id};
      $state=$parser->parse($not,$state);

      if (!defined $state) { $L->log("Failed to parse state of $id: ".$parser->error(),"ERR"); next; } # something failed.

      # we have a new state, also get last event data
      my %event=%{$parser->lastEvent()};

      # update our parse-HASH
      $PARSE->{$id}=$state;

      if (!defined $event{event}) { $L->log("Event type was not defined for $id. Skipping to next event.","INFO"); next; }

      if ($event{event} == $Notification::FIN) {
         # this notification has finished its work. Lets check if it is a 
         # dataset-remove notification or not
         my $about=$state->{about} || 0;
         my $from=$state->{from} || 0;
         my $cancel=$state->{cancel} || 0;
         my $type=$state->{type} || "";
         my @empty;
         my $threadids=\@empty;
         if ((exists $state->{threadids}) && (defined $state->{threadids})) {
            $threadids=$state->{threadids};
         }

         $L->log ("Notification $id has the FIN-event. Notification-type is: $type","DEBUG");
         if (lc($type) eq "dataset.remove") {
            # this is a remove event - needs to be handled. Get metadata of dataset
            my $md=$db->getEntityMetadata($about);
            if (!defined $md) { $L->log("Unable to get metadata of entity $about: ".$db->error(),"ERR"); }
            if (!$cancel) {
               # no expire increase, this dataset is to be removed
               $L->log ("Notification $id is a ended \"dataset.remove\"-type, removing the dataset $about.","DEBUG");
               # open fileinterface
               my $ev=fiEval->new();
               if (!$ev->success()) {
                  $L->log ("Unable to instantiate fiEval: ".$ev->error(),"ERR");
                  next;
               }
               if (!$ev->evaluate("remove",$about)) {
                  # failed to remove dataset, 
                  $L->log ("Unable to remove dataset $about that had expired: ".$ev->error(),"ERR");
                  next;
               }
               # removal was successful - also tag removed tag in metadata, let the cache handle it
               my %rmd;
               $rmd{$SysSchema::MD{"dataset.removed"}}=time();
               cacheAdd($C_META,$about,\%rmd);
               # attempt to sync cache
               cacheSync($db);
 
               # send notification that dataset was removed, include old threads
               my $notid=$notif->send(type=>"dataset.info",about=>$about,from=>$SysSchema::FROM_MAINTENANCE,threadids=>$threadids,
                                      message=>"Hi,\n\nPlease be informed that the dataset with id $about \"".($md->{$SysSchema::MD{"dc.description"}}||"")."\" created by ".($md->{$SysSchema::MD{"dc.creator"}}||"")." (".$md->{$SysSchema::MD{"dataset.creator"}}.") has has been removed.".
                                      "\n\nTo login to the AURORA-system use:".
                                      "\n\n".$CFG->value("system.www.base").
                                     "\n\nBest regards,".
                                     "\n\n   Aurora System") || "";

               # input log entry
               my $msg="Dataset expired and was now removed. Notification $notid has been created.";
               $log->send(entity=>$about,logmess=>$msg,loglevel=>$Content::Log::LEVEL_INFO,logtag=>$SHORTNAME);
               # update distlog.
               my $entry=createDistLogEntry(
                                          event=>"REMOVE",
                                          fromid=>$about,
                                          uid=>$from
                                        );
               $log->send(entity=>$about,logmess=>$entry,loglevel=>$Content::Log::LEVEL_DEBUG,logtag=>"$SHORTNAME DISTLOG");
            } else {
               # this was cancelled/stopped - no removal of data
               $L->log ("Notification $id of type $type was cancelled. No removal of data.","DEBUG");
               # send notification that removal was stopped, include threadids               
               my $notid=$notif->send(type=>"dataset.info",about=>$about,from=>$SysSchema::FROM_MAINTENANCE,threadids=>$threadids,
                                      message=>"Hi,\n\nPlease be informed that the removal process of dataset with id $about \"".$md->{$SysSchema::MD{"dc.description"}}."\" created by ".$md->{$SysSchema::MD{"dc.creator"}}." (".$md->{$SysSchema::MD{"dataset.creator"}}.") has been cancelled.".
                                      "\n\nTo login to the AURORA-system use:".
                                      "\n\n".$CFG->value("system.www.base").
                                     "\n\nBest regards,".
                                     "\n\n   Aurora System") || "";
               # no removal - write db log entry
               my $msg="Dataset removal was cancelled in notification $id. No dataset removal will be performed at this time. Notification $notid was created.";
               $log->send(entity=>$about,logmess=>$msg,loglevel=>$Content::Log::LEVEL_INFO,logtag=>$SHORTNAME);
            }
         } elsif ((lc($type) eq "dataset.close") && ($cancel == 0)) {
            # this is a dataset close event which was not cancelled, so close it.
            my $md=$db->getEntityMetadata($about);
            if (!defined $md) { 
               # if we cannot get the metadata, we skip to next and wait with closing the dataset
               $L->log ("Unable to retrieve metadata of $about: ".$db->error(),"ERR");
               next;
            }
            # we have the metadata - check if it is removed in the meantime
            # if it is not been removed, just skip this part and go straight to 
            # deleting the notification.
            if ($md->{$SysSchema::MD{"dataset.removed"}} == 0) {
               # dataset has not been removed, we can close it               
               # open fileinterface
               my $ev=fiEval->new();
               if (!$ev->success()) {
                  $L->log ("Unable to instantiate fiEval: ".$ev->error(),"ERR");
                  next;
               }
               # attempt to get datapath to dataset
               my $path=$ev->evaluate("datapath",$about); # get path to data
               if (!defined $path) {
                  # something failed getting the datapath
                  $L->log ("Unable to find datapath for dataset $about: ".$ev->error(),"ERR");
                  # this is a more critical error that needs to be dealt with, move notification to alternative folder
                  # so that it is left alone by ht maintenance-service
                  if (!$nots->move($nots->folder()."/$id",$nots->folder()."/.failed/$id")) {
                     # failed to move notification - let log know
                     $L->log ("Failed to move notification $id due to critical failure: ".$nots->error(),"ERR");
                     next;
                  }
                  # notify admins that the notification has been disabled and moved to failed because of
                  # a critical error
                  my $notid=$notif->send(type=>"dataset.info",about=>1,from=>$SysSchema::FROM_MAINTENANCE,threadids=>$threadids,
                                         message=>"Hi,\n\nPlease be informed that the dataset with id $about \"".($md->{$SysSchema::MD{"dc.description"}}||"")."\" created by ".($md->{$SysSchema::MD{"dc.creator"}}||"UNKNOWN")." (".$md->{$SysSchema::MD{"dataset.creator"}}.") could not be closed due to a critical error: ".$ev->error()." It has been moved to failed to avoid further disturbances.".
                                        "\n\nTo login to the AURORA-system use:".
                                        "\n\n".$CFG->value("system.www.base").
                                        "\n\nBest regards,".
                                        "\n\n   Aurora System") || "";
                  # add log entry
                  $log->send(entity=>$about,logtag=>$SHORTNAME,logmess=>"Unable to close dataset due to critical error: ".$ev->error()." The close dataset notification has been moved to failed and notification $notid created and sent to root (1).");
                  next;
               }

               # get just template for parent 
               my $parent=$db->getEntityParent($about);
               if (!$parent) {
                  $L->log ("Failed to close dataset $about because of failure to get parent id:  ".$db->error(),"ERR");
                  next;
               }
               my $tmplparent=$db->getEntityTemplate($db->getEntityTypeIdByName("DATASET"),$db->getEntityPath($parent));
               if (!defined $tmplparent) {
                  $L->log ("Failed to close dataset $about because of failure to get parent $parent template:  ".$db->error(),"ERR");
                  next;
               }

               # calculate its size
               my $store=Store->new();
               # open store, if possible
               if (!$store->open(remote=>"/tmp/dummy",local=>$path)) {
                  # something failed opening the Store
                  $L->log ("Unable to close dataset $about because we failed to open Store to calculate its size: ".$store->error(),"ERR");
                  next;
               }
               # calculate size
               my $size=$store->localSize();
               if (!defined $size) {
                  # something failed
                  $L->log ("Unable to close dataset $about because we failed to calculate its size: ".$store->error(),"ERR");
                  next;
               }

               # close dataset
               if (!$ev->evaluate("close",$about)) {
                  # failed to close dataset, 
                  $L->log ("Unable to close dataset $about: ".$ev->error(),"ERR");
                  next;
               }

               # dataset is closed, write dataset metadata
               # decide the lifespan based on template from praent
               my $lifespan=8888888888; # default to a long time to ensure nothing just disappears
               if ((exists $tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}{default})) {
                  $lifespan=$tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}{default};
               }

               # storage area closed, we have the size - store it and set status to closed
               my $time=time();
               my %nmd;
               $nmd{$SysSchema::MD{"dataset.size"}}=$size;
               $nmd{$SysSchema::MD{"dataset.status"}}=$SysSchema::C{"status.closed"};
               $nmd{$SysSchema::MD{"dataset.closed"}}=$time;
               # also set its expire date upon closing
               $nmd{$SysSchema::MD{"dataset.expire"}}=$time+$lifespan;
               # reset notified intervals, empty array will erase old values
               my @empty;
               $nmd{$SysSchema::MD{"dataset.notified"}}=\@empty;

               # add changes to cache and let the cache handle the writes
               cacheAdd($C_META,$about,\%nmd);
               # attempt to sync cache with db
               cacheSync($db);
               # notify user(s) that dataset was closed by maintenance-service
               my $notid=$notif->send(type=>"dataset.info",about=>$about,from=>$SysSchema::FROM_MAINTENANCE,threadids=>$threadids,
                                      message=>"Hi,\n\nPlease be informed that the dataset with id $about \"".($md->{$SysSchema::MD{"dc.description"}}||"")."\" created by ".($md->{$SysSchema::MD{"dc.creator"}}||"UNKNOWN")." (".$md->{$SysSchema::MD{"dataset.creator"}}.") has been closed by the Maintenance-service.".
                                     "\n\nTo login to the AURORA-system use:".
                                     "\n\n".$CFG->value("system.www.base").
                                     "\n\nBest regards,".
                                     "\n\n   Aurora System") || "";

               # Dataset has been closed, so we need to reacquire path
               $path=$ev->evaluate("datapath",$about);
               if (defined $path) {
                  # list contents of dataset, recursive and with md5-summing and 
                  # utf8 decode. Save to dataset log
                  my $struct=listFolders($path,1,1,1);
                  my @nlisting;
                  recurseListing($struct,\@nlisting,"");
                  # we have a list of entries that can be added to log after successful close
                  foreach (@nlisting) {
                     my $entry=$_;
                     # add log entry
                     $log->send(entity=>$about,logtag=>$SHORTNAME." TRANSFER",logmess=>$entry,loglevel=>$Content::Log::LEVEL_DEBUG);
                  }
               }

               # add log entry
               $log->send(entity=>$about,logtag=>$SHORTNAME,logmess=>"Dataset closed by the Maintenance-service. Notification $notid created.");
               # add a distribution log entry
               my $entry=createDistLogEntry(
                                            event=>"TRANSFER",
                                            from=>"UNKNOWN",
                                            fromid=>$SysSchema::FROM_UNKNOWN,
                                            fromhost=>"",
                                            fromhostname=>"",
                                            fromloc=>"",
                                            toloc=>$about,
                                            uid=>$from
                                           );

               $log->send(entity=>$about,logtag=>$SHORTNAME." DISTLOG",logmess=>$entry,loglevel=>$Content::Log::LEVEL_DEBUG);  
            }
         } elsif ((lc($type) eq "dataset.close") && ($cancel == 1)) {
            # closing of dataset was cancelled - inform user
            my $md=$db->getEntityMetadata($about);
            if (!defined $md) { $L->log ("Unable to get metadata of entity $about: ".$db->error(),"ERR"); }
            # notify user(s) that closing of dataset was cancelled
            my $notid=$notif->send(type=>"dataset.info",about=>$about,from=>$SysSchema::FROM_MAINTENANCE,threadids=>$threadids,
                                   message=>"Hi,\n\nPlease be informed that the closure of dataset with id $about \"".$md->{$SysSchema::MD{"dc.description"}}."\" created by ".$md->{$SysSchema::MD{"dc.creator"}}." (".$md->{$SysSchema::MD{"dataset.creator"}}.") has been cancelled.".
                                  "\n\nTo login to the AURORA-system use:".
                                  "\n\n".$CFG->value("system.www.base").
                                  "\n\nBest regards,".
                                  "\n\n   Aurora System") || "";
            # add log entry
            $log->send(entity=>$about,logtag=>$SHORTNAME,logmess=>"Dataset closure was cancelled in notification $id. Notification $notid created.");
         }
         # just clean away the notification
         $L->log ("Removing notification $id.","DEBUG");
         # delete parse-hash data for this id
         delete ($PARSE->{$id});
         # remove notification itself
         if (!$nots->delete($not)) {
            # something went sideways - log it
            $L->log ("Failed to delete notification: ".$db->error(),"ERR");
         }
      }
   }
}

sub maintainDistributions {
   my $db=shift;

   # create log-instance
   my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));

   # dist queue instance
   my $dq=DistributionQueue->new(folder=>$CFG->value("system.dist.location"));

   # get datasets to work on
   my $maxretry=$CFG->value("system.dist.maxretry") || 2;
   my $ancient=$CFG->value("system.maintenance.dist.timeout") || (86400*30);

   $L->log ("Looking for failed distributions that have been retried its maximum of times.","INFO");

   # get distributions that are failed and maxretry has been used up (we cheat by putting maxretry+1 and adding timeout)
   # these sets are in the FAILED-phase and a certain amount of time must have passed.
   my $failed=$dq->enumTasks(undef,undef,$SysSchema::C{"status.failed"},$maxretry+1,$ancient);

   foreach (keys %{$failed}) {
      my $task=$_;

      # get random task id
      my $taskid=$dq->getTaskRandomID($task);

      $L->log ("Found distribution-task $taskid that has failed-status.","DEBUG");

      # get dataset id
      my $did=$failed->{$task}{datasetid} || 0;

      # check if we are in the right phase
      my $retry=$failed->{$task}{tags}{retry};
      my $phase=$failed->{$task}{tags}{phase};
      if ($phase ne $SysSchema::C{"phase.failed"}) { next; } # we are not interested in this one

      $L->log ("Distribution-task $taskid is also in failed-phase. Dealing with this task.","DEBUG");

      # all requirements are met, this task needs to be dealt with
      # attempt to rapture the task
      if ($dq->raptureTask($task)) {
         # task has been raptured
         $L->log ("Distribution-task $taskid has experienced rapture...","DEBUG");
         # add log entry
         $log->send(entity=>$did,logtag=>$SHORTNAME,logmess=>"Distribution-task $taskid has experienced rapture...");
      } else {
         # failed rapturing task
         $L->log ("Distribution-task $taskid could not be raptured: ".$dq->error(),"ERROR");
      }
   }  
}

# clean up after interfaces, such as zip/tar
sub maintainInterfaces {
   my $db=shift;

   my $folder=$CFG->value("interface.archive.location") || "";
   my $grace=$CFG->value("system.maintenance.interface.tmp.timeout") || 1209600;

   if ($folder eq "") { return; }

   # we are ready to check if any zip/tar files are ready to be removed
   if (opendir (DH,"$folder")) {
      # we were able to open folder for reading it
      my @items=grep { $_ =~ /^.*\.(zip|tar\.gz|lock)$/ } readdir DH;
      # close dir-handler
      closedir (DH);
      # go through each match and check time
      my $time=time();
      foreach (@items) {
         my $item=$_;

         my $ftime=(stat("$folder/$item"))[8] || 0; # access time
         if ($time > ($ftime+$grace)) {
            # delete file
            $L->log("Removing interface file $item because of usage-timeout.","DEBUG");
            unlink ("$folder/$item");
         }
      }
   } 
}

sub maintainTokens {
   my $db=shift;

   # get current time
   my $time=time();

   # instantiate system log
   my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));

   # get all datasets that have any token defined on it and it has passed or is equal to current time
   my @md=("AND"); # all of the basic criteria has to be true
   push @md,{$SysSchema::MD{"dataset.tokenbase"}.".*.expire" => { "<" => $time }};
   my ($ids)=$db->getEntityByMetadataKeyAndType (\@md,undef,undef,$SysSchema::MD{"dataset.created"},"ASC",undef,[$db->getEntityTypeIdByName("DATASET")]);

   if (!defined $ids) {
      $L->log ("Unable to query for datasets with tokens: ".$db->error(),"ERR");
      return;
   }

   # go through all datasets that have expired tokens
   foreach (@{$ids}) {
      my $id=$_;

      # get dataset metadata to select each expired token
      my $md=$db->getEntityMetadata($id);

      if (!defined $md) { 
         $L->log ("Unable to get metadata for dataset $id: ".$db->error(),"ERR");
         next;
      }

      # convert metadata to MetadataCollection
      my $mdc=MetadataCollection->new(base=>$SysSchema::MD{"dataset.tokenbase"},depth=>3);
      my $mdh=$mdc->metadata2Hash($md);

      # get tokens that have expired
      my @tokens;
      foreach (keys %{$mdh}) {
         my $token=$_;
         my $expire=$mdh->{$token}{expire};
         if ((defined $expire) && ($time > $expire)) { push @tokens,$token; }
      }

      # open fileinterface to remove tokens
      my $ev=fiEval->new();
      if (!$ev->success()) {
         $L->log ("Unable to instantiate fiEval: ".$ev->error(),"ERR");
         next;
      }

      # go through each expired token and notify fileinterface to removed them
      foreach (@tokens) {
         my $token=$_;

         if (!$ev->evaluate("tokenremove",$token)) {
            # failed to remove dataset, 
            $L->log ("Unable to expire token $token on dataset $id that has expired: ".$ev->error(),"ERR");
            next;
         }
         # success - remove token from metadata
         my @empty;
         my %smd;
         $smd{$SysSchema::MD{"dataset.tokenbase"}.".${token}.expire"}=\@empty;

         # add changes to cache and let the cache handle the writes
         cacheAdd($C_META,$id,\%smd);
         # attempt to sync cache with db
         cacheSync($db);

         # notify log that token was removed
         my $sum=substr(sectools::sha256sum($token),0,8);
         $log->send(entity=>$id,logtag=>$SHORTNAME,logmess=>"Token $sum is expired and has been removed.",loglevel=>$Content::Log::LEVEL_INFO);  
      }
   }
}

sub maintainEntityMetadata {
   my $db=shift;
   # instantiate system log
   my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));

   # start a transaction here
   my $trans=$db->useDBItransaction();

   # get all metadata that is to be deleted because of changes in METADATA-table
   my $sql=$db->doSQL("SELECT ENTITY.entity,entityparent,entitytype,metadatakey,metadataval from ENTITY ".
                      "LEFT JOIN METADATA on ENTITY.entity=METADATA.entity and METADATA.metadatakey IN (20,22,24) ".
                      "WHERE metadataval IS NULL OR (metadatakey = 22 and entitytype <> metadataval)");

   if (!defined $sql) {
      # some error
      $L->log ("Unable to get entity metadata that is missing or has changed: ".$db->error(),"ERR");
      return;
   }

   # we have a result - lets iterate over it and fill the METADATA-table
   my $replace;
   while (my @row=$sql->fetchrow_array()) {
      my $entity=$row[0];
      my $parent=$row[1];
      my $type=$row[2];
      my $key=$row[3];
      my $val;

      # we will do a replace, since changes/faults in this entity metadata should be
      # quite rare
      if (!defined $key) {
         # we have no way of knowing which of keys 20 (id), 22 (type) and 24 (parent) is missing
         # so we write all 3
         $replace=$db->doSQL("REPLACE INTO `METADATA` VALUES ($entity,20,1,$entity),($entity,22,1,$type),($entity,24,1,$parent)");
      } else {
         # we only write the key of row in the operation
         # we do not know if value is wrong or missing, so we look at key and fill in
         # the right value from the ENTITY-table part of the result.
         if ($key == 20) { $val=$entity; }
         if ($key == 22) { $val=$type; }
         if ($key == 24) { $val=$parent; }
         $replace=$db->doSQL("REPLACE INTO `METADATA` VALUES ($entity,$key,1,$val)");
      }

      if (!defined $replace) {
         # some error
         $L->log ("Unable to replace entity-metadata in METADATA: ".$db->error(),"ERR");
         return;
      }
   }

   $L->log ("Successfully checked and/or updated entity-metadata in the METADATA-table","INFO");
}

sub maintainDBCleanup {
   my $db=shift;
   # instantiate system log
   my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));

   # get lifespan of a statlog entry, defaults to 3 months
   my $lifespan=$CFG->value("system.maintenance.statlog.lifespan");
   $lifespan=(defined $lifespan ? $lifespan : 7776000);
   # get lifespan of a tunnell log entry, defaults to 3 months
   my $tunlifespan=$CFG->value("system.maintenance.tunnellog.lifespan");
   $tunlifespan=(defined $tunlifespan ? $tunlifespan : 7776000);
   # get lifespan of a userlog entries, defaults to 3 months
   my $userlifespan=$CFG->value("system.maintenance.userlog.lifespan");
   $userlifespan=(defined $userlifespan ? $userlifespan : 7776000);

   # calculate statlog threshold
   my $threshold = time() - $lifespan;

   # calculate tunnell log threshold
   my $tunthreshold = time() - $tunlifespan;

   # calculate userlog threshold
   my $userthreshold = time() - $userlifespan;

   # start a transaction here
   my $trans=$db->useDBItransaction();

   my $sql;

   # only attempt removal of statlogs if value is positive. Zero-value means keep indefinetly
   if ($lifespan) {
      # ensure that we do not have entries in statlog that are older than
      # what the config allows (lifespan)
      $sql = $db->doSQL("DELETE FROM STATLOG WHERE timedate < $threshold");
      if (!defined $sql) {
         # something failed - notify and exit
         $L->log ("Unable to delete old statlog-entries from database: ".$db->error(),"ERR");
         return;
      }
   }

   # only attempt removal of tunnell logs if values is positive
   # zero-value means keep indefintely
   if ($tunlifespan) {
      # also remove all tunnell-logs that are above threshold
      $sql = $db->doSQL("DELETE FROM LOG where logtime < $tunthreshold and logtag = \"RESTSRVC TUNNEL\" AND ".
                        "entity in (select entity from ENTITY natural left join ENTITYTYPE WHERE ".
                        "entitytypename = \"COMPUTER\")");
      if (!defined $sql) {
         $L->log ("Unable to delete old tunnel-log entries from the database: ".$db->error(),"ERR");
         return;
      }
   }

   # only attempt removal of userlogs if value is positive. Zero-value means keep indefinetly
   if ($userlifespan) {
      # ensure that we do not have entries in userlog that are older than
      # what the config allows (userlifespan)
      $sql = $db->doSQL("DELETE FROM USERLOG WHERE timedate < $userthreshold");
      if (!defined $sql) {
         # something failed - notify and exit
         $L->log ("Unable to delete old userlog-entries from database: ".$db->error(),"ERR");
         return;
      }
   }

   # success - we can exit
   $L->log ("Successfully cleaned up database...","INFO");
}

sub cacheExists {
   my $type=shift || 0;
   my $id = shift || 0; # AURORA entity id
   my $value = shift || 0;
   my $name = shift || ""; # value name, optional

   # check if we have a cacheData object already, if not create one
   my $cache;
   if ($CACHE->exists($id)) { $cache=$CACHE->get($id); }
   else { return 0; }
   # get existing content
   my $content=$cache->get();
   # check if we have a hash, if not create one
   if (!ref($content) eq "HASH") { my %h; $content=\%h; $cache->set($content); }

   if ($type == $C_META) {
      # check if given value exists in metadata specified by name
      my $found=0;
      my $ref;
      # go through all metadata entries as a sorted journal.
      # last value for a given key is left standing
      foreach (sort {$a <=> $b} keys %{$content->{$type}}) {
         my $time=$_;
         if (exists $content->{$type}{$time}{$name}) {
            # a value exists here - put a ref to it
            $ref=$content->{$type}{$time}{$name};
         }
      }
      # now lets check the ref it is other than undef
      if (defined $ref) {
         # check the refs value if we find what we are looking for?        
         if (ref($ref) eq "ARRAY") {
            my %h=map { $_ => 1; } @{$ref};
            # check if value desired exists in cache or not?
            if (exists $h{$value}) { $found=1; }  
         } else {
            if ($ref eq $value) { $found=1; }
         }
      }
      return $found;
   } else {
      # this is an invalid type, so the value does not exist
      return 0;
   }
}

sub cacheAdd {
   my $type = shift || 0;
   my $id = shift || 0; # AURORA entity ID
   my $value = shift || 0;

   # check if we have a cacheData object already, if not create one
   my $cache;
   if ($CACHE->exists($id)) { $cache=$CACHE->get($id); }
   else { $cache=cacheData->new(id=>$id); $CACHE->add($cache); }
   # get existing content, if any
   my $content=$cache->get();
   # check if we have a hash, if not create one
   if (!ref($content) eq "HASH") { my %h; $content=\%h; $cache->set($content); }

   if ($type == $C_META) {
      # metadata, add to new position
      my $h=$content->{$type};
      # let the order of the metadata entries be decided
      # by hi-res time
      my $time=time();
      # add metadata reference
      $content->{$type}{$time}=$value;
      $cache->set($content);
      cacheWrite();
      return 1;
   } else {
      # invalid type, ergo invalid operation
      return 0;
   } 
}

sub cacheWrite {
  # write all cache to file 
  if (!$CACHE->save()) {
     # something failed updating cache, notify log
     $L->log ("Unable to write cache to file: ".$CACHE->error(),"ERR");            
     return 0;
  } else { return 1; }
}

sub cacheSync {
   my $db=shift;
   # sync cache with database and empty as needed
   # go through each cacheData-instance in the cache-handler
   $CACHE->resetGetNext();
   while (my $cd=$CACHE->getNext()) {
      my $data=$cd->get();
      my $id=$cd->id();
      if (ref($data) ne "HASH") { $L->log("Invalid metadata for id $id in DB-sync. Must be HASH-reference.","ERR"); next; } # invalid data, ignore it
#      if (ref($data) ne "HASH") { $CACHE->remove($id); next; } # invalid data, remove it?
      my %md;
      # first do metadata, go through metadata as it was added, in ascending order by time
      foreach (sort { $a <=> $b } keys %{$data->{$C_META}}) {
         my $time=$_;
         my $mdata=$data->{$C_META}{$time};
         if (ref($mdata) ne "HASH") { $L->log("Invalid metadata for id $id in DB-sync. Must be HASH-reference.","ERR"); next; } # invalid metadata, skip it
         # accumulate metadata, overwriting old with new
         %md=(%md,%{$mdata});
      }
      # then attempt to write metadata to database
      # set override option to force update of critical system metadata
      if ($db->setEntityMetadata($id,\%md,undef,undef,1)) {
         # remove cacheData-instance from cache-handler
         $CACHE->remove($cd);
         # save cache to file to ensure consistency
         cacheWrite();
      } else {
         # we failed to update metadata, lets notify about that
         $L->log ("Unable to sync metadata cache with AURORA database for id $id: ".$db->error(),"ERR");            
      }
   }
}

sub doSetup {
   # update maintenance operations defaults
   $DEXPIRE=$CFG->value("system.maintenance.operations.expire.interval");
   $DEXPIRED=$CFG->value("system.maintenance.operations.expired.interval");
   $DNOT=$CFG->value("system.maintenance.operations.notification.interval");
   $DDIST=$CFG->value("system.maintenance.operations.distribution.interval");
   $DINT=$CFG->value("system.maintenance.operations.interface.interval");
   $DTOK=$CFG->value("system.maintenance.operations.token.interval");
   $DEMETA=$CFG->value("system.maintenance.operations.entitymetadata.interval");
   $DDBCLEAN=$CFG->value("system.maintenance.operations.dbcleanup.interval");

   # ensure default if none defined
   if (!defined $DEXPIRE) { $DEXPIRE=(3600*5); }
   if (!defined $DEXPIRED) { $DEXPIRED=(3600*5); }
   if (!defined $DNOT) { $DNOT=(3600*5); }
   if (!defined $DDIST) { $DDIST=(3600*5); }
   if (!defined $DINT) { $DINT=(3600*5); }
   if (!defined $DTOK) { $DTOK=(3600*5); }
   if (!defined $DEMETA) { $DEMETA=300; }
   if (!defined $DDBCLEAN) { $DDBCLEAN=86400; }
}

sub signalHandler {
   my $sig=shift;

   if ($sig eq "HUP") {
      $L->log ("HUP-signal received. Reloading settings-file and updating internal variables","WARNING");
      # handle HUP by reloading config-files
      if ($CFG->load()) {
         # update essential settings
         doSetup();
         $L->log ("Settings-file reloaded successfully and internal variables updated","WARNING");
      } else {
         $L->log ("Unable to reload settings-file: ".$CFG->error(),"ERR");
      }
   } elsif ($sig eq "TERM") {
      # terminate mainsrvc.pl gracefully
      $L->log ("$sig-signal received. Saving cache and exiting...","WARNING");
      cacheWrite();
      exit(0);
   } elsif ($sig eq "USR1") {
      # terminate mainsrvc.pl gracefully
      my $msg="Running with the following settings: EXPIRE: $DEXPIRE EXPIRED: $DEXPIRED NOTIFICATION: $DNOT DISTRIBUTION: $DDIST ".
              "INTERFACE: $DINT TOKEN: $DTOK ENTITY-METADATA: $DEMETA DBCLEANUP: $DDBCLEAN";
      $L->log ($msg,"INFO");
      # also print to STDOUT this time
      print  "$msg\n";
   }
}

