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
use ISO8601 qw(time2iso);
use fiEval;
use LogParser;
use sectools;
use Unicode::String;
use Data::Dumper;

# turn off buffering on stdout
$| = 1; 

my $CFG=Settings->new();
$CFG->load("system.yaml");

header();

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

if ((@ARGV == 0) || (!exists $opts{i})) {
   help();
   exit(1);
}

my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

my $dbi;
if (!defined ($dbi=$db->getDBI())) {
   die "Error ".$db->error()."\n";
} 

# get entity
my $id=$opts{i} || 0;
$id=~s/(\d+)/$1/;

if ($id == 0) { help(); exit(1); }

# check that id is a dataset or not
if ($db->getEntityTypeName($id) ne "DATASET") {
   print "Error! The entity id $id is not a dataset entity or does not exist. Unable to proceed...\n\n";
   exit(1);
}

# get checksum type to use when checking files against
# log entries.
my $chksum = ($opts{c} eq "md5" || $opts{c} eq "sha256" || $opts{c} eq "xxh32" || 
              $opts{c} eq "xxh64" || $opts{c} eq "xxh128" ? $opts{c} : "md5");

# start by getting entity metadata
my $md = $db->getEntityMetadata($id, { parent => 1 });

if (!$md) {
   print "Error! Unable to get entity ${id}'s metadata: ".$db->error().". Unable to proceed...\n\n";
   exit(1);
}
# get creator id
my $creator = $md->{$SysSchema::MD{"dataset.creator"}};

# get creator ids name (if available)
my $cmd = $db->getEntityMetadata($creator);
my $creatorstr = (defined $cmd ? $cmd->{$SysSchema::MD{"name"}} : "N/A");

# get computer id and name of dataset source
my $computerid = $md->{$SysSchema::MD{"dataset.computer"}} || 0;
my $computername = $md->{$SysSchema::MD{"dataset.computername"}} || "N/A";

# collect some dataset metadata
my $closed = $md->{$SysSchema::MD{"dataset.closed"}} || "UNDEFINED";
my $mdcreator = $md->{$SysSchema::MD{"dc.creator"}} || "N/A";
my $removed = $md->{$SysSchema::MD{"dataset.removed"}} || 0;
my $status = $md->{$SysSchema::MD{"dataset.status"}};
my $mdsize = $md->{$SysSchema::MD{"dataset.size"}};

# print some dataset information
print "Metadata Information:\n";
print "   Dataset ID: $id\n";
print "   Dataset Size: ".(!defined $mdsize ? "NOT DEFINED" : $mdsize)." (".(!defined $mdsize ? "N/A" : size($mdsize)).")\n";
print "   Dataset Computer: $computername ($computerid)\n";
print "   Dataset Status: $status\n";
print "   Dataset Created: ".time2iso($md->{$SysSchema::MD{"dataset.created"}})." (".$md->{$SysSchema::MD{"dataset.created"}}.")\n";
print "   Dataset Creator: $creatorstr ($creator) ($mdcreator)\n";
print "   Dataset Description: ".$md->{$SysSchema::MD{"dc.description"}}."\n";

# ensure this dataset it automated
my $type=$md->{$SysSchema::MD{"dataset.type"}};
# fix for compability with some older datasets
if ($type eq "AUTOMATIC") { $type=$SysSchema::C{"dataset.auto"}; }
print "   Dataset type: $type\n";
if ($type ne $SysSchema::C{"dataset.auto"}) {
   print "Error! Dataset $id is not a AUTOMATED dataset and cannot be analyzed by this tool...\n";
   exit(1);
}

# get dataset log
my $log = $db->getLogEntries($id);

if (!$log) {
   print "Error! Unable get entity ${id}'s log entries: ".$db->error().". Unable to proceed...\n\n";
   exit(1);
}

# parse the log
my $logparser = LogParser->new(log=>$log);
my $logdata = $logparser->parse();

