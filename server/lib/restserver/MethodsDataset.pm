#!/usr/bin/perl -w
# Copyright (C) 2019-2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
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
# MethodsDataset: Dataset methods for the AURORA REST-server
#
package MethodsDataset;
use strict;
use RestTools;
use Time::HiRes qw(time);
use Content::YAML;
use Content::Log;
use StoreCollection;
use MetadataCollection;
use DistributionQueue;
use FileInterface;
use POSIX qw (strftime);
use DistLog;
use fiEval;
use Not;
use ISO8601; 
use Digest::SHA;
use Digest::MD5;

sub registermethods {
   my $srv = shift;

   $srv->addMethod("/changeDatasetExpireDate",\&changeDatasetExpireDate,"Change the expiration date of a dataset.");
   $srv->addMethod("/checkDatasetTemplateCompliance",\&checkDatasetTemplateCompliance,"Check metadata compliance with metadata for datasets based upon a parent group and computer.");
   $srv->addMethod("/closeDataset",\&closeDataset,"Close a dataset.");  
   $srv->addMethod("/createDataset",\&createDataset,"Create a dataset, either automatic or manual.");  
   $srv->addMethod("/createDatasetToken",\&createDatasetToken,"Create a dataset token.");
   $srv->addMethod("/deleteDatasetMetadata",\&deleteDatasetMetadata,"Delete metadata for a dataset.");     
   $srv->addMethod("/enumDatasetPermTypes",\&enumDatasetPermTypes,"Enumerate all DATASET permission types.");
   $srv->addMethod("/extendDatasetToken",\&extendDatasetToken,"Extend lifetime for a dataset token.");
   $srv->addMethod("/getDatasetAggregatedPerm",\&getDatasetAggregatedPerm,"Get aggregated/inherited perm on dataset.");
   $srv->addMethod("/getDatasetExpirePolicy",\&getDatasetExpirePolicy,"Get a datasets expire policy.");
   $srv->addMethod("/getDatasetPerm",\&getDatasetPerm,"Get perms on dataset itself.");
   $srv->addMethod("/getDatasetPerms",\&getDatasetPerms,"Get perms of all users on dataset.");
   $srv->addMethod("/getDatasetLog",\&getDatasetLog,"Get a dataset\'s log.");
   $srv->addMethod("/getDatasetMetadata",\&getDatasetMetadata,"Get a dataset\'s metadata.");
   $srv->addMethod("/getDatasetSystemMetadata",\&getDatasetSystemMetadata,"Get a dataset\'s open system metadata.");
   $srv->addMethod("/getDatasetSystemAndMetadata",\&getDatasetSystemAndMetadata,"Get a dataset\'s normal metadata and open system metadata.");
   $srv->addMethod("/getDatasets",\&getDatasets,"Get datasets that match key- and value criteria(s) moderated by user permissions.");
   $srv->addMethod("/getDatasetTemplate",\&getDatasetTemplate,"Get template for datasets based upon parent group and computer.");
   $srv->addMethod("/listDatasetFolder",\&listDatasetFolder,"List dataset files and folders with metadata.");
   $srv->addMethod("/moveDataset",\&moveDataset,"Move dataset to another group.");
   $srv->addMethod("/removeDataset",\&removeDataset,"Remove dataset.");
   $srv->addMethod("/removeDatasetToken",\&removeDatasetToken,"Remove a dataset token.");
   $srv->addMethod("/setDatasetMetadata",\&setDatasetMetadata,"Set a dataset\'s metadata.");
   $srv->addMethod("/setDatasetPerm",\&setDatasetPerm,"Set a dataset\'s perms.");
}

