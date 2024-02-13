#!/usr/bin/perl -w
# Copyright (C) 2019-2024 Bård Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway
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

my %SET = (
    ADMIN => [
              "COMPUTER_CHANGE","COMPUTER_CREATE","COMPUTER_DELETE",
              "COMPUTER_MEMBER_ADD","COMPUTER_MOVE","COMPUTER_PERM_SET","COMPUTER_READ","COMPUTER_REMOTE","COMPUTER_WRITE",
              "COMPUTER_TEMPLATE_ASSIGN","DATASET_CHANGE","DATASET_CREATE","DATASET_DELETE",
              "DATASET_LIST","DATASET_LOG_READ","DATASET_METADATA_READ","DATASET_MOVE",
              "DATASET_PERM_SET","DATASET_PUBLISH","DATASET_READ","DATASET_RERUN","DATASET_CLOSE","DATASET_EXTEND_UNLIMITED",
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
                 "DATASET_LOG_READ","DATASET_METADATA_READ","DATASET_MOVE",
                 "DATASET_PERM_SET","DATASET_PUBLISH","DATASET_READ","DATASET_RERUN","DATASET_CLOSE"
                ],
    GROUPMEMBER => [
                    "DATASET_LIST","DATASET_LOG_READ","DATASET_METADATA_READ","DATASET_READ","DATASET_CREATE","DATASET_CLOSE"
                   ],
    GROUPGUEST => [
                   "DATASET_CREATE"
                  ],
    CREATE => [qw(DATASET_CREATE)],
    COMPTER => [qw(COMPUTER_READ)],
    'DATASETALL' => [
        "DATASET_CREATE","DATASET_DELETE","DATASET_CHANGE","DATASET_MOVE","DATASET_PUBLISH","DATASET_LOG_READ",
        "DATASET_RERUN","DATASET_PERM_SET","DATASET_READ","DATASET_LIST","DATASET_METADATA_READ","DATASET_CLOSE"
    ]
    );

my $CFG=Settings->new();
$CFG->load("system.yaml");

my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

my $dbi;
if (!defined ($dbi=$db->getDBI())) {
   die "Error ".$db->error()."\n";
} 

my $subject = shift || 0;
chomp $subject;
unless ($subject =~ /^\d+$/) {
    my $sql = "select entity from METADATA natural join METADATAKEY where metadataidx=1 and metadatakeyname='%s' and metadataval=%s";
    if ($subject =~ /\@/) { $sql = sprintf($sql, 'system.user.username', $dbi->quote($subject)); }
    else                  { $sql = sprintf($sql, 'system.authenticator.oauthaccesstoken.user', $dbi->quote("$subject\@ntnu.no")); }
    my $entity = ( $dbi->selectrow_array($sql) )[0];
    print "Mapped '$subject' to $entity\n";
    $subject = $entity;
}
die "No valid subject!" unless $subject = int($subject);

my $object = shift || 0;
die "No valid object!" unless $object = int($object);

my $perms = "@ARGV";
chomp($perms);
my @perms = ();

foreach (split /(\s|,)+/, $perms) {
    if (exists $SET{$_}) { push(@perms, @{$SET{$_}}); }
    else                 { push(@perms, $_); }
}
print "PERMS: @perms\n";

my %change =();
foreach (@perms) {
    my $col = s/\/// ? 'permdeny' : 'permgrant';
    my $verb = s/\-// ? 'clear' : 'set';
    push(@{$change{$col}{$verb}}, $_);
}

my %has = ();
($has{permgrant}, $has{permdeny}) = @{ $db->getEntityPermByObject($subject,$object) };

my %get = ();
foreach my $col (keys %change) {
    print "$col $subject on $object:\n";
    print "  + ",join(",", $db->getPermTypeValueByName(@{$change{$col}{set}})),"\n";
    print "  - ",join(",", $db->getPermTypeValueByName(@{$change{$col}{clear}})),"\n";
    $get{$col} = defined($has{$col}) ? $has{$col} : '';
    $get{$col} = $db->setBitmask(   $get{$col}, $db->createPermBitmask(@{$change{$col}{set}}));
    $get{$col} = $db->clearBitmask( $get{$col}, $db->createPermBitmask(@{$change{$col}{clear}}));
    print "  = ",join(",", $db->deconstructBitmask($get{$col})),"\n";
}
if (!$db->setEntityPermByObject($subject,$object,$get{permgrant},$get{permdeny})) {
   print "Failed to set entity perm: ".$db->error()."\n";
}