# pick data from the log-parse
my $task=$logdata->{task_id}||"";
my $taskq=qq($task);
# all transfers completed
my $tcompleted=$logdata->{transfer_all_completed};
# acquire-phase completed
my $completed=$logdata->{acquire_phase_completed};
# remote size of dataset
my $rsize=$logdata->{remote_size};
# acquire-phase counter in total
my $acount=$logdata->{acquire_phase_run_count};
# acquire-phase failure count
my $afail=$logdata->{acquire_phase_failure_count};
# twin-problem - two or more acquire processes at once
my $twin=$logdata->{acquire_phase_simultaneous};

# local size of dataset
my $lsize;
# size compliance
my $sizecomp=0;

# task id
print "Task ID: $task\n";

# info on number of times attempted acquire
print "   Acquire-phase run $acount time(s)\n";
# info on if acquire-phase had twins/doubles
if ($twin) { print "   Acquire-phase had one or more processes running at the same time.\n"; }
else { print "   Acquire-phase only had one process running at a time.\n"; }

# Info on remote size
if (defined $rsize) { print "   Remote Size: $rsize (".size($rsize).").\n"; }
else { print "   Unable to find remote size of dataset. Suggests issues during acquire-phase.\n"; }
if ($closed) { print "   Metadata close time for dataset: ".($closed eq "UNDEFINED" ? $closed : time2iso($closed))." ($closed)\n"; }
else { print "   Unable to find close time for dataset in metadata. Suggests issues during acquire-phase.\n"; }
 
# Info on all acquire-operations
if ($tcompleted) { print "   Dataset completed all acquire operations successfully...\n"; }
else { print "   Dataset did not complete all acquire operations successfully...\n"; }

# check if we have a completed acquire-phase or not?
if ($completed) {
   # we have a completed acquire-phase - go through it and analyse the actual data of the 
   # dataset...
   print "   Dataset completed acquire-phase successfully...\n";
   #print "TRANSFER LOG: ".Dumper(\%nlog);
} else {
   print "   Unable to find dataset ${id}'s acquire-phase end which seems to indicate this dataset never finished transferring its data. Expect missing or wrong metata...\n";
   if ($tcompleted) { print "   However, all acquire-operation transfers completed successfully, which might indicate that the data of the dataset is intact.\n"; }
}

