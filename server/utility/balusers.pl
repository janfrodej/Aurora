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
use SysSchema;
use Data::Dumper;
use UnicodeTools;

my $CFG=Settings->new();
$CFG->load("system.yaml");

my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

my $dbi;
if (!defined ($dbi=$db->getDBI())) {
   die "Error ".$db->error()."\n";
} 

# parameters are:
# ARGV0 = parent i

if (!defined $ARGV[0]) {
   print "$0 [parent]\n";
   print "\n";
   print "Parent specified the entity id of the parent group for which you wish to balance its USER-entity children.\n\n";
   exit(1);
}

# get parent id
my $parent=$ARGV[0] || 0;

# check if entity is a group
if ($db->getEntityTypeName($parent) ne "GROUP") {
   print "ERROR! The chosen parent id $parent is not a GROUP-type entity or it does not exist. Unable to proceed...\n";
   exit (1);
}

# get the parents children that are users
my $uchldr=$db->getEntityChildren($parent,[$db->getEntityTypeIdByName("USER")],0);
if (!defined $uchldr) {
   print "ERROR! Unable to retrieve the parents USER children: ".$db->error()."\n";
   exit (1);
}

# get the name of all the children
my $uchildren=$db->getEntityMetadataList($SysSchema::MD{fullname},$uchldr);
if (!defined $uchildren) {
   print "ERROR! Unable to retrieve the USER childrens fullnames: ".$db->error()."\n";
   exit(1);
}

# get all group children of parent
my $gchldr=$db->getEntityChildren($parent,[$db->getEntityTypeIdByName("GROUP")],0);
if (!defined $gchldr) {
   print "ERROR! Unable to get parent entity ${parent}\'s GROUP children: ".$db->error()."\n";
   exit(1);
}
my $gchildren=$db->getEntityMetadataList($SysSchema::MD{name},$gchldr);
if (!defined $gchildren) {
   print "ERROR! Unable to get names of parent entity ${parent}\'s children: ".$db->error()."\n";
   exit(1);
}

my $uno=@{$uchldr};
print "Number of users to move: $uno\n";
# go through each child and move it to sub-group
foreach (keys %{$uchildren}) {
   my $user=$_;
   my $name=$uchildren->{$user};
   my $group=$parent;

   my $letter=uc(map2azmath(map2az(substr($name,0,1))));

   my $found=0;
   foreach (keys %{$gchildren}) {
      my $c=$_;

      if ($gchildren->{$c} eq $letter) { $found=$c; last; }
   }
   # if found, set that as group
   if ($found) { $group=$found; }
   else {
      # start transaction
      my $trans=$db->useDBItransaction();
      # sub-group does not exist already - create it
      my $grp=$db->createEntity($db->getEntityTypeIdByName("GROUP"),$parent);
      if (!defined $grp) {
         print "ERROR! Unable to create child group of parent $parent: ".$db->error()."\n";
         $trans->rollback();
         exit(1);
      }
      my %md;
      $md{$SysSchema::MD{name}}=$letter;
      if (!$db->setEntityMetadata($grp,\%md)) {
         print "ERROR! Unable to set group name when creating group \"$letter\": ".$db->error()."\n";
         $trans->rollback();
         exit(1);
      } else { $group=$grp; }
      # update group children hash
      $gchildren->{$grp}=$letter;
   }
   # now, lets move the USER entity into the group
   print "Moving USER $user ($name) to GROUP $group (".$gchildren->{$group}.")...\n";
   if (!$db->moveEntity($user,$group)) {
      print "ERROR! Unable to move USER $user ($name) into GROUP $group (".$gchildren->{$group}."): ".$db-error()."\n";
      exit(1);
   }
}

