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
use Settings;

# settings instance
my $CFG=Settings->new();
$CFG->load();

my $ACKLOC=$CFG->value("system.notification.location")||"";

my $arg=$ARGV[0] || "";

if (($arg eq "") || (uc($arg) ne "-Y")) { 
   print "$0 Copyright(C) 2022 Jan Frode Jæger, NTNU, Trondheim\n";
   print "\n";
   print "Clear unused AURORA ACKs belonging to removed notifications.\n\n";
   print "Syntax:\n";
   print "   $0 -y\n\n";
   print "Notification location: $ACKLOC\n\n";
   exit(0);
}

# read all folder names in the AURORA notification-folder
opendir (DH,"$ACKLOC/") || die "Error! Unable to open AURORA notification-folder."; 
my %f=map { $_ => 1 } grep { $_ !~ /^\.{1,2}$/ } readdir (DH); 
closedir(DH) || die "Error! Unable to close AURORA notification-folder."; 

# read all folder names in the AURORA notification Ack-folder
opendir (DH,"$ACKLOC/Ack") || die "Error! Unable to open AURORA notification Ack-folder.";
my @a=grep { $_ !~ /^\.{1,2}$/ } readdir(DH); 
closedir(DH) || die "Error! Unable to close AURORA notification Ack-folder."; 

foreach (@a) {
  my $n=$_; 
  my $sn=$n; 
  $sn=~s/^([a-zA-Z0-9]+)\_.*$/$1/; 
  if (!exists $f{$sn}) { print "Removing $ACKLOC/Ack/$n\n"; unlink ("$ACKLOC/Ack/$n"); }
}
