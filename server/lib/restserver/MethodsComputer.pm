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
# MethodsComputer: Computer-entity methods for the AURORA REST-server
#
package MethodsComputer;
use strict;
use RestTools;
use sectools;
use Store;
use Store::FTP;
use Store::RSyncSSH;
use Store::SCP;
use Store::SFTP;
use Store::SMB;
use MetadataCollection;
use StoreCollection;
use Net::DNS;
use IPC::Open3;
use Symbol 'gensym';

sub registermethods {
   my $srv = shift;
   $srv->addMethod("/createComputer",\&createComputer,"Creates a computer-entity with given name.");
   $srv->addMethod("/deleteComputer",\&deleteComputer,"Delete a computer-entity.");
   $srv->addMethod("/deleteComputerMetadata",\&deleteComputerMetadata,"Delete computer metadata.");
   $srv->addMethod("/enumComputerPermTypes",\&enumComputerPermTypes,"Enumerate all COMPUTER permission types.");
   $srv->addMethod("/enumComputers",\&enumComputers,"Enumerate all computer entities.");
   $srv->addMethod("/getComputerAggregatedPerm",\&getComputerAggregatedPerm,"Get aggregated/inherited perm on computer.");
   $srv->addMethod("/getComputerPerm",\&getComputerPerm,"Get perms on comptuer itself.");
   $srv->addMethod("/getComputerMetadata",\&getComputerMetadata,"Retrieves the computers metadata.");
   $srv->addMethod("/getComputerName",\&getComputerName,"Retrieves the computers display name.");
   $srv->addMethod("/getComputersByPerm",\&getComputersByPerm,"Retrieves the computer entities starting from given entity root matched against a bitmask for the user.");
   $srv->addMethod("/getComputerTunnelProtocols",\&getComputerTunnelProtocols,"Enumerate protocols that tunneling for a specified computer support.");
   $srv->addMethod("/listComputerFolder",\&listComputerFolder,"Retrieves a list of a specified folder from a computer entity.");
   $srv->addMethod("/moveComputer",\&moveComputer,"Move computer to another group.");
   $srv->addMethod("/openComputerTunnel",\&openComputerTunnel,"Open tunnel access to a computer.");
   $srv->addMethod("/setComputerMetadata",\&setComputerMetadata,"Sets/changes a computers metadata.");
   $srv->addMethod("/setComputerName",\&setComputerName,"Sets/changes a computers name.");
}

