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

my %TKEYS = (
   name => "[^\\000-\\037\\177]+",    # name of template itself
   parent => "\\d+",                  # parent of template in case of create
   regex => ".*",                     # regex for given key
   flags => "[a-zA-Z+\\_\\,]+",       # flags for given key
   min => "\\d+",                     # min for given key
   max => "\\d+",                     # max for given key
   comment => "[^\\000-\\037\\177]+", # comment for constraint
   default => ".*",                   # default value(s) for given key
);

my $CFG=Settings->new();
$CFG->load("system.yaml");

my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

my $dbi;
if (!defined ($dbi=$db->getDBI())) {
   die "Error ".$db->error()."\n";
} 

if (!defined $ARGV[0]) {
   print "$0 [0] [template-name] parent=value\n";
   print "$0 [tmpl] [keyname] [regex=value] [flags=value] [min=value] [max=value] [comment=value] [default=value]\n";
   print "\n";
   print "To create template set tmpl to 0 and template-name to the name of the template. Also state the parent.\n";
   print "To set values on template, set values on one of the above key-names. Flags are specified\n";
   print "as textual names of permissions separated by comma\n";
   exit(1);
}

my %kvals;

# get tmplid, 0 for create template
my $tmpl=$ARGV[0] || 0;
# get keyname or whatever (for setting name of template)
my $keyname=$ARGV[1] || "\000";
# check keyname
if (($tmpl > 0) && ($keyname !~ /^[a-zA-Z\.0-9]*$/)) {
   print "Invalid keyname: $keyname\n";
   die;
}
elsif ($tmpl == 0) {
   # keyname is the name of the template
   $kvals{name}=$keyname;
}

# get all key->value pairs
for (my $i=2; $i < @ARGV; $i++) {
   my $kv=$ARGV[$i];

   # get key->value
   my ($key,$value)=split("=",$kv);
   $key=lc($key);
   # check if key exists
   if (exists $TKEYS{$key}) {
      # check with regex
      my $qregex=qq($TKEYS{$key});
      if ($value =~ /^$qregex$/) {
         $kvals{$key}=$value;
      } else {
         print "Value ($value) of template key $key does not meet regex check. Skipping it...\n";
      }
   }  
}

# check if entity is a template
if (($tmpl > 0) && ($db->getEntityTypeName($tmpl) ne "TEMPLATE")) {
   print "The chosen tmpl id $tmpl is not a TEMPLATE-type entity or it does not exist. Unable to proceed...\n";
   exit (1);
}

# if flags was specified - convert it to bitmask
if (exists $kvals{flags}) {
   my @flags=split(",",$kvals{flags});
   $kvals{flags}=$db->createBitmask($db->getTemplateFlagBitByName (@flags));   
}

if (exists $kvals{default}) {
   my @defaults=split(",",$kvals{default});
   if (@defaults > 1) { $kvals{default}=\@defaults; } # save as array if more than one value, else leave alone.
}

my %constr;
if (exists $kvals{default}) { $constr{default}=$kvals{default}; }
if (exists $kvals{regex}) { $constr{regex}=$kvals{regex}; }
if (exists $kvals{flags}) { $constr{flags}=$kvals{flags}; }
if (exists $kvals{min}) { $constr{min}=$kvals{min}; }
if (exists $kvals{max}) { $constr{max}=$kvals{max}; }
if (exists $kvals{comment}) { $constr{comment}=$kvals{comment}; }

# check if we are to create the previous template
if ($tmpl == 0) {
   # create template
   if (exists $kvals{parent}) {
      my $t=$db->createTemplate($kvals{parent});
      if ($t > 0) {
         print "Successfully created template $t\n";
         $tmpl=$t;
      } else {
         print "Failed to create template: ".$db->error()."\n";
         exit (1);
      }
   } else {
      print "Missing parameter parent. Unable to create template...\n";
      exit(1);
   }
}

# check if we are to set template's name
if (exists $kvals{name}) {
   # template exists set its name
   my %md;
   $md{$SysSchema::MD{name}}=$kvals{name};
   if ($db->setEntityMetadata($tmpl,\%md)) {
      print "Successfully set the name of template $tmpl to $kvals{name}\n";
      exit(0);
   } else {
      print "Failed to set the name of the template $tmpl: ".$db->error()."\n";
      exit (1);
   }
}

# constraints to set
my %md;
$md{$keyname}=\%constr;
if ($db->setTemplate($tmpl,\%md)) {
   print "Updated template $tmpl with the chosen constraints successfully...\n";
   exit(0);
} else {
   print "Failed to update template $tmpl: ".$db->error."\n";
   exit(1);
}
