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
# Script to create a bunch of test datasets
#
use strict;
use lib qw(../lib);
use JSON;
use Term::ReadKey;
use Data::Dumper;
use Time::HiRes;
use ISO8601;
use SysSchema;
use sectools;
use fiEval;

my $CMD="./restcmd.pl";

my %opts;

print "AuthType [AuroraID]: ";
my $authtype=<STDIN>;
$authtype=~s/[\r\n]//g;
if ($authtype eq "") { $authtype="AuroraID"; }

print "Email-address: ";
my $email=<STDIN>;
$email=~s/[\r\n]//g;

print "AuthStr (not visible, for AuroraID - just the pw): ";
ReadMode('noecho'); 
my $authstr=ReadLine (0);
print "\n";
$authstr=~s/[\r\n]//g;
ReadMode('normal');

# put email and authstr together of AuroraID auth type
if ($authtype eq "AuroraID") { $authstr=$email.",".$authstr; }

print "Hostname: ";
my $host=<STDIN>;
$host=~s/[\r\n]//g;

print "Port [9393]: ";
my $port=<STDIN>;
$port=~s/[\r\n]//g;
$port=($port ne "" ? $port : 9393);

my $pdef="./certs/private.key";
print "Private key [$pdef]: ";
my $key=<STDIN>;
$key=~s/[\r\n]//g;
$key=$key||$pdef;

$pdef="./certs/public.key";
print "Public key [$pdef]: ";
my $pkey=<STDIN>;
$pkey=~s/[\r\n]//g;
$pkey=$pkey||$pdef;

my $cadef="./certs/DigiCertCA.crt";
print "CA [$cadef]: ";
my $ca=<STDIN>;
$ca=~s/[\r\n]//g;
$ca=$ca||$cadef;

print "Number of datasets to create: ";
my $count=<STDIN>;
$count=~s/[\r\n]//g;
$count=~s/[^\d]+//g;
$count=$count||0;

print "Group to create datasets under: ";
my $group=<STDIN>;
$group=~s/[\r\n]//g;
$group=~s/[^\d]+//g;
$group=$group||0;

print "Computer to create dataset from: ";
my $computer=<STDIN>;
$computer=~s/[\r\n]//g;
$computer=~s/[^\d]+//g;
$computer=$computer||0;

print "Path to fetch data from on computer: ";
my $path=<STDIN>;
$path=~s/[\r\n]//g;
$path=$path||"/dummy";

# add to hash
$opts{authtype}=$authtype;
$opts{authstr}=$authstr;
$opts{host}=$host;
$opts{port}=$port;
$opts{key}=$key;
$opts{pkey}=$pkey;
$opts{ca}=$ca;

my @NOUN=("metal","object","quantum","atom","liquid","instrument","quark","dark-matter","dark-hole","matter","beam","spot","substance","computer","bit","energy","gas","plasma","solid","rock","plant","animal","tree","owl","mushroom","grass","bee","flower","crow","raven","neutron","electron","cell","nucleus","beam","accelerator","box","cat","dog","arm","leg","head","brain","nerve","vein","foot","knee","hair","nail","hand",
          "finger","painting","glass","fabric","frame","chair","rabbit","fuzzy");
my @ADJ=("weird","green","blue","cloudy","tainted","slow","quick","biological","chemical","physical","quantum","technological","disruptive",
         "nuclear","red","white","murky","dubious","environmental","debauched","stellar","nice","excellent","pretty","ugly",
         "outstanding","acceptable","medium","small","large","enormous","micro");
my @PREP=("aboard","about","above","across","after","against","along","amid","among","anti","around","as","at","before","behind","below","beneath",
          "beside","besides","between","beyond","but","by","concerning","considering","despite","down","during","except","excepting","excluding",
          "following","for","from","in","inside","into","like","minus","near","of","off","on","onto","opposite","outside","over","past","per",
          "plus","regarding","round","save","since","than","through","to","toward","towards","under","underneath","unlike","until","up","upon",
          "versus","via","with","within","without");
my @INTR=("A","Sample of","Experiment with","Trial of","Trial with","Collection of","A series of","Series of","Series with");

my $SNOUN=@NOUN;
my $SADJ=@ADJ;
my $SPREP=@PREP;
my $SINTR=@INTR;

my $creator="$0";