sub createComputer {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $name=$SysSchema::CLEAN{entityname}->($query->{name});
   my $metadata=$SysSchema::CLEAN{metadata}->($query->{metadata});

   # check that parent is a group
   if ((!$db->existsEntity($parent)) || ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$parent,["COMPUTER_CREATE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the COMPUTER_CREATE permission on the GROUP $parent. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # get name from metadata if it is there, ignoring what is set in name-parameter
   if (exists $metadata->{$SysSchema::MD{name}}) { $name=$SysSchema::CLEAN{entityname}->($metadata->{$SysSchema::MD{name}}); }

   # check name
   if ((!defined $name) || ($name eq "")) {
      # name does not fulfill minimum criteria
      $content->value("errstr","Computer name is missing and does not fulfill minimum requirements. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # add name to metadata (again if already there)
   $metadata->{$SysSchema::MD{name}}=$name;

   # check that name does not exist already
   my %search;
   $search{$SysSchema::MD{name}}=$name;
   my @type=($db->getEntityTypeIdByName("COMPUTER"))[0];
   my $ids=$db->getEntityByMetadataKeyAndType(\%search,undef,undef,$SysSchema::MD{name},undef,undef,\@type);

   if (!defined $ids) {
      # something failed
      $content->value("errstr","Unable to search for potential computers with same name \"$name\": ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # check if we have match that says we have other computer with same name
   if (@{$ids} > 0) {
      # we have computer with same name already - duplicate not allowed of tidyness reasons
      $content->value("errstr","Another computer has the same name as \"$name\" already. Duplicates not allowed. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # we are ready to create computer, start transaction already out here
   my $trans=$db->useDBItransaction();
   my $id=$db->createEntity($type[0],$parent);

   if (defined $id) {
      # computer created - set id in metadata
      $metadata->{$SysSchema::MD{"entity.id"}}=$id;
      my $ctype=($db->getEntityTypeIdByName("COMPUTER"))[0];
      if (!defined $ctype) {
         # something failed
         $content->value("errstr","Unable to get COMPUTER entity type id: ".$db->error());
         $content->value("err",1);
         return 0;
      }
      $metadata->{$SysSchema::MD{"entity.type"}}=$ctype;
      $metadata->{$SysSchema::MD{"entity.parent"}}=$parent;
      $metadata->{$SysSchema::MD{"entity.id"}}=$id;

      # set name (and other properties) by using metadata
      my $res=$db->setEntityMetadata($id,$metadata);

      if ($res) {
         # succeeded in setting name - return the group id and resulting name after cleaning
         $content->value("id",$id);
         $content->value("name",$name);
         $content->value("errstr","");
         $content->value("err",0);
         return 1;
      } else {
         # some error
         $content->value("errstr","Unable to set computer name: ".$db->error());
         $content->value("err",1);
         return 0;
      }
   } else {
      # some error
      $content->value("errstr","Unable to create computer: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub deleteComputer {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="COMPUTER";
   MethodsReuse::deleteEntity($mess,\%opt,$db,$userid);

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

sub deleteComputerMetadata {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $metadata=$SysSchema::CLEAN{metadatalist}->($query->{metadata}); # remove non .-related keys
   # if metadata is empty, ensure we only delete .*, not system metadata which are protected
   if ((!defined $metadata) || (@{$metadata} == 0)) { my @md=(".*"); $metadata=\@md; }

   # check that computer exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("COMPUTER"))[0])) {
      # does not exist 
      $content->value("errstr","Computer $id does not exist or is not a COMPUTER entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["COMPUTER_CHANGE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the COMPUTER_CHANGE permission on the COMPUTER $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # attempt to delete metadata
   if (defined $db->deleteEntityMetadata($id,$metadata)) {
      # success
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr","Unable to delete computer metadata: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub enumComputerPermTypes {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="COMPUTER";
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

sub enumComputers {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="COMPUTER";
   MethodsReuse::enumEntities($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("computers",$mess->value("computers"));
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

sub getComputerAggregatedPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # computer to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="COMPUTER";   
   # attempt to set group perm
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

sub getComputerPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # computer to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="COMPUTER";   
   # attempt to set group perm
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

sub getComputerMetadata {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that entity exists
   if (!$db->existsEntity($id)) {
      # computer does not exist
      $content->value("errstr","Computer $id does not exist. Unable to fulfill request.");
      $content->value("err",1);
      return 0;    
   }

   # check that entity is of right type
   if ($db->getEntityType($id) != ($db->getEntityTypeIdByName("COMPUTER"))[0]) {
      # wrong entity type
      $content->value("errstr","Id $id is not a COMPUTER entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;    
   }

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   # computer metadata is open under the "." namespace, so no perm needed
   MethodsReuse::getEntityMetadataByPerm($mess,\%opt,$db,$userid);

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
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub getComputerName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="COMPUTER";
   MethodsReuse::getEntityName($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("name",$mess->value("name"));
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

sub getComputersByPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{root}=$query->{root};
   $opt{perm}=$query->{perm};
   $opt{permtype}=$query->{permtype};
   $opt{entitytype}=["COMPUTER"];
   MethodsReuse::getEntitiesByPermAndType($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success - get entities
      my @computers=@{$mess->value("entities")};
      # get each computers name
      my %computers;
      my $m=$db->getEntityMetadataList($SysSchema::MD{name},\@computers);
      if (!defined $m) {
         # something failed fetching metadata
         $content->value("errstr","Unable to get metadata for computers: ".$db->error());
         $content->value("err",1);
         return 0;
      }

      # create the return hash explicitly in case some 
      # computer lacks a name
      foreach (@computers) {
         my $computer=$_;
         
         $computers{$computer}=$m->{$computer} || "";
      }

      # set return values
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("computers",\%computers);
      return 1;
   } else {
      # failure
      $content->value("errstr","Unable to fetch computers: ".$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub getComputerTunnelProtocols {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that computer exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("COMPUTER"))[0])) {
      # does not exist 
      $content->value("errstr","Computer $id does not exist or is not a COMPUTER entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # we are ready to get tunneling information - acquire the computers aggregated template
   my @tmplpath=$db->getEntityPath($id);
   if (!defined $tmplpath[0]) {
      # unable to get parent path
      $content->value("errstr","Unable to get path to computer $id: ".$db->error());
      $content->value("err",1);
      return 0;             
   }
   my $tmpl=$db->getEntityTemplate($db->getEntityTypeIdByName("COMPUTER"),@tmplpath);
   if (!defined $tmpl) {
      # unable to get template
      $content->value("errstr","Unable to get computer template: ".$db->error());
      $content->value("err",1);
      return 0;             
   }
   # get acceptable protocol names and their port-number
   my $mc=MetadataCollection->new(base=>$SysSchema::MD{"gk.base"});
   # convert template into a gatekeeper hash
   my $gkhash=$mc->template2Hash($tmpl);

   # get protocols
   my @protocols=keys %{$gkhash->{protocols}};

   # return result, if any
   $content->value("errstr","");
   $content->value("err",0);
   $content->value("protocols",\@protocols);
   return 1;   
}

sub listComputerFolder {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # computer id
   my $path=$query->{path}; # relative path on computer

   # check that entity exists
   if (!$db->existsEntity($id)) {
      # does not exist
      $content->value("errstr","Entity $id does not exist. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check that entity is of type computer
   if ($db->getEntityType($id) != ($db->getEntityTypeIdByName("COMPUTER"))[0]) {
      # wrong entity type
      $content->value("errstr","Id $id is not a COMPUTER entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;    
   }

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["COMPUTER_READ"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the COMPUTER_READ permission on the COMPUTER $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # clean path, squash any ..
   $path=$SysSchema::CLEAN{pathsquash}->($path);
   # remove multiple slashes
   $path=~s/^(.*)\/$/$1/g;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   # computer metadata is open under the "." namespace, so no perm needed
   MethodsReuse::getEntityMetadataByPerm($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success - get metadata
      my $md=$mess->value("metadata");

      # get computer template
      my $templ=$db->getEntityTemplate(($db->getEntityTypeIdByName("COMPUTER"))[0],$db->getEntityPath($id));

      if (!defined $templ) {
         # something failed
         $content->value("errstr","Unable to get COMPUTER $id template: ".$db->error());
         $content->value("err",1);
         return 0;
      }

      # attempt to get task to be used
      my $task=getEntityTask($db,$id);
      if (!$task) {
         # unable to fulfill request without a valid task
         $content->value("errstr","Unable to find a task for COMPUTER $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }

      # task found, get its definition
      my $taskmd=$db->getEntityMetadata($task);
      if (!defined $taskmd) {
         # something failed
         $content->value("errstr","Unable to get TASK $task metadata: ".$db->error());
         $content->value("err",1);
         return 0;
      }
      # create storecollection instance
      my $scoll=StoreCollection->new(base=>$SysSchema::MD{"storecollection.base"});
      # fetch part of task metadata that are related to storecollections to a HASH
      my $tskhash=$scoll->metadata2Hash($taskmd);

      # get metadatacollection data from template and computer
      my $mc=MetadataCollection->new(base=>$SysSchema::MD{"computer.task.base"});
      # make store collection hash from template
      my $thash=$mc->template2Hash($templ);
      # make store collection hash from computer metadata
      my $chash=$mc->metadata2Hash($md);
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

      # get store entity id
      my $storeid=$tskhash->{get}{1}{store} || 0;

      # attempt to get metadata for store
      my $smd=$db->getEntityMetadata($storeid);

      if (!defined $smd) {
         # something failed
         $content->value("errstr","Unable to get Store $storeid metadata: ".$db->error().". Request failed.");
         $content->value("err",1);
         return 0;
      }

      # get store class id
      my $sclass=$smd->{$SysSchema::MD{"store.class"}}; 
      # get store classparams
      my %cparam=%{$tskhash->{get}{1}{classparam}}; 
      # get store params
      my %param=%{$tskhash->{get}{1}{param}};
      # try to instantiate class and use class param
      my $sandbox=$cfg->value("system.sandbox.location") || "/nonexistant";
      my $store=$sclass->new(%cparam,sandbox=>$sandbox) || undef;

      if (!defined $store) {
         # failed to get an instantiated store class
         $content->value("errstr","Unable to instantiate Store-class $sclass: $!. Request failed.");
         $content->value("err",1);
         return 0;
      }

      # relpath
      my $relpath=$path;

      # get root path
      my $rpath=$SysSchema::CLEAN{path}->($md->{$SysSchema::MD{"computer.path"}});
      # remove multiple slashes
      $rpath=~s/^(.*)\/$/$1/g;
      # get useusername setting
      my $uname=$SysSchema::CLEAN{bool}->($md->{$SysSchema::MD{"computer.useusername"}});

      # construct absolute path
      my $apath;
      my $email;
      if ($uname) {
         # get username of authenticated user
         my $umd=$db->getEntityMetadata($userid);
         if (defined $umd) {
            $email=$SysSchema::CLEAN{email}->($umd->{$SysSchema::MD{username}});
            $apath="$rpath/$email/$path";
            $relpath="$email/$path";
         } else {
            # something failed
            $content->value("errstr","Unable to retrieve user $userid\'s metadata: ".$db->error().". Request failed.");
            $content->value("err",1);
            return 0;
         }
      } else {
         # no username in path
         $apath="$rpath/$path";
      }
      # remove multiple slashes
      $apath=~s/^(.*)\/$/$1/g;
      # clean path again
      $apath=$SysSchema::CLEAN{pathsquash}->($apath);

      # add path to param
      $param{remote}=$apath;
      # add dummy local
      $param{local}="/dev/null";
      # attempt to open store with param
      if (!$store->open(%param)) {
         # unable to open store - this failed
         $content->value("errstr","Unable to open Store $sclass: ".$store->error().". Request failed.");
         $content->value("err",1);
         return 0;
      }

      # attempt to get files and folders
      my $res=$store->listRemote($apath);

      # close store to clean up tmp-files etc.
      $store->close();

      # check if we got result ok
      if (defined $res) {
         # it was successful - ensure we have F,D and L present, although empty
         if (keys %{$res->{F}} == 0) { $res->{F}=undef; }
         if (keys %{$res->{D}} == 0) { $res->{D}=undef; }
         if (keys %{$res->{L}} == 0) { $res->{L}=undef; }

         # send response
         $content->value("errstr","");
         $content->value("err",0);
         $content->value("class",$sclass); 
         $content->value("path",$relpath); # only list postfix
         $content->value("folder",$res);
         # return if username has been added to the folder path
         # also return the username being used, if so
         $content->value("useusername",($uname ? 1 : 0));
         if ($uname) { $content->value("username",$email); }
         return 1;
      } else {
         # something failed
         $content->value("errstr","Unable to fetch folder list from computer $id: ".$store->error());
         $content->value("err",1);
         return 0;
      }
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub moveComputer {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{parent}=$query->{parent};
   $opt{type}="COMPUTER";
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

sub openComputerTunnel {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # convert dns/ipv6 to ipv4
   sub addr2ipv4 {
      my $addr=shift;

      my $ipv4;
      if ($addr !~ /^[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3}$/) {
         # this is not a IPv4-address, check if IPv6 or DNS
         my $resolv = Net::DNS::Resolver->new();
         if ($addr =~ /[\:]+/) {
            # IPv6 - get reverse
            my @ptr=rr($addr);
            $addr=$ptr[0]->rdstring();
         }

         # get A-record of DNS
         my $query=$resolv->query($addr,"A");
         if ($query) {
            foreach my $rr (grep { $_->type eq "A" } $query->answer()) {
               # grab first and end loop
               $ipv4 = $rr->address();
               last;
            }
         }
      } else { $ipv4=$addr; }

      # check that we have a valid IPv4-address
      if ($ipv4 !~ /^[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3}$/) {
         # we failed to get a valid IPv4-address, this is fatal
         return 0;
      }

      # success - return ipv4-address
      return $ipv4;
   }

   # we need computer id, port-/protocol-name, source-ip to open for
   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $prot=$SysSchema::CLEAN{"gk.protocol"}->($query->{protocol});
   my $client;
   if (!defined $query->{client}) { $client=$query->{"SYSTEM_REMOTE_ADDR"}; }
   else { $client=$query->{client}; }
   $client=$SysSchema::CLEAN{"host"}->($client);
   my $forceipv4=$SysSchema::CLEAN{"gk.forceipv4"}->($query->{forceipv4});

   # check that computer exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("COMPUTER"))[0])) {
      # does not exist 
      $content->value("errstr","Computer $id does not exist or is not a COMPUTER entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # check that user has necessary permissions
   my $allowed=hasPerm($db,$userid,$id,["COMPUTER_REMOTE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the COMPUTER_REMOTE permission on the COMPUTER $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }
 
   # get ssh location
   my $SSH=$cfg->value($SysSchema::CFG{sshlocation}) || "/usr/bin/ssh";

   # start transaction
   my $tr=$db->useDBItransaction();

   # get computer metadata
   my $cmd=$db->getEntityMetadata($id);
   if (!defined $cmd) {
      # unable to get metadata
      $content->value("errstr","Unable to get computer metadata: ".$db->error());
      $content->value("err",1);
      return 0;             
   }
   # get computer dns/ip from metadata
   my $computer=$cmd->{$SysSchema::MD{"computer.host"}} || "";

   my $nclient=($forceipv4 ? addr2ipv4($client) : $client);

   if (!$nclient) {
      # we failed to get a valid IPv4-address, this is fatal
      $content->value("errstr","Cannot resolve client \"$client\" to its IPv4 A-record. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }
   # update client
   $client=$nclient;

   # get templates in effect
   my $parent=$db->getEntityParent($id);
   if (!defined $parent) {
      # unable to get parent
      $content->value("errstr","Unable to get computer parent: ".$db->error());
      $content->value("err",1);
      return 0;             
   }
   my @tmplpath=$db->getEntityPath($parent);
   if (!defined $tmplpath[0]) {
      # unable to get parent path
      $content->value("errstr","Unable to get path to computer $id parent $parent: ".$db->error());
      $content->value("err",1);
      return 0;             
   }
   my $tmplparent=$db->getEntityTemplate($db->getEntityTypeIdByName("COMPUTER"),@tmplpath);
   if (!defined $tmplparent) {
      # unable to get parent template
      $content->value("errstr","Unable to get computer template: ".$db->error());
      $content->value("err",1);
      return 0;             
   }
   # get acceptable protocol names and their port-number
   my $mc=MetadataCollection->new(base=>$SysSchema::MD{"gk.base"});
   # convert template into a gatekeeper hash
   my $gkhash=$mc->template2Hash($tmplparent);

   # check that specified protocol exists - it is always uppercase after cleaning
   if (!exists $gkhash->{protocols}{$prot}) {
      $content->value("errstr","Specified protocol \"$prot\" is not valid for this computer. Unable to fulfill request.");
      $content->value("err",1);
      return 0;                
   }

   # get script, keyfile, port and gatekeeper host
   my $script=$SysSchema::CLEAN{"gk.script"}->($gkhash->{script}) || "MISSING";
   my $keyfile=$SysSchema::CLEAN{"gk.keyfile"}->($gkhash->{keyfile}) || "MISSING";
   my $port=$SysSchema::CLEAN{"port"}->($gkhash->{protocols}{$prot}) || 0;
   my $gkhost=$SysSchema::CLEAN{"host"}->($gkhash->{host}) || "0.0.0.0";
   my $user=$SysSchema::CLEAN{"username"}->($gkhash->{username}) || "dummy";
   my $knownhosts=$gkhash->{knownhosts} || "dummy";
   # remove backslashes
   $knownhosts=~s/\\//g;

   my $gkhoststr=($forceipv4 ? addr2ipv4($gkhost) : $gkhost);

   if (!$gkhoststr) {
      # we failed to get a valid IPv4-address, this is fatal
      $content->value("errstr","Cannot resolve gatekeeper-server \"$gkhost\" to its IPv4 A-record. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # save knownhosts-data to a temporary file
   my $randstr=sectools::randstr(32);
   # save name of file for later use and removal
   my $khfile="/tmp/$randstr";
   # create file with key
   if (open (FH,">","$khfile")) {
      print FH "$knownhosts\n";
      close (FH);
   } else {
      # unable to write temporary knownhosts-file - abort
      $content->value("errstr","Cannot open temporary knownhosts file for writing: $!. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # we are ready to call script
   my $sandbox=$cfg->value("system.sandbox.location") || "/nonexistant";
   my @SSH = ( '/usr/bin/ssh',$gkhost,
               '-l',$user,
               '-i',$sandbox."/$keyfile",
               '-o','PasswordAuthentication=no',
               '-o','StrictHostKeyChecking=yes',
               '-o','UserKnownHostsFile='.$khfile,
               $script,
   );
   my $R=gensym;
   my $pid=open3(undef,$R,$R,@SSH,$client,$computer,$port);
   my $rin='';
   vec($rin,fileno($R),1) = 1;
   my $rbuf="";
   my $alive=time();
   my @lines;
   my $err=0;
   while (1) {
      my $nfound=select (my $rout=$rin,undef,my $rfail=$rin,0.25);
      if ($nfound) {
         # check if there was anything on STDOUT/STDERR
         if (vec($rout, fileno($R), 1)) {
            # more data, update alive-time
            $alive=time();
            # read 
            my $data;
            my $no=sysread ($R,$data,2048);
            if (!defined $no) {
               # error sysread
               push @lines,"Unable to read STDOUT/STDERR while reading data from the gatekeeper: $!";
               $err=1;
               last;
            } elsif ($no > 0) {
               # we have some data, update read-buffer
               $rbuf.=$data;
            } else {
               # EOF - finished with all reading
               last;
            }
         }

         # check for new lines from STDOUT/STDERR
         while ($rbuf =~ /^([^\n]*\n)(.*)$/s) {
            # we have a new line
            $alive=time();
            my $line=$1;
            $rbuf=$2;
            $line=~s/[\n]//g;
            if (!defined $rbuf) { $rbuf=""; }
            # print to the parent process, including time stamp
            push @lines,$line;
         }
      }
      if (($alive+30) < time()) { # 30 sec timeout
         push @lines,"Timeout reading STDOUT/STDERR from gatekeeper-script.";
         $err=1;
         last;
      }
   }
   # get no of lines
   my $size=@lines;
   my $lline="UNKNOWN REASON";
   if ($size > 0) { $lline=$lines[$size-1]; }

   eval { close($R); };
   eval { unlink ($khfile); };
      
   # reap child
   waitpid($pid,0);
 
   if (($err) || ($lline !~ /^\d+/)) {
      # some failure
      $content->value("errstr","Gatekeeper-script failed: $lline. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # we are successful - log tunnel
   my $msg="User $userid successfully opened a tunnel to computer $id (".$cmd->{$SysSchema::MD{name}}.") on port $port ($prot) from $client going through $gkhoststr:$lline.";
   $log->send(entity=>$id,logmess=>$msg,loglevel=>$Content::Log::LEVEL_DEBUG,logtag=>$main::SHORTNAME." TUNNEL");

   # return result from gatekeeper-script
   $content->value("errstr","");
   $content->value("err",0);
   $content->value("tunnel","$gkhoststr:$lline");
   $content->value("protocol",$prot);
   return 1;    
}

sub setComputerMetadata {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $metadata=$SysSchema::CLEAN{metadata}->($query->{metadata}); # remove non .-related keys
   my $mode=$query->{mode};

   # check that computer exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("COMPUTER"))[0])) {
      # does not exist 
      $content->value("errstr","Computer $id does not exist or is not a COMPUTER entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   if (defined $mode) {
      $mode=$SysSchema::CLEAN{"metadatamode"}->($mode);
   } else {
      $mode="UPDATE";
   }

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["COMPUTER_CHANGE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the COMPUTER_CHANGE permission on the COMPUTER $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # start transaction
   my $tr=$db->useDBItransaction();

   # check mode, remove current metadata if mode is replace
   if ($mode eq "REPLACE") {
      # attempt to remove all .-related metadata
      if (!$db->deleteEntityMetadata($id,[".*"])) { # remove all .-something data (no not touch system-metadata)
         $content->value("errstr","Could not remove old COMPUTER metadata when dataset in mode $mode: ".$db->error().". Unable to fulfill the request.");
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
      $content->value("errstr","Unable to set computer metadata: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub setComputerName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{duplicates}=0;
   $opt{type}="COMPUTER";
   $opt{name}=$query->{name};
   # attempt to set name
   MethodsReuse::setEntityName($mess,\%opt,$db,$userid,$cfg,$log);

   # check result
   if ($mess->value("err") == 0) {
      # success
      $content->value("name",$mess->value("name"));
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

=head1 COMPUTER METHODS

=head2 createComputer()

Creates a computer entity.

Input parameters are the following:

=over

=item

B<metadata> Metadata to set on computer entity upon creation. This is decided by any templates that are in effect (please see 
the MethodsTemplate.pm or AuroraDB.pm for more information on templating). One can also set metadata that are not required by 
any templates if so wished. The textual name of the computer can also be set in this metadata and it will take precedence over 
the name-parameter. Optional (although dependant upon templates). The structure of the metadata parameter is as follows:

  metadata => (
                ".system.entity.name" => STRING,
                ".whatever.one.wants" => STRING,
                .
                .
                ".whatever.one.can"   => STRING,
              )

It basically consists of a number of key->value pairs.

=cut

=item

B<name> Display name of the new computer entity. Can also be set in the metadata instead. Metadata takes precedence. STRING. 
Required.

=cut

=item

B<parent> Parent where the computer entity is to be created. This value is an INTEGER with the database entity ID of the GROUP 
that is to be the parent. Only GROUP entities are valid in this parameter. Required.

=cut

=back

The display name entered either as parameter "name" or as metadata (".system.entity.name") must be unique for a computer in the 
entire entity tree. If any other computer entity has the same display name, the method will fail in its attempt to create 
the entity.

The user calling this method must also have the COMPUTER_CREATE permission on the parent group in question.

The method only accepts non-system namespaced metadata (starting with ".").

=cut

=head2 deleteComputer()

Deletes a computer entity.

Input parameter is:

=over

=item

B<id> Entity id from database of the computer entity to delete. INTEGER. Required.

=cut

=back

Methods requires the user to have the COMPUTER_DELETE permission on the given computer.

=cut

=head2 deleteComputerMetadata()

Deletes computer metadata.

Accepts the following parameters:

=over

=item

B<id> Entity ID of the computer entity to delete metadata from. INTEGER. Required.

=cut

=item

B<metadata> Array of metadata values to remove. ARRAY. Optional. If the array is empty or not specified all metadata values of the 
given computer entity will be removed (in the non-system namespace).

=cut

=back

This method requires that the user has the COMPUTER_CHANGE permission on the computer entity in question.

The method only accepts non-system namespaced metadata key-values.

=cut

=head2 enumComputerPermTypes()

Enumerates the computer permission types that exists.

No input is accepted.

It returns a structure with all the valid permissions for a computer entity in the following structure:

  types => (
             STRING,             
             STRING,
             STRING,
           (

which is an array containing all the computer entity permission types in a textual fashion.

=cut

=head2 enumComputers()

Enumerates all computer entities in the database.

No input is accepted.

The return structure is as follows:

  computers => (
                 INT => STRING,
                 INT => STRING,
                 .
                 .
                 INT => STRING
               (

where INT is the entity id from the database and STRING is the textual display name of the entity.

=cut

=head2 getComputerAggregatedPerm()

Gets the aggregated/inherited permissions of a user on a computer entity.

Input parameters are as follows:

=over

=item

B<id> Entity ID of computer object to get permissions on. INTEGER. Required.

=cut

=item

B<user> Entity ID of user subject from the database for which we are getting the permissions for (who they are valid for).
INTEGER. Optional. Will default to authenticated user if none is specified.

=cut

=back

Returns a structure of aggregated perms upon success:

  perm => (
            PERMISSION_NAME,
            PERMISSION_NAME,
            .
            .
            PERMISSION_NAME
          )

where PERMISSION_NAME is the STRING representation of the permission type that the specified user has on the given entity 
object.

=cut

=head2 getComputerPerm()

Get the permissions on the computer object in question.

Input is the following:

=over

=item

B<id> Computer entity id (from the database) to get the permissions on. INTEGER. Required.

=cut

=item

B<user> User entity id (from the database) that the permissions are valid for. INTEGER. Optional. Will default to logged on 
user if not specified.

=cut

=back

Returns the following structure upon success:

  perm => ( 
            grant => [ PERMISSIONa, PERMISSIONb .. PERMISSIONn ],
            deny =>  [ PERMISSIONd, PERMISSIONe .. PERMISSIONo ],
          )

The PERMISSION-values in the grant- or deny- arrays are STRING names of the permissions that have been set in either grant- or 
deny.

=cut

=head2 getComputerMetadata()

Fetches the open metadata of a computer entity (everything that starts with a dot ".").

Input parameters are as follows:

=over

=item

B<id> Computer ID from the database of object to get the metadata of. INTEGER. Required.

=cut

=back

Upon success returns the following structure:

  metadata => (
                KEYa  => VALUE,
                KEYb  => VALUE,
                .
                .
                KEYn  => VALUE,
              )

KEY is the name of the metadata key (STRING) and VALUE  is the value (STRING) for that metadata key.

This method only returns metadata in the open non-system namespace (starting with a dot ".").

=cut

=head2 getComputerName()

Gets the display name of the computer.

Input parameters are:

=over

=item

B<id> Computer entity ID from the database of the computer to get the name of. INTEGER. Required.

=cut

=back

Upon success returns the name:

  name => STRING

where STRING is the textual name of the computer.

=cut

=head2 getComputersByPerm()

Get list of computers based upon a set of permissions.

Input parameters are:

=over

=item

B<perm> A set of permissions that has to exist on the computer entities returned. ARRAY. Optional. If no values are specified 
all computers entitites are returned.

=cut

=item

B<permtype> The matching criteria to use with the permissions specified in the "perm"-parameter. Valid values are: ALL (logical 
and) or ANY (logical or). STRING. Optional. If not specified will default to logical operator "ALL".

=cut

=item

B<root> Entity ID of where to start in the entity tree (matching everything from there and below). INTEGER. Optional. If not 
specified will default to 1 (ROOT).

=cut

=back

The return structure upon success is:

  computers => (
                 INTEGERa => STRING,
                 INTEGERb => STRING,
                 .
                 .
                 INTEGERn => STRING,
               )

where INTEGER is the computer id from the database and STRING is the display name of the computer.

=cut

=head2 getComputerTunnelProtocols()

Gets the supported protocols for remote control on the computer specified.

Accepts only one input parameter: id. INTEGER. Required. It defines the entity ID from the AURORA 
database of the computer that one wishes to get the supported protocols of.

Upon success returns an ARRAY:

  protocols = ["PROT1" .. "PROTn"]

where PROT1 and so on is the textual name of the protocol(s) supported.

=cut

=head2 listComputerFolder()

List the folder contents of a computer.

Input parameters are:

=over

=item

B<id> The computer entity ID from the database of the computer to list folder contents of. INTEGER. Required.

=cut

=item

B<path> The relative path (to the storage area defined for the computer) to list. STRING. Optional. Will default to top of 
the storage area defined for computer.

=cut

=back

The method will use the Store-method defined in the computers StoreCollection metadata in the first get-store defined. It 
will attempt to utilize that Store-instance to list the contents of the computer folder.

Any double dots ("..") will be squashed.

Upon success the method returns the following structure:

  class       => STRING
  path        => STRING
  useusername => [0||1] # says if username has been appended to datapath
  username    => STRING # only present if useusername = 1.
  folder => (
              F => (
                     FILENAMEa => (
                                    type => STRING # F (file)
                                    name => STRING # file name
                                    size => INTEGER # size of file in bytes
                                    datetime => INTEGER # datetime in UTC of file
                                  )
                     .
                     .
                     FILENAMEn => (
                                    ....
                                  )
                   )
              D =>
                   (
                     FOLDERNAMEa => (
                                      type => STRING # D (folder) 
                                      name => STRING # name of folder object 
                                      size => INTEGER # size of folder entry (not its contents)
                                      datetime => INTEGER # datetime in UTC of folder object.
                                   )
                     .
                     .
                     FOLDERNAMEn => ( ... )
                   )
              L => (
                     LINKNAMEa => (
                                    type => STRING # L (symlink)
                                    name => STRING # name of link object
                                    size => INTEGER # size of link entry (not its contents)
                                    datetime => INTEGER # datetime in UTC of link object
                                    target => STRING # name of target or source that symlink points to
                                  )
                     .
                     .
                     LINKNAMEn => ( ... )
                   )
            )

Class is the Store-class used to get the folder-listing in textual format (eg. "Store::RSyncSSH"). Path is the complete path 
used on the local computer to access the folder being listed. 

The folder return value contains a sub-structure that first defines the objects in that folder sorted in its 
type (either F for File, D for Folder or L for symlink). Under that we have FILENAMEx, FOLDERNAMEx and LINKNAMEx, which are 
the names of the objects of that given type (either File, Folder or Symlink). Under each named entry the data for each item 
is listed: type, size, name and datetime. The folder sub-structure can be read more about in the documentation of the 
Store-classes.

The "userusername" return value says if the computer has a policy that states if the username is to be added to the 
datapath defined for the computer entity. It is either 1 (true) or 0 (false) if this is enforced by policy. 
If the useusername value is 1, another value "username" is present that gives the username being added.

=cut

=head2 moveComputer()

Moves a computer entity to another part of the entity tree.

Input is:

=over

=item

B<id> Computer entity ID from the database of the computer to move. INTEGER. Required.

=cut

=item

B<parent> Parent group entity ID from the database of the group which will be the new parent of the computer. INTEGER. 
Required.

=cut

=back

The method requires the user to have COMPUTER_MOVE permission on the computer being moved and COMPUTER_CREATE on the parent 
group it is being moved to.

=cut

=head2 openComputerTunnel()

This method attempts to open a tunnel on a gatekeeper-server for a client to a computer in AURORA for remote 
access and control.

Accepts the following input parameteres:

=over

=item

B<id> Entity ID from the AURORA database of the computer that you want to open a tunnel to. INTEGER. Required.

=cut

=item

B<client> DNS or IP of client computer that is to be allowed to tunnel to the computer specified in the id-parameter. STRING. 
Optional. If not specified will default to IP-address of the caller of the method.

=cut

=item

B<protocol> Protocol to use when opening the tunnel. STRING. Required. This is the textual name of the protocol to use 
when connecting to the computer in the AURORA-system. It decides which port to open and the textual name has to match 
one of the names in the template definition on the computer in question. The textual name is always in uppercase, but 
if specified in lower case, it will be converted.

=cut

=item

B<forceipv4> Decides if the method is to force IPv4 conversion (A-record) of the DNS- or IP address of the client-address and 
the gatekeeper-address specified in the computer-template. BOOLEAN. Optional. If not specified it will default to 1 or true. 
Acceptable values are 0 for false, 1 for true. The gatekeeper address is only converted for use in the returned 
data of the tunnel-data. If some of these addresses are already IPv4 A-records, they are kept as-is.

=cut

=back

This method required that the user calling the method has the COMPUTER_REMOTE-permission on the computer entity in 
question (as identified by the id-parameter).

The method also uses template-information for the computer entity that one tries to open a tunnel to.

The template is to have the following structure in AURORA:

   .system.gatekeeper.script = "/whatever/path/to/gatekeeper-script"
   .system.gatekeeper.host = "mygatekeeper.server.domain"
   .system.gatekeeper.username = "username"
   .system.gatekeeper.keyfile = "mykeyfile.gk_keyfile"
   .system.gatekeeper.knownhosts = "KNOWNHOSTS_DATA"
   .system.gatekeeper.protocols.RDP = 3389
   .system.gatekeeper.protocols.VNC = 5900

Important to note here is that the keyfile that is used to connect to the gatekeeper-server needs to have an ending called 
".gk_keyfile". The keyfile for the gatekeeper needs to reside in the sandbox-location of the AURORA-server (please see the 
sandbox-location in the settings-file). The protocols part of the structure can consist of as many protocols as one has 
available for the computers at the location in the AURORA entity tree that the template takes effect. Please note also 
that the protocols needs to have uppercase names. When calling the method, the uppercase protocol names specified here are the 
ones that will be valid for a computer in question.

Returns the following answer upon success:

   tunnel => "GATEKEEPER-SERVER:PORT"

where PORT is the new port that is available for the client in question to use in order to reach the remote admin 
features of the computer in question. The GATEKEPPER-SERVER is the IPv4-converted A-record of the gatekeeper-server if 
forceipv4 is enabled.

=cut

=head2 setComputerMetadata()

Sets metadata on the computer entity.

Input parameters are:

=over

=item

B<id> The computer entity ID from the database to set metadata on. INTEGER. Required.

=cut

=item

B<metadata> The metadata key->values to set on the computer. HASH. Required. If none is specified, it will basically set 
the existing values for the computer metadata again.

=cut

=item

B<mode> The mode that the metadata is updated with. STRING. Optional. Defaults to "UPDATE". Valid
values are either "UPDATE" or "REPLACE". This sets if the metadata that is delivered to the method
is to be appended/updated on the computer or if it is to replace all non-system metadata (under "."-something).

=cut

=back

The metadata input will only accept metadata in the non-system namespace (starting with ".").

The method requires the user to have the COMPUTER_CHANGE permission on the computer specified in order to succeed.

=cut

=head2 setComputerName()

Set the display name of the computer.

Input parameters:

=over

=item

B<id> Computer entity ID from the database of the computer to change name. INTEGER. Required.

=cut

=item

B<name> The new computer name to set. STRING. Required. Does not accept blank string and the new name must not 
conflict with any existing computer name on the same GROUP-level in the tree (including itself).

=cut

=back

Method requires the user to have the COMPUTER_CHANGE permission on the computer changing its name.

=cut
