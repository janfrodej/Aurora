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

my $CFG=Settings->new();
$CFG->load("system.yaml");

my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

my $dbi;
if (!defined ($dbi=$db->getDBI())) {
   die "Error ".$db->error()."\n";
} 

if (!defined $ARGV[0]) {
   print "$0 [entity] [type]\n";
   print "\n";
   print "\"entity\" specifies the entity id of the entity to get the template of.\n";
   print "\"type\" specifies entity type the aggregated template is valid for. If not specified default to the entity type of the entity id given in the \"entity\" parameter.\n\n";
   exit(1);
}

# get id
my $id=$ARGV[0] || 0;
my $type=$ARGV[1] || "";

$type = ($type ne "" ? ($db->getEntityTypeIdByName(uc($type)))[0] : $db->getEntityType($id)); 

if (!defined $type) {
   print "Error! Invalid template entity type specified and/or unable to determine correct entity type. Unable to continue...\n";
   exit(1);
}

print "TYPE: $type\n";

my @path=$db->getEntityPath($id);

my $data=$db->getEntityTemplate($type,@path);
if (!defined $data) {
   print "Error! Failed to get template for entity id $id: ".$db->error()."\n";
   exit(1);
}

# convert flags
foreach (keys %{$data}) {
   my $key=$_;

   my @perms=$db->getTemplateFlagNameByBit($db->deconstructBitmask($data->{$key}{flags}));
   $data->{$key}{flags}=\@perms;
}

# print template
print "TEMPLATE: ".Dumper($data);
