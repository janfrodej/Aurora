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
use SysSchema;
use SystemLogger;
use Log;
use Time::HiRes qw(time);
use ISO8601;
use sectools;
use AuroraVersion;
use Data::Dumper;

# set UTF-8 encoding on STDIN/STDOUT
binmode(STDIN, ':encoding(UTF-8)');
binmode(STDOUT, ':encoding(UTF-8)');

# version constant
my $VERSION=$AuroraVersion::VERSION;

my $BASENAME=$0;

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
if ((!exists $opts{s}) && (!exists $opts{f})) {
   help("Missing parameter \"s\" or \"f\" - no query specified.");
}

# check for variable replacements
my $R=();
if (exists $opts{r}) {
   my @vars=split(/(?<!\\),/,$opts{r});
   foreach (@vars) {
      my $var=$_;
      $var=~/^\s*(\d+)\s*\=(.*)$/;
      my $no=$1;
      my $value=$2;
      if ((defined $no) && (defined $value) && ($no =~ /^\d+$/)) { $R->{$no}=$value; }
   }
}

# read SQL query
my @queries;
if (!defined $opts{f}) { push @queries,$opts{s}||"show tables"; }

# perform query - check if from file or not
my $sql;
if ((@queries == 0) && (exists $opts{f})) {
   # read operations from file
   my $fname=$opts{f}||"";
   if (!open (FH,"<",$fname)) {
      help("Unable to open file \"$fname\" for reading.");
   }
   # read the file contents
   @queries=grep { $_ =~s/[\r\n]//g } <FH>;
   close (FH);
}

# execute the queries
foreach (@queries) {
   my $query=$_;
   # check if replacement is to be performed
   if (exists $opts{r}) { $query=replace($query,$R); }
   if ((exists $opts{rd}) && ($opts{rd})) { next; }
   my $sql=$db->doSQL($query);
   if (!defined $sql) {
      # something failed
      print "ERROR! ".$db->error()."\n";
      exit(1);
   }
   output($sql);
}

sub output {
   my $sql=shift;
   # check which output has been selected
   if ((exists $opts{c}) && ($opts{c})) {
      # dump as CSV
      my $i=0;
      my $sep=$opts{cs}||";";
      my $header=$opts{ch}||0;
      while (my $ref=$sql->fetchrow_hashref()) {
         # print header the first time
         if (($i == 0) && ($header)) { print join("$sep",sort {$a cmp $b} keys %{$ref})."\n"; }
         $i++;

         print join("$sep",map { $_=quotemeta((defined $ref->{$_} ? $ref->{$_} : "NULL")) } sort {$a cmp $b} keys %{$ref})."\n";
      }
   } elsif ((exists $opts{d}) && ($opts{d})) {
      # dump using Data::Dumper
      my %h;
      my $i=0;
      while (my $ref=$sql->fetchrow_hashref()) {
         $i++;
         $h{$i}=$ref;
      }
      # dump result 
      print Dumper(\%h);
   } else {

   }
}

# variable replacement
sub replace {
   my $stment=shift;
   my $r=shift;

   foreach (keys %{$r}) {
      my $no=$_;

      # replace this in statement
      $stment=~s/(?<!\\)\{$no(?<!\\)\}/$r->{$no}/g;
   }
   # return result
   if ((exists $opts{rd}) && ($opts{rd})) { print "DRY-RUN: $stment\n"; }
   return $stment;
}

sub help {
   my $error=shift;

   print "$BASENAME, version $VERSION, Copyright(C) 2021 NTNU\n";
   print "\nQuery the AURORA-db using SQL.\n\n";
   print "Syntax:\n";
   print "   $0 [OPT] [OPTVALUE]\n";
   print "\n";
   print "The following options are available:\n\n";
   print "   -c  Dump the result from the query in a CSV-format to screen. Must evaluate to true or false\n";
   print "   -cs Separator to use when dumping with -c. Default is \";\"\n";
   print "   -ch Print header or not when dumping with -c. Default is false. Value must evaluate to true or false.\n";
   print "   -d  Dump the result from the query using Data::Dumper.\n";
   print "   -f  Read SQL queries/operations from a file.\n";
   print "   -r  Replacement variable definition(s). The option-value is defined as: \"1=ABC,2=CBA,3=DEF..N=XYZ\".\n";
   print "   -rd Replacement dry run or not. Default is false. Value must evaluate to true or false. The replaced values are displayed on screen.\n";
   print "   -s  Query to execute.\n";
   if (defined $error) {
      print "\nERROR! $error\n";
   }
   print "\n";
   exit(0);
}