# if not removed, attempt to check transfer, 
# even if not any of them completed successfully...
# and compare with log entries if possible
my $fimode;
my $localcalc=0;
my $size_compliance=0;
my $checksum_compliance=0;
my $compliance_check=0;
if (!$removed) {
   # Attempt to calculate local size
   # create fiEval-instance - we must locate the data of the dataset
   my $ev=fiEval->new();
   if (!$ev->success()) {
      print "   Error! Unable to instantiate FI-instance: ".$ev->error().". Cannot continue calculating local size...\n";
   } else {
      # attempt to get path of dataset
      my $dpath=$ev->evaluate("datapath",$id);
      if (!$dpath) {
         # failed to get dpath - abort
         print "   Error! Unable to get path to dataset data: ".$ev->error().". Cannot continue with calculating local size...\n";
      } elsif ($dpath =~ /^\/Aurora\/.*\/[a-zA-Z0-9]{32}\/data$/) {
         # we have a path
         print "   Dataset $id path is: $dpath\n";
         # get dataset fi-mode
         $fimode=$ev->evaluate("mode",$id);
         if (!defined $fimode) { print "      Error! Unable to get dataset $id mode: ".$ev->error()."\n"; }
         else { print "   Dataset $id is in mode: $fimode\n"; }
         # we are ready start going through the dataset data
         print "   Attempting to get sizes of all files in dataset $id...\n";
         my %files=();
         recurse_folder (\%files,$dpath);
         $localcalc=1;
         # we have recursed through all files - lets calculate size
         print "      All files stat'ed and will calculate sum total of all files...\n";
         $lsize=0;
         foreach (keys %files) {
            my $file=$_;
            $lsize = $lsize + $files{$file};
            # check if we find file in question in dataset log
         }
         print "      Total size calculated for dataset: $lsize (".size($lsize).")\n";
         if ((defined $lsize) && (defined $rsize) && ($lsize == $rsize)) {
            print "      Local size matches estimated remote size...\n";
            $sizecomp=1;
         } else {
            print "      Local size does not match estimated remote size...\n";
         }
         # do a more thorough check if size is in compliance
         if ($sizecomp) {
            # sizes locally and remote are in compliance
            # check if log contains keys that contain individual size and checksums
            my $cupper=($lsize >= 11000000000 ? " Have a cupper of coffee..." : "..");
            print "   Attempting to check size and checksum locally with log data.$cupper\n";
            print "   Checksum-type: $chksum\n";
            print "   ";
            my $scompl=1;
            my $ccompl=1;
            my $found=0;
            my %check=();
            my %nlog = %{$logdata->{transfer_log}};
            foreach (keys %nlog) {
               my $no=$_;
               if ($nlog{$no} =~ /^\((\d+)\)\(([^\:\)]+)\:([^\)]+)\)\(([^\)]+)\)\(([a-zA-Z0-9]+)\)\s{1}(.+)$/) {
                  my $sz=$1;
                  my $usr=$2;
                  my $grp=$3;
                  my $date=$4;
                  my $csum=$5;
                  my $name=Unicode::String::utf8($6);
                  $found=1;
                  $check{$name}{size}=$sz;
                  $check{$name}{user}=$usr;
                  $check{$name}{group}=$grp;
                  $check{$name}{date}=$date;
                  $check{$name}{checksum}=$csum;
                  $check{$name}{name}=$name;
                  print ".";
                  # check to see if this entry exists in files
                  if (exists $files{"$dpath/$name"}) {
                     # entry exists - lets compare with local data
                     my $lsz=$files{"$dpath/$name"};
                     # checksum local file
                     my $res="";
                     if ($chksum eq "md5") { $res=sectools::md5sum_file("$dpath/$name"); }
                     elsif ($chksum eq "sha256") { $res=sectools::sha256sum_file("$dpath/$name"); }
                     elsif ($chksum eq "xxh32") { $res=sectools::xxhsum_file("$dpath/$name",32); }
                     elsif ($chksum eq "xxh64") { $res=sectools::xxhsum_file("$dpath/$name",64); }
                     elsif ($chksum eq "xxh128") { $res=sectools::xxhsum_file("$dpath/$name",128); }
                     else { $res=sectools::md5sum_file("$dpath/$name"); }

                     if (($res !~ /^Error\!.*$/) && ($res =~ /^([a-zA-Z0-9]+)$/)) {
                        # we have a checksum - check it              
                        my $checksum=$1;
                        if ($csum eq $checksum) { 
                           $check{$name}{checksum_compliance}=1;
                        } else { 
                           $check{$name}{checksum_compliance}=0;
                           $check{$name}{checksum_local}=$checksum;
                           $ccompl=0;
                           print "\n      Error! Local file $dpath/$name ($checksum) does not have the same checksum as the log ($csum)...\n";
                           print "   ";
                        }
                     } elsif ($res =~ /^Error\!.*/) {
                        print "\n      $res...\n";
                     }
                     # compare file sizes
                     if ($lsz == $sz) { $check{$name}{size_compliance}=1; }
                     else { 
                        $check{$name}{size_compliance}=0;
                        $check{$name}{size_local}=$lsz;
                        $scompl=0;
                        print "      Error! Local file $dpath/$name ($lsz Byte(s)) does not have the same size as the log ($sz Byte(s))...\n";
                        print "   ";
                     }
                  } else {
                     # this entry does not exist locally - it means it is not in sync with remote log
                     print "\n      Error! File $name does not exist locally...\n";
                     $scompl=0;
                     $ccompl=0;
                  }
               }              
            }
            print "\n";
            $compliance_check=$found;
            $size_compliance=($scompl && $found ? 1 : 0);
            $checksum_compliance=($ccompl && $found ? 1 : 0);
            my $sizestr=($size_compliance == 0 ? "FALSE" : "TRUE");
            my $checksumstr=($checksum_compliance == 0 ? "FALSE" : "TRUE");
            print "      Local file size compliance with log: $sizestr\n";
            print "      Local file checksum compliance with log: $checksumstr\n"; 
         }
      } else {
         print "      Error! Datapath of dataset $id ($dpath) is not valid. Unable to calculate local size...\n";
      }
   }
} elsif ($removed > 0) {
   print "Dataset har been removed at ".time2iso($removed)." ($removed). No data-calculation will be performed...\n";
}

