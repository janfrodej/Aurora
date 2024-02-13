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
# Script to create a bunch of test-users
#
use strict;
use JSON;
use Term::ReadKey;
use Data::Dumper;

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

print "Parent: ";
my $parent=<STDIN>;
$parent=~s/[\r\n]//g;
$parent=~s/[^\d]+//g;
$parent=$parent||0; # default to invalid entity

print "Number of users to create: ";
my $count=<STDIN>;
$count=~s/[\r\n]//g;
$count=~s/[^\d]+//g;
$count=$count||0;

print "Start at count [1]: ";
my $start=<STDIN>;
$start=~s/[\r\n]//g;
$start=~s/[^\d]+//g;
$start=$start||1;

# add to hash
$opts{authtype}=$authtype;
$opts{authstr}=$authstr;
$opts{host}=$host;
$opts{port}=$port;
$opts{key}=$key;
$opts{pkey}=$pkey;
$opts{ca}=$ca;

# we have all the information we need to create, but first test credentials
my $r;
# ok, lets perform the operations needed to create the users
for (my $i=$start; $i <= ($start-1)+$count; $i++) {
   # because of balanced scheme, we randomly allocate first letter of fullname to A-Z.
   my $letter=chr(65+(int(rand(26))));
   my $user=lc($letter)."ser${i}\@localhost";
   my $fullname="${letter}ser $i";
   print "Creating user: $user\n";
   $r=execute (\%opts,"createUser {\"parent\":$parent,\"username\":\"$user\",\"fullname\":\"$fullname\",\"balanced\":1}");
   if ($r->{err} != 0) { use Data::Dumper; print Dumper($r); last; }
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

