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
use strict;
use lib qw(/usr/local/lib/aurora);
use AuroraDB;
use Settings;
use Log;
use SystemLogger;
use Time::HiRes qw(time);
use Data::Dumper;
use AuroraVersion;
use DBD::SQLite::Constants ':dbd_sqlite_string_mode';

# version constant
my $VERSION=$AuroraVersion::VERSION;

# set debug level
my $DEBUG="ERR";

# get command line options (key=>value)
my %OPT=@ARGV;
%OPT=map {uc($_) => $OPT{$_}} keys %OPT;
# see if user has overridden debug setting
if (exists $OPT{"-D"}) { 
   my $d=$OPT{"-D"} || "ERR";
   $DEBUG=$d;
}

# set base name
my $BASENAME="$0 AURORA Log-Service";
# set parent name
$0=$BASENAME." Daemon";
# set short name
my $SHORTNAME="LOGSRVC";

# instantiate syslog logger
my $L=SystemLogger->new(ident=>"$BASENAME",priority=>$DEBUG);
if (!$L->open()) { die "Unable to open SystemLogger: ".$L->error(); }

my $CFG=Settings->new();
$CFG->load();

print "$BASENAME, version $VERSION, Copyright(C) 2019 NTNU\n\n";

# AURORA database instance
my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

# log instance
my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),
                 user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"),
                 sqlite_string_mode=>DBD_SQLITE_STRING_MODE_UNICODE_FALLBACK);

# disable buffering when using sleep
$| = 1;

# loop until killed
my $logfile=$CFG->value("system.log.filename");
my $mtstamp=0;
while (1) {
   # get log database files modified time
   my $cmtstamp=(stat($logfile))[9] || 0;
   # wait one second before going on to ensure that the saved timestamp is old enough
   sleep(1);
   # get dbi instance to keep the db connection alive
   my $dbi=$db->getDBI();
   if (!defined $dbi) {
      if (!$L->log ("Unable to connect to database: ".$db->error(),"ERR")) { print "ERROR: ".$L->error()."\n"; }
      # wait 3 sec before moving on
      sleep (3);
      next;
   }
   # if current modified time is larger than saved modified time - update logs
   if ((defined $dbi) && ($cmtstamp > $mtstamp)) {
      my $coll;
      if (!($coll=$log->receive())) {
         die time()." ERROR! receiving log-messages: ".$log->error()."\n";
      } else {
         $L->log ("Number of log entries found to potentially add to AURORA: ".$coll->size(),"DEBUG");
         # create a Content::Log instance
         my $cl=Content::Log->new();
         # go through each log entry
         $coll->resetnext();
         # first we add each content to a hash sorted on entity id
         my %add;
         while (my $c=$coll->next()) {
            my $entity=$c->value("entity");
            my $pos = (keys %{$add{$entity}}) + 1 || 1;
            # add current record to the entity hash
            $add{$entity}{$pos} = $c;
         }
         # go through each entity and add its log entry(ies)
         foreach (keys %add) {
            my $entity = $_;
            # create a new ContentCollection instance
            my $scoll=ContentCollection->new(type=>$cl);
            my $abort=0;
            my $count=0;
            # go through each entry in entity and add it to database
            foreach (keys %{$add{$entity}}) {
               my $pos = $_;
               # put log entry into Aurora
               my $logtime=$add{$entity}{$pos}->value("logtime");
               my $loglevel=$add{$entity}{$pos}->value("loglevel");
               my $logtag=$add{$entity}{$pos}->value("logtag");
               my $logmess=$add{$entity}{$pos}->value("logmess");
               # check if entity exists or not, if not skip it so we do not hang the logger on invalid entity ids
               if (!$db->existsEntity($entity)) { $L->log ("Entity $entity does not exist. Skipping this log entry.","WARNING"); next; }
               $L->log ("Adding log entry to AURORA database: $logtime $entity $loglevel $logtag ".($logmess||"undef"),"DEBUG");
               if (!$db->setLogEntry($logtime,$entity,$loglevel,$logtag,$logmess)) {
                  $L->log ("Unable to add log entry to AURORA: ".$db->error(),"ERR");
                  # we abort processing here, since log entries need to be added in correct order, so we cannot skip any
                  $L->log (" Aborting processing...","FATAL");
                  $abort=1;
                  last;
               } else {
                  # add log entry to successful collection            
                  $scoll->add($add{$entity}{$pos});
                  $count++;
               }
            }
            $L->log ("Added $count log entries to AURORA database.","DEBUG");
            # check abort flag
            if (!$abort) {
               # update to saved timestamp on log database file
               $mtstamp=$cmtstamp;
            }
            # delete log entries that were successfully added
            $L->log ("Cleaning up and deleting log entries that were successfully added to AURORA...","INFO");
            if (!$log->delete($scoll)) {
               $L->log ("Unable to delete log entries from temporary log location: ".$log->error(),"WARNING");
            }
         }
      }
   } else {
      # no change to database - doing nothing
      $L->log ("No changes to log database file. Doing nothing.","DEBUG");
   }
   # wait 3 sec before moving on
   sleep (3);
}
