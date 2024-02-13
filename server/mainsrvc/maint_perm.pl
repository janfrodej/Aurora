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
# MAINT_PERM: AURORA service to perform maintenance-operations permission-related tables
#
use strict;
use lib qw(/usr/local/lib/aurora);
use POSIX;
use Settings;
use AuroraDB;
use SysSchema;
use SystemLogger;
use Log;
use MetadataCollection;
use Time::HiRes qw(time);
use ISO8601;
use sectools;
use AuroraVersion;

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
my $BASENAME="$0 AURORA MAINT_PERM";
# set parent name
$0=$BASENAME." Daemon";
# set short name
my $SHORTNAME="MAINT_PERM";

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

# maintenance operations defaults
my ($DSEQ,$DEFF);

# setup operations defaults
doSetup();

# set last time the various
# maintenance operations where run (=never)
my $lseq=0;
my $leff=0;

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
   } 

   # get time right now
   my $time=time();

   # check if we are due or overdue for a new maintenance operation
   # interval of 0 or less means not to run that operation at all
   if (($DSEQ > 0) && ($time >= ($lseq+$DSEQ))) {
      $L->log ("Running sequence-operation.","INFO");      
      $lseq=$time;
      maintainSequences($db); # check/fix sequence-table errors
   }
   if (($DEFF > 0) && ($time >= ($leff+$DEFF))) {
      $L->log ("Running permeffective-operation.","INFO");      
      $leff=$time;
      maintainPermEffective($db); # update/maintain permeffective-table
   }

   # wait a little bit
   sleep (1);
}

sub maintainSequences {
   my $db=shift;

   # get current time
   my $time=time();
   # instantiate system log
   my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));

   # check if we have orphaned entities in the ENTITY_SEQUENCE-table
   my $sql=$db->doSQL ("DELETE from ENTITY_SEQUENCE where entity not in (SELECT entity FROM ENTITY)");
   if (!defined $sql) {
      # problem deleting from sequence-table. Log error and move on...
      $L->log ("Unable to delete possible orphans from ENTITY_SEQUENCE-table: ".$db->error(),"ERR");
      return;
   }

   # check if sequences are missing
   my $ok=1;
   $sql=$db->doSQL ("SELECT * FROM `ENTITY` LEFT JOIN `ENTITY_SEQUENCE` on ENTITY.entity=ENTITY_SEQUENCE.entity WHERE sequence is NULL");
   if (!defined $sql) {
      # something failed with doing the query, log and move on
      $L->log ("Unable to perform ENTITY_SEQUENCE-table integrity check: ".$db-error(),"ERR");
      return;
   } else {
      # we have a result, check that the number of rows are 0, if not we have a sequence-table error
      my @rows=$sql->fetchrow_array();
      if (@rows > 0) { $ok=0; }
   }

   $sql=$db->doSQL ("select e.entity FROM ENTITY e join ENTITY_SEQUENCE es on es.entity=e.entity ".
                    "join ENTITY_SEQUENCE ps on ps.entity=e.entityparent WHERE ps.sequence > es.sequence");
   if (!defined $sql) {
      # something failed with doing the query, log and move on
      $L->log ("Unable to perform ENTITY_SEQUENCE-table integrity check: ".$db-error(),"ERR");
      return;
   } else {
      # we have a result, check that the number of rows are 0, if not we have a sequence-table error
      my @rows=$sql->fetchrow_array();
      if (@rows > 0) { $ok=0; }
   }

   if (!$ok) {
      $L->log ("There are integrity issues with the ENTITY_SEQUENCE-table. Attempting correction.","ERR");
      # sequence the entire entity tree since we do not know where or what branch of the tree is the problem
      my $total=$db->sequenceEntity(1);
      if ($total == 0) {
         # some issue with the sequencing, return error and move on
         $L->log ("Unable to correct integrity issues with the ENTITY_SEQUENCE-table: ".$db->error(),"ERR");  
      } else {
         $L->log ("Successfully corrected the ENTITY_SEQUENCE-table. Number of corrected entities: $total","INFO");
      }
   } else { $L->log ("Integrity of ENTITY_SEQUENCE-table is ok.","INFO"); }

   return;
}

sub maintainPermEffective {
   my $db=shift;

   # instantiate system log
   my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));

   # run update of permeffective-table from the AuroraDB-library
   my $res=$db->updateEffectivePermsConditional();

   if (!defined $res) {
      # something went belly up (as we say)
      $L->log ("Unable to update permeffective-table: ".$db->error(),"ERR");
      return;
   }

   $L->log ("Successfully updated permeffective-table.","INFO");

   return;
}

sub doSetup {
   # update maintenance operations defaults
   $DSEQ=$CFG->value("system.maintenance.operations.sequence.interval");
   $DEFF=$CFG->value("system.maintenance.operations.permeffective.interval");

   # ensure default if none defined
   if (!defined $DSEQ) { $DSEQ=3600; }
   if (!defined $DEFF) { $DEFF=5; }
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
      $L->log ("$sig-signal received. Exiting...","WARNING");
      exit(0);
   } elsif ($sig eq "USR1") {
      # terminate mainsrvc.pl gracefully
      my $msg="Running with the following settings: SEQUENCE: $DSEQ PERMEFF: $DEFF";
      $L->log ($msg,"INFO");
      # also print to STDOUT this time
      print  "$msg\n";
   }
}