# check if metadata size is in compliance
my $fixopts=(exists $opts{f} && $opts{f} ? 1 : 0);
if ((!$compliance_check) && ($sizecomp) && ($mdsize != $lsize) && (!$fixopts)) { print "Dataset ${id}'s metadata size mismatch with calculation. Run with the \"-f\" option to fix this...\n"; }
elsif (($compliance_check) && ($size_compliance) && ($checksum_compliance) && ($mdsize != $lsize) && (!$fixopts)) {
   print "Dataset ${id}'s metadata size mismatch with calculation. Run with the \"-f\" option to fix this...\n";
}

# sum up analysis
if (($localcalc) && ($status eq $SysSchema::C{"status.closed"})) {
   # local calculation has been done and the set is closed
   if ((!$compliance_check) && ($sizecomp)) { print "Analysis Conclusion $id: OK\n"; }
   elsif (($compliance_check) && ($size_compliance) && ($checksum_compliance)) { print "Analysis Conclusion $id: OK\n"; }
   else { print "Analysis Conclusion $id: NOT OK\n"; }
} elsif ($status ne $SysSchema::C{"status.closed"}) {
   # dataset is not closed and so it never completed ok - we therefore accept it as is
   print "Analysis Conclusion $id: OK\n";
} elsif ($removed > 0) {
   # whatever has happened, the dataset has been removed and the user knows it.
   print "Analysis Conclusion $id: OK\n";
} else {
   # local calculation has not been done or other reason for it being ok is present - impossible to know if set is ok or not
   print "Analysis Conclusion $id: NOT OK\n";
}

# if fix has been specified, the dataset is open and everything seems to be ok
# attempt to close the dataset and write the metadata for the operation
if (($fixopts) && ($status eq $SysSchema::C{"status.open"}) &&
    (($sizecomp) || (($size_compliance) && ($checksum_compliance)))) {
   # the dataset seems to be ok - attempting to close it and set metadata
   print "Attempting to fix dataset $id by closing it and setting its metadata...\n";
   if (close_dataset($id,$db)) { write_md($id,$db,$lsize); }
} elsif (($fixopts) && ($status eq $SysSchema::C{"status.closed"})) {
   # check and possibly fix metadata
   print "Attempting to fix dataset ${id}'s metadata...\n";
   write_md($id,$db,$lsize);
} elsif (($fixopts) && ($status eq $SysSchema::C{"status.open"})) {
   print "Unable to fix dataset $id because the size and/or the checksum is not in compliance with the remote source...\n";
} elsif ($fixopts) {
   print "Unable to fix dataset $id because the dataset has the wrong status: $status...\n";
}

sub close_dataset {
   my $id=shift;
   my $db=shift;

   # instantiate fiEval-object
   my $ev=fiEval->new();
   if (!$ev->success()) {
      print "   Error! Unable to instantiate FI-instance: ".$ev->error().". Cannot close and/or set metadata of dataset...\n";
      return 0;
   }

   # check mode of dataset, if already ro - do nothing
   # just proceed to write metadata
   my $mode=$ev->evaluate("mode",$id);
   if (!$mode) {
      my $err=$ev->error();
      print "   Error! Unable to get mode of dataset $id: $err...\n"; 
      return 0;
   }

   # we have fi-instance - close storage dataset
   if (uc($mode) eq "RW") { print "   Attempting to close dataset $id...\n"; }
   if ((uc($mode) eq "RW") && (!$ev->evaluate("close",$id))) {
      my $err=$ev->error();
      print "      Error! Unable to close dataset $id: $err...\n";
      return 0;
   }
   # success - purge links etc., do not check result
   $ev->evaluate("purge",$id);

   return 1;
}

