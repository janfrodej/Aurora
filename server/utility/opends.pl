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

my $id = $ARGV[0] || 0;
my $postpath=sprintf("%03d/%03d/%d", int($id/10**6),int($id/10**3) % 10**3,$id);
my $postpath2=sprintf("%03d/%03d/", int($id/10**6),int($id/10**3) % 10**3);

my $FOLDER="/Aurora/fi-default";
my $from = "$FOLDER/ro/$postpath";
my $to = "$FOLDER/rw/$postpath2";

print "ID: $id\n";
print "FROM: $from\n";

print "Continue [Y/N]? ";
my $wait = <STDIN>;
$wait=~s/[\r\n]//g;

# check if we have Yes or not
if (uc($wait) ne "Y") { die "Info! User chose not to continue. Exiting..."; }

# first move in place
if (!-e "$from") { die "ERROR! Source \"$from\" does not exist. Unable to continue..."; }
my $res=qx(/bin/mv $from $to 2>&1);
if ($? != 0) { die "ERROR! $res"; }

# symlink
chdir ($to); # stand in folder in question
unlink ("/Aurora/view/$postpath"); # remove old link
$res=symlink ("../../../rw-default/$postpath","/Aurora/view/$postpath"); # create new link
if (!$res) { die "ERROR! $!"; }
print "Dataset $id was moved from $from to $to...\n";

# database work - update FI
$res = qx(/local/app/aurora/dist/utility/dbquery.pl -c 1 -ch 2 -s "UPDATE FI_DATASET set perm=10,timestamp=UNIX_TIMESTAMP() where entity=$id");
if ($? != 0) { die "ERROR! $res"; }
print "Dataset $id timestamp updated in FI_DATASET.\n";

# update status-tag of dataset
$res = qx(/local/app/aurora/dist/utility/dbquery.pl -c 1 -ch 2 -s "UPDATE METADATA set metadataval=\\"OPEN\\" where metadataval=\\"CLOSED\\" and entity=$id");
if ($? != 0) { die "ERROR! $res"; }
print "Dataset $id changed status to OPEN\n";

# add log entry
my $mess="Dataset $id has been moved from CLOSED to OPEN state by manual intervention.";
$res = qx(/local/app/aurora/dist/utility/addlogentry.pl -id $id -t "MANUAL" -s "$mess");
if ($? != 0) { die "ERROR! $res"; }
print "Dataset $id had its log amended.\n";