sub changeDatasetExpireDate {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $expiredate=$query->{expiredate};

   if (!defined $expiredate) {
      # missing parameter
      $content->value("errstr","Missing input parameter \"expiredate\". Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }
   # we have an expire date - clean it
   $expiredate=$Schema::CLEAN_GLOBAL{trueint}->($expiredate);

   # check that dataset exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   # need to differentiate between DELETE and EXTEND_UNLIMITED
   my $allowed=hasPerm($db,$userid,$id,["DATASET_DELETE"],"ALL","ANY",1,1,undef,1);
   my $unlimited=hasPerm($db,$userid,$id,["DATASET_EXTEND_UNLIMITED"],"ALL","ANY",1,1,undef,1);

   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the DATASET_DELETE permission on the dataset $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # start transaction
   my $tr=$db->useDBItransaction();

   # get dataset md
   my $md=$db->getEntityMetadata($id);
   if (!defined $md) {
      # something failed
      $content->value("errstr","Unable to get the metadata of dataset $id: ".$db->error());
      $content->value("err",1);
      return 0;      
   }
   # get dataset remove-status
   my $removed=$md->{$SysSchema::MD{"dataset.removed"}};
   if ($removed > 0) {
      # dataset was removed, cannot continue
      $content->value("errstr","Dataset data has already been removed. Cannot change expire date. Unable to fulfill request.");
      $content->value("err",1);
      return 0;      
   }

   # get the dataset status
   my $status=$md->{$SysSchema::MD{"dataset.status"}};

   # check if dataset is closed
   my $etype="close";
   if ($status eq $SysSchema::C{"status.open"}) {
      # dataset is still open - we can extend we separate settings
      $etype="open";
   }

   # get dataset current expire date
   my $oldexpiredate=$md->{$SysSchema::MD{"dataset.expire"}} || 0;
   # get when dataset was created
   my $created=$md->{$SysSchema::MD{"dataset.created"}} || 0;
   # get when dataset was closed, if at all
   my $close=$md->{$SysSchema::MD{"dataset.closed"}} || 0;

   # user is allowed to change expire date, check templates on expire window
   my $parent=$db->getEntityParent($id);
   my @tmplpath=$db->getEntityPath($parent);
   my $tmplparent=$db->getEntityTemplate($db->getEntityTypeIdByName("DATASET"),@tmplpath);
   # decide the lifespan based on template from parent
   my $lifespan=(86400*7); # default it to a week to ensure it doesnt just disappear
   my $extendmax=(86400*3); # default maximum to extend per time is 3 days.
   my $extendlimit=(86400*30); # default limit of extension is a month.
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.$etype.lifespan"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.$etype.lifespan"}}{default})) {
      $lifespan=$tmplparent->{$SysSchema::MD{"dataset.$etype.lifespan"}}{default};
   }
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.$etype.extendmax"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.$etype.extendmax"}}{default})) {
      $extendmax=$tmplparent->{$SysSchema::MD{"dataset.$etype.extendmax"}}{default};
   }
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.$etype.extendlimit"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.$etype.extendlimit"}}{default})) {
      $extendlimit=$tmplparent->{$SysSchema::MD{"dataset.$etype.extendlimit"}}{default};
   }

   # current time
   my $time=time();
   my $timeiso=time2iso($time);

   # calculate expiredate (absolute relative based on signed/non-signed scalar)
   # to absolute
   if ($expiredate < 0) { # if signed, this is a relative expiredate
      $expiredate=$oldexpiredate-$expiredate;
   } 
   # create iso version of expiredate
   my $expireiso=time2iso($expiredate);
   # calculate the extension
   my $extension=$expiredate-$oldexpiredate;
   # calculate window
   my $window=($etype eq "close" ? $close+$extendlimit : $created+$extendlimit);
   my $windowiso=time2iso($window);

   # ensure that extension is more than current-datetime
   if ($expiredate <= $time) {
      # this is too low a value
      $content->value("errstr","New expire-date $expireiso for dataset $id is too close or lower than current time ($timeiso). Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   # check that we do not try to extend too 
   # much at a time
   if (($extension > $extendmax) &&
       (!$unlimited)) {
      my $days=floor($extendmax / 86400);
      $content->value("errstr","New expire-date $expireiso is attempting to set the expire date beyond the extendmax-limit ($days day(s)) ".
                      "for each extension-attempt and you do not have the DATASET_EXTEND_UNLIMITED-permission. ".
                      "Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   # check that we do not attempt to extend beyond the 
   # expiration window
   if (($expiredate > $window) &&
       (!$unlimited)) {
      $content->value("errstr","New expire-date $expireiso is beyond the expiration window ($windowiso) for this dataset and you do not have the DATASET_EXTEND_UNLIMITED-permission. Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   # so far, so good - we can now attempt to set the new expiredate.
   my %nmd;
   # new expire date
   $nmd{$SysSchema::MD{"dataset.expire"}}=$expiredate;
   # reset notified intervals, empty array will erase old values
   my @empty;
   $nmd{$SysSchema::MD{"dataset.notified"}}=\@empty;
   if (!$db->setEntityMetadata($id,\%nmd)) {
      # something failed setting metadata
      $content->value("errstr","Unable to change dataset $id expiration-date because metadata could not be saved for dataset $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
   # add log entry
   $log->send(entity=>$id,logtag=>$main::SHORTNAME,logmess=>"Dataset expire date changed to $expireiso by user ($userid).");

   # success if we come to here...
   $content->value("errstr","");
   $content->value("err",0);
   $content->value("expiredate",$expiredate); # return new expire date
   return 1;
}

sub checkDatasetTemplateCompliance {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $computer=$Schema::CLEAN{entity}->($query->{computer});
   my $metadata=$SysSchema::CLEAN{metadata}->($query->{metadata});

   my $iddef=defined $query->{id};

   # check that dataset exists and is the right type
   if (($iddef) && ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0]))) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # check if parent exists and is the right type
   if ((!$iddef) && ((!$db->existsEntity($parent)) || ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0]))) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check if computer exists and is the right type
   my @pathreq;
   if ((!$iddef) && ((!$db->existsEntity($computer)) || ($db->getEntityType($computer) != ($db->getEntityTypeIdByName("COMPUTER"))[0]))) {
      # does not exist 
      $content->value("errstr","Computer $computer does not exist or is not a COMPUTER entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } elsif (!$iddef) {
      # get path of computer, but do it later
      push @pathreq,$computer;
   } else {
      # get path of computer from entity's metadata
      my $md=$db->getEntityMetadata($id,$SysSchema::MD{"dataset.computer"});
      if (defined $md) {
         # success - get computer
         my $comp=$md->{$SysSchema::MD{"dataset.computer"}} || 0;
         push @pathreq,$comp;
      } else {
         # something failed
         $content->value("errstr","Unable to get computer of dataset $id: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      }
   }

   # add path of dataset or group
   if (!$iddef) { push @pathreq,$parent; } #@path=$db->getEntityPath($parent); }
   else { push @pathreq,$id; } # @path=$db->getEntityPath($id); }

   # get all paths in one go
   my $paths=$db->getEntityPath(@pathreq);

   # check if we got paths successfully or not
   if (!defined $paths) {
      # something failed
      $content->value("errstr","Unable to get entity paths: ".$db->error().". Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   my @cpath;
   my @path;
   @cpath=@{$paths->{$pathreq[0]}};
   @path=@{$paths->{$pathreq[1]}};

   # combine path, dataset/group has precedence, but only if dataset not yet created
   my @apath;
   if ($iddef) {
      push @apath,@path; # only include the datasets path, since dataset exists
   } else {
      # we have no dataset, so DATASET template comes from computer, then group.
      push @apath,@cpath;
      push @apath,@path;
   }

   # we are ready to check compliance
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   if (!$iddef) { $opt{id}=$computer; }
   else { $opt{id}=$id; }
   $opt{path}=\@apath;
   $opt{type}="DATASET";
   $opt{metadata}=$metadata;
   MethodsTemplate::checkTemplateCompliance($mess,\%opt,$db,$userid);
   # check return value
   if ($mess->value("err") == 0) {
      # success - get metadata
      my $md=$mess->value("metadata");
      # remove everything that does not start with ".".
      my $nm=$SysSchema::CLEAN{metadata}->($md);
      # set return values
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("metadata",$nm);
      $content->value("compliance",$mess->value("compliance"));
      $content->value("noncompliance",$mess->value("noncompliance"));
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub closeDataset {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check if id exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["DATASET_CLOSE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the DATASET_CLOSE permission on the dataset $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # get dataset metadata
   my $md=$db->getEntityMetadata($id);

   if (!defined $md) {
      # something failed
      $content->value("errstr","Failed to get metadata for dataset $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # check that this is a MANUAL dataset, or else refuse
   if ($md->{$SysSchema::MD{"dataset.type"}} eq $SysSchema::C{"dataset.auto"}) {
      # not allowed to close a non-manual dataset - that is done by Store-service
      $content->value("errstr","It is not allowed to close a automated dataset. That is done by the store-service when all acquire-operations have completed successfully.");
      $content->value("err",1);
      return 0;
   }

   # we have metadata - check the dataset status flag
   my $status=$md->{$SysSchema::MD{"dataset.status"}};
   if ($status ne $SysSchema::C{"status.open"}) {
      # dataset has wrong status, cannot close it
      $content->value("errstr","Dataset $id has wrong status: $status. Status must be: ".$SysSchema::C{"status.open"}.". Cannot close it.");
      $content->value("err",1);
      return 0;
   }

   # it has the right status - we can close it, but first calculate size of local data
   my $ev=fiEval->new();
   if (!$ev->success()) {
      # unable to instantiate fiEval
      $content->value("errstr","Unable to instantiate fiEval-instance: ".$ev->error());
      $content->value("err",1);
      return 0;
   }

   # storage opened - calculate size of data
   my $path=$ev->evaluate("datapath",$id); # get path to data
   my $store=Store->new();
   # open store, if possible
   if (!$store->open(remote=>"/tmp/dummy",local=>$path)) {
      # something failed opening the Store
      $content->value("errstr","Unable to close dataset $id because of failure to open the data area for size check: ".$store->error());
      $content->value("err",1);
      return 0;
   }
   my $size=$store->localSize();
   if (!defined $size) {
      # something failed
      $content->value("errstr","Unable to close dataset $id because of failure to get size of data: ".$store->error());
      $content->value("err",1);
      return 0;
   }

   # attempt to close storage/change to RO mode
   if (!$ev->evaluate("close",$id)) {
      my $err=$ev->error() || "";
      $content->value("errstr","Unable to close dataset $id because of failure to close storage area: $err.");
      $content->value("err",1);
      return 0;
   }

   # run a purge to update links, access etc...
   $ev->evaluate("purge",$id);

   # get just template for parent 
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
   my %nmd;
   $nmd{$SysSchema::MD{"dataset.size"}}=$size;
   $nmd{$SysSchema::MD{"dataset.status"}}=$SysSchema::C{"status.closed"};
   $nmd{$SysSchema::MD{"dataset.closed"}}=$time;
   # also set its expire date upon closing
   $nmd{$SysSchema::MD{"dataset.expire"}}=$time+$lifespan;
   # reset notified intervals, empty array will erase old values
   my @empty;
   $nmd{$SysSchema::MD{"dataset.notified"}}=\@empty;
   if (!$db->setEntityMetadata($id,\%nmd)) {
      # something failed setting metadata
      $content->value("errstr","Unable to close dataset because metadata could not be saved for dataset $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # list contents of dataset - use listDatasetFolder-method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{md5sum}=1;
   listDatasetFolder($mess,\%opt,$db,$userid,$cfg,$log);
   if ($mess->value("err") == 0) {
      # success - get structure and then make log entries
      my %struct=%{$mess->value("folder")};
      my @nlisting;
      recurseListing(\%struct,\@nlisting,"");
      # we have a list of entries that can be added to log after successful close
      foreach (@nlisting) { 
         my $entry=$_;
         # add log entry
         $log->send(entity=>$id,logtag=>$main::SHORTNAME." TRANSFER",logmess=>$entry,loglevel=>$Content::Log::LEVEL_DEBUG);
      }
   }

   # add log entry
   $log->send(entity=>$id,logtag=>$main::SHORTNAME,logmess=>"Dataset closed by user ($userid).");

   # add a distribution log entry
   my $entry=createDistLogEntry(
                                event=>"TRANSFER",
                                from=>"UNKNOWN",
                                fromid=>$SysSchema::FROM_UNKNOWN,
                                fromhost=>"",
                                fromhostname=>"",
                                fromloc=>"",                                
                                toloc=>$id,
                                uid=>$userid
                               );

   $log->send(entity=>$id,logtag=>$main::SHORTNAME." DISTLOG",logmess=>$entry,loglevel=>$Content::Log::LEVEL_DEBUG);

   # success if we come to here...   
   $content->value("errstr","");
   $content->value("err",0);
   $content->value("size",$size); # return calculated size for the curious
   return 1;
}

sub createDataset {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $type=$SysSchema::CLEAN{createtype}->($query->{type}); # man/auto
   my $metadata=$query->{metadata};
   my $computer=$Schema::CLEAN{entity}->($query->{computer});
   my $path=$query->{path};
   my $delete=$SysSchema::CLEAN{bool}->($query->{delete}); # defaults to 0 if none specified

   # check if parent exists and is the right type
   if ((!$db->existsEntity($parent)) || ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check if computer exists and is the right type
   if ((!$db->existsEntity($computer)) || ($db->getEntityType($computer) != ($db->getEntityTypeIdByName("COMPUTER"))[0])) {
      # does not exist 
      $content->value("errstr","Computer $computer does not exist or is not a COMPUTER entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   if ((defined $metadata) && (ref($metadata) ne "HASH")) {
      # does not exist 
      $content->value("errstr","Metadata is not a HASH. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # if type is auto, it also needs to exist a path-parameter
   if (($type eq $SysSchema::C{"dataset.auto"}) && (!defined $path)) {
      # path is not defined on an automated dataset - failure
      $content->value("errstr","No path parameter defined. Automated datasets require a path parameter. Unable to fulfill request.");
      $content->value("err",1);
      return 0;      
   } elsif ($type eq $SysSchema::C{"dataset.auto"}) {
      # this is automated dataset and path is defined - clean it
      $path=$SysSchema::CLEAN{path}->($path);
   }

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$parent,["DATASET_CREATE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the DATASET_CREATE permissions on the GROUP $parent. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # check if we have perms to read dataset from computer if AUTOMATED
   if ($type eq $SysSchema::C{"dataset.auto"}) {
      # user must have ALL of the perms on ANY of the levels
      my $allowed=hasPerm($db,$userid,$computer,["COMPUTER_READ"],"ALL","ANY",1,1,undef,1);
      if (!$allowed) {
         # user does not have the required permission or something failed
         if (!defined $allowed) {
            $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
            $content->value("err",1);
            return 0;      
         } else {
            $content->value("errstr","User does not have the COMPUTER_READ permission on the COMPUTER $computer. Unable to fulfill the request.");
            $content->value("err",1);
            return 0;      
         }
      }
   }

   # strip away illegal metadata keys (everything that do not start with ".").
   my $md=$SysSchema::CLEAN{metadata}->($metadata);

   # get paths to computer and parent in one call
   my $paths=$db->getEntityPath($computer,$parent);
   my @cpath=@{$paths->{$computer}};
   my @gpath=@{$paths->{$parent}};

   if ((!defined $cpath[0]) || (!defined $gpath[0])) {
      # something failed
      $content->value("errstr","Unable to get COMPUTER or GROUP path: ".$db->error().". Unable to fulfill the request.");
      $content->value("err",1);
      return 0;      
   }

   # group overrules computer and comes last in aggregate path
   my @apath;
   push @apath,@cpath;
   push @apath,@gpath;

   # check metadata compliance with the computer and its DATASET aggregated template (inherited)
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{parent}=$parent;
   $opt{computer}=$computer;
   $opt{metadata}=$md;
   checkDatasetTemplateCompliance($mess,\%opt,$db,$userid);
   # check return value
   my $compl;
   if ($mess->value("err") == 0) {
      # success - get metadata hash
      $compl=$mess->get();
   }

   if (defined $compl) {
      # check if we are ok or not
      if ($compl->{compliance}) {
         # we are compliant
         # auto/man
         if ($type eq $SysSchema::C{"dataset.auto"}) {
            # modify metadata hash and add relevant values
            $md->{$SysSchema::MD{"dataset.userpath"}}=$path;
         } elsif ($type eq $SysSchema::C{"dataset.man"}) {
            # modify metadata hash and add relevant values
         }

         # get just template for parent
         my $tmplparent=$db->getEntityTemplate($db->getEntityTypeIdByName("DATASET"),@gpath);
         # decide the lifespan based on template from parent
         my $lifespan=(86400*7); # default it to a week to ensure it doesnt just disappear
         my $extendmax=(86400*3); # default maximum to extend per time is 3 days.
         my $extendlimit=(86400*30); # default limit of extension is a month.
         if ((exists $tmplparent->{$SysSchema::MD{"dataset.open.lifespan"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.open.lifespan"}}{default})) {
            $lifespan=$tmplparent->{$SysSchema::MD{"dataset.open.lifespan"}}{default};
         }
         if ((exists $tmplparent->{$SysSchema::MD{"dataset.open.extendmax"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.open.extendmax"}}{default})) {
            $extendmax=$tmplparent->{$SysSchema::MD{"dataset.open.extendmax"}}{default};
         }
         if ((exists $tmplparent->{$SysSchema::MD{"dataset.open.extendlimit"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.open.extendlimit"}}{default})) {
            $extendlimit=$tmplparent->{$SysSchema::MD{"dataset.open.extendlimit"}}{default};
         }

         # get aggregate template and metadata for parent, computer and user for inheritance
         my $aggmdata=mergeMetadata($db,undef,undef,$computer,$parent,$userid);
         # get users metadata
         my $umd=$db->getEntityMetadata($userid);
         if (!defined $umd) {
            $content->value("errstr","Unable to get USER entity metadata: ".$db->error().". Unable to fulfill request");
            $content->value("err",1);
            return 0;
         }
         my $fullname=$umd->{$SysSchema::MD{fullname}} || "John Doe";
         # set shared metadata values between the dataset types
         my $time=time();
         # we do not care what DublinCore creator was set to during creation - we override it with the creating users info
         $md->{$SysSchema::MD{"dc.creator"}}=$fullname;
         # other metadata
         $md->{$SysSchema::MD{"dataset.computer"}}=$computer;
         $md->{$SysSchema::MD{"dataset.creator"}}=$userid;
         $md->{$SysSchema::MD{"dataset.status"}}=$SysSchema::C{"status.open"};
         $md->{$SysSchema::MD{"dataset.type"}}=$type;
         $md->{$SysSchema::MD{"dataset.created"}}=$time;
         $md->{$SysSchema::MD{"dataset.removed"}}=0; # dataset is not yet removed.
         my $dtyp=($db->getEntityTypeIdByName("DATASET"))[0];
         if (!defined $dtyp) {
            $content->value("errstr","Unable to get DATASET entity type id: ".$db->error().". Unable to fulfill request");
            $content->value("err",1);
            return 0;
         }
         $md->{$SysSchema::MD{"entity.type"}}=$dtyp;
         $md->{$SysSchema::MD{"entity.parent"}}=$parent; # parent id redundancy for search reasons

         # also set its open expire time upon creation.
         $md->{$SysSchema::MD{"dataset.expire"}}=$time+$lifespan;

         # we are ready to create dataset and add metadata - start transaction
         my $tr=$db->useDBItransaction();
         if (defined $tr) {
            # create the entity
            my $id=$db->createEntity(($db->getEntityTypeIdByName("DATASET"))[0],$parent);
            if (defined $id) {
               # entity created - input metadata
               $md->{$SysSchema::MD{"entity.id"}}=$id; # dataset id - redundancy for search reasons
               if (!$db->setEntityMetadata($id,$md,$db->getEntityTypeIdByName("DATASET"),\@apath)) {
                  # failed
                  # $tr->rollback(); ?
                  $content->value("errstr","Unable to set dataset entity metadata: ".$db->error().". Unable to fulfill request");
                  $content->value("err",1);
                  return 0;
               } 

               # give creating user relevant dataset permissions on dataset
               # make it future-proof (or alternately shoot ourselves in the foot)
               my @perms=$db->enumPermTypes();
               if (!defined $perms[0]) {
                  # something failed
                  $content->value("errstr","Unable to enumerate perm types: ".$db->error().". Unable to fulfill request");
                  $content->value("err",1);
                  return 0;
               }
               my @dperms;
               foreach (@perms) {
                  my $perm=$_;

                  # only select perms beginning with DATASET_ and we revoke MOVE and DELETE and EXTEND_UNLIMITED for user
                  if (($perm =~ /^DATASET\_.*$/) && ($perm ne "DATASET_MOVE") && ($perm ne "DATASET_DELETE") && ($perm ne "DATASET_EXTEND_UNLIMITED")) {
                     push @dperms,$perm;
                  }
               }
               # create bitmask
               my $umask=$db->createBitmask($db->getPermTypeValueByName(@dperms));
               # grant bitmask perms to user on dataset
               if (!$db->setEntityPermByObject($userid,$id,$umask,undef,undef)) {
                     $content->value("errstr","Unable to give creating user all dataset permissions on dataset $id: ".$db->error());
                     $content->value("err",1);
                     # this is a failure - rollback database changes
                     $tr->rollback(); 
                     # return failure
                     return 0;
               }

               # create data storage, before logging anything
               my $ev=fiEval->new();
               if (!$ev->success()) {
                  # unable to instantiate fiEval
                  $content->value("errstr","Unable to instantiate fiEval-instance: ".$!);
                  $content->value("err",1);
                  # rollback db changes
                  $tr->rollback(); 
                  return 0;
               }

               if ((!$ev->evaluate("create",$id,$userid,$parent)) || ($ev->evaluate("mode",$id) ne "rw")) {
                  my $err=$ev->error() || "";
                  # this is a failure - delete database changes
                  my $dberr="";
                  $content->value("errstr","Unable to create RW storage area for dataset $id: $err$dberr. Unable to fulfill request");
                  $content->value("err",1);
                  # rollback db changes
                  $tr->rollback(); 
                  # return failure
                  return 0;
               }

               # add log entry
               $log->send(entity=>$id,logtag=>$main::SHORTNAME,logmess=>"Created $type dataset");
               $log->send(entity=>$id,logtag=>$main::SHORTNAME,logmess=>"Status is ".$SysSchema::C{"status.open"});

               # set if dataset has been disted
               my $disted=1;

               # get template from computer by inheritance, first get template settings
               my $templ;
               if ($disted) {
                  $templ=$db->getEntityTemplate(($db->getEntityTypeIdByName("COMPUTER"))[0],@cpath);

                  if (!defined $templ) {
                     $disted=0;
                  }
               }

               # if still disted, get metadata of computer
               my $mdcomp;
               if ($disted) {
                  # we have a template - retrieve the metadata of the computer itself
                  $mdcomp=$db->getEntityMetadata ($computer);

                  if (!defined $mdcomp) {
                     $disted=0;
                  }
               }

               # get task, start with invalid id
               my $task=0;
               if ($disted) {
                  # get task-entity to use for this computer
                  $task=getEntityTask($db,$computer);
                  if ((!$task) && ($type eq $SysSchema::C{"dataset.auto"})) {
                     $disted=0;
                  }
               }

               # if we're still disted, we have what we need to proceed
               if ($disted) {
                  my $tskhash;
                  if ($task) {
                     # we have a valid task - get its task definition
                     my $taskmd=$db->getEntityMetadata($task);                        
                     if (!defined $taskmd) {
                        $content->value("errstr","Unable to get TASK entity $task metadata: ".$db->error().". Unable to fulfill request");
                        $content->value("err",1);
                        return 0;
                     }
                     # we have template metadata, computer metadata and task metadata - convert to storecollection hashes
                     my $sc=StoreCollection->new(base=>$SysSchema::MD{"storecollection.base"});
                     # make store collection hash from task metadata
                     $tskhash=$sc->metadata2Hash($taskmd);

                     # get metadatacollection data from template and computer
                     my $mc=MetadataCollection->new(base=>$SysSchema::MD{"computer.task.base"});
                     # make store collection hash from template
                     my $thash=$mc->template2Hash($templ);
                     # make store collection hash from computer metadata
                     my $chash=$mc->metadata2Hash($mdcomp);
                     # merge template and computer metadata hashes, computer having precedence
                     my $mdcoll=$mc->mergeHash($thash,$chash);

                     # pick classparam and param data from template and computer, overriding task-definition
                     # in the first get-definition (all else is left intact)
                     if ((exists $mdcoll->{param}) && (ref($mdcoll->{param}) eq "HASH")) {
                        foreach (keys %{$mdcoll->{param}}) {
                           my $name=$_;
                           my $value=$mdcoll->{param}{$name};
                           $tskhash->{get}{1}{param}{$name}=$value;
                        }
                     }
                     if ((exists $mdcoll->{classparam}) && (ref($mdcoll->{classparam}) eq "HASH")) {
                        foreach (keys %{$mdcoll->{classparam}}) {
                           my $name=$_;
                           my $value=$mdcoll->{classparam}{$name};
                           $tskhash->{get}{1}{classparam}{$name}=$value;
                        }
                     }
                  }

                  # get put-definitions from owner group
                  my $class=ref($content);
                  my $mess=$class->new();
                  my %opt;
                  $opt{id}=$parent;
                  $opt{type}="GROUP";
                  MethodsReuse::getEntityTaskAssignments($mess,\%opt,$db,$userid);

                  # check return value
                  if ($mess->value("err") == 0) {
                     # get assignments
                     my $assigns=$mess->value("assignments");
                     # check if we have any assignments for current computer
                     if (exists $assigns->{$computer}) {
                        # get assignments
                        my @alist;
                        if (ref($assigns->{$computer}) eq "ARRAY") { @alist=@{$assigns->{$computer}}; }
                        # go through each assigned task and collect data
                        foreach (@alist) {
                           my $atask=$_;

                           # attempt to get task, if group do not have permissions, it will fail
                           # we therefore set userid to parent (=group)
                           my $class=ref($content);
                           my $mess=$class->new();
                           my %opt;
                           $opt{id}=$atask;
                           MethodsTask::getTask($mess,\%opt,$db,$parent,undef,undef,1);
                           if ($mess->value("err") == 0) {
                              # we got the task definition
                              my $taskdef=$mess->value("task");
                              # collect put data
                              foreach (keys %{$taskdef->{put}}) {
                                 my $no=$_;
                                 my $pos=(keys %{$tskhash->{put}})+1;
                                 $tskhash->{put}{$pos}=$taskdef->{put}{$no};
                              }
                           } 
                        }
                     }
                  }

                  # get put-definitions from user
                  $class=ref($content);
                  $mess=$class->new();
                  %opt=();
                  $opt{id}=$userid;
                  $opt{type}="USER";
                  MethodsReuse::getEntityTaskAssignments($mess,\%opt,$db,$userid);

                  # check return value
                  if ($mess->value("err") == 0) {
                     # get assignments
                     my $assigns=$mess->value("assignments");
                     # check if we have any assignments for current computer
                     if (exists $assigns->{$computer}) {
                        # get assignments
                        my @alist;
                        if (ref($assigns->{$computer}) eq "ARRAY") { @alist=@{$assigns->{$computer}}; }
                        # go through each assigned task and collect data
                        foreach (@alist) {
                           my $atask=$_;

                           # attempt to get task, if user do not have permissions, it will fail                    
                           my $class=ref($content);
                           my $mess=$class->new();
                           my %opt;
                           $opt{id}=$atask;
                           MethodsTask::getTask($mess,\%opt,$db,$userid,undef,undef,1);
                           if ($mess->value("err") == 0) {
                              # we got the task definition
                              my $taskdef=$mess->value("task");
                              # collect put data
                              foreach (keys %{$taskdef->{put}}) {
                                 my $no=$_;
                                 my $pos=(keys %{$tskhash->{put}})+1;
                                 $tskhash->{put}{$pos}=$taskdef->{put}{$no};
                              }
                           } 
                        }
                     }
                  }

                  # overwrite first get with path param if auto
                  if ($type eq $SysSchema::C{"dataset.auto"}) {
                     # auto dataset
                     # set the userpath that was asked for
                     $tskhash->{get}{1}{param}{remote}=$SysSchema::CLEAN{pathsquash}->($path);
                     # set computer id
                     $tskhash->{get}{1}{computer}=$computer;
                     # set computer name, so we also have that
                     $tskhash->{get}{1}{computername}=$mdcomp->{$SysSchema::MD{name}} || "";
                     # set StoreCollection used, which basically comes from the computer
                     $tskhash->{get}{1}{storecollection}=$task;
                  }

                  # we have a store collection hash, write it to a distribution queue
                  my $dq=DistributionQueue->new(folder=>$cfg->value("system.dist.location"));

                  # define todo
                  my $todo="";
                  if ($type eq $SysSchema::C{"dataset.auto"}) {
                     # automated datasets do both acquire and distribute-phase
                     $todo=$SysSchema::C{"phase.acquire"}; # always attempt acquire on create dataset and automated
                     # check if any dist exists, only attempt it if it exists
                     if (keys %{$tskhash->{put}} > 0) { $todo.=",".$SysSchema::C{"phase.dist"}; } else { delete ($tskhash->{put}); }
                     # check if caller asked for remote data to be deleted, we then copy connection
                     # data from the acquire/get-part of the storecollection
                     if ($delete) { 
                        # if not defined, use get-task no 1 for the delete.
                        if (!defined $tskhash->{del}) { $tskhash->{del}{1}=$tskhash->{get}{1}; } 
                        # add the delete as part of the phase
                        $todo.=",".$SysSchema::C{"phase.delete"};
                     }
                  } else {
                     # manual datasets only do distribute phase if it exists
                     if (keys %{$tskhash->{put}} > 0) { $todo=$SysSchema::C{"phase.dist"}; } else { delete ($tskhash->{put}); }
                  }

                  # instantiate Content-class and convert StoreCollection into YAML
                  my $c=Content::YAML->new(deref=>1);                  
                  my $data=$c->encode($tskhash);
                  
                  # add task to distribution queue, only if todo is non-empty
                  if ($todo ne "") {
                     my $task=$dq->addTask($userid,$id,$data,todo=>$todo);

                     if (defined $task) {
                        $log->send(entity=>$id,logtag=>$main::SHORTNAME,logmess=>"Added dataset task to store-service queue as task $task.");
                     } else {
                        $log->send(entity=>$id,logtag=>$main::SHORTNAME,logmess=>"Failed to add task to store-service queue: ".$dq->error(),loglevel=>$Content::Log::LEVEL_ERROR);
                     }
                  }
               } else {
                  # adding to distribution queue failed
                  $log->send(entity=>$id,logtag=>$main::SHORTNAME,logmess=>"Failed to get template and/or metadata of computer. Unable to define StoreCollection.",loglevel=>$Content::Log::LEVEL_ERROR);
               }

               # everything has gone ok, commit changes to database
               if (!$tr->commit()) {
                  # commit failure
                  $content->value("errstr","Unable to commit database changes for createDataset: ".$db->error().". Unable to fulfill request");
                  $content->value("err",1);
                  $tr->rollback();
                  return 0;
               }

               # purge dataset, to update it (setting up permissions, who have access, link-tree)
               # do this after commit, to ensure that FileInterface can do its job properly
               $ev->evaluate("purge",$id);
   
               # we are successful in creating dataset
               $content->value("errstr","");
               $content->value("err",0);
               $content->value("id",$id);
               return 1;
            } else {
               # something failed - rollback
               $tr->rollback();
               $content->value("errstr","Unable to create dataset entity: ".$db->error().". Unable to fulfill request");
               $content->value("err",1);
               return 0;                  
            }
         } else {
            # something failed
            $content->value("errstr","Unable to instantiate transaction object: ".$db->error().". Unable to fulfill request");
            $content->value("err",1);
            return 0;
         }      
      } else {
         # we are non-compliant
         $content->value("errstr","The metadata key(s): @{$compl->{noncompliance}} are not compliant with computer template. Unable to fulfill request");
         $content->value("err",1);
         return 0;
      }
   } else {
      # something failed
      $content->value("errstr","Failed to check computer template compliance: ".$mess->value("errstr").". Unable to fulfill request");
      $content->value("err",1);
      return 0;
   }
}

sub createDatasetToken { # Create a token for a dataset 

    # Read from rest call interface, 
    #
    my ($content, $query, $db, $userid, $cfg, $log) = @_; # Rest call interface
    my ($id, $token, $expire) = _get_params( $query, 
	id     => [$Schema::CLEAN{entity}],          # Dataset id
	token  => [$SysSchema::CLEAN{datasetToken}], # Template token, overrides id if given
	expire => [$Schema::CLEAN_GLOBAL{trueint}],  # Optional expire time, relative from now if negative
	);

    # This method uses database transaction
    my $tr = $db->useDBItransaction();
    
    # Process and check the id
    #
    $id = $1 if $token and $token =~ /^(\d+)/; # Extracted id from $token and replace id if given
    return _with_error($content, "No valid dataset id is supplied. Unable to fulfill request.") unless $id;
    return _with_error($content, "Dataset $id does not exist. Unable to fulfill request.")      unless $db->existsEntity($id);
    return _with_error($content, "Entity $id is not a dataset. Unable to fulfill request.")
	unless $db->getEntityType($id) == ($db->getEntityTypeIdByName("DATASET"))[0];
    
    # Process and check expire
    #
    $expire = -86400 unless defined $expire;   # Default expire one day from now
    $expire = time() - $expire if $expire < 0; # Convert expire from relative to absolute if negative
    return _with_error($content, "Expire time in the past. Unable to fulfill request.") unless $expire > time();
    
    # Connect the file interface
    # 
    my $fi = fiEval->new();
    return _with_error($content, "Unable to instantiate fiEval: ".$fi->error().". Unable to fulfill request.") unless $fi->success();

    # Check user permission according to datasets file interface mode
    #
    # Get required permissions
    my $mode = $fi->evaluate("mode",$id);                                         # Get the mode
    my $required = { rw => ["DATASET_CREATE"], ro => ["DATASET_READ"] }->{$mode}; # Map permissions
    return _with_error($content, "Dataset $id is not in valid state for operation") unless $required;
    #
    # Check permissions
    my $allowed = hasPerm($db, $userid, $id, $required, "ALL", "ANY", 1, 1, undef, 1);
    return _with_error($content, "Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.")
	unless defined($allowed);
    return _with_error($content, "User does not have the $required permission on the dataset $id. Unable to fulfill request.")
	unless $allowed;
    
    # Do the actual work;
    #
    # Create the token
    $token = $fi->evaluate("token", $token || $id);
    return _with_error($content, "Unable to create token for dataset $id: ".$fi->error().". Unable to fulfill request.") unless $token;
    #
    # Set the expiration
    my $expirekey = $SysSchema::MD{"dataset.tokenbase"}.".$token.expire";                  # Build expire key for token
    unless ( $db->setEntityMetadata( $id, { $expirekey => $expire }) ) {                   # Set the expire time
	$fi->evaluate("tokenremove", $token);                                              #   or rollback
	return _with_error($content, "Unable to set the token expiretime: ".$db->error().". Unable to fulfill request."); #   and report
    }

    # Task successfully completet. Report and return result
    #
    # Get short name
    my $shortname = substr(Digest::SHA->new(256)->add($token)->hexdigest, 0, 8);
    #
    $log->send(entity => $id,logtag=>$main::SHORTNAME,logmess => "Token $shortname created"); # Add log entry
    $content->value("token", $token);                                 # Set return values
    return _with_success($content);                                   # Return success 
}

sub deleteDatasetMetadata {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $metadata=$SysSchema::CLEAN{metadatalist}->($query->{metadata}); # remove non .-related keys
   # if metadata is empty, ensure we only delete .*, not system metadata which are protected
   if ((!defined $metadata) || (@{$metadata} == 0)) { my @md=(".*"); $metadata=\@md; }

   # check that dataset exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["DATASET_CHANGE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the DATASET_CHANGE permission on the dataset $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # get the entity metadata to check if it has status removed
   my $md=$db->getEntityMetadata($id);
   if (!defined $md) {
      # unable to get metadata
      $content->value("errstr","Unable to get dataset metadata: ".$db->error());
      $content->value("err",1);
      return 0;             
   }
   # get status
   my $removed=$md->{$SysSchema::MD{"dataset.removed"}};
   if ($removed > 0) {
      # it is removed, not allowed to update metadata
      $content->value("errstr","Dataset $id has been removed. You are not allowed to delete metadata. Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   # attempt to set metadata
   if ($db->deleteEntityMetadata($id,$metadata)) {
      # success
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr","Unable to delete dataset metadata: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub enumDatasetPermTypes {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="DATASET";
   # attempt to enumerate
   MethodsReuse::enumPermTypesByEntityType($mess,\%opt,$db,$userid,$cfg,$log);

   # check result
   if ($mess->value("err") == 0) {
      # success
      $content->value("types",$mess->value("types"));
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub extendDatasetToken { # Extend an existsing or expired token.

    # Read from rest call interface, 
    #
    my ($content, $query, $db, $userid, $cfg, $log) = @_; # Rest call interface
    my ($token, $expire) = _get_params( $query, 
	token  => [$SysSchema::CLEAN{datasetToken}], # Template token, overrides id if given
	expire => [$Schema::CLEAN_GLOBAL{trueint}],  # Optional expire time, relative from now if negative
	);

    # This method uses database transaction
    my $tr = $db->useDBItransaction();

    # Check token and extract id
    #
    return _with_error($content, "No valid token is supplied. Unable to fulfill request.") unless $token; # Didnt pass the Schema test
    my ($id) = $token =~ /^(\d+)/; # Extracted id from $token

    # Process and check expire
    #
    $expire = -86400 unless defined $expire;   # Default expire one day from now
    $expire = time() - $expire if $expire < 0; # Convert expire from relative to absolute if negative
    return _with_error($content, "Expire time in the past. Unable to fulfill request.") unless $expire > time();
    
    # Connect the file interface
    # 
    my $fi = fiEval->new();
    return _with_error($content, "Unable to instantiate fiEval: ".$fi->error().". Unable to fulfill request.") unless $fi->success();

    # Check user permission according to datasets file interface mode
    #
    # Get required permissions
    my $mode = $fi->evaluate("mode",$id);                                         # Get the mode
    my $required = { rw => ["DATASET_CREATE"], ro => ["DATASET_READ"] }->{$mode}; # Map permissions
    return _with_error($content, "Dataset $id is not in valid state for operation. Unable to fulfill request.") unless $required;
    #
    # Check permissions
    my $allowed = hasPerm($db, $userid, $id, $required, "ALL", "ANY", 1, 1, undef, 1);
    return _with_error($content, "Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.")
	unless defined($allowed);
    return _with_error($content, "User does not have the $required permission on the dataset $id. Unable to fulfill request.")
	unless $allowed;
    
    # Do the actual work;
    #
    # Make sure the token exists
    $token = $fi->evaluate("token", $token);
    return _with_error($content, "Unable to extend token for dataset $id: ".$fi->error().". Unable to fulfill request.") unless $token;
    #
    # Set the expiration
    my $expirekey = $SysSchema::MD{"dataset.tokenbase"}.".$token.expire";                  # Build expire key for token
    my $oldexpire = $db->getEntityMetadata( $id, $expirekey, [$id]);                       # Get existsing expire time
    unless ( $db->setEntityMetadata( $id, { $expirekey => $expire }) ) {                   # Set the expire time
	$fi->evaluate("tokenremove", $token) unless $oldexpire;                            #   or rollback if no existing expire
	return _with_error($content, "Unable to set the token expiretime: ".$db->error().". Unable to fulfill request."); #   and report
    }

    # Task successfully completet. Report and return result
    #
    # Get short name
    my $shortname = substr(Digest::SHA->new(256)->add($token)->hexdigest, 0, 8);
    #
    $log->send(entity => $id,logtag=>$main::SHORTNAME,logmess => "Token $shortname extended"); # Add log entry
    $content->value("token", $token);                                  # Set return values
    return _with_success($content);                                    # Return success 
}

sub getDatasetAggregatedPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # dataset to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="DATASET";   
   # attempt to get perm
   MethodsReuse::getEntityAggregatedPerm($mess,\%opt,$db,$userid,$cfg,$log);

   # check result
   if ($mess->value("err") == 0) {
      # success
      $content->value("perm",$mess->value("perm"));
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub getDatasetExpirePolicy {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # dataset to get expire policy of

   # check that dataset exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # get expire policies for user
   my $parent=$db->getEntityParent($id);
   my @tmplpath=$db->getEntityPath($parent);
   my $tmplparent=$db->getEntityTemplate($db->getEntityTypeIdByName("DATASET"),@tmplpath);
   # decide the lifespan based on template from parent
   my $lifespanopen=(86400*7); # default it to a week to ensure it doesnt just disappear
   my $extendmaxopen=(86400*3); # default maximum to extend per time is 3 days.
   my $extendlimitopen=(86400*30); # default limit of extension is a month.
   my $lifespanclose=(86400*7); # default it to a week to ensure it doesnt just disappear
   my $extendmaxclose=(86400*3); # default maximum to extend per time is 3 days.
   my $extendlimitclose=(86400*30); # default limit of extension is a month.
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.open.lifespan"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.open.lifespan"}}{default})) {
      $lifespanopen=$tmplparent->{$SysSchema::MD{"dataset.open.lifespan"}}{default};
   }
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.open.extendmax"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.open.extendmax"}}{default})) {
      $extendmaxopen=$tmplparent->{$SysSchema::MD{"dataset.open.extendmax"}}{default};
   }
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.open.extendlimit"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.open.extendlimit"}}{default})) {
      $extendlimitopen=$tmplparent->{$SysSchema::MD{"dataset.open.extendlimit"}}{default};
   }
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}{default})) {
      $lifespanclose=$tmplparent->{$SysSchema::MD{"dataset.close.lifespan"}}{default};
   }
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.close.extendmax"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.close.extendmax"}}{default})) {
      $extendmaxclose=$tmplparent->{$SysSchema::MD{"dataset.close.extendmax"}}{default};
   }
   if ((exists $tmplparent->{$SysSchema::MD{"dataset.close.extendlimit"}}) && (exists $tmplparent->{$SysSchema::MD{"dataset.close.extendlimit"}}{default})) {
      $extendlimitclose=$tmplparent->{$SysSchema::MD{"dataset.close.extendlimit"}}{default};
   }

   my %policy;
   $policy{open}{lifespan}=$lifespanopen;
   $policy{open}{extendmax}=$extendmaxopen;
   $policy{open}{extendlimit}=$extendlimitopen;

   $policy{close}{lifespan}=$lifespanclose;
   $policy{close}{extendmax}=$extendmaxclose;
   $policy{close}{extendlimit}=$extendlimitclose;

   # success if we come to here...
   $content->value("errstr","");
   $content->value("err",0);
   $content->value("expirepolicy",\%policy);
   return 1;
}

sub getDatasetPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # dataset to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="DATASET";   
   # attempt to get dataset perm
   MethodsReuse::getEntityPerm($mess,\%opt,$db,$userid,$cfg,$log);

   # check result
   if ($mess->value("err") == 0) {
      # success
      my %perm;
      $perm{grant}=$mess->value("grant");
      $perm{deny}=$mess->value("deny");
      $content->value("perm",\%perm);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub getDatasetPerms {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # dataset to get perms on

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{type}="DATASET";
   # attempt to set group perm
   MethodsReuse::getEntityPermsOnObject($mess,\%opt,$db,$userid,$cfg,$log);

   # check result
   if ($mess->value("err") == 0) {
      # success
      $content->value("perms",$mess->value("perms"));
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub getDatasetLog {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # clean id
   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that dataset exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["DATASET_LOG_READ"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the DATASET_LOG_READ permission on the dataset $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # check if we have loglevel param
   my $level=1; # default = include all loglevels
   my $loglevel=$db->getLoglevelNameByValue(1);
   if (defined $query->{loglevel}) {
      $loglevel=$Schema::CLEAN{"loglevelname"}->($query->{loglevel});
      # check if valid loglevel and get its ID
      if (!($level=$db->getLoglevelByName($loglevel))) {
         # some error
         $content->value("errstr","Unable to get loglevel value of \"$loglevel\": ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      }
   }

   # we have permissions - attempt to get log
   my $logs=$db->getLogEntries($id);
   if (defined $logs) {
      # success - go through each hit and insert textual loglevel name
      foreach (keys %{$logs}) {
         my $idx=$_;

         # ensure that we want this loglevel message in the response
         if ($logs->{$idx}{loglevel} < $level) { delete ($logs->{$idx}); next; }

         # convert to textual loglevel
         $logs->{$idx}{loglevel}=$db->getLoglevelNameByValue($logs->{$idx}{loglevel});
      }
      # return result
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("loglevel",$loglevel);
      $content->value("log",$logs);
      
      return 1;
   } else {
      # failure
      $content->value("errstr","Unable to get log entries for dataset $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getDatasetMetadata {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that dataset exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ANY of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["DATASET_READ","DATASET_CHANGE","DATASET_METADATA_READ"],"ANY","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the DATASET_READ, DATASET_CHANGE or DATASET_METADATA_READ permissions on the dataset $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # get the ids metadata
   my $md=$db->getEntityMetadata ($id);

   if (defined $md) {
      # we have metadata - return it without system stuff
      $md=$SysSchema::CLEAN{metadata}->($md);
      # return the result
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("metadata",$md);
      return 1;
   } else {
      # something failed
      $content->value("errstr","Unable to get metadata of entity $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getDatasetSystemMetadata {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that dataset exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ANY of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["DATASET_READ","DATASET_CHANGE","DATASET_METADATA_READ"],"ANY","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the DATASET_READ, DATASET_CHANGE or DATASET_METADATA_READ permissions on the dataset $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # get the ids metadata
   my %opts=(parent=>1);
   my $md=$db->getEntityMetadata ($id,\%opts);

   if (defined $md) {
      # we have open system metadata - return it 
      my @include=@{$SysSchema::MDPUB{DATASET}};
      $md=$SysSchema::CLEAN{metadatasystem}->($md,\@include);
      # return the result
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("metadata",$md);
      return 1;
   } else {
      # something failed
      $content->value("errstr","Unable to get metadata of entity $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getDatasetSystemAndMetadata {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that dataset exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ANY of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["DATASET_READ","DATASET_CHANGE","DATASET_METADATA_READ"],"ANY","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the DATASET_READ, DATASET_CHANGE or DATASET_METADATA_READ permissions on the dataset $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # get the ids metadata
   my %opts=(parent=>1);
   my $md=$db->getEntityMetadata ($id,\%opts);

   if (defined $md) {
      # we have metadata - return it with open system metadata
      my @include=@{$SysSchema::MDPUB{DATASET}};
      $md=$SysSchema::CLEAN{metadata}->($md,\@include);
      # return the result
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("metadata",$md);
      return 1;
   } else {
      # something failed
      $content->value("errstr","Unable to get metadata of entity $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getDatasets {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $metadata=$query->{metadata};
   my $sortby=$Schema::CLEAN{orderby}->($query->{sortby});
   my $sort=$Schema::CLEAN{order}->($query->{sort});
   my $offset=$Schema::CLEAN{offset}->($query->{offset});
   my $count=$Schema::CLEAN{offsetcount}->($query->{count});
   my $sorttype=$Schema::CLEAN{sorttype}->($query->{sorttype});

   sub check_for_metadata_keys {
      my $meta=shift;  
      my $search=shift; 

      if (ref($meta) eq "ARRAY") {
         for (my $i=1; $i < @{$meta}; $i++) { 
            if ((ref($meta->[$i]) eq "HASH") || (ref($meta->[$i]) eq "ARRAY"))  { if (check_for_metadata_keys($meta->[$i],$search)) { return 1; } } 
         }
      } elsif (ref($meta) eq "HASH") {
         foreach (keys %{$meta}) { 
            my $k=$_;
            # check for existence of any of the given keys
            # if so, abort further checks
            if (exists $search->{$k}) { return 1; }
            # if not found, we recurse down the key
            else { if (check_for_metadata_keys ($meta->{$k},$search)) { return 1; } }
         }
         # none of the keys exists here - return false
         return 0;
      }
   }

   if ((defined $metadata) && (ref($metadata) ne "ARRAY")) {
      # does not exist 
      $content->value("errstr","Metadata is not an ARRAY. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # metadata to include in clean
   # even though it is system metadata
   my @i=@{$SysSchema::MDPUB{DATASET}};

   # clean metadata
   my $parent=0;
   my $cleaned=0;
   ($parent,$metadata,$cleaned)=$SysSchema::CLEAN{metadatasql}->($metadata,\@i);

   # check if metadata-structure has been cleaned/keys removed.
   # if so, notify and fail.
   if ($cleaned) {
      # failure
      $content->value("errstr","Unable to get datasets because key(s) in the metadata-structure was/were cleaned away not being allowed.");
      $content->value("err",1);
      # upon failure also include metadata structure as it was used
      # since value(s) has(ve) been cleaned away
      $content->value("metadata",$metadata);
      return 0;
   }

   # do some heuristics and check if the SQLstruct has asked for
   # parent name or not and if not choose to use just the METADATA-table
   my $table=1; # we set the METADATA_COMBINED as default
   my %mkeys=( $SysSchema::MD{"entity.parentname"}=>1 );
   if (!check_for_metadata_keys($metadata,\%mkeys)) { $table=0; }
   # also, if none of the mkeys were found check if they exist
   # in the sortby option, then also select the METADATA_COMBINED table
   if ((!$table) && (exists $mkeys{$sortby})) { $table=1; }   
   # set perm needed - any will give you a list
   my $perm=$db->createBitmask($db->getPermTypeValueByName("DATASET_DELETE","DATASET_CHANGE","DATASET_MOVE",
                               "DATASET_PUBLISH","DATASET_RERUN","DATASET_PERM_SET","DATASET_READ",
                               "DATASET_LOG_READ","DATASET_LIST"));

   # ready to get entity(ies) with parent metadata
   my @type=($db->getEntityTypeIdByName("DATASET"));
   my $entities=$db->getEntityPermByPermAndMetadataKeyAndType ($userid,$perm,"ANY",$metadata,$offset,$count,$sortby,$sort,\@type,$table,$sorttype);

   # go through each entity and retrieve data
   if (defined $entities) {
      # success
      # get all metadata
      my @ents=map { $entities->{$_}{entity} } keys %{$entities};
      my $md=$db->getEntityMetadataMultipleList (undef,\@ents,1);
      my %result;
      foreach (keys %{$entities}) {
         my $no=$_;

         # get entity
         my $entity=$entities->{$no}{entity};
         my $perm=$entities->{$no}{perm};

         if (defined $md->{$entity}) {
            # success - clean away system metadata, except include

            # add to result hash
            $result{$no}{id}=$entity;
            $result{$no}{perm}=permToArray($db,$perm);

            # return the metadata asked for - include some shortcuts and conversion (creator)
            $result{$no}{parentid}=$md->{$entity}{$SysSchema::MD{"entity.parent"}} || 0;
            $result{$no}{parentname}=$md->{$entity}{$SysSchema::MD{"entity.parentname"}} || "UNDEFINED";
            $result{$no}{entitytype}=$md->{$entity}{$SysSchema::MD{"entity.type"}} || 0;
            $result{$no}{created}=$md->{$entity}{$SysSchema::MD{"dataset.created"}} || "";
            $result{$no}{creator}=$md->{$entity}{$SysSchema::MD{"dc.creator"}} || "";
            $result{$no}{creatorid}=$md->{$entity}{$SysSchema::MD{"dataset.creator"}} || 0;
            $result{$no}{computerid}=$md->{$entity}{$SysSchema::MD{"dataset.computer"}} || 0;
            $result{$no}{computername}=$md->{$entity}{$SysSchema::MD{"dataset.computername"}} || "UNDEFINED";
            $result{$no}{description}=$md->{$entity}{$SysSchema::MD{"dc.description"}} || "";
            $result{$no}{expire}=$md->{$entity}{$SysSchema::MD{"dataset.expire"}} || 0;
            $result{$no}{status}=$md->{$entity}{$SysSchema::MD{"dataset.status"}};
            $result{$no}{removed}=$md->{$entity}{$SysSchema::MD{"dataset.removed"}} || 0;
            $result{$no}{type}=$md->{$entity}{$SysSchema::MD{"dataset.type"}} || 0;
         } else {
            # some metadata might be missing due to delays in the maintenance-services.
            # We will create a "hollow" dataset...
            # add to result hash
            $result{$no}{id}=$entity;
            $result{$no}{perm}=permToArray($db,$perm);

            # return the metadata asked for - include some shortcuts and conversion (creator)
            $result{$no}{parentid}=$db->getEntityParent($entity);

            $result{$no}{parentname}="UNDEFINED";
            $result{$no}{entitytype}=($db->getEntityTypeIdByName ("DATASET"))[0];
            $result{$no}{created}="";
            $result{$no}{creator}="";
            $result{$no}{creatorid}=0;
            $result{$no}{computerid}=0;
            $result{$no}{computername}="UNDEFINED";
            $result{$no}{description}="";
            $result{$no}{expire}=0;
            $result{$no}{status}="";
            $result{$no}{removed}=0;
            $result{$no}{type}=($db->getEntityTypeIdByName ("DATASET"))[0];
         }
      }
      my $no=keys %result || 0;
      my $total=$db->getLimitTotal() || 0;
      # return the result
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("datasets",\%result);
      $content->value("returned",$no);
      $content->value("total",$total);
      # even on success, include metadata structure as it was used
      # since values might have been cleaned away
      $content->value("metadata",$metadata);   
      return 1;
   } else {
      # failure
      $content->value("errstr","Unable to get datasets: ".$db->error());
      $content->value("err",1);
      # upon failure also include metadata structure as it was used
      # since values might have been cleaned away
      $content->value("metadata",$metadata);
      return 0;
   }
}

sub getDatasetTemplate {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $computer=$Schema::CLEAN{entity}->($query->{computer});

   my $iddef=defined $query->{id};

   # check that dataset exists and is the right type
   if (($iddef) && ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0]))) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # check if parent exists and is the right type (only if no id)
   if ((!$iddef) && ((!$db->existsEntity($parent)) || ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0]))) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check if computer exists and is the right type (only if no id)
   my @pathreq;
   if ((!$iddef) && ((!$db->existsEntity($computer)) || ($db->getEntityType($computer) != ($db->getEntityTypeIdByName("COMPUTER"))[0]))) {
      # does not exist 
      $content->value("errstr","Computer $computer does not exist or is not a COMPUTER entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } elsif (!$iddef) {
      # get path of computer
      push @pathreq,$computer;
   }

   # get path of entity or group
   if (!$iddef) { push @pathreq,$parent; }
   else { push @pathreq,$id; }

   my $paths;
   # a little trick to deal with the dual backwards
   # compatible nature of getEntityPath
   if (@pathreq == 1) {
      my @p=$db->getEntityPath(@pathreq);
      $paths->{$pathreq[0]}=\@p;
   } else {
      $paths=$db->getEntityPath(@pathreq);
   }

   if (!defined $paths) {
      # something failed
      $content->value("errstr","Unable to get path: ".$db->error().". Unable to fulfill request");
      $content->value("err",1);
      return 0;
   }

   my @cpath;
   my @path;
   if (@pathreq == 1) {
      @path=@{$paths->{$pathreq[0]}};
   } else {
      @cpath=@{$paths->{$pathreq[0]}};
      @path=@{$paths->{$pathreq[1]}}; 
   }
   # combine path, dataset/group has precedence
   my @apath;
   push @apath,@cpath;
   push @apath,@path;

   # we are ready to fetch template
   my $templ=$db->getEntityTemplate($db->getEntityTypeIdByName("DATASET"),@apath);

   if (defined $templ) {
      # we have a template - convert flags for each key
      foreach (keys %{$templ}) {
         my $key=$_;

         my @flags;
         if (defined $templ->{$key}{flags}) {
            @flags=@{flagsToArray($db,$templ->{$key}{flags})};

         }
         # change flags to new value
         $templ->{$key}{flags}=\@flags;
      }

      # remove everything that does not start with ".".
      my $ntempl=$SysSchema::CLEAN{metadata}->($templ);

      # we have a template - return it
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("template",$ntempl);
      return 1;
   } else {
      # something went to shits
      $content->value("errstr","Unable to get dataset template: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub listDatasetFolder {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get dataset id and clean it
   my $id=$Schema::CLEAN{entity}->($query->{id});
   # md5 sum or not? Default = false/0.
   my $md5sum=$Schema::CLEAN{boolean}->($query->{md5sum});

   # check that dataset exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["DATASET_READ"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the DATASET_READ permission on the dataset $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # get the entity metadata to check if it has status closed
   my $md=$db->getEntityMetadata($id);
   if (!defined $md) {
      # unable to get metadata
      $content->value("errstr","Unable to get dataset $id metadata: ".$db->error());
      $content->value("err",1);
      return 0;             
   }

   # get status
   my $status=$md->{$SysSchema::MD{"dataset.status"}};
   if ($status ne $SysSchema::C{"status.closed"}) {
      # it is not closed, not allowed to list files and folders
      $content->value("errstr","Dataset $id has not been closed yet. You are not allowed to list files and folders. Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   # requirements fulfilled - ready to read dataset structure
   my $ev=fiEval->new();
   if (!$ev->success()) {
      # unable to instantiate fiEval
      $content->value("errstr","Unable to instantiate fiEval-instance: ".$ev->error());
      $content->value("err",1);
      return 0;
   }

   # ensure we have dataset and that it can be viewed/is RO
   if ($ev->evaluate("mode",$id) ne "ro") {
      # unable to start process
      my $err=(defined $ev->error() ? ": ".$ev->error() : "");
      $content->value("errstr","Unable to open dataset $id to read files and folders$err. Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   # get source path
   my $source=$ev->evaluate ("datapath",$id) || "/DUMMY/DUMMY";

   # append /data to the path
#   $source.="/data";

   # get structure, do recursive and also md5-sum if so specified
   my $struct=listFolders ($source,1,$md5sum,1);

   # return result whatever that may be...
   $content->value("folder",$struct);
   $content->value("errstr","");
   $content->value("err",0);
   return 1;
}

sub moveDataset {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{parent}=$query->{parent};
   $opt{type}="DATASET";
   $opt{parenttype}="GROUP";
   MethodsReuse::moveEntity($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub removeDataset {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check if id exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["DATASET_DELETE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the DATASET_DELETE permission on the dataset $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # get dataset metadata
   my $md=$db->getEntityMetadata($id);

   if (!defined $md) {
      # something failed
      $content->value("errstr","Failed to get metadata for dataset $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # get user metadata
   my $umd=$db->getEntityMetadata($userid);

   if (!defined $umd) {
      # something failed
      $content->value("errstr","Failed to get metadata for user $userid: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # we have metadata - check the dataset status flag
   my $status=$md->{$SysSchema::MD{"dataset.status"}};
   if ($status eq $SysSchema::C{"status.open"}) {
      # not allowed to remove open datasets, close first
      $content->value("errstr","Not allowed to remove open datasets. They must be closed first. Unable to continue.");
      $content->value("err",1);
      return 0;
   }

   # it has the right status - we can remove it
   my $ev=fiEval->new();
   if (!$ev->success()) {
      # unable to instantiate fiEval
      $content->value("errstr","Unable to instantiate fiEval-instance: ".$ev->error());
      $content->value("err",1);
      return 0;
   }

   my $mode=$ev->evaluate("mode",$id);
   if ((!defined $mode) || (lc($mode) ne "ro")) {
      my $err=": ".$ev->error();
      # some issue with reading the storage
      $content->value("errstr","Unable to remove dataset $id because of failure to open storage area and/or the storage does not have RO status$err");
      $content->value("err",1);
      return 0;
   }

   # create notification to remove
   my $fullname=$umd->{$SysSchema::MD{"fullname"}} || "";
   my $email=$umd->{$SysSchema::MD{"email"}} || "";
   my $not=Not->new();
   $not->send(type=>"dataset.remove",about=>$id,from=>$SysSchema::FROM_REST,
              message=>"Hi,\n\nDataset $id (".($md->{$SysSchema::MD{"dc.description"}} || "N/A").") created on the ".time2iso($md->{$SysSchema::MD{"dataset.created"}}||0).
                       " has been requested for removal by user $fullname ($email).".
                       "\n\nBest regards,\n\n   Aurora System");
 
   # add log entry
   $log->send(entity=>$id,logtag=>$main::SHORTNAME,logmess=>"Dataset requested for removal by user $userid. Notification created.");

   # success if we come to here...   
   $content->value("errstr","");
   $content->value("err",0);
   return 1;
}

sub removeDatasetToken { # Remove a token

    # Read from rest call interface, 
    #
    my ($content, $query, $db, $userid, $cfg, $log) = @_; # Rest call interface
    my ($token, $expire) = _get_params( $query, 
	token  => [$SysSchema::CLEAN{datasetToken}], # Template token, overrides id if given
	);

    # This method uses database transaction
    my $tr = $db->useDBItransaction();

    # Check token and extract id
    #
    return _with_error($content, "No valid token is supplied. Unable to fulfill request.") unless $token; # Didnt pass the Schema test
    my ($id) = $token =~ /^(\d+)/; # Extracted id from $token

    # Connect the file interface
    # 
    my $fi = fiEval->new();
    return _with_error($content, "Unable to instantiate fiEval: ".$fi->error().". Unable to fulfill request.") unless $fi->success();

    # Check user permission according to datasets file interface mode
    #
    # Get required permissions
    my $mode = $fi->evaluate("mode",$id);                                         # Get the mode
    my $required = { rw => ["DATASET_CREATE"], ro => ["DATASET_READ"] }->{$mode}; # Map permissions
    return _with_error($content, "Dataset $id is not in valid state for operation. Unable to fulfill request.") unless $required;
    #
    # Check permissions
    my $allowed = hasPerm($db, $userid, $id, $required, "ALL", "ANY", 1, 1, undef, 1);
    return _with_error($content, "Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.")
	unless defined($allowed);
    return _with_error($content, "User does not have the $required permission on the dataset $id. Unable to fulfill request.")
	unless $allowed;
    
    # Do the actual work;
    #
    # Remove the token
    my $tokenRemoved = $fi->evaluate("tokenremove", $token);
    return _with_error($content, "Unable to remove token for dataset $id: ".$fi->error().". Unable to fulfill request.") unless $tokenRemoved;
    #
    # remove any token metadata
    my $tokenkeys = $SysSchema::MD{"dataset.tokenbase"}.".$token.*";                           # Build like-key for token
    $db->deleteEntityMetadata($id, [$tokenkeys])                                               # Delete the metadata
	or return _with_error($content, "Unable to remove token metadata: ".$db->error().". Unable to fulfill request."); #   or report error
    $db->deleteMetadataKey($tokenkeys)                                                         # Delete the metadata keys
	or return _with_error($content, "Unable to remove token metadatakeys: ".$db->error().". Unable to fulfill request."); #   or report

    # Task successfully completet. Report and return result
    #
    # Get short name
    my $shortname = substr(Digest::SHA->new(256)->add($token)->hexdigest, 0, 8);
    #
    $log->send(entity => $id,logtag=>$main::SHORTNAME,logmess => "Token $shortname removed"); # Add log entry
    $content->value("token", $token);                                 # Set return values
    return _with_success($content);                                   # Return success 
}

sub setDatasetMetadata {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $metadata=$SysSchema::CLEAN{metadata}->($query->{metadata}); # remove non .-related keys
   my $mode=$query->{mode};

   # check that dataset exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   if (defined $mode) {
      $mode=$SysSchema::CLEAN{"metadatamode"}->($mode);
   } else {
      $mode="UPDATE";
   }

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["DATASET_CHANGE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the DATASET_CHANGE permission on the dataset $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # get the entity metadata to check if it has status removed
   my $md=$db->getEntityMetadata($id);
   if (!defined $md) {
      # unable to get metadata
      $content->value("errstr","Unable to get dataset metadata: ".$db->error());
      $content->value("err",1);
      return 0;             
   }
   # get status
   my $removed=$md->{$SysSchema::MD{"dataset.removed"}};
   if ($removed > 0) {
      # it is deleted, not allowed to update metadata
      $content->value("errstr","Dataset $id has been removed. You are not allowed to update the metadata. Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   # start transaction
   my $tr=$db->useDBItransaction();

   # check mode, remove current metadata if mode i replace
   if ($mode eq "REPLACE") {
      # attempt to remove all .-related metadata
      if (!$db->deleteEntityMetadata($id,[".*"])) { # remove all .-something data (no not touch system-metadata)
         $content->value("errstr","Could not remove old DATASET metadata when dataset in mode $mode: ".$db->error().". Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      } 
   }

   # attempt to set metadata
   if ($db->setEntityMetadata($id,$metadata)) {
      # success
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr","Unable to set DATASET metadata: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub setDatasetPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # dataset to set perm on
   my $user=$query->{user}; # subject which perm is valid for
   my $grant=$query->{grant}; # grant mask to set 
   my $deny=$query->{deny}; # deny mask to set
   my $op=$query->{operation};

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{grant}=$grant;
   $opt{deny}=$deny;
   $opt{operation}=$op;
   $opt{type}="DATASET";
   # attempt to set group perm
   MethodsReuse::setEntityPerm($mess,\%opt,$db,$userid,$cfg,$log);

   # check result
   if ($mess->value("err") == 0) {
      # success
      my %perm;
      $perm{grant}=$mess->value("grant");
      $perm{deny}=$mess->value("deny");
      $content->value("perm",\%perm);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

1;

__END__

=encoding UTF-8

=head1 DATASET METHODS

=head2 changeDatasetExpireDate()

Change the dataset's expiration date.

This method takes the following parameters:

=over

=item

B<id> Dataset ID from the database of the dataset to change expiration date on. INTEGER. Required.

=cut

=item

B<expiredate> The new expire date to set on the dataset in question. INTEGER. Required. This is the unix datetime to set in 
seconds from epoch (19700101) or relative to old/current expire date. The difference between absolute and relative expiredate 
is determined by the signing of the expiredate-parameter. If the expiredate is > 0, then it is absolute, if expiredate < 0 it is 
taken as a relative number of seconds since the current expire date.

=cut

=back

This method required that the user has the DATASET_DELETE-permission on the dataset in question. If the user wished to extend the 
expiration date of the dataset beyond the limit set in template(s) on the "extendlimit"-setting or beyond the maximum extension 
time per attempt to extend (extendmax), the user needs the DATASET_EXTEND_UNLIMITED-permission. Please note that in either case 
the DATASET_DELETE-permission is needed.

Changing expire-dates in AURORA relies on some settings through templates called:

- system.dataset.close.extendmax
- system.dataset.close.extendlimit

These two settings are read from AURORA when the user attempts to change the expire date and the ones in effect through 
templates will be used.

The general rule is that the user with the DATASET_DELETE-permission can choose to extend the expire-date of the dataset 
with a maximum of "extendmax"-seconds per time he tries to change the expire date. Furthermore, he can only extend the 
expiration date of the dataset up until the "extendlimit"-settings, which is basically used as the number of seconds after 
the close-date of the dataset in question. So, the user cannot extend the expire-date of the dataset beyond this limit. 
In order to do that, the template(s) in effect needs to be changed or he needs to additionally have the DATASET_EXTEND_UNLIMITED-
permission on the dataset, which are typically only given to administrators.

The user can however without any hindrances limit the expire-date down to the current time and basically then ask for the dataset 
to expire immediately. This will, however, not remove the dataset immediately, but start a voting-process on whether this is 
to be done or not.

Upon success this method returns the new expiredate that has been set:

   expiredate => INTEGER

=cut

=head2 checkDatasetTemplateCompliance()

Checks the given metadata's compliance with the dataset aggregated template.

Input parameters are:

=over

=item

B<computer> Computer entity ID from the database that identifies where to fetch dataset templates from computer. INTEGER. 
Required. When the aggregated template is figured out, it first takes the aggregated dataset template from the computer and 
merges it with aggregated template valid on the group that is the parent of the dataset.

=cut

=item

B<id> Dataset entity ID from the database of the dataset that is the basis for the compliance check. INTEGER. Optional. This 
must be specified if the dataset that is the basis for the compliance check already exists. If it doesn't exist, this value 
can be left undefined and instead specify the "parent" parameter (see below).

=cut

=item

B<metadata> This is the metadata to check the compliance of. HASH. Required. This is a set of key->value pairs.

=cut

=item

B<parent> Group entity ID from the database that is to be the parent of a not yet existing dataset. INTEGER. Optional. If 
the parameter "id" is not specified it is required to fill in the "parent", so that this method can check compliance for a 
set of metadata against at dataset created under a certain group entity.

=cut

=back

Returns the following structure:

   compliance => INTEGER  # Overall compliance. 0 for non-compliant, 1 for compliant.
   noncompliance => ARRAY # contains the names (STRING) of the metadata key(s) (or template key(s)) that are non-compliant. The ARRAY will be empty if metadata is compliant.
   metadata => (
                 KEYa => (
                           comment => STRING # textual explanation of what value(s) are required on this key.
                           compliance => INTEGER # 0 = non-compliant, 1 = compliant. Refer to this specific key.
                           default => STRING or ARRAY # default value(s) if none is specified. Comes from template.
                           flags => ARRAY # textual flags that are set, if any.
                           min => INTEGER # minimum number of values into this key. 0 = no minimum, N > 0 = minimum number needed
                           max => INTEGER # maximum number of values allowed in this key. 0 = no maximum, N > 0 = maximum allowed
                           reason => STRING # textual explanation why a key is not in compliance (if it is non-compliant).
                           regex => STRING # regex that are used to check the value specified to this key.
                           value => STRING or ARRAY # value from metadata into method or from template                                                     
                         )
                 .
                 .
                 KEYn => ( ... )
               )

For more information about the return structure (especially the metadata sub-structure), look at the setTemplate-method of 
the REST-server.

=cut

=head2 closeDataset()

Closes a dataset.

Input parameters are:

=over

=item

B<id> Dataset entity ID from the database that identifies the dataset that one wishes to close. INTEGER. Required.

=cut

=back

This method requires that the user has the DATASET_CLOSE permission on the dataset in question.

=cut

=head2 createDataset()

Creates a new dataset.

Input parameters are:

=over

=item

B<computer> Computer entity ID from the database that is used to create dataset. It is used to note which computer the 
dataset came from, but also to collect any inherited template settings on that computer for datasets. This aggregated 
template is then combined with the template aggregated from the group that the dataset is created on. INTEGER. Required.

=cut

=item

B<delete> Specifies if the data of the dataset is to be deleted from the computer that it was fetched from after being 
transferred. INTEGER. 0 = no, 1 = yes. Optional. It is only used by automated datasets.

=cut

=item

B<metadata> Metadata entries for the creation of the dataset. HASH. Optional. The metadata specified key->value pairs for 
values that are required by the template.

=cut

=item

B<parent> Group entity ID from the database that the dataset is to be created on. INTEGER. Required.

=cut

=item

B<path> Relative path to where to fetch dataset data from? STRING. Optional. It is only required when creating automated 
datasets in order to tell AURORA which sub-folder one wants to archive from the computer.

=cut

=item

B<type> Specifies the dataset type to create. STRING. Optional. Defaults to AUTOMATED. Valid values are only "AUTOMATED" or "MANUAL".

=cut

=back

The method requires that the user has the DATASET_CREATE permission on the parent group in question. Furthermore, if the 
dataset is a automated dataset, the user also needs the COMPUTER_READ permission on the computer in question.

Upon success returns the id of the newly created dataset in the id-field:

   id => INTEGER

=cut

=head2 createDatasetToken()

Create a dataset token.

Input parameters

=over

=item

B<id> Dataset ID from database of the dataset to create a token for. INTEGER. Required unless token is given.

=cut

=item

B<token> Existing dataset token to extract dataset id from. Overrides id. Required unless id is given.

=cut

=item

B<expire> The expire time in unixtime. Negative numbers are relative (-3600 is one hour from now). Setting expire to the past results in error.

=back

Required permission:

=over

=item

DATASET_CREATE on an open (rw) dataset

=cut

=item

DATASET_READ on a closed (ro) dataset.

=back

Returns the following structure upon success:

   token => STRING

=cut

=head2 deleteDatasetMetadata()

Delete metadata from a dataset.

Input parameters:

=over

=item

B<id> Dataset entity ID from the database of the dataset to delete metadata on. INTEGER. Required.

=cut

=item

B<metadata> The metadata to remove from the dataset specified. HASH. Optional. If not specified will delete all non-system 
metadata (starting with ".").

=cut

=back

The dataset cannot have been removed, because then it is not allowed to delete metadata.

The method requires that the user has the DATASET_CHANGE permission on the specified dataset.

It is only permitted with the open namespace keys in the metadata (starting with "."). Other keys are removed from the 
input.

=cut

=head2 enumDatasetPermTypes()

Enumerates the dataset permission types.

No input is accepted.

Returns the dataset permission types in the following structure:

   types => [ PERMa, PERMb .. PERMn ]

The PERMa and so on are the textual name of the permission type. The types are returned as an ARRAY of STRING.

=cut

=head2 extendDatasetToken()

Adjust expire time for a dataset token. An expired or removed token will be reinstated.

Input parameters

=over

=item

B<token> Existing dataset token to extend.

=cut

=item

B<expire> The new expire time in unixtime. Negative numbers are relative (-3600 is one hour from now). Setting expire to the past results in error. The new expire time may be before exsisting time to shorten the lifetime.

=back

Required permission:

=over

=item

DATASET_CREATE on an open (rw) dataset

=cut

=item

DATASET_READ on a closed (ro) dataset.

=back

Returns the following structure upon success:

   token => STRING

=cut

=head2 getDatasetAggregatedPerm()

Gets the inherited or aggretaed permission on a given dataset.

Input parameters are:

=over

=item

B<id> Dataset entity ID from the database of the dataset to get inherited permission on. INTEGER. Required.

=cut

=item

B<user> User entity ID from the database of the user that the permission is valid for. INTEGER. Optional. Will default to 
authenticated user on the REST-server if no user id has been specified.

=cut

=back

The result upon success is returned in the following structure:

  perm => [ PERMa, PERMb .. PERMb ]

PERMa and so on is the textual name of the permission type. The perm-key is a ARRAY of STRING. The perm-key can be an empty 
array if user has no permissions on the given dataset.

=cut

=head2 getDatasetExpirePolicy()

Gets the open- and close expire policies in effect for a given dataset.

Accepted input parameters are:

=over

=item

B<id> Dataset ID of dataset to get expire policy of. INTEGER. Required.

=cut

=back

This method returns both the open- and close expire policies in effect for a 
given dataset.

Upon success the method returns the following structure:

  expirepolicy => (
                    open => (
                              lifespan => INTEGER
                              extendmax => INTEGER
                              extendlimit => INTEGER
                            )
                    close => (
                               lifespan => INTEGER
                               extendmax => INTEGER
                               extendlimit => INTEGER
                             )
                  )

=cut

=head2 getDatasetLog()

Gets the log for the dataset.

Input parameters

=over

=item

B<id> Dataset entity ID of the dataset to get the log of. INTEGER. Required.

=cut

=item

B<loglevel> Start loglevel to get log entries from. STRING. Optional. This parameter specified which loglevel is the lowest 
that one wants to get. The method will return everything from that level and up in the response. If loglevel is not specified 
it defaults to "DEBUG". The method will then return all log messages from loglevel DEBUG and up.

=cut

=back

Upon success the following structure is returned:

  loglevel => STRING # the loglevel start point for the entries returned
  log => (
           1 => (
                  loglevel => STRING  # the loglevel of this, specific log-entry
                  message  => STRING  # the textual string of the log entry itself
                  time     => STRING  # unix datetime in hi-res of the log entry (eg. 12345678.1234). String of float.
                  idx      => INTEGER # the auto-increment value of this log entry in the database
                  tag      => STRING  # the textual tag string for the entry. Defaults to "NONE".
                )
           .
           .
           N => ( ... )
         )

The returned log entries are returned with the key as an INTEGER giving the correct timed order of the entries. The key 
is just a running number from 1 to N (depending on size of log).

The method requires that the user has the DATASET_LOG_READ permission on the given dataset.

=cut

=head2 getDatasetMetadata()

Gets the metadata of a dataset.

Input parameters are:

=over

=item

B<id> Dataset entity ID from the database to get the metadata of. INTEGER. Required.

=cut

=back

The returned information upon success is the following structure:

  metadata => (
                KEYa => STRING
                KEYb => STRING
                .
                .
                KEYc => STRING
              )

KEY in this case is the textual name of the metadata key (STRING). It points to the value of that key, also being a STRING.

The method requires that the user has either the DATASET_READ, DATASET_CHANGE or DATASET_METADATA_READ permissions on the dataset specified.

It only returns metadata in the open namespace (starting with ".").

=cut

=head2 getDatasetPerm()

Gets the permissions on a given dataset entity (not inherited/aggregated).

Input parameters are:

=over

=item

B<id> Dataset entity ID from the database that one wishes to get the permissons on. INTEGER. Required.

=cut

=item

B<user> User entity ID from the database which one wishes to get the permissions of. INTEGER. Optional. If no user entity id 
has been specified it will default to the authenticated user on the REST-server.

=cut

=back

The result upon success is returned in the following structure:

  perm => (
            grant => [ PERMa, PERMb .. PERMn ]
            deny => [ PERMa, PERMb .. PERMn ]
          )

PERMa and so on are the textual permission that the given user has on the specified dataset. Permissions on a dataset itself 
are divided into "grant" and "deny" permissions. Deny is applied before grant.

=cut

=head2 getDatasetPerms()

Gets all the permission(s) on a given dataset entity, both inherited and what has been set and the effective perm for each 
user who has any permission(s).

Input parameter is:

=over

=item

B<id> Dataset entity ID from the database that one wishes to get the permissions on. INTEGER. Required.

=cut

=back

Upon success the resulting structure returned is:

  perms => (
             USERa => (
                        inherit => [ PERMa, PERMb .. PERMn ] # permissions inherited down on the dataset from above
                        deny => [ PERMa, PERMb .. PERMn ] # permissions denied on the given dataset itself.
                        grant => [ PERMa, PERMb .. PERMn ] # permissions granted on the given dataset itself. 
                        perm => [ PERMa, PERMb .. PERMn ] # effective permissions on the given dataset (result of the above)
                      )
             .
             .
             USERn => ( .. )
           )

USERa and so on are the USER entity ID from the database who have permission(s) on the given dataset. An entry for a user 
only exists if that user has any permission(s) on the dataset. The sub-key "inherit" is the inherited permissions from above 
in the entity tree. The "deny" permission(s) are the denied permission(s) set on the dataset itself. The "grant" permission(s) are 
the granted permission(s) set on the dataset itself. Deny is applied before grant. The sub-key "perm" is the effective or 
resultant permission(s) after the others have been applied on the given dataset.

The permissions that users has through groups on a given dataset are not expanded. This means that the group will be listed 
as having permissions on the dataset and in order to find out if the user has any rights, one has to check the membership of 
the group in question (if the user is listed there).

Permission information is open and requires no permission to be able to read. PERMa and so on are the textual permission 
type that are set on one of the four categories (inherit, deny, grant and/or perm). These four categories are ARRAYS of 
STRING. Some of the ARRAYS can be empty, although not all of them (then there would be no entry in the return perms for 
that user).

The perms-structure can be empty if no user has any permission(s) on the dataset.

=cut

=head2 getDatasets()

Search for and return datasets that match search criteria. 

Input parameters are:

=over

=item

B<count> Number of matches to return. INTEGER. Optional. If not specified it will default to 2^64-1. 
It is not possible to ask for more than the default number of matches at a time (see offset parameter).

=cut

=item

B<metadata> The SQLStruct of search criteria. ARRAY. Optional. If not specified will return all 
datasets that user has the necessary permission(s) on. See the main REST-server introduction for 
information on the SQLStruct structure and use.

=cut

=item

B<offset> The start offset in the search matches found. INTEGER. Optional. Must be a positive 
integer >= 1. If none is specified it defaults to 1. This parameter together with the "count" 
parameter defines the returned search match window. It utilizes the functions of the SQL database 
to limit the search matches returned thus optimizing speed.

=cut

=item

B<sort> Sorts the matches in either ascending or descending order. STRING. Optional. If none is 
given it will default to ascending. This parameter must either be "ASC" or "DESC".

=cut

=item

B<sortby> Sets the metadata key to sort the matches by. STRING. Optional. If none is given it 
will default to "system.dataset.time.created" (dataset creation time). As the default key 
indicates this parameter accepts to be set to a system metadata key (even though it might not
be returned in the match).

=cut

=item

B<sorttype> Sets the way the result is to be sorted. INTEGER. Optional. Must be a value from 0 to 2. 
If none is given the default is 0 (case-insensitive alphanumerical sort). The valid values means the 
following: 0 = case-insensitive alphanumerical sort, 1 = numerical sort, 2 = case-sensitive alphanumerical 
sort.

=cut

=back

This method will only return datasets that the user has the necessary permission(s) on. In order 
for a dataset to be returned in the match (besides matching the given search criteria) the user 
must have one or more of the following permissions: DATASET_DELETE, DATASET_CHANGE, DATASET_MOVE, 
DATASET_PUBLISH, DATASET_RERUN, DATASET_PERM_SET, DATASET_READ, DATASET_LOG_READ or DATASET_LIST. 
Please see separate documentation for an explanation of the meaning of the various permissions.

Upon success the method will return the following HASH structure:

  returned => INTEGER # number of returned matches (dependant upon count parameter)
  total => INTEGER    # number of matches in total (of the search, irrespective of the count parameter)
  metadata => ()      # HASH structure with the cleaned version of the metadata as used in the search
  datasets => (
                1 => (
                       computerid => INTEGER  # computer entity id which is/was the source of the dataset
                       computername => STRING # textual name of computer which is/was the source of the dataset
                       created => STRING      # timedate in unixtime (UTC) of dataset creation time (hires time with microsecs - 12345678.54321). String of float.
                       creator => STRING      # textual name of the creator from metadata
                       creatorid => INTEGER   # user entity ID from database of creator at creation time (might not be the same as "creator" from metadata.)
                       description => STRING  # Dublin Core description metadata
                       expire => STRING       # timedate in unixtime (UTC) of dataset expiration time (hires time with microseconds - 12345678.54321). String of float.
                       id => INTEGER          # dataset entity ID from database
                       perm => ARRAY          # the permission(s) that the user has on the dataset
                       status => STRING       # current status of dataset (open, closed)
                       removed => STRING      # timedate when dataset was removed, or 0 if not removed yet.
                       type => STRING         # MANUAL or AUTOMATED.
                       parentid => INTEGER    # entity id of dataset parent
                       parentname => STRING   # textual name of dataset parent
                       entitytype => INTEGER  # entity type of dataset (which is dataset)
                     )
                .
                .
                N => ( ... )
              )

Some of the values placed in the datasets sub-hash are system metadata that are deemed 
necessary to be there and accessible/readable.

Lastly, some of the values in the datasets sub-hash are aggregates from other parts of the 
database, such as the perm-value (an aggregate of the users permissions on the dataset in question 
based on the entity tree).

The immediate key in the datasets sub-hash are numbers from 1 to N. These signify the order of 
the returned matches and are always numbered 1 to N, independant upon how the search window 
has been defined (see the offset- and count- parameters).

Please note that the "metadata" sub-hash will always be returned, even upon failure. It shows the 
metadata-structure as it was used after cleaning in the search. It is a good point to check if 
any of the search criteria keys have been removed because they are not allowed to be used in 
the search. This might lead to metadata-structures that are not usable by the REST-server and it 
fails its SQL-search.

=cut

=head2 getDatasetSystemAndMetadata()

Get a dataset's system- (only a subset) and open metadata.

Input parameters are:

=over

=item

B<id> Dataset entity ID from database of the dataset to get metadata of. INTEGER. Required.

=cut

=back

The method will only retrieve a sub-set of the system metadata (see the getDatasetSystemMetadata 
method). All of the open metadata are also returned with the subset of the system metadata.

It is required for the user to have either DATASET_READ, DATASET_CHANGE or DATASET_METADATA_READ permission(s) on the 
dataset in question.

=cut

=head2 getDatasetSystemMetadata()

Get a sub-set of the dataset's system metadata (non-open metadata).

Input parameters are:

=over

=item

B<id> Dataset entity ID from the database of the dataset to get system metadata of. INTEGER. Required.

=cut

=back

The method will only get a sub-set of the system metadata that are considered acceptable to 
deliver. Per today these are: dataset- status, created (datetime of creation), closed (datetime 
when it was closed), expire (datetime of expire time), deleted (if it has been deleted or not), 
type (AUTOMATED or MANUAL) and creator (who created the dataset).

It is required for the user to have either the DATASET_READ, DATASET_CHANGE or DATASET_METADATA_READ permission(s) on the 
dataset in question.

=cut

=head2 getDatasetTemplate()

Get the aggregated dataset template.

Input parameters are:

=over

=item

B<computer> Computer entity ID from database of the computer that the dataset comes from. INTEGER. 
Optional/Required. It is used to fetch any dataset templates that are placed on the computer or its 
ancestors. This parameter is not needed if the "id"-parameter has been defined.

=cut

=item

B<id> Dataset entity ID of the dataset to get aggregated template of. INTEGER. Optional/Required. 
This parameter is not required if one has set the parent parameter. If no parent-parameter is set 
this parameter must be specified.

=cut

=item

B<parent> Group entity ID from the database of the parent group that a non-existing dataset 
is to be placed on. This enables to get the metadata template of a dataset that has not been 
created yet (have a look at the conundrum of the who came first of the hen and the egg).

=cut

=back

Upon success the following structure is returned:

  template = (
               KEYa => (
                         comment => STRING # textual explanation of what value(s) are required on this key.
                         default => STRING or ARRAY # default value(s) if none is specified. Comes from template.
                         flags => ARRAY # textual flags that are set, if any.
                         min => INTEGER # minimum number of values into this key. 0 = no minimum, N > 0 = minimum number needed
                         max => INTEGER # maximum number of values allowed in this key. 0 = no maximum, N > 0 = maximum allowed
                         regex => STRING # regex that are used to check the value specified to this key.
                       )
                 .
                 .
                 KEYn => ( ... )               
             )

For more information about the return structure (especially the metadata sub-structure), look at the setTemplate-method of 
the REST-server.

=cut

=head2 listDatasetFolder()

Lists the files- and folders- in the stored dataset.

Input parameters are:

=over

=item

B<id> Dataset entity ID from database of the dataset to list content of. INTEGER. Required.

=cut

=item

B<md5sum> Set if all encountered files are to be md5-summed or not? INTEGER. Optional. Default is 0/false. 
Valid values are 0 for false and 1 for true.

=cut

=back

This method requires that the user has the DATASET_READ permission on the dataset in question.

Upon success the following structure is returned:

  folder => (
            ITEMNAMEa => (
                           "." => (
                                    name => STRING # name of the item, in this case a folder
                                    type => STRING # either D or F, in this case D for folder.
                                    size => INTEGER # size of item in bytes.
                                    atime => INTEGER # atime of item in unix datetime.
                                    mtime => INTEGER # mtime of item in unix datetime.
                                    md5 => STRING; # md5-sum of file, if enabled.
                                  )
                           ITEMNAMEc => ( ... )
                           ITEMNAMEd => ( ... )
                           .
                           .
                           ITEMNAMEx
                         )
            ITEMNAMEb => (
                           "." => (
                                    name => STRING # name of item, in this case a file
                                    type => STRING # either D or F, in this case F for file.
                                    size => INTEGER # size of item in bytes.
                                    atime => INTEGER # atime of item in unix datetime.
                                    mtime => INTEGER # mtime of item in unix datetime.
                                  )
                         )
            .
            .
            ITEMNAMEn
          )

The "folder" hash structure starts with the items in the top folder of the dataset. These items can 
be either files or folders. The name of this item is put into the sub-hash of the itemname under 
the "."-name. This is done for both files and folders (to maintain the similarity of the structure). 
The reason for folders is obviously because this information cannot be stored directly in the 
sub-hash as it may conflict with item-names in that folder. "." on the other hand signifies the 
folder itself and as such is also used for the file-item entries.

Each item in the returned result has a key called "type" and it is either filled with a "D" for 
folder or a "F" for file.

Error-messages on the md5 attribute will have the form: "N/A: Some Error Message".

=cut

=head2 moveDataset()

Move a dataset to another group entity.

Input parameters are:

=over

=item

B<id> Dataset entity ID from database of the dataset to move. INTEGER. Required.

=cut

=item

B<parent> Group entity ID from database of the group to move the dataset to. INTEGER. Required.

=cut

=back

This method requires that the user has the DATASET_MOVE permission on the dataset being moved and 
the DATASET_CREATE permission on the new parent group.

=cut

=head2 removeDataset()

Attempts to remove a dataset.

This method accepts the following input:

=over

=item

B<id> The Dataset ID from the database to remove. INTEGER. Required.

=cut

=back

This method requires the DATASET_DELETE permission on the dataset in question.

It is not allowed to remove open datasets - they must be closed first. If the dataset is 
closed, calling this method will start a dataset remove notification-process that can 
eventually lead to the removal of the dataset by the Maintenance-service.

=cut

=head2 removeDatasetToken()

Remove a dataset token.

Input parameters

=over

=item

B<token> Existing dataset token to remove.

=back

Required permission:

=over

=item

DATASET_CREATE on an open (rw) dataset

=cut

=item

DATASET_READ on a closed (ro) dataset.

=back

Returns the following structure upon success:

   token => STRING

=cut

=head2 setDatasetMetadata()

Set the metadata of the dataset.

Input parameters are:

=over

=item

B<id> Dataset entity ID from the database of the dataset to set metadata on. INTEGER. Required.

=cut

=item

B<metadata> The metadata hash of the key->values to set on the specified dataset. HASH. Required.

=cut

=item

B<mode> The mode that the metadata is updated with. STRING. Optional. Defaults to "UPDATE". Valid 
values are either "UPDATE" or "REPLACE". This sets if the metadata that is delivered to the method 
is to be appended/updated on the dataset or if it is to replace all non-system metadata (under "."-something).

=cut

=back

The method requires that the user has the DATASET_CHANGE permission on the dataset in question. It 
is also required that the dataset has not been removed prior to trying to set/update any metadata.

=cut

=head2 setDatasetPerm()

Set permissions on a dataset.

Input parameters are:

=over

=item

B<id> Dataset entity ID from the database of the dataset to set permissions on. INTEGER. Required.

=cut

=item

B<user> User entity ID from the database of the user to set permission for. INTEGER. Optional. If 
not specified will default to set permission for the user authenticated on the REST-server.

=cut

=item

B<operation> How to set the permissions on the dataset in question. STRING. Optional. If not 
specified will default to "APPEND". Accepted values are: "APPEND", "REPLACE" or "REMOVE".

=cut

=item

B<grant> The grant permission(s) to set on the group. ARRAY of STRING. Optional.

=cut

=item

B<deny> The deny permission(s) to set on the group. ARRAY of STRING. Optional.

=cut

=back

This method requires the user to have the DATASET_PERM_SET permission.

Upon success will return the following structure:

  perm => (
            grant => ARRAY    # STRINGs of permissions set
            deny => ARRAY     # STRINGs of permissions set
          )

This will be the grant- and deny- permissions that have ended up being set.

=cut
