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
use Settings;
use SysSchema;
use AuroraDB;
use LogParser;

# settings instance
my $CFG=Settings->new();
$CFG->load();

# get parameters
my %opts;
my $pos=-1;
my $valpos=-1;
foreach (@ARGV) {
   my $arg=$_;
   $arg=~s/^\s+(.*)\s+$/$1/;
   $pos++;

   if ($arg =~ /^\-(\w+)$/) {
      my $lcarg=lc($1);
      $opts{$lcarg}=(defined $ARGV[$pos+1] ? $ARGV[$pos+1] : "");
      $valpos=$pos+1;
   } 
}

# show header
header();

if ((@ARGV == 0) || (!exists $opts{i})) {
   help();
   exit(1);
}

my $id = $opts{i} || 0;

# database instance
my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

# connect to database
$db->getDBI();

# update db-connection
if (!$db->connected()) {
   print "Unable to connect to DB: ".$db->error()."\n";
   exit(1);
}

# check that id is a dataset or not
if ($db->getEntityTypeName($id) ne "DATASET") {
   print "Error! The entity id $id is not a dataset entity or does not exist. Unable to proceed...\n";
   exit(1);
}

# get dataset log
my $log = $db->getLogEntries($id);

if (!$log) {
   print "Error! Unable get entity ${id}'s log entries: ".$db->error().". Unable to proceed...\n";
   exit(1);
}

# get dataset metadata
my $md = $db->getEntityMetadata($id);
if (!defined $md) {
   print "Error! Unable to get entity ${id}'s metadata: ".$db->error().". Unable to proceed...\n";
}

# parse log and mine data
my $plog = LogParser->new(log=>$log);
my $logdata=$plog->parse();

# go to the correct option selected
my $optok=0;
if ($opts{c}) { $optok=1; fix_closed($id,$db,$logdata,$md); }
if ($opts{n}) { $optok=1; fix_notint($id,$db,$logdata,$md); }
if ($opts{r}) { $optok=1; fix_removed($id,$db,$logdata,$md); }
if ($opts{s}) { $optok=1; fix_status($id,$db,$logdata,$md); }
if ($opts{sz}) { $optok=1; fix_size($id,$db,$logdata,$md); }
if ($opts{t}) { $optok=1; fix_type($id,$db,$logdata,$md); }

if (!$optok) { print "Error! No accepted options found. Unable to continue...\n"; exit(1); }

# fix closed dataset
sub fix_closed {
   my $id = shift;
   my $db = shift;
   my $log = shift;
   my $md = shift;

   # get value of close-option
   my $value = uc($opts{c} || "");

   if (($value ne $SysSchema::C{"status.open"}) && ($value ne $SysSchema::C{"status.closed"})) {
      print "Error! Setting status \"$value\" is not valid. Unable to continue...\n";
   }

   my $ans=""; # count as force in a force scenario
   if (!$opts{f}) {
      # no force, so ask if ok
      print "Set status of dataset $id to $value? Y/N [y]: ";
      $ans=<STDIN>;
      $ans=~s/[\r\n]//g;
      $ans=uc($ans);
   }

   if (($ans eq "") || ($ans eq "Y")) {
      # decided to go ahead / force
      my %upd = ( $SysSchema::MD{"dataset.status"} => $value, );
      my $res = $db->setEntityMetadata($id,\%upd);
      if (defined $res) {
         # success
         print "Success! Updated dataset $id status key to \"$value\"...\n";
      } else {
         print "Error! Unable to update dataset $id status key: ".$db->error()."\n";
      }
   }
}

# fix notification intervals, if expire has long since 
# passed and its datetime also exists in the intervals.
sub fix_notint {
   my $id = shift;
   my $db = shift;
   my $log = shift;
   my $md = shift;
}

