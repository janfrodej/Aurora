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
# dbquery: query/update data from/in AURORA database
#
use strict;
use lib qw(/usr/local/lib/aurora);
use POSIX;
use Settings;
use AuroraDB;
use Schema;
use SystemLogger;
use Log;
use Time::HiRes qw(time);
use AuroraVersion;
use Sys::Hostname;

# version constant
my $VERSION=$AuroraVersion::VERSION;

my $BASENAME=$0;

my %SRC=(
   1 => "RESTSRVC",
   2 => "MAINT_GEN",
   3 => "NOTSRVC",
   4 => "LOGSRVC",
   5 => "STORESRVC ".uc(hostname()),
   6 => "FI",
);

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

if (@ARGV == 0) {
   help();
}

# database instance
my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

# connect to database
my $dbi=$db->getDBI();

# update db-connection
if ((!defined $dbi) || (!$db->connected())) {
   print "Unable to connect to database: ".$db->error()."\n";
   exit(1);
}

# check for query
if ((!exists $opts{id}) || (!exists $opts{s})) {
   help("Missing parameter \"id\" and/or \"s\".");
}

# get id and log entry string and clean them
my $id=$Schema::CLEAN_GLOBAL{id}->($opts{id});
my $entry=$Schema::CLEAN{logmess}->($opts{s});
# clean optional values, if any
my $im;
if (defined $opts{im}) { $im=$SRC{$Schema::CLEAN_GLOBAL{id}->($opts{im})}; }
my $tag;
if (defined $opts{t}) { 
   $tag=$Schema::CLEAN{logtag}->($opts{t}); 
   # if imitate service has been set, combine the imitation with the 
   # manual tag
   if (defined $im) {
	$tag = $im." ".$tag;
   }
} elsif (defined $im) {
   # no tag defined, but imitate is set, so tag is equal to imitate
   $tag=$im;
}
my $time;
if (defined $opts{tm}) { $time=$Schema::CLEAN{logtime}->($opts{tm}); }
# default level to INFO (2)
my $level=2;
if (defined $opts{l}) { $level=$Schema::CLEAN{loglevel}->($opts{l}); }

# attempt to add log entry to AURORA database
if ($db->setLogEntry($time,$id,$level,$tag,$entry)) {
   print "Successfully added given log entry to entity $id...\n";
} else {
   help ($db->error());
}

sub help {
   my $error=shift;

   print "$BASENAME, version $VERSION, Copyright(C) 2022 NTNU\n";
   print "\nAdd a log entry to AURORA\n\n";
   print "Syntax:\n";
   print "   $0 [OPT] [OPTVALUE]\n";
   print "\n";
   print "The following options are available:\n\n";
   print "   -id Dataset ID to add log entry to. Required.\n";
   print "   -s  Log entry string to add. Required.\n";
   print "   -l  Integer loglevel of log entry. Optional. Defaults to INFORMATION:\n";
   print "           1 = DEBUG, 2 = INFORMATION, 3 = WARNING,\n";
   print "           4 = ERROR, 5 = FATAL\n";
   print "   -t  Log entry tag. Optional, defaults to \"NONE\". Free-text [a-zA-Z0-9_-]{1,16}.\n";
   print "   -tm Time stamp of log entry (unixtime UTC). Optional. Defaults to current time.\n";
   print "   -im Imitate source of log entry as one of the AURORA-services:\n";
   print "           1 = REST-server, 2 = Maintenance-service, 3 = Notification-service,\n";
   print "           4 = LOG-service, 5 = Store-service, 6 = FileInterface\n";
   if (defined $error) {
      print "\nERROR! $error\n";
   }
   print "\n";
   exit(0);
}
