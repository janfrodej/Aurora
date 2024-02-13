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
# MethodsGeneral: General, non-entity specific methods for the AURORA REST-server
#
package MethodsGeneral;
use strict;
use RestTools;
use AckHandler;
use NotificationHandler;
use NotificationParser;

my $SSH_KEYSCAN = "/usr/bin/ssh-keyscan";

sub registermethods {
   my $srv = shift;
   
   $srv->addMethod("/ackNotification",\&ackNotification,"Acknowledge a notification.");
   $srv->addMethod("/enumEntityTypes",\&enumEntityTypes,"Enumerate all entity type names.");
   $srv->addMethod("/enumPermTypes",\&enumPermTypes,"Enumerate all perm type names.");
   $srv->addMethod("/getEntities",\&getEntities,"Search for entities.");
   $srv->addMethod("/getHostSSHKeys",\&getHostSSHKeys,"Retrieve a given hosts public SSH keys.");
   $srv->addMethod("/getMetadata",\&getMetadata,"Get general metadata of an entity.");
   $srv->addMethod("/getName",\&getName,"Get name of an entity.");
   $srv->addMethod("/getPath",\&getPath,"Get path down to an entity in the tree including the entity itself.");
   $srv->addMethod("/getType",\&getType,"Get type of an entity.");
   $srv->addMethod("/ping",\&ping,"Pings AURORA REST-server to see if it is still running");
   $srv->addMethod("/getTree",\&getTree,"Get the AURORA entity-tree from a given entity.");
}

