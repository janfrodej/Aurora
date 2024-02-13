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
use Schema;
use SysSchema;
use Settings;
use Term::ReadKey;
use AuroraDB;
use Time::HiRes qw(time);
use Data::Dumper;

my $CFG=Settings->new();
$CFG->load("system.yaml");

if (@ARGV == 0) {
   print "$0 Get a complete overview of who have access to COMPUTER- and DATASET-resources\n\n";
   print "SYNTAX: $0 [PREFIX of FILENAMES]\n\n";
   print "Saves files to [PREFIX]-computers.csv and [PREFIX]-datasets.csv\n\n";
   exit (0);
}

my $db=AuroraDB->new(
    data_source=>$CFG->value("system.database.datasource"),
    user=>$CFG->value("system.database.user"),
    pw=>$CFG->value("system.database.pw")
);

my $dbi=$db->getDBI();

if (!defined $dbi) {
   die "Unable to connect to the AURORA-database: ".$db->error()."\n";
}

if (!$db->connected()) {
   die "Not connected to the AURORA-database...\n";
}

# we are ready
my $file=$ARGV[0] || "dummy";

# open file
my $COMP;
if (!open ($COMP,">","$file-computers.csv")) {
   die "Unable to open CSV-file $file-computers.csv: $!\n";
}

# first get statistics of computer use
print "Generating and saving matrix on computers and who have access ($file-computers.csv)...\n";
my @ctype=$db->getEntityTypeIdByName("COMPUTER");
my @utype=$db->getEntityTypeIdByName("USER");

my $cents=doit($db,"enumEntitiesByType",\@ctype);

# get the display names of all the computers
my $names=doit($db,"getEntityMetadataList",$SysSchema::MD{"name"},$cents);

# go through each computer found
my $line="COMPUTER;COMPUTERID;RESPONSIBLE-USERS;USERS WITH ACCESS\n";
print $COMP $line;
foreach (@{$cents}) {
   my $computer=$_;

   # new line in the csv
   $line="";

   # get computer display name
   my $name=$names->{$computer} || "NOT DEFINED ($computer)";
   $line=$line."$name;$computer;";

   # who is responsible for the computer?
   my $rents=doit($db,"getEntityPermsForObject",$computer,$db->createBitmask($db->getPermTypeValueByName("COMPUTER_CHANGE")),@utype);
   # get each responsible users name
   my $rnames=doit($db,"getEntityMetadataList",$SysSchema::MD{"name"},[keys %{$rents}]);
   # add each user entity to responsible column
   $line=$line.join(",",map { escapeit($rnames->{$_}) } keys %{$rents});

   # ensure semicolon at the end of line
   $line=($line =~ /^.*\;$/ ? $line : $line.";" );

   # get USER-entities that have COMPUTER_READ permission on the the computer in question
   my $uents=doit($db,"getEntityPermsForObject",$computer,$db->createBitmask($db->getPermTypeValueByName("COMPUTER_READ")),@utype);
   # get each responsible users name
   my $unames=doit($db,"getEntityMetadataList",$SysSchema::MD{"name"},[keys %{$uents}]);
   # add each user entity to responsible column
   $line=$line.join(",",map { escapeit($unames->{$_}) } keys %{$uents});

   # mark as utf8
   utf8::encode($line);

   # write info to file
   print $COMP "$line\n";
}

close ($COMP);

my $DSET;
if (!open ($DSET,">","$file-datasets.csv")) {
   die "Unable to open CSV-file $file-datasets.csv: $!\n" ;
}

print "Generating and saving matrix on datasets and who have list and read access ($file-datasets.csv)...\n";

# get statistics of datasets
my @dtype=$db->getEntityTypeIdByName("DATASET");
my $dents=doit($db,"enumEntitiesByType",\@dtype);

# get the description of all datasets
my $descr=doit($db,"getEntityMetadataList",$SysSchema::MD{"dc.description"},$dents);

# go through each dataset found
$line="DATASET ID;DESCRIPTION;COMPUTER;COMPUTERID;CREATOR;LIST ACCESS;READ ACCESS\n";
print $DSET $line;
foreach (@{$dents}) {
   my $dataset=$_;

   $line="";

   # get dataset metadata
   my $dmd=doit($db,"getEntityMetadata",$dataset);
   my $computer=$dmd->{$SysSchema::MD{"dataset.computer"}};
   # get computer name
   my $cname="COMPUTER DELETED ($computer)";
   if ($db->existsEntity($computer)) {
      $cname=doit($db,"getEntityMetadata",$computer,$SysSchema::MD{name});
      $cname=$cname->{$SysSchema::MD{name}};
   }
   # get creator
   my $creatorid=$dmd->{$SysSchema::MD{"dataset.creator"}};
   my $creator="USER DELETED ($creatorid)";
   if ($db->existsEntity($creatorid)) {
      $creator=doit($db,"getEntityMetadata",$creatorid,$SysSchema::MD{name});
      $creator=$creator->{$SysSchema::MD{name}};
   }
   $line=$line."$dataset;".$descr->{$dataset}.";$cname;$computer;$creator;";

   # get users with list access
   my $uents=doit($db,"getEntityPermsForObject",$dataset,$db->createBitmask($db->getPermTypeValueByName("DATASET_LIST")),@utype);

   # get each users name
   my $unames=doit($db,"getEntityMetadataList",$SysSchema::MD{"name"},[keys %{$uents}]);
   # add each user entity to column
   $line=$line.join(",",map { escapeit($unames->{$_}) } keys %{$uents});

   # ensure semicolon at the end of line
   $line=($line =~ /^.*\;$/ ? $line : $line.";" );

   # get users with read access to dataset
   $uents=doit($db,"getEntityPermsForObject",$dataset,$db->createBitmask($db->getPermTypeValueByName("DATASET_READ","DATASET_CHANGE")),@utype);

   # get each users name
   $unames=doit($db,"getEntityMetadataList",$SysSchema::MD{"name"},[keys %{$uents}]);
   # add each user entity to column
   $line=$line.join(",",map { escapeit($unames->{$_}) } keys %{$uents});

   # mark as utf8
   utf8::encode($line);

   # write info to file
   print $DSET "$line\n";
}

close ($DSET);

sub doit {
   my $db=shift;
   my $method=shift;
   my @args=@_;

   my $res=$db->$method(@args);

   if (!defined $res) {
      die "Unable to get result from $method: ".$db->error()."\n";
   } else {
      return $res;
   }
}

sub escapeit {
   my $str=shift;

   $str=~s/([\;\,])/\\$1/g;

   return $str;
}
