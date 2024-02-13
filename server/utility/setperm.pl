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
use Data::Dumper;

my %ALIAS=(
   ADMIN => [
             "COMPUTER_CHANGE","COMPUTER_CREATE","COMPUTER_DELETE","COMPUTER_FOLDER_LIST",
             "COMPUTER_MEMBER_ADD","COMPUTER_MOVE","COMPUTER_PERM_SET","COMPUTER_READ","COMPUTER_REMOTE","COMPUTER_WRITE",
             "COMPUTER_TEMPLATE_ASSIGN","DATASET_CHANGE","DATASET_CREATE","DATASET_DELETE",
             "DATASET_LIST","DATASET_LOG_READ","DATASET_CLOSE","DATASET_METADATA_READ","DATASET_MOVE",
             "DATASET_PERM_SET","DATASET_PUBLISH","DATASET_READ","DATASET_RERUN","DATASET_EXTEND_UNLIMITED",
             "GROUP_CHANGE","GROUP_CREATE","GROUP_DELETE","GROUP_MEMBER_ADD",
             "GROUP_MOVE","GROUP_PERM_SET","GROUP_TEMPLATE_ASSIGN","GROUP_FILEINTERFACE_STORE_SET","STORE_CHANGE",
             "STORE_CREATE","TEMPLATE_CHANGE","TEMPLATE_CREATE","TEMPLATE_DELETE",
             "TEMPLATE_PERM_SET","USER_CHANGE","USER_CREATE","USER_DELETE","USER_MOVE",
             "USER_READ","TASK_CHANGE","TASK_CREATE","TASK_DELETE","TASK_MOVE","TASK_READ",
             "TASK_EXECUTE","NOTICE_CHANGE","NOTICE_CREATE","NOTICE_DELETE","NOTICE_MOVE",
             "NOTICE_READ","TASK_PERM_SET",
             "SCRIPT_CREATE","SCRIPT_CHANGE","SCRIPT_DELETE","SCRIPT_MOVE","SCRIPT_PERM_SET","SCRIPT_READ"
            ],
   COMPUTERUSER => [
                    "COMPUTER_READ"
                   ],
   GROUPADM => [
                "DATASET_CHANGE","DATASET_CREATE","DATASET_DELETE","DATASET_LIST",
                "DATASET_LOG_READ","DATASET_CLOSE","DATASET_METADATA_READ","DATASET_MOVE",
                "DATASET_PERM_SET","DATASET_PUBLISH","DATASET_READ","DATASET_RERUN"
               ],
   GROUPMEMBER => [
                   "DATASET_LIST","DATASET_LOG_READ","DATASET_METADATA_READ","DATASET_READ","DATASET_CREATE","DATASET_CLOSE"
                  ],
   GROUPGUEST => [
                  "DATASET_CREATE"
                 ],
   CREATE => [
              "DATASET_CREATE"
             ],
);

my %OPER = (
   '+' => 1,
   '-' => 0,
   '=' => undef,
);

my $CFG=Settings->new();
$CFG->load("system.yaml");

my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

my $dbi;
if (!defined ($dbi=$db->getDBI())) {
   die "Error ".$db->error()."\n";
} 

my $subject=$ARGV[0] || 0;
my $op=undef;
my $opstr="=";
if ($subject =~ /^([\+\-\=]{1}).*$/) { $opstr=$1; $op=$OPER{$opstr}; }
$subject=~s/^[\+\-\=]?(.*)$/$1/;
$subject=~s/^(\d+)$/$1/;
$subject=$subject || 0;
my $object=$ARGV[1] || 0;
$object=~s/^(\d+)$/$1/;
$object=$object || 0;
my $grantdeny=(uc($ARGV[2] || "GRANT") =~ /^(GRANT|DENY)$/ ? uc($ARGV[2] || "GRANT") : "GRANT");

my @avperms=split(",",$ARGV[3] || "DATASET_DUMMY");

if (($subject == 0) || ($object == 0)) { 
   my @aliases=keys %ALIAS;
   print "ALIASES ARE: @aliases\n\n";
   print "Syntax: $0 [[+|-|=]subject] [object] [grant|deny] [permnames-comma-separated]\n\n"; 
   print "   + means add these bits to exising bitmask\n";
   print "   - means clear these bits from exiting bitmask\n";
   print "   = means replace bitmask with these bits (default)\n\n";
   print "[grant|deny] must be one of these two. Upon other values will default to grant.\n";
   exit(1);
}

print "Bit operation: $opstr\n";
print "Add bits to: $grantdeny\n";

# expand aliases, if any
my %perms;
foreach (@avperms) {
   my $perm=$_;
   if (exists $ALIAS{$perm}) { foreach (@{$ALIAS{$perm}}) { $perms{$_}=1; } }
   else { $perms{$perm}=1; }
}

my @perms=sort {$a cmp $b} keys %perms;
print "PERMS:\n".join ("\n",@perms);
print "\n\n";

# check validity of bits
my @bits;
for (my $i=0; $i < @perms; $i++) {
   my $bit=($db->getPermTypeValueByName($perms[$i]))[0];

   if (!defined $bit) {
      print "Unknown perm $perms[$i] - skipping it...\n";
   } else {
     push @bits,$bit;
   }
}
print "\nBITS: @bits\n";

my $mask=$db->createBitmask(@bits);
if ($grantdeny eq "GRANT") {
   if (!$db->setEntityPermByObject($subject,$object,$mask,'',$op)) {
      print "\nFailed to set entity perm: ".$db->error()."\n";
   }
} else {
   if (!$db->setEntityPermByObject($subject,$object,'',$mask,$op)) {
      print "\nFailed to set entity perm: ".$db->error()."\n";
   }
}
