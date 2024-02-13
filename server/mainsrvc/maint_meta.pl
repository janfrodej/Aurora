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
# MAINT_META: AURORA service to perform maintenance of METADATA-tables
#
use strict;
use lib qw(/usr/local/lib/aurora);
use POSIX;
use Settings;
use AuroraDB;
use SysSchema;
use SystemLogger;
use Log;
use Time::HiRes qw(time);
use ISO8601;
use sectools;
use AuroraVersion;
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
my $BASENAME="$0 AURORA MAINT_META";
# set parent name
$0=$BASENAME." Daemon";
# set short name
my $SHORTNAME="MAINT_META";

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
my ($DMETA);

# setup operations defaults
doSetup();

# set last time the various
# maintenance operations where run (=never)
my $lmeta=0;

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
   if (($DMETA > 0) && ($time >= ($lmeta+$DMETA))) {
      $L->log ("Running metadata combined-operation.","INFO");      
      $lmeta=$time;
      maintainMetadata($db); # update/maintain METADATA_COMBINED-table
   }

   # wait a little bit
   sleep (1);
}

sub maintainMetadata {
   my $db=shift;
   # instantiate system log
   my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"));

   # start a transaction here
   my $trans=$db->useDBItransaction();

   # get all metadata that is to be deleted because of changes in METADATA-table
   my $sql=$db->doSQL("select MDC.entity,MDC.metadatakey,MDC.metadataidx FROM METADATA_COMBINED MDC ".
                      "left join METADATA MD on MDC.entity=MD.entity and MDC.metadatakey=MD.metadatakey and MDC.metadataidx=MD.metadataidx ". 
                      "where MDC.metadatakey NOT IN (25,27) and (MD.metadatakey IS NULL OR MD.metadataidx IS NULL)");

   if (!defined $sql) {
      # some error
      $L->log ("Unable to get metadata that has been removed from METADATA-table: ".$db->error(),"ERR");
      return;
   }

   # we have an answer, lets iterate over it and remove
   while (my @row=$sql->fetchrow_array()) {
      my $entity=$row[0];
      my $key=$row[1];
      my $idx=$row[2];

      my $delete=$db->doSQL("DELETE FROM METADATA_COMBINED WHERE entity=$entity and metadatakey=$key and metadataidx=$idx");
      if (!defined $delete) {
         # some error
         $L->log ("Unable to delete metadata from METADATA_COMBINED: ".$db->error(),"ERR");
         return;
      }
   }
   
   # get all metadata that is to be updated/have changed in METADATA-table
   $sql=$db->doSQL("select MD.entity,MD.metadatakey,MD.metadataidx,MD.metadataval FROM (select * from METADATA) MD ".
                   "left join (select * FROM METADATA_COMBINED where metadatakey <> 25 and metadatakey <> 27) MDC ".
                   "on MD.entity=MDC.entity and MD.metadatakey=MDC.metadatakey and MD.metadataidx=MDC.metadataidx ".
                   "WHERE MD.metadataval <> MDC.metadataval");

   if (!defined $sql) {
      # some error
      $L->log ("Unable to get metadata that has changed in METADATA-table: ".$db->error(),"ERR");
      return;
   }

   my $dbi=$db->getDBI();

   # we have an answer, lets iterate over it and remove
   while (my @row=$sql->fetchrow_array()) {
      my $entity=$row[0];
      my $key=$row[1];
      my $idx=$row[2];
      my $value=$row[3];
      $value=$dbi->quote($value);

      my $update=$db->doSQL("UPDATE METADATA_COMBINED set metadataval=$value where entity=$entity and metadatakey=$key and metadataidx=$idx");
      if (!defined $update) {
         # some error
         $L->log ("Unable to update metadata of METADATA_COMBINED: ".$db->error(),"ERR");
         return;
      }
   }

   # get all metadata that is new and do not exist in METADATA_COMBINED already
   $sql=$db->doSQL("select distinct MD.entity,MD.metadatakey,MD.metadataidx,MD.metadataval FROM ".
                   "(select * from METADATA) MD ".
                   "left join (select * FROM METADATA_COMBINED) MDC on MD.entity=MDC.entity and MD.metadatakey=MDC.metadatakey and MD.metadataidx=MDC.metadataidx ".
                   "WHERE MDC.metadataidx IS NULL and MDC.metadataval IS NULL");

   if (!defined $sql) {
      # some error
      $L->log ("Unable to get metadata that has changed in METADATA-table: ".$db->error(),"ERR");
      return;
   }

   # we have an answer, lets iterate over it and insert
   my $values="";
   while (my @row=$sql->fetchrow_array()) {
      my $entity=$row[0];
      my $key=$row[1];
      my $idx=$row[2];
      my $value=$row[3];
      $value=$dbi->quote($value);

      $values=($values eq "" ? "($entity,$key,$idx,$value)" : $values.",($entity,$key,$idx,$value)");
   }

   if ($values ne "") {
      $sql=$db->doSQL("INSERT INTO METADATA_COMBINED (entity,metadatakey,metadataidx,metadataval) VALUES $values");
      if (!defined $sql) {
         # some error
         $L->log ("Unable to insert metadata to METADATA_COMBINED: ".$db->error(),"ERR");
         return;
      }
   }

   # get all parentnames and computernames that are to be synthetically inserted
   # convert key id to key for name in the same process (P2.metadatakey+1).
   $sql=$db->doSQL("select distinct P2.entity as entity,P2.metadatakey+1 as metadatakey,P2.name as name from ".
                   "(select distinct P.entity,P.metadatakey as metadatakey,METADATA.metadataval as name FROM ".
                   "  (select METADATA.entity as entity,metadatakey,metadataval as parentid from METADATA ".
                   "    left join ENTITY on METADATA.entity=ENTITY.entity where metadatakey=24 or metadatakey=26) P ".
                   "    left join METADATA on P.parentid=METADATA.entity and METADATA.metadatakey=21) P2 ".
                   "left join METADATA_COMBINED on P2.entity=METADATA_COMBINED.entity and P2.metadatakey=METADATA_COMBINED.metadatakey-1 ".
                   "and (METADATA_COMBINED.metadatakey=25 or METADATA_COMBINED.metadatakey=27) ".
                   "where (METADATA_COMBINED.metadataval IS NULL OR METADATA_COMBINED.metadataval <> P2.name)");

   if (!defined $sql) {
      # some error
      $L->log ("Unable to get synthetic metadata to insert into METADATA_COMBINED-table: ".$db->error(),"ERR");
      return;
   }

   # we have an answer, lets iterate over it and insert/update where necessary
   while (my @row=$sql->fetchrow_array()) {
      my $entity=$row[0];
      my $key=$row[1];
      # the computer entity might be missing in some cases - set the name to blank
      my $value=($key == 27 ? (!defined $row[2] ? "" : $row[2]) : $row[2]);
      
      $value=$dbi->quote($value);

      my $replace=$db->doSQL("REPLACE INTO `METADATA_COMBINED` VALUES ($entity,$key,1,$value)");

      if (!defined $replace) {
         # some error
         $L->log ("Unable to replace metadata in METADATA_COMBINED: ".$db->error(),"ERR");
         return;
      }  
   }

   # update all missing or wrong entity type ids in METADATA and METADATA_COMBINED
   # 22 = entity type id
   # 23 = entity type name
   $sql=$db->doSQL("SELECT distinct METADATA.entity,ENTITY.entitytype,entitytypename FROM METADATA left join ENTITY on METADATA.entity = ENTITY.entity ".
                   "left join ENTITYTYPE on ENTITY.entitytype = ENTITYTYPE.entitytype WHERE METADATA.entity NOT IN ".
                   "(SELECT distinct METADATA.entity from METADATA left join ENTITY on METADATA.entity = ENTITY.entity where metadatakey = 22 AND ".
                   "metadataval = ENTITY.entitytype)");

   if (!defined $sql) {
      # some error
      $L->log ("Unable to get entities that have missing or wrong entity type id and type name: ".$db->error(),"ERR");
      return;
   }

   # we have an answer, lets iterate over it and insert/update where necessary
   while (my @row=$sql->fetchrow_array()) {
      my $entity=$row[0];
      my $type=$row[1];
      my $typename=$row[2];

      # if type is missing and we have typename, try to look it up
      if ((!defined $type) && (defined $typename)) {
         # get entity type from name, if not - skip
         my @tmptype = $db->getEntityTypeIdByName($typename);
         if (defined $tmptype[0]) {
            $type=$tmptype[0];
         } else {
            # something failed - skip this one
            next;
         }
      } elsif ((!defined $type) && (!defined $typename)) {
         # skip this one
         next;
      }
      
      $typename=$dbi->quote($typename);

      # first lets update/put in place entity type id in METADATA
      my $replace=$db->doSQL("REPLACE INTO `METADATA` VALUES ($entity,22,1,$type)");

      if (!defined $replace) {
         # some error
         $L->log ("Unable to replace metadata in METADATA: ".$db->error(),"ERR");
         return;
      }  

      # also update type id and type name in METADATA_COMBINED
      $replace=$db->doSQL("REPLACE INTO `METADATA_COMBINED` VALUES ($entity,22,1,$type),($entity,23,1,$typename)");

      if (!defined $replace) {
         # some error
         $L->log ("Unable to replace metadata in METADATA_COMBINED: ".$db->error(),"ERR");
         return;
      }  

   }

   $L->log ("Successfully updated the METADATA_COMBINED-table","INFO");

   return;
}

sub doSetup {
   # update maintenance operations defaults
   $DMETA=$CFG->value("system.maintenance.operations.metadata.interval");

   # ensure default if none defined
   if (!defined $DMETA) { $DMETA=30; }
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
      my $msg="Running with the following settings: METADATA: $DMETA";
      $L->log ($msg,"INFO");
      # also print to STDOUT this time
      print  "$msg\n";
   }
}