sub ackNotification {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$SysSchema::CLEAN{notificationid}->($query->{id});         
   my $rid=$SysSchema::CLEAN{rid}->($query->{rid});

   # check that we have a valid notification id
   if ($id eq "") {
      # invalid notification id
      $content->value("errstr","Invalid or missing notification id. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }
   if ($rid eq "") {
      # invalid rid
      $content->value("errstr","Invalid or missing rid specified. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # instantiate ack-handler
   my $ack=AckHandler->new(folder=>$cfg->value("system.notification.location")."/Ack");

   if ($ack->exists($id,$rid)) {
      # this is a valid id and rid - touch the file
      if ($ack->touch($id,$rid)) {
         # ack-file touched successfully - retrieve entity/dataset this relates to
         
         # get notification folder path, start with defaults and env
         my $folder=($ENV{"AURORA_PATH"} ? $ENV{"AURORA_PATH"}."/notification" : "/local/app/aurora/notification");
         # if we have a setting for location in config-files, use that instead.
         $folder=($cfg->value("system.notification.location") ? $cfg->value("system.notification.location") : $folder);

         # get notification types
         my %nottypes=%{$cfg->value("system.notification.types")};

         # create notifications handler
         my $nots=NotificationHandler->new(folder=>$folder);

         # read all notifications present
         $nots->update();
         $nots->resetNext();
         while (my $not=$nots->getNext()) {
            my $nid=$not->id() || 0;

            # check if we have found the notification in question,
            # if not, skip ahead
            if ($nid ne $id) { next; }

            # we have found it - create notification parser instance
            my $parser=NotificationParser->new(nottypes=>\%nottypes, db=>$db);

            # parse notification
            my %cur;
            my $state=$parser->parse($not,\%cur);

            # attempt to get dataset id
            my $did = $state->{about} || 0;
            # attempt to get notification type that one is trying to acknowledge
            my $type = $state->{type} || "N/A";

            if ($did > 0) {
               # we have found the dataset id, lets log the ack to the dataset
               # log
               $log->send(entity=>$did,logtag=>$main::SHORTNAME,logmess=>"Notification $nid of type $type acknowledged by user $userid.");
            }
            # we are in any event fininshed
            last;
         }

         $content->value("errstr","");
         $content->value("err",0);
         return 1;
      } else {
         # unable to touch ack-file
         $content->value("errstr","Unable to ack notification rid: ".$ack->error());
         $content->value("err",1);
         return 0;
      }
   } else {
      # missing notification id and rid
      $content->value("errstr","Cannot ack notification. Unable to locate notification $id and rid $rid. It is either invalid or have been confirmed already. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }
}

sub enumEntityTypes {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # no input to method outputs all entity type names
   my @types=$db->enumEntityTypes();

   if (defined $types[0]) {
      # we have values
      my %ntypes;
      foreach (@types) {
         my $key=$_;

         my $name=($db->getEntityTypeNameById($key))[0] || "NOT DEFINED";
         $ntypes{$key}=$name;
      }

      # return them
      $content->value("types",\%ntypes);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # something failed
      $content->value("errstr","Unable to get entity types: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub enumPermTypes {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
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

sub getEntities {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $name=$SysSchema::CLEAN{entityname}->($query->{name});
   my $count=$query->{count};
   my $offset=$query->{offset};
   my $include=$query->{include};
   my $exclude=$query->{exclude};

   if ((defined $include) && (ref($include) ne "ARRAY")) {
      # wrong type 
      $content->value("errstr","Include parameter is not an array-reference. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   if ((defined $exclude) && (ref($exclude) ne "ARRAY")) {
      # wrong type
      $content->value("errstr","Exclude parameter is not an array-reference. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   if ((!defined $name) || ($name eq "")) {
      # wrong type
      $content->value("errstr","No name-parameter specified. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # convert includes to entity type ids
   my %includes;
   if (defined $include) {
      foreach (@{$include}) {
         my $in=$Schema::CLEAN{entitytypename}->($_);

         if ($in eq "DATASET") { next; } # not allowed to include datasets

         my $type=($db->getEntityTypeIdByName($in))[0];
         if (defined $type) {
            # we have a valid type - save it
            $includes{$type}=1;
         }
      }
   }

  # convert excludes to entity type ids
   my %excludes;
   if (defined $exclude) {
      foreach (@{$exclude}) {
         my $ex=$Schema::CLEAN{entitytypename}->($_);

         if ($ex eq "DATASET") { next; } # we will add this exclude ourselves

         my $type=($db->getEntityTypeIdByName($ex))[0];
         if (defined $type) {
            # we have a valid type - save it
            $excludes{$type}=1;
         }
      }
   }
   # add DATASET-type to excludes
   $excludes{($db->getEntityTypeIdByName("DATASET"))[0]}=1;

   # the combined result of include and exclude
   my @types;
   if (!defined $include) { @types=$db->enumEntityTypes(); } else { @types=keys %includes; }
   # go through each include and remove any excludes
   my $pos=-1;
   foreach (@types) {
      my $type=$_;
      $pos++;
      # if this type is to be excluded, remove it
      if (exists $excludes{$type}) { splice (@types,$pos,1); }
   }

   # create SQLStruct for search
   my %search;
   if (defined $name) { $search{$SysSchema::MD{"name"}}{"="}=$name; }

   my $entities=$db->getEntityByMetadataKeyAndType (\%search,$offset,$count,$SysSchema::MD{name},undef,undef,\@types,1);

   # go through each entity and retrieve data
   if (defined $entities) {
      # we have a list of entities, get the needed metadata for them
      my @mdkeys=($SysSchema::MD{"name"},$SysSchema::MD{"entity.parent"},$SysSchema::MD{"entity.parentname"},$SysSchema::MD{"entity.type"});
      my $md=$db->getEntityMetadataMultipleList (\@mdkeys,$entities,1);
      if (defined $md) {
         # create result hash
         my %result;
         foreach (@{$entities}) {
            my $id=$_;
            $result{$id}{name}=$md->{$id}{$SysSchema::MD{name}}||"N/A";
            $result{$id}{parent}=$md->{$id}{$SysSchema::MD{"entity.parent"}}||0;
            $result{$id}{parentname}=$md->{$id}{$SysSchema::MD{"entity.parentname"}}||"N/A";
            $result{$id}{type}=($db->getEntityTypeNameById($md->{$id}{$SysSchema::MD{"entity.type"}}))[0]||"N/A";
         }
         $content->value("errstr","");
         $content->value("err",0);
         my $matches=@{$entities};
         $content->value("matches",$matches);
         $content->value("entities",\%result);
      } else {
         $content->value("errstr","Unable to get entity metadata: ".$db->error());
         $content->value("err",1);
         return 0;
      }
   } else {
      $content->value("errstr","Unable to get entities: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getHostSSHKeys {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $host=$SysSchema::CLEAN{host}->($query->{host});
   my $port=$SysSchema::CLEAN{port}->($query->{port});

   # set default if 0
   if ($port == 0) { $port=22; }

   # we are ready to ask host for ssh keys
   my $result = qx($SSH_KEYSCAN -p $port -T 3 -t dsa,ecdsa,ed25519,rsa "$host" 2>&1);
   # check execution result
   if ($? != 0) {
      # An error occured - get the last line of result
      my @lines=split("[\r\n]",$result);
      my $err=pop(@lines);   
      $err=~s/[\r\n]//g;
      $content->value("errstr","Unable to get host SSH keys: ".$err);
      $content->value("err",1);
      return 0;
   }

   # get quoted host
   my $qhost=qq($host);

   # we have a result from ssh-keyscan. Go through and collect.
   # Lines of interest must start with hostname. All others are ignored.
   my %sshkeys=();
   my @lines=split("[\r\n]",$result);
   foreach (@lines) {
      my $line=$_;
      if ($line =~ /^$qhost\s+([^\s]+)\s+([a-zA-Z0-9\/\+\=]+)[\r\n]*$/) {
         # add key to hash
         $sshkeys{$1}=$2;
      }
   }

   $content->value("errstr","");
   $content->value("err",0);
   $content->value("sshkeys",\%sshkeys);
   return 1;
}

sub getMetadata {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that entity exists
   if (!$db->existsEntity($id)) {
      # does not exist
      $content->value("errstr","Entity does not exist: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # get entity metadata from extended table
   my %opt;
   $opt{parent}=1;
   my $md=$db->getEntityMetadata ($id,\%opt);

   if (defined $md) {
      # get type of entity
      my $type=uc(($db->getEntityTypeNameById($md->{$SysSchema::MD{"entity.type"}}||""))[0]||"");
      # create a hash of allowed metadata for the given type
      my %enttype=();
      if (exists $SysSchema::MDPUB{$type}) {
         # we have specific data for given type
	 %enttype=map { $_ => 1 } @{$SysSchema::MDPUB{$type}};
      }
      # create hash of allowed general metadata
      my %all=map { $_ => 1 } @{$SysSchema::MDPUB{ALL}};

      # metadata is defined - return some of it
      my %nmd=();
      foreach (keys %{$md}) {
         my $key=$_;
        
         # check if key exists in the allowed hashes
         if ((exists $all{$key}) || (exists $enttype{$key})) {
            # we are allowed to publish this metadata
            $nmd{$key}=$md->{$key};
         }
      }
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("metadata",\%nmd);
      return 1;      
   } else {
      # something failed
      $content->value("errstr","Unable to retrieve metadata of $id: ".$db->error());
      $content->value("err",1);

      return 0;
   }
}

sub getName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   # attempt to get name
   MethodsReuse::getEntityName($mess,\%opt,$db,$userid,$cfg,$log);

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

sub getPath {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that entity exists
   if (!$db->existsEntity($id)) {
      # does not exist
      $content->value("errstr","Entity does not exist: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # get path
   my @path=$db->getEntityPath ($id);

   if (defined $path[0]) {
      # path is defined - return it.
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("path",\@path);
      return 1;      
   } else {
      # something failed
      $content->value("errstr","Unable to retrieve path of entity $id: ".$db->error());
      $content->value("err",1);

      return 0;
   }
}

sub getType {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that entity exists
   if (!$db->existsEntity($id)) {
      # does not exist
      $content->value("errstr","Entity does not exist: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # get entity type
   my $type=$db->getEntityTypeName ($id);

   if (defined $type) {
      # type is defined - return it.
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("type",$type);
      return 1;      
   } else {
      # something failed
      $content->value("errstr","Unable to retrieve entity type of $id: ".$db->error());
      $content->value("err",1);

      return 0;
   }
}

sub ping {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # set return values - in addition timestamps are added by the server.
   $content->value("errstr","");
   $content->value("err",0);

   return 1;
}

sub getTree {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   # default to 1 or the root
   if ($id == 0) { $id=1; }
   # get exclude option, if any
   my $exclude=$query->{exclude};
   # get include option, if any
   my $include=$query->{include};
   # get depth option, if any
   my $depth=$query->{depth};
   # include template metadata on groups or not?
   my $tmplmd=$Schema::CLEAN{boolean}->($query->{templatemetadata});

   # check that entity exists
   if (!$db->existsEntity($id)) {
      # does not exist
      $content->value("errstr","Entity does not exist: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   if ((defined $include) && (ref($include) ne "ARRAY")) {
      # wrong type - exit not before passing it to getEntityTree
      $content->value("errstr","Include parameter is not an array-reference. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   if ((defined $exclude) && (ref($exclude) ne "ARRAY")) {
      # wrong type - exit not before passing it to getEntityTree
      $content->value("errstr","Exclude parameter is not an array-reference. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # include dataset flag
   my $idset=0;

   # convert includes to entity type ids
   my @includes;
   if (defined $include) {
      foreach (@{$include}) {
         my $in=$Schema::CLEAN{entitytypename}->($_);

         if ($in eq "DATASET") { $idset=1; }

         my $type=($db->getEntityTypeIdByName($in))[0];
         if (defined $type) {
            # we have a valid type - save it
            push @includes,$type;
         }
      }
   }

   # convert excludes to entity type ids
   my @excludes;
   my $domit=0;
   if (defined $exclude) {
      foreach (@{$exclude}) {
         my $ex=$Schema::CLEAN{entitytypename}->($_);

         if ($ex eq "DATASET") { $domit=1; }

         my $type=($db->getEntityTypeIdByName($ex))[0];
         if (defined $type) {
            # we have a valid type - save it
            push @excludes,$type;
         }
      }
   }
   $idset=($idset ? 1 : ($domit ? 0 : 1));

   # retrieve tree
   my $tree=$db->getEntityTree($id,\@includes,\@excludes,$depth);
   if (defined $tree) {
      # success - get tree's entities
      my @ids=keys %{$tree};
      # get all these ids names
      my $names=$db->getEntityMetadataMultipleList ([$SysSchema::MD{name},
                                                     $SysSchema::MD{"fi.store"},
                                                     $SysSchema::MD{"dataset.closed"},
                                                     $SysSchema::MD{"dataset.removed"},
                                                     $SysSchema::MD{"dataset.expire"},
                                                     $SysSchema::MD{"dataset.type"},
                                                     $SysSchema::MD{"dataset.size"},
                                                     $SysSchema::MD{"dc.description"},
                                                     $SysSchema::MD{"dataset.created"},
                                                     $SysSchema::MD{"dc.creator"},
                                                     $SysSchema::MD{"dataset.status"}],\@ids);
      if (!defined $names) {
         # does not exist or something failed
         $content->value("errstr","Unable to retrieve entity tree's given names: ".$db->error());
         $content->value("err",1);
         return 0;
      } 
      # add names to tree hash and convert type
      my %tmplnames=();
      foreach (keys %{$tree}) {
         my $key=$_;

         # set entity name
         $tree->{$key}{name}=$names->{$key}{$SysSchema::MD{name}} || "NOT DEFINED ($key)";
         # convert type to readable string
         $tree->{$key}{type}=($db->getEntityTypeNameById($tree->{$key}{type}))[0];
         # add other metadata, if at all
         $tree->{$key}{metadata}={};
         if (uc($tree->{$key}{type}) eq "GROUP") {
            # we only add possible fileinterface store if entity is a group.
            $tree->{$key}{metadata}{$SysSchema::MD{"fi.store"}}=$names->{$key}{$SysSchema::MD{"fi.store"}} || "";
            # include template metadata or not...
            if ($tmplmd) {
               # get possible template assignments on this group
               my $assign=$db->getEntityTemplateAssignments($key);
               # add any assignments to the tree data
               $tree->{$key}{templates}={};
               foreach (keys %{$assign}) {
                  my $typeid=$_;
                  my $typename=($db->getEntityTypeNameById($typeid))[0];

                  my $templates=$assign->{$typeid};

                  my @list;
                  foreach (@{$templates}) {
                     my $tmpl=$_;

                     # check if we need to get the name of the template
                     my $name="";
                     if (!exists $tmplnames{$tmpl}) {
                        # get template name
                        my $md=$db->getEntityMetadata($tmpl,undef,$SysSchema::MD{name});
                        $name=(defined $md->{$SysSchema::MD{name}} ? $md->{$SysSchema::MD{name}}." ($tmpl)" : "N/A");
                        # save template name for reuse
                        $tmplnames{$tmpl}=$name;
                     } else {
                        $name=$tmplnames{$tmpl};
                     }
                     push @list,$name;
                  }
                  # add all templates of this type to the metadata in the tree
                  # if any assigned
                  if (@list > 0) {
                     # we have assignments on this key
                     $tree->{$key}{templates}{$typename}=\@list;
                  }
               }
            }
         } elsif (uc($tree->{$key}{type}) eq "DATASET") {
            $tree->{$key}{metadata}{$SysSchema::MD{"dataset.status"}}=$names->{$key}{$SysSchema::MD{"dataset.status"}} || "";
            $tree->{$key}{metadata}{$SysSchema::MD{"dataset.closed"}}=$names->{$key}{$SysSchema::MD{"dataset.closed"}};
            $tree->{$key}{metadata}{$SysSchema::MD{"dataset.removed"}}=$names->{$key}{$SysSchema::MD{"dataset.removed"}} || 0;
            $tree->{$key}{metadata}{$SysSchema::MD{"dataset.expire"}}=$names->{$key}{$SysSchema::MD{"dataset.expire"}} || 0;
            $tree->{$key}{metadata}{$SysSchema::MD{"dataset.type"}}=$names->{$key}{$SysSchema::MD{"dataset.type"}} || "N/A";
            $tree->{$key}{metadata}{$SysSchema::MD{"dc.description"}}=$names->{$key}{$SysSchema::MD{"dc.description"}} || "NOT DEFINED ($key)";
            $tree->{$key}{metadata}{$SysSchema::MD{"dataset.created"}}=$names->{$key}{$SysSchema::MD{"dataset.created"}} || 0;
            $tree->{$key}{metadata}{$SysSchema::MD{"dc.creator"}}=$names->{$key}{$SysSchema::MD{"dc.creator"}} || "N/A";
            if (defined $names->{$key}{$SysSchema::MD{"dataset.size"}}) {
               $tree->{$key}{metadata}{$SysSchema::MD{"dataset.size"}}=$names->{$key}{$SysSchema::MD{"dataset.size"}};          
            }
         }
      }

      # get DATASET type id
      my $type=($db->getEntityTypeIdByName("DATASET"))[0];
 
      if (!defined $type) {
         # does not exist or something failed
         $content->value("errstr","Unable to retrieve DATASET entity-type: ".$db->error());
         $content->value("err",1);
         return 0;
      }

      # get GROUP type id
      my $grouptype=($db->getEntityTypeIdByName("GROUP"))[0];
      if (!defined $grouptype) {
         # something failed - abort
         $content->value("errstr","Unable to get entity type id of GROUP: ".$db->error());
         $content->value("err",1);
         return 0;
      }

      # get perm for entities in tree if dataset is included
      my $perms;
      if ($idset) {
         # only get perms for DATASETs
         my @incl=($type);
         # MAKE SOME HEURISTICS HERE AT SOME POINT THAT LOOKS AT
         # DEPTH ASKED FOR, ENTITIES RETURNED AND FEED THAT $ENTITIES-list
         # INTO METHOD TO FURTHER LIMIT THE JOB IT DOES AND WHAT IT RETURNS.
         # IN OTHER WORDS - OPTIMIZE SPEED BASED ON LIKELIHOOD OF LOTS OF DATASETS.
         $perms=$db->getEntityByPermAndType($userid,undef,"ANY",\@incl);
         if (!defined $perms) {
            $content->value("errstr","Unable to get permission on tree: ".$db->error());
            $content->value("err",1);
            return 0;
         }
      }

      # go through tree and process it
      my $create=$db->createBitmask($db->getPermTypeValueByName("DATASET_CREATE"));
      foreach (keys %{$tree}) {
         my $id=$_;

         # sort the children at the same time - first check that they exist
         my @childpool=grep { exists $tree->{$_} } @{$tree->{$id}{children}};
         my @grouppool=grep { $tree->{$_}{type} eq "GROUP" } @childpool;
         my @nogrouppool=grep { $tree->{$_}{type} ne "GROUP" } @childpool;
         # then sort them, first group, then the rest
         my @cgroup=sort { lc($tree->{$a}{name}) cmp lc($tree->{$b}{name}) } @grouppool;
         my @cnogroup=sort { lc($tree->{$a}{name}) cmp lc($tree->{$b}{name}) } @nogrouppool;
         my @children;
         push @children,@cgroup;
         push @children,@cnogroup;
         # set new children sort order
         $tree->{$id}{children}=\@children;

         if ($tree->{$id}{type} eq "DATASET") {
            # this entity is a DATASET-entity - check its perms
            # grab only relevant perms (DATASET_.*)
            my $perm=$perms->{$id}||'';
            my $dperms=arrayToPerm($db,[grep { $_ =~ /^DATASET\_.*$/ } @{permToArray($db,$perm)}]);
            # we only check DATASET perms and if user only has CREATE or NONE, we will remove the dataset.
            if (($perm eq '') || ($perm eq $create)) {
               # perms for user is empty on this or only has create perm
               # prune from tree
               delete ($tree->{$id});
               # go to next entity in tree
               next;
            }
         }
      }
      # clean tree of dangling children
      foreach (keys %{$tree}) {
         my $id=$_;

         if (!exists $tree->{$id}{children}) { next; }

         # go through children
         my @children=@{$tree->{$id}{children}};
         my $size=@children;
         my @keep;
         foreach (@children) {
            my $c=$_;
 
            if (exists $tree->{$c}) {
               push @keep,$c;
            }
         }
         $tree->{$id}{children}=\@keep;
      }
      # finished pruning - return it.
      $content->value("tree",$tree);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # something failed
      $content->value("errstr","Unable to get entity tree: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

1;

__END__

=encoding UTF-8

=head1 GENERAL METHODS

=head2 ackNotification()

Acknowledges a notice from a Notification.

Accepts the following parameters:

=over

=item

B<id> Notification ID of notification that the notice has been generated from. STRING. Required. 

=cut

=item

B<rid> Notice random id (rid) for the acknowledgement. STRING. Required.

=cut

=back

This methods requires no user permissions except being able to login to the AURORA REST-server.

Returns no special feedback upon success.

=cut

=head2 enumEntityTypes()

Enumerates all entity types in the database.

No input is accepted.

Upon success return the following HASH:

  types = (
             ENTITYTYPEa => STRING # ID to textual name
             ENTITYTYPEb => STRING
             .
             .
             ENTITYTYPEz => STRING
          )

ENTITYTYPEa and so on are the entitytype ID and the STRING is the textual name of the entitytype type. 

=cut

=head2 enumPermTypes()

Enumerates all permission types in the database.

No input is accepted.

Upon success return the following ARRAY:

  types = ["PERMISSIONa","PERMISSION_b" ... "PERMISSIONz"]

PERMISSIONa and so on are the textual string name of the permission type. 

=cut

=head2 getEntities()

Search for and retrieve entity(ies) matching name and type.

Accepted input parameters are:

=over

=item

B<name> The entity name to search for. STRING. Required. This is the name to search for when matching 
entities in the AURORA database. The name parameter also accepts wildcards in the form of "*". It is possible to place one 
or several asterix within the search-string as one needs to.

=cut

=item

B<count> The number of entity hits to return. INTEGER. Optional. If not specified it will return all matches if not offset 
has been set (see the offset parameter). The parameter is in the range 1 - N.

=cut

=item

B<offset> The window or offset to get hits from. INTEGER. Optional. It specified to start from N offset and then get X number of 
hits as defined by the count-parameter. If offset is specified, the maximum number of count-parameter hits to return are 2000 at 
a time. If no offset specified the method will return all matches.

=cut

=item

B<include> The entity type(s) to include in the match. ARRAY of STRING. Optional. If not specified will default to matching all entities, 
except DATASET (consult the separate search-method for datasets: getDatasets()). The include parameter is applied first, then a possible 
exclude parameter is applied thereafter removing possible entries specified in include.

=cut

=item

B<exclude> The entity type(s) to exclude in the match. ARRAY of STRING. Optional. If not specified will default to only excluding DATASET-
entities. If specified, DATASET-entites will still be excluded. The include-parameter is applied before the entries in the 
exclude-parameter. That means that the exclude-parameter will potentially remove entries in the include-parameter list.

=item

=back

Upon success this method returns the following structures:

   entities => (
                 entityID1 => {
                                name => STRING,  # textual name of entity
                                type => STRING,  # textual entity type
                                parent => INTEGER, # entity parent id
                                parentname => INTEGER, # entity textual parent name
                              }
                 .
                 .
                 entityIDn => { ... }
              )
   matches => INTEGER # number of matches found of given name-parameter

=cut

=head2 getHostSSHKeys()

Gets a hosts public SSH Keys through ssh-keyscan.

Input parameters:

=over

=item

B<host> Hostname or ip of host to get the public ssh keys of. Required. STRING.

=cut

=item

B<port> Port number to use when connecting to retrieve the hosts public ssh keys. Optional. INTEGER. If none is 
specified it will default to 22.

=back

Upon success returns the following structure:

   sshkeys => (
      TYPE1 => PUBLIC KEY,
      .
      .
      TYPEn => PUBLIC KEY,
   )

TYPE is the key type (ssh-rsa, ssh-dsa etc.). PUBLIC KEY is the actual key itself.

=cut

=head2 getMetadata()

Gets the general, open metadata of an entity.

Input parameters:

=over

=item

B<id> Entity ID from the database of the entity to get the metadata of. INTEGER. Required.

=cut

=back

Upon success return the following structure:

   (
      metadata => (
         NAMESPACE1 = STRING,
         .
         .
         NAMESPACEn = STRING,
      )
   )

Where NAMESPACE is the name of a specific metadata value of the entity. It will only return metadata for an entity that is 
deemed open and public.

=cut

=head2 getName()

Gets the name of an entity.

Input parameters:

=over

=item

B<id> Entity ID from the database of the entity to get the name of. INTEGER. Required.

=cut

=back

Upon success return the following value:

   name => STRING # the textual display name of the entity in question.

=cut

=head2 getPath()

Gets the path down to an entity in the entity tree (including the entity itself).

Input parameters:

=over

=item

B<id> Entity ID from the database of the entity to get the path to. INTEGER. Required.

=cut

=back

Upon sucess return the following ARRAY:

   path => [ IDa, IDb .. IDz ]

where IDa and so on are the entity IDs from the database of the entity in the path down to the entity in question.

The first element of the array is the topmost element in the entity tree and then the succeeding elements 
descends down to the entity in question in correct order.

=cut

=head2 getType()

Gets the type name of an entity.

Input parameters:

=over

=item

B<id> Entity ID from the database of the entity to get the entity type of. INTEGER. Required.

=cut

=back

Upon sucess returns the textual entity type name:

   type = STRING # textual type name of entity

=cut

=head2 ping()

Pings the server to see if it floats or not.

No input accepted.

The method just checks that the server respons and is working and upon success returns just the global values of 
"received", "delievered", "err" and "errstr".

=cut

=head2 getTree()

Get the entity tree.

Input parameters:

=over

=item

B<id> The start entity ID from the database in the entity tree. INTEGER. Optional. If not specified will default to 
the root entity (1). This option makes it possible to just get parts of the tree by specifying a start point somehwere else 
in the tree than the top root-entity.

=cut

=item

B<include> List of entity types to include in the result. ARRAY of STRING. Optional. If not specified will return all 
entity types that exists in the tree (except if some are excluded with the exclude-parameter). If specified the 
method will return the entity types that have been designated in this parameter only. Eg. one can choose to return 
only the datasets by specifying this parameter to ["DATASET"]. Whatever is specified in include is subsequently 
altered by any exclude-parameter.

=cut

=item

B<exclude> List of entity types to exclude from the result. ARRAY of STRING. Optional. If not specified will return 
all entity types that exists in the tree (except if include parameter has been specified). If specified the method 
will not return the entity types that have been designated in this parameter. Eg. one can choose not to return 
the datasets by specifying this parameter to ["DATASET"]. However, if both include- and exclude- parameters have 
been specified, the include parameter comes first and then the exclude parameter removes potential items from 
that list.

=cut

=item

B<depth> Maximum depth from depth of start entity (id-parameter). INTEGER. Optional. If not specified all start 
entity children will be returned independant of their depths. A depth of 0 returns only the start entity itself 
(its a tree, so we only return start-entity and its children moderated by depth), 1 returns the start entity itself and 
all entities on the level below it and so on.

=cut

=item

B<templatemetadata> Include template metadata information on any GROUP entity that are found in the tree. INTEGER. Optional. If not specified at all it 
will default to 0 or false. Valid values are 0 (false) and 1 (true).

=cut

=back

Upon success will return the following HASH-structure:

  tree => (
            IDa => (
                     id => INTEGER
                     parent => INTEGER,
                     type => STRING,
                     name => STRING,
                     metadata => (
                        metadataA => STRING,
                        .
                        .
                        metadataZ => STRING
                                 )
                     children => [ IDb...IDn ]
                   )
            IDb => (
                     id => INTEGER,
                     parent => INTEGER,
                     type => STRING,
                     name => STRING,
                     metadata => (
                        metadataA => STRING,
                        .
                        .
                        metadataZ => STRING,
                                 )
                     children => [],
                   )
            .
            .
            IDz => ( ... )
          )

All the information in the tree is flat, so that all entities resides in the first level of the HASH. Each sub-hash then 
refers to entities on the top level through its children array. All entities in the tree will return its id, parent, type, name 
and an array of its children (if any) except the top root-node (1), which does not have any parent. The entity type is the 
textual string version of the type (eg. "DATASET", "GROUP", "COMPUTER" and so on and so forth).

In addition to the set group of information like: id, parent, type, name and children, each sub-hash also includes a metadata 
sub-hash that contains metadata that might be relevant to the the entity. Eg. for GROUP-entities the fileinterface store-name 
will be included if it has been set at all.

=cut