# fix missing or wrong removed time
sub fix_removed {
   my $id = shift;
   my $db = shift;
   my $log = shift;
   my $md = shift;

   my $removed = (exists $log->{removed_time} && $log->{removed_time} > 0 ? $log->{removed_time} : 0);

   if ($removed) {
      my $reply=""; # will count as force in force-scenario
      if (!$opts{f}) {
         print "Removal time was: $removed\n";
         print "Proceed? [Y] Y/N : ";
         my $reply=<STDIN>;
         $reply=~s/[\r\n]//g;
         $reply=uc($reply);
      }
      if (($reply eq "") || ($reply eq "Y")) {
         # decided to go ahead / force 
         print "Setting \"".$SysSchema::MD{"dataset.removed"}."\" of $id to $removed...\n";
         my %upd = ( $SysSchema::MD{"dataset.removed"} => $removed, );
         my $res = $db->setEntityMetadata($id,\%upd);
         if (defined $res) {
            # success
            print "Success! Updated dataset $id removed value to \"$removed\"...\n";
         } else {
            print "Error! Unable to update dataset $id removed value: ".$db->error()."\n";
         }
      }
   }
}

# fix a dataset status-flag (OPEN vs CLOSED)
sub fix_status {
   my $id = shift;
   my $db = shift;
   my $log = shift;
   my $md = shift;

   my $value = uc($opts{s} || "");

   if (($value ne $SysSchema::C{"status.open"}) && ($value ne $SysSchema::C{"status.closed"})) {
      print "Error! Setting status \"$value\" is not valid. Unable to continue...\n";
   }

   my $ans=""; # count as force in a force scenario
   if (!$opts{f}) {
      # no force, so ask if ok
      print "Set status of dataset $id to $value? Y/N [y]: ";
      $ans=<STDIN>;
      $ans=~s/[\r\n]//g;
      $ans=uc($ans);
   }

   if (($ans eq "") || ($ans eq "Y")) {
      # decided to go ahead / force
      my %upd = ( $SysSchema::MD{"dataset.status"} => $value, );
      my $res = $db->setEntityMetadata($id,\%upd);
      if (defined $res) {
         # success
         print "Success! Updated dataset $id status key to \"$value\"...\n";
      } else {
         print "Error! Unable to update dataset $id status key: ".$db->error()."\n";
      }
   }
}

# fix the local size stored in the metadata
sub fix_size {
   my $id = shift;
   my $db = shift;
   my $log = shift;
   my $md = shift;

}

# fix the dataset type if not valid
sub fix_type {
   my $id = shift;
   my $db = shift;
   my $log = shift;
   my $md = shift;

   my $value = uc($opts{t} || "");

   if (($value ne $SysSchema::C{"dataset.man"}) && ($value ne $SysSchema::C{"dataset.aut"})) {
      print "Error! Setting type \"$value\" is not valid. Unable to continue...\n";
   }

   my $ans=""; # count as force in a force scenario
   if (!$opts{f}) {
      # no force, so ask if ok
      print "Set type of dataset $id to $value? Y/N [y]: ";
      $ans=<STDIN>;
      $ans=~s/[\r\n]//g;
      $ans=uc($ans);
   }

   if (($ans eq "") || ($ans eq "Y")) {
      # decided to go ahead / force 
      my %upd = ( $SysSchema::MD{"dataset.type"} => $value, );
      my $res = $db->setEntityMetadata($id,\%upd);
      if (defined $res) {
         # success
         print "Success! Updated dataset $id type key to \"$value\"...\n";
      } else {
         print "Error! Unable to update dataset $id type key: ".$db->error()."\n";
      }
   }
}

sub header {
   print "$0 Copyright(C) 2023 Jan Frode Jæger, NTNU, Trondheim\n\n";
}

sub help {
   print "Syntax:\n";
   print "\nFix dataset metadata\n";
   print "\n";
   print "   $0 [OPTION] [VALUE]\n";
   print "\n";
   print "Valid options:\n";
   print "\n";
   print "   -c  [1|0]    Fix closed dataset.\n";
   print "   -f  [1|0]    Force changes without prompts. BOOLEAN. Optional.\n";
   print "   -i  [n]      Dataset ID to work with. INTEGER. Required.\n";
   print "   -n  [1|0]    Fix notification intervals of dataset.\n";
   print "   -r  [1|0]    Fix removed-time metadata.\n";
   print "   -s  [STATUS] Fix dataset status. STATUS is the status to set.\n";
   print "   -sz [1|0]    Fix dataset size.\n";
   print "   -t  [TYPE]   Fix dataset type. TYPE is the type to set.\n";
   print "\n";
}
