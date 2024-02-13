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
   print "$0 [tmpl]\n";
   print "\n";
   print "tmpl specifies the template id of the template to get the constraints of.\n\n";
   exit(1);
}

# get tmplid
my $tmpl=$ARGV[0] || 0;

# check if entity is a template
if ($db->getEntityTypeName($tmpl) ne "TEMPLATE") {
   print "The chosen tmpl id $tmpl is not a TEMPLATE-type entity or it does not exist. Unable to proceed...\n";
   exit (1);
}

my $data=$db->getTemplate($tmpl);
if (!defined $data) {
   print "Failed to get template for tmpl id $tmpl: ".$db->error()."\n";
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