sub write_md {
   my $id=shift;
   my $db=shift;
   my $size=shift;

   # get template for parent
   my $parent=$db->getEntityParent($id);
   my @tmplpath=$db->getEntityPath($parent);
   my $tmplparent=$db->getEntityTemplate($db->getEntityTypeIdByName("DATASET"),@tmplpath);

   # decide the lifespan based on template from praent
   my $lifespan=(86400*7); # default it to a week to ensure it doesnt just disappear
   my $extendmax=(86400*3); # default maximum to extend per time is 3 days.
   my $extendlimit=(86400*30); # default limit of extension is a month.
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}{default})) {
      $lifespan=$tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}{default};
   }
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.close.extendmax"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.close.extendmax"}}{default})) {
      $extendmax=$tmplparent->{$SysSchema::MD{"dataset.close.extendmax"}}{default};
   }
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.close.extendlimit"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.close.extendlimit"}}{default})) {
      $extendlimit=$tmplparent->{$SysSchema::MD{"dataset.close.extendlimit"}}{default};
   }

   # storage area closed, we have the size - store it and set status to closed
   my $time=time();
   my %md;
   if ($status ne $SysSchema::C{"status.closed"}) {
      # the dataset is not already closed, so we write the metadata for closing it
      print "   Dataset is not marked as closed. Updating dataset metadata with closing information...\n";
      $md{$SysSchema::MD{"dataset.status"}}=$SysSchema::C{"status.closed"};
      $md{$SysSchema::MD{"dataset.closed"}}=$time;
      # also set its expire date upon closing
      $md{$SysSchema::MD{"dataset.expire"}}=$time+$lifespan;
      $md{$SysSchema::MD{"dataset.extendmax"}}=$extendmax;
      $md{$SysSchema::MD{"dataset.extendlimit"}}=$time+$extendlimit;
   }

   # check that size is correct
   if ((!defined $mdsize) || ($mdsize != $size)) {
      # metadata size does not exist or is wrong - update it
      print "   Metadata size is missing or not correct. Updating dataset metadata size...\n";
      $md{$SysSchema::MD{"dataset.size"}}=$size;
   }

   # update system metadata here and override template to ensure update
   print "   Attempting to write metadata on dataset $id...\n";
   if (!$db->setEntityMetadata($id,\%md,undef,undef,1)) {
      # some failure
      print "      Error! Unable to set metadata for dataset $id: ".$db->error()."...\n";;
   }

   return;
}

sub recurse_folder {
   my $files=shift;
   my $curpath=shift||"./";

   # print "      Checking files in folder: $curpath\n";

   # attempt to open folder and read entries
   if (opendir (DH,"$curpath")) {
      # success - read entries
      my @entries = grep { !/^[\.]{1,2}$/ } readdir(DH);
      closedir(DH);
      # go through entries
      foreach (@entries) {
         my $entry=$_;

         if (-d "$curpath/$entry") {
            # this is a folder - recurse further down
            recurse_folder($files,"$curpath/$entry");
         } elsif (-f "$curpath/$entry") {
            # this is a file - get its size
            my $size = (stat("$curpath/$entry"))[7];
            # add to hash
            $files->{"$curpath/$entry"}=$size;
         }
      }
   }
}

sub header {
   print "$0 Copyright(C) 2022 Jan Frode Jæger, NTNU\n";
   print "\n";
}

sub help {
   print "$0 [OPT] [VALUE]\n";
   print "\n";
   print "Possible options:\n\n";
   print "-h   Show this help-screen.\n";
   print "-i   Entity id of dataset to check. Mandatory.\n";
   print "-f   Fix/not fix a dataset that is open and/or have not set its metadata (1/0).\n";
   print "-c   Set checksum type to use when checking files. Optional. Defaults to md5. Valid values:\n";
   print "     md5, sha256, xxh32, xxh64, xxh128\n";
   print "\n";
}

sub size {
   my $k = shift() / 1024;
   my $f = int(log($k || 1)/log(1024));
   my $u = (qw(KB MB GB TB EB))[$f];
   return sprintf("%0.1f$u", $k/1024**$f);
}
