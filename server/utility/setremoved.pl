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

# settings instance
my $CFG=Settings->new();
$CFG->load();

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

my $id=$ARGV[0] || 0;

# check that id is a dataset or not
if ($db->getEntityTypeName($id) ne "DATASET") {
   print "Error! The entity id $id is not a dataset entity or does not exist. Unable to proceed...\n\n";
   exit(1);
}

# get dataset log
my $log = $db->getLogEntries($id);

if (!$log) {
   print "Error! Unable get entity ${id}'s log entries: ".$db->error().". Unable to proceed...\n\n";
   exit(1);
}

# go through log and attempt to get removed timestamp
my $removed=0;
foreach (sort {$a <=> $b} keys %{$log}) {
   my $no = $_;

   # check if we started another round of the acquire-phase
   if ($log->{$no}{message} =~ /Dataset\s+expired\s+and\s+was\s+now\s+removed/) {
      $removed=$log->{$no}{time};
      last;
   }
}

if ($removed) {
   print "Removal time was: $removed\n";
   print "Proceed? [Y] Y/N : ";
   my $reply=<STDIN>;
   $reply=~s/[\r\n]//g;
   $reply=uc($reply);
   if (($reply eq "") || ($reply eq "Y")) {
      # decided to go ahead
      print "Updating metadata of $id....\n";
      my $res=$db->doSQL("UPDATE METADATA set metadataval=$removed where metadatakey=125 and entity=$id");
      print "RESULT: $res\n";
   }
}
