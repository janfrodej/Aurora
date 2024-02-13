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
# Script to create a research group and its roles.
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

print "Private key: ";
my $key=<STDIN>;
$key=~s/[\r\n]//g;

print "Public key: ";
my $pkey=<STDIN>;
$pkey=~s/[\r\n]//g;

print "CA: ";
my $ca=<STDIN>;
$ca=~s/[\r\n]//g;

print "Parent Entity ID for Research Group (integer): ";
my $parent=<STDIN>;
$parent=~s/[\r\n]//g;

print "Entity ID for Lab user-role (integer): ";
my $labuser=<STDIN>;
$labuser=~s/[\r\n]//g;

print "Group-name (NTNU-FAC-DEP MyName): ";
my $name=<STDIN>;
$name=~s/[\r\n]//g;

# add to hash
$opts{authtype}=$authtype;
$opts{authstr}=$authstr;
$opts{host}=$host;
$opts{port}=$port;
$opts{key}=$key;
$opts{pkey}=$pkey;
$opts{ca}=$ca;
$opts{parent}=$parent;
$opts{labuser}=$labuser;
$opts{name}=$name;

# we have all the information we need to create, but first test credentials
my $r;
#$r=execute (\%opts,"ping");
# ok, lets perform the operations needed to create the research group.
print "Creating Research Group $name\n";
$r=execute (\%opts,"createGroup {\"name\":\"$name\",\"parent\":$parent}");
# get the created id
my $grid=$r->{id} || 0;
# create roles sub-group
print "Creating the roles sub-group\n";
$r=execute (\%opts,"createGroup {\"name\":\"roles\",\"parent\":$grid}");
my $rid=$r->{id} || 0;
# create permission/roles group
print "Creating the role group ${name}_adm\n";
$r=execute (\%opts,"createGroup {\"name\":\"${name}_adm\",\"parent\":$rid}");
my $adm=$r->{id} || 0;
print "Creating the role group ${name}_member\n";
$r=execute (\%opts,"createGroup {\"name\":\"${name}_member\",\"parent\":$rid}");
my $member=$r->{id} || 0;
print "Creating the role group ${name}_guest\n";
$r=execute (\%opts,"createGroup {\"name\":\"${name}_guest\",\"parent\":$rid}");
my $guest=$r->{id} || 0;
# set permissions on the role groups on the research group
print "Setting group permissions for ${name}_adm on ${name}\n";
$r=execute (\%opts,"setGroupPerm {\"id\":$grid,\"user\":$adm,\"grant\":[\"DATASET_CHANGE\",\"DATASET_CREATE\",\"DATASET_CLOSE\",\"DATASET_DELETE\",\"DATASET_LIST\",\"DATASET_LOG_READ\",\"DATASET_METADATA_READ\",\"DATASET_MOVE\",\"DATASET_PERM_SET\",\"DATASET_PUBLISH\",\"DATASET_READ\",\"DATASET_RERUN\"]}");
print "Setting group permissions for ${name}_member on ${name}\n";
$r=execute (\%opts,"setGroupPerm {\"id\":$grid,\"user\":$member,\"grant\":[\"DATASET_LIST\",\"DATASET_LOG_READ\",\"DATASET_METADATA_READ\",\"DATASET_READ\",\"DATASET_CREATE\",\"DATASET_CLOSE\"]}");
print "Setting group permissions for ${name}_guest on ${name}\n";
$r=execute (\%opts,"setGroupPerm {\"id\":$grid,\"user\":$guest,\"grant\":[\"DATASET_CREATE\"]}");
# adding role groups as members of the lab user-group
$r=execute (\%opts,"getGroupMembers {\"id\":$labuser}");
my @members=keys %{$r->{members}};
push @members,"\"".$adm."\"";
push @members,"\"".$member."\"";
push @members,"\"".$guest."\"";
my $memberstr=join (",",@members);
print "Adding ${name}_-adm, guest and member as members of the lab user group $labuser\n";
$r=execute (\%opts,"addGroupMember {\"id\":$labuser,\"member\":[$memberstr]}");

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