# we have all the information we need to create
my $r;
# ok, lets perform the operations needed to create the datasets
for (my $i=1; $i <= $count; $i++) {
   my $type=rnd(2);
   $type=($type == 1 ? $SysSchema::C{"dataset.man"} : $SysSchema::C{"dataset.auto"});
   # create a random description of the dataset
   my $description=join (" ",$INTR[rnd($SINTR)],$ADJ[rnd($SADJ)],$NOUN[rnd($SNOUN)],$PREP[rnd($SPREP)],$ADJ[rnd($SADJ)],$NOUN[rnd($SNOUN)],$NOUN[rnd($SNOUN)]);
   my $date=time2iso(time());

#   print "TYPE: $type DATE: $date GROUP: $group COMPUTER: $computer CREATOR: $creator\n";

   print "Creating $type dataset: $description\n";
   $r=execute (\%opts,"createDataset {\"computer\":$computer,\"delete\":0,\"parent\":$group,\"path\":\"$path\",\"type\":\"$type\",".
               "\"metadata\":{\"".$SysSchema::MD{"dc.description"}."\":\"$description\",\"".$SysSchema::MD{"dc.creator"}."\":\"$creator\",".
               "\"".$SysSchema::MD{"dc.date"}."\":\"$date\"}}");

   if ($r->{err} != 0) { use Data::Dumper; print Dumper($r); last; }

   # do some post-work of putting data in place if this is a manual dataset
   if ($type eq "MANUAL") {
      # put data in place and then close the dataset
      my $id=$r->{id}||0;
      print "   Generating data for $type dataset $id...\n";
      # create FI instance and retrieve datapath
      my $ev=fiEval->new();
      if (!$ev->success()) {
         # unable to instantiate
         print "   ERROR! Unable to instantiate FI: ".$ev->error()."\n";
         last;
      }
      my $datapath=$ev->evaluate("datapath",$id);
      if (!$datapath) {
         print "   ERROR! Unable to get datapath of dataset $id: ".$ev->error()."\n";
         last;
      }
      # we have datapath - lets put some data there
      # we will put 1 - 20 files there
      my $n=rnd(19)||1;
      print "   Generating $n file(s) for dataset $id...\n";      
      for (my $j=1; $j <= $n; $j++) {
         # create a random file name
         my $name=sectools::randstr(10).".txt";
         # open file for writing
         if (!open (FH,">","$datapath/$name")) {
            # unable to open file for writing
            print "   ERROR! Unable to create data file $datapath/$name: $!\n";
            exit (1);
         }
         # we have a file to write to
         my $r=rnd(9)||1;
         for (my $k=1; $k <= $r; $k++) { # lines/rows
            my $c=rnd(19)||1;
            my $s="";
            for (my $l=1; $l <= $c; $l++) { # words/columns
               $s.=($s eq "" ? $PREP[rnd($SPREP)] : " ".$PREP[rnd($SPREP)]);
            }
            # lets print this row
            print FH "$s\n";
         }
         # close file
         close (FH);
      }
      # close the dataset
#      print "   Data generated for dataset $id. Closing the dataset...\n";
#      my $res=execute (\%opts,"closeDataset {\"id\":$id}");
      # check if something failed
#      if ($res->{err} != 0) { use Data::Dumper; print Dumper($res); last; }   
      sleep(5); # let the REST-server breathe
   }
   sleep(5) # let the REST-server breathe
}

print "Finished!...\n";

sub execute {
   my $opts=shift;
   my $command=shift;

   my $res=qx($CMD -t $opts->{authtype} -s $opts->{authstr} -h $opts->{host} -o $opts->{port} -k $opts->{key} -p $opts->{pkey} -c $opts->{ca} '$command');
   if ($? != 0) {
      print "   ERROR! Unable to execute script command: $command ($res). Aborting...\n";
      exit(1);
   }
   # add utf8-flag
   utf8::encode($res);
   # decode res
   my $h=decode($res);
   if (!defined $h) {
      exit(1);
   }
   # check success
   if ($h->{err} != 0) {
      print "   ERROR! REST-server returned: ".$h->{errstr}."\n";
   }
   return $h;
}

sub rnd {
  my $c=shift||1;
  return int(rand($c));
}

sub decode {
   my $content=shift || "";

   my $err;
   my $h;
   local $@;
   eval { my $a=JSON->new(); $h=$a->decode ($content); };
   $@ =~ /nefarious/ and $err=$@;
   
   if (!defined $err) {
      # decoding was a success - return structure
      return $h;
   } else {
      # an error occured
      print "Unable to decode JSON: $err\n";
      return undef;
   }
}  

