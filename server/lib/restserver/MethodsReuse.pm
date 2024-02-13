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
# MethodsReuse: Reuseable methods for the AURORA REST-server
#
package MethodsReuse;
use strict;
use RestTools;

### Methods that are reused throughout the REST-server

sub deleteEntity {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # entity to delete
   my $type=$Schema::CLEAN{entitytypename}->($query->{type}); # entity-type that entity to be deleted must fulfill

   # check that id is valid
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName($type))[0])) {
      # does not exist 
      $content->value("errstr","$type $id does not exist or is not a $type entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["${type}_DELETE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the ${type}_DELETE permission on the $type $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # ready to attmept delete
   if ($db->deleteEntity ($id)) {
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to delete $type $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub enumEntities {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get type
   my $type=$Schema::CLEAN{entitytypename}->($query->{type});
   my $pltype=lc($type)."s";
   # get namespace for name, optional
   my $namespace=$query->{namespace} || $SysSchema::MD{name};
   # get required perm, if any
   my $perm=$query->{perm} || undef;

   # check perm first 
   my $mask;
   if (defined $perm) {
      # perm is defined, create mask
      $mask=$db->createBitmask($db->getPermTypeValueByName($perm));
   }

   # enumerate entities
   my $ids;
   if (defined $perm) {
      $ids=$db->getEntityByPermAndType($userid,$mask,"ANY",\@{[($db->getEntityTypeIdByName($type))]});
   } else {
      my $idlist=$db->enumEntitiesByType(\@{[($db->getEntityTypeIdByName($type))]});
      if (defined $idlist) { my %idhash=map { $_ => 1 } @{$idlist}; $ids=\%idhash; }
   }

   if (defined $ids) {
      # we got result - go through each and get their names    
      my @ents=keys %{$ids};
      my $mdlist=$db->getEntityMetadataList($SysSchema::MD{name},\@ents);
      if (!defined $mdlist) {
         # something failed
         $content->value("errstr","Unable to get name of entities: ".$db->error());
         $content->value("err",1);
         return 0;
      }
      my %result;
      foreach (@ents) {
         my $key=$_;

         if (exists $mdlist->{$key}) {
            $result{$key}=$mdlist->{$key};
         } else {
            $result{$key}="NOT DEFINED";
         }
      }

      # return result(s)
      $content->value($pltype,\%result);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # something failed
      $content->value("errstr","Unable to enumerate $pltype: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub enumPermTypesByEntityType {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $type=$Schema::CLEAN{entitytypename}->($query->{type});
   my $qtype=qq($type);

   # get permission types
   my @perms;
   if ($type ne "") {
      # get the type's perms
      @perms=grep { $_ =~ /^$qtype.*$/ } $db->enumPermTypes();
   } else {
      # get all
      @perms=$db->enumPermTypes();
   }

   # check if we have a valid result
   if (defined $perms[0]) {
      # success - return perm names
      $content->value("types",\@perms);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # something failed
      if ($type ne "") {
         $content->value("errstr","Unable to get $type permission types: ".$db->error());
      } else {
         $content->value("errstr","Unable to get permission types: ".$db->error());
      }
      $content->value("err",1);
      return 0;
   }
}

sub getEntityName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # entity to get name of
   my $type=$Schema::CLEAN{entitytypename}->($query->{type}); # entity-type that entity must fulfill

   # check that id is valid
   if ((!$db->existsEntity($id)) || ((defined $query->{type}) && ($db->getEntityType($id) != ($db->getEntityTypeIdByName($type))[0]))) {
      # does not exist 
      $content->value("errstr","$type $id does not exist or is not a $type entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # ready to attempt to get entity name
   my $res=$db->getEntityMetadata ($id,$SysSchema::MD{name});
   my $name=$res->{$SysSchema::MD{name}} || "NOT DEFINED";
   if (defined $res) {
      $content->value("name",$name);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to get entity name of $type $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub setEntityName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # entity to get name of
   my $type=$Schema::CLEAN{entitytypename}->(uc($query->{type})); # entity-type that entity must fulfill
   my $name=$SysSchema::CLEAN{entityname}->($query->{name}); # entity-name
   my $duplicates=$SysSchema::CLEAN{duplicates}->($query->{duplicates}); # whether to allow duplicates of name or not (undef=none,0=not in group,1=ok)

   # check that id is valid
   if ((!$db->existsEntity($id)) || ((defined $query->{type}) && ($db->getEntityType($id) != ($db->getEntityTypeIdByName($type))[0]))) {
      # does not exist 
      $content->value("errstr","$type $id does not exist or is not a $type entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["${type}_CHANGE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the ${type}_CHANGE permission on the $type $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # check that name has a valid value
   if ((!defined $name) || ($name eq "")) {
      # name does not fulfill minimum criteria
      $content->value("errstr","$type name is missing and does not fulfill minimum requirements. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check if duplicates are allowed
   if (!$duplicates) { # undef=no dupl i tree, 0=no dupl i same group, 1=dupl ok
      # no duplicates allowed - check if it is in tree or on same group-level
      if (!defined $duplicates) {
         # no duplicates in tree at all
         my %search;
         $search{$SysSchema::MD{name}}=$name;
         my @type=($db->getEntityTypeIdByName($type))[0];
         my $ids=$db->getEntityByMetadataKeyAndType(\%search,undef,undef,$SysSchema::MD{name},undef,undef,\@type);

         if (!defined $ids) {
            # something failed
            $content->value("errstr","Unable to search for duplicate $type: ".$db->error());
            $content->value("err",1);
            return 0;
         }

         # check all received ids if they match id of entity to rename
         my $diff=1;
         foreach (@{$ids}) {
            my $i=$_;

            # check if id does not match the id changing its name, if so not allowed
            if ($i != $id) { $diff=0; last; }
         }

         # check if we have match that says we have other entity with same name
         if ((@{$ids} > 0) && (!$diff)) {
            # we have entity with same name already and it is not itself - duplicate not allowed
            $content->value("errstr","Another $type has the same name as \"$name\" already. Duplicates not allowed in entire tree. Unable to fulfill request.");
            $content->value("err",1);
            return 0;
         }
      } else {
         # no duplicates in same group
         # get parent-entitys GROUP-children and check if name exists already
         my @type=($db->getEntityTypeIdByName($type))[0];
         if (!defined $type[0]) {
            # something failed - abort
            $content->value("errstr","Unable to get entity type id of $type: ".$db->error());
            $content->value("err",1);
            return 0;
         }
         my $parent=$db->getEntityParent($id);
         if (!defined $parent) {
            # something failed - abort
            $content->value("errstr","Unable to get parent of $type $id: ".$db->error());
            $content->value("err",1);
            return 0;
         }
         my $children=$db->getEntityChildren($parent,\@type);
         if (!defined $children) {
            # something failed - abort
            $content->value("errstr","Unable to get children of parent $parent: ".$db->error());
            $content->value("err",1);
            return 0;
         }
         my $names;
         if (@{$children} > 0) { $names=$db->getEntityMetadataList($SysSchema::MD{name},$children); }

         # check name case-insensitive
         foreach (keys %{$names}) {
            my $entid=$_;

            if (lc($names->{$entid}||"NOT DEFINED") eq lc($name)) {                 
               # we already have this name at this level - check if it has the same id
               if ($entid != $id) {
                  # this is a different entity than the one we are setting name on, not allowed with duplicates
                  $content->value("errstr","$type name already exists as a child of parent $parent. Duplicates on same level not allowed. Unable to fulfill request.");
                  $content->value("err",1);
                  return 0;
               }
            }
         }
      }
   }

   # ready to attempt to set entity name
   my %md;
   $md{$SysSchema::MD{name}}=$name;
   my $res=$db->setEntityMetadata ($id,\%md);
   if ($res) {
      $content->value("name",$name);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to set name of $type $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub addEntityMember {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $object=$Schema::CLEAN{entity}->($query->{object}); # entity to add member(s) to.
   my $subjects=$query->{subjects}; # ref to LIST of entity ids
   my $type=$Schema::CLEAN{entitytypename}->($query->{type}); # entity-type that object must fulfill

   # check that id is valid
   if ((!$db->existsEntity($object)) || ($db->getEntityType($object) != ($db->getEntityTypeIdByName($type))[0])) {
      # does not exist 
      $content->value("errstr","$type $object does not exist or is not a $type entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # check that subjects is a LIST-ref
   if ((!defined $subjects) || (ref($subjects) ne "ARRAY")) {
      # wrong type or not defined
      $content->value("errstr","Subjects is not defined or it is not an array. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$object,["${type}_MEMBER_ADD"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the ${type}_MEMBER_ADD permission on the $type $object. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # ready to attempt to add member(s)
   my $ids=$db->addEntityMember ($object,@{$subjects});
   if (defined $ids) {
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to add members to $type $object: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getEntityMembers {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # entity to get members of
   my $type=$Schema::CLEAN{entitytypename}->($query->{type}); # entity-type that entity must fulfill

   # check that id is valid
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName($type))[0])) {
      # does not exist 
      $content->value("errstr","$type $id does not exist or is not a $type entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # ready to attempt to get members
   my $ids=$db->getEntityMembers ($id);
   if (defined $ids) {
      # get entity name of members
      my %members;
      my $mlist;
      if (@{$ids} > 0) { $mlist=$db->getEntityMetadataList($SysSchema::MD{name},$ids); }

      my %result;
      # go through ids and add data from mlist 
      foreach (@{$ids}) {
         my $ent=$_;

         $result{$ent}=$mlist->{$ent} || "NOT DEFINED";
      }
      $content->value("members",\%result);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to get members of $type $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub removeEntityMember {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $object=$Schema::CLEAN{entity}->($query->{object}); # entity to remove member(s) from.
   my $subjects=$query->{subjects}; # ref to LIST of entity ids
   my $type=$Schema::CLEAN{entitytypename}->($query->{type}); # entity-type that object must fulfill

   # check that id is valid
   if ((!$db->existsEntity($object)) || ($db->getEntityType($object) != ($db->getEntityTypeIdByName($type))[0])) {
      # does not exist 
      $content->value("errstr","$type $object does not exist or is not a $type entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # check that subjects is a LIST-ref
   if ((defined $subjects) && (ref($subjects) ne "ARRAY")) {
      # wrong type or not defined
      $content->value("errstr","Subjects is not not an array-reference. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$object,["${type}_MEMBER_ADD"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the ${type}_MEMBER_ADD permission on the $type $object. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # ready to attempt to remove member(s)
   my $ids;
   if (defined $subjects) { $ids=$db->removeEntityMember ($object,@{$subjects}); }
   else { $ids=$db->removeEntityMember ($object); } # remove all members
   if (defined $ids) {
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to remove member(s) from $type $object: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getEntityMetadataByPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my @perm;
   if (defined $query->{perm}) {
      @perm = @{$query->{perm}};
   }
   my $permtype = $Schema::CLEAN{permtype}->($query->{permtype});

   # check perm entries - if any
   if (defined $perm[0]) {
      # go through each permission name and check that is it valid      
      my @uperms=@{getInvalidPermArrayElements($db,\@perm)};
      if (@uperms > 0) {
         # one or more of the permissions are unknown
         $content->value("errstr","Permission(s) @uperms are unknown. Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      }
   }

   # we accept given perms on effective, inherited and grant
   my $allowed=hasPerm($db,$userid,$id,\@perm,$permtype,"ANY",1,1,undef,1);
   if ($allowed) {
      # we have a permission match and we can get the entity's metadata
      my $md=$db->getEntityMetadata($id);
      if (defined $md) {
         # we have metadata - return it
         $content->value("errstr","");
         $content->value("err",0);
         $content->value("metadata",$md);
         return 1;
      } else {
         # something went wrong
         $content->value("errstr","Cannot retrieve metadata for ".$db->getEntityTypeNameById($db->getEntityType($id))." entity $id: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0; 
      }
   } else {
      # we do not have any perms or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error());
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","The necessary permission(s): ".@perm." are missing for user $userid on ".$db->getEntityTypeNameById($db->getEntityType($id))." entity.");
         $content->value("err",1);
         return 0; 
      }
   }
}

sub getEntitiesByPermAndType {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $root = $query->{root} || 1;
   my @perm;
   if ((defined $query->{perm}) && (ref($query->{perm}) ne "ARRAY")) {
      $content->value("errstr","Perm is not an ARRAY-reference. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   if (defined $query->{perm}) {
      @perm = @{$query->{perm}};
   }
   my $permtype = $Schema::CLEAN{permtype}->($query->{permtype});
   my @entitytype;
   if (defined $query->{entitytype}) {
      @entitytype = @{$query->{entitytype}};
   }

   # check that entity types exists
   my @etypes;
   foreach (@entitytype) {
      my $type=$_;

      my $ti=($db->getEntityTypeIdByName($type))[0];
      
      if (!$ti) {
         # invalid type
         $content->value("errstr","Unknown entitytype $type specified. Unable to fulfill request.");
         $content->value("err",1);
         return 0;         
      } else {
         # success - add to list
         push @etypes,$ti;
      }
   }

   # check perm entries - if any
   my $permmask;
   if (defined $perm[0]) {
      # go through each permission name and check that is it valid
      my @uperms=@{getInvalidPermArrayElements($db,\@perm)};
      if (@uperms > 0) {
         # one or more of the permissions are unknown
         $content->value("errstr","Permission(s) @uperms are unknown. Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      }
      # all elements are valid - create bitmask from textual array
      $permmask=arrayToPerm($db,\@perm);
   }

   # ready to ask DB about entities
   my $entities = $db->getEntityChildrenPerm($userid,$root,1,\@etypes);

   if (defined $entities) {
      # we have a result      
      my @match;
      if ((defined $permmask) && ($permtype eq "ALL")) {
         # masktype is ALL
         @match=grep{(($entities->{$_}||'') & $permmask) eq $permmask} keys %$entities;
      } elsif ((defined $permmask) && ($permtype eq "ANY")) {
         # masktype is ANY
         @match=grep{(($entities->{$_}||'') & $permmask) !~ /\A\000*\z/} keys %$entities;
      } else {
         # ignoring mask and masktype returning everything
         @match=keys %$entities;
      }

      # return the result
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("entities",\@match);

      return 1;
   } else {
      # something failed
      $content->value("errstr","Unable to fetch entities: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub setEntityPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # entity to set perm on
   my $user=$Schema::CLEAN{entity}->($query->{user}); # subject which perm is to be set for
   if ($user == 0) { $user=$userid; } # default to user authenticated if invalid user
   my $grant=$query->{grant}; # grant mask to set
   my $deny=$query->{deny}; # deny mask to set
   my $op=$SysSchema::CLEAN{permop}->($query->{operation}); # replace, append or remove. Append is default
   my $type=$Schema::CLEAN{entitytypename}->($query->{type}); # entity-type to set perm on

   # check that id is valid
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName($type))[0])) {
      # does not exist 
      $content->value("errstr","$type $id does not exist or is not a $type entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # check that grant and deny are valid
   if ((defined $grant) && (ref($grant) ne "ARRAY")) {
      # invalid grant mask
      $content->value("errstr","Grant-parameter is not an array. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check for invalid perm elements
   my $invalid=MethodsGeneral::getInvalidPermArrayElements($grant);

   if (@{$invalid} > 0) {
      # failed its grant perm array
      $content->value("errstr","Invalid grant-permissions: @{$invalid}. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check that grant and deny are valid
   if ((defined $deny) && (ref($deny) ne "ARRAY")) {
      # invalid grant mask
      $content->value("errstr","Deny-parameter is not an array. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check for invalid perm elements
   $invalid=MethodsGeneral::getInvalidPermArrayElements($deny);

   if (@{$invalid} > 0) {
      # failed its deny perm array
      $content->value("errstr","Invalid deny-permissions: @{$invalid}. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # convert grant and deny to bitmasks
   my $grantm=MethodsGeneral::arrayToPerm($db,$grant);
   my $denym=MethodsGeneral::arrayToPerm($db,$deny);

   # merge deny and grant arrays
   my @perms;
   if (defined $grant) { push @perms,@{$grant}; }
   if (defined $deny) { push @perms,@{$deny}; }
   push @perms,"${type}_PERM_SET"; # we must also be allowed to set the perm

   # check if user are allowed to set permissions 
   # user must have all the corresponding permissions he is setting himself on the object in
   # question or on the parent by inheritance.
   my $allowed=MethodsGeneral::hasPerm($db,$userid,$id,\@perms,"ALL","ANY",undef,1,undef,1);
   if (!$allowed) {
      if (!defined $allowed) {
         # something failed with database operation
         $content->value("errstr","Unable to check your permissions before proceeding: ".$db->error()." Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      } else {
         # user does not have the required permission
         $content->value("errstr","You do not have the ${type}_PERM_SET permission on $type $id and/or the permissions on $type $id that your are trying to set (in order to give, you must have). Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # we are ready to set perm
   my $res = $db->setEntityPermByObject ($user,$id,$grantm,$denym,$op);

   if (defined $res) {
      my ($grantr,$denyr) = @{$res};
      # convert result bitmasks to arrays
      my $g=MethodsGeneral::permToArray($db,$grantr);
      my $d=MethodsGeneral::permToArray($db,$denyr);
      $content->value("grant",$g);
      $content->value("deny",$d);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to set permissions on $type $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getEntityPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # entity to set perm on
   my $user=$Schema::CLEAN{entity}->($query->{user}); # subject which perm is to be got for
   if ($user == 0) { $user=$userid; } # default to user authenticated if invalid user
   my $type=$Schema::CLEAN{entitytypename}->($query->{type}); # entity-type to get perm on

   # check that id is valid
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName($type))[0])) {
      # does not exist 
      $content->value("errstr","$type $id does not exist or is not a $type entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # we are ready to get perm
   my $perms = $db->getEntityPermByObject ($user,$id);

   if (defined $perms) {
      # convert result bitmasks to arrays
      my $g=MethodsGeneral::permToArray($db,$perms->[0]); 
      my $d=MethodsGeneral::permToArray($db,$perms->[1]); 
      $content->value("grant",$g);
      $content->value("deny",$d);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to get permissions on $type $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getEntityAggregatedPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # entity to set perm on
   my $user=$Schema::CLEAN{entity}->($query->{user}); # subject which perm is to be got for
   if ($user == 0) { $user=$userid; } # default to user authenticated if invalid user
   my $type=$Schema::CLEAN{entitytypename}->($query->{type}); # entity-type to get perm on

   # check that id is valid
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName($type))[0])) {
      # does not exist 
      $content->value("errstr","$type $id does not exist or is not a $type entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # we are ready to get perm
   my $perm = $db->getEntityPerm ($user,$id);

   if (defined $perm) {
      # convert result bitmasks to arrays
      my $p=MethodsGeneral::permToArray($db,$perm); 
      $content->value("perm",$p);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to get aggregated permissions on $type $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getEntityPermsOnObject {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # entity to get perms on
   my $type=$Schema::CLEAN{entitytypename}->($query->{type}); # entity-type that entity must fulfill

   # check that id is valid
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName($type))[0])) {
      # does not exist 
      $content->value("errstr","$type $id does not exist or is not a $type entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # ready to attempt to get perms on object
   my $perms=$db->getEntityPermsOnObject ($id);
   if (defined $perms) {
      # go through resulting hash - first get all names of keys
      my @ids=keys %{$perms};
      my $res=$db->getEntityMetadataList($SysSchema::MD{name},\@ids);
      foreach (keys %{$perms}) {
         my $subject=$_;

         my $inherit=$perms->{$subject}{inherit};
         my $grant=$perms->{$subject}{grant};
         my $deny=$perms->{$subject}{deny};
         my $perm=$perms->{$subject}{perm};

         # get subjects name
         my $name=$res->{$subject} || "NOT DEFINED";
         $perms->{$subject}{name}=$name;

         $perms->{$subject}{inherit}=\@{permToArray($db,$inherit)};
         $perms->{$subject}{grant}=\@{permToArray($db,$grant)};
         $perms->{$subject}{deny}=\@{permToArray($db,$deny)};
         $perms->{$subject}{perm}=\@{permToArray($db,$perm)};
      }
      
      $content->value("perms",$perms);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to get perms on $type $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub moveEntity {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # entity to move
   my $parent=$Schema::CLEAN{entity}->($query->{parent}); # parent to move entity to
   my $type=$Schema::CLEAN{entitytypename}->($query->{type}); # entity-type to move
   my $parenttype=$Schema::CLEAN{entitytypename}->($query->{parenttype}); # needed type for parent

   # check that id is valid
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName($type))[0])) {
      # does not exist 
      $content->value("errstr","$type $id does not exist or is not a $type entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # check that parent id is valid
   if ((!$db->existsEntity($parent)) || ($db->getEntityType($parent) != ($db->getEntityTypeIdByName($parenttype))[0])) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a $parenttype entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["${type}_MOVE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the ${type}_MOVE permission on the $type $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # user must have ALL of the perms on ANY of the levels
   $allowed=hasPerm($db,$userid,$parent,["${type}_CREATE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the ${type}_CREATE permission on the $parenttype $parent. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # start transaction
   my $tr=$db->useDBItransaction();

   # ready to attmept move
   if ($db->moveEntity ($id,$parent)) {
      # entity moved successfully - update metadata
      my %md;
      $md{$SysSchema::MD{"entity.parent"}}=$parent;  # update parentid as metadata - redundancy for searching
      if (!$db->setEntityMetadata($id,\%md)) {
         $content->value("errstr","Unable to update metadata of ${type} $id: ".$db->error);
         $content->value("err",1);
         return 0;      
      }
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to move $type $id to parent $parenttype $parent: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getEntityTaskAssignments {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get type, id and default
   my $type=$Schema::CLEAN{entitytypename}->($query->{type});
   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that id is valid and of type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName($type))[0])) {
      # does not exist or invalid
      $content->value("errstr","$type $id does not exist or is not a $type-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # ready to get assignments
   my @md;
   push @md,$SysSchema::MD{"task.assigns"}.".*";
   my $res=$db->getEntityMetadata($id,@md);
   if (defined $res) {
      # success - get all assignments
      my $mdc=MetadataCollection->new(base=>$SysSchema::MD{"task.assigns"});
      my $ahash=$mdc->metadata2Hash($res);

      # go through hash keys and convert any scalar values to array
      foreach (keys %{$ahash}) {
         my $computer=$_;
         my $ref=$ahash->{$computer};
         if (ref($ref) ne "ARRAY") {
            my @l;
            push @l,$ref;
            # update reference in hash
            $ahash->{$computer}=\@l;
         }
      }

      $content->value("assignments",$ahash);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed to get default
      $content->value("errstr","Unable to get $type $id task assignments: ".$db->error());
      $content->value("err",1);
      return 0;
   } 
}

sub setEntityTaskAssignments {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get type, id and default
   my $type=$Schema::CLEAN{entitytypename}->($query->{type});
   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $assigns=$query->{assignments};

   # check that id is valid and of type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName($type))[0])) {
      # does not exist or invalid
      $content->value("errstr","$type $id does not exist or is not a $type-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # first check that user has the necessary permissions
   my $allowed=MethodsGeneral::hasPerm($db,$userid,$id,["${type}_CHANGE"],"ALL","ANY",undef,1,undef,1);
   if (!$allowed) {
      if (!defined $allowed) {
         # something failed with database operation
         $content->value("errstr","Unable to check your permissions on $type $id: ".$db->error()." Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      } else {
         # user does not have the required permission
         $content->value("errstr","You do not have the ${type}_CHANGE permission on $type $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # ensure assignments is a hash
   if ((!defined $assigns) || (ref($assigns) ne "HASH")) {
      $content->value("errstr","$type assignments is not a HASH-reference. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # go through assignments and ensure they are valid
   my %cassigns;
   foreach (keys %{$assigns}) {
      my $key=$_;

      if ($key =~ /^\d+$/) {
         # correct format, check if contents is an array or not
         if (ref($assigns->{$key}) eq "ARRAY") { 
            # go through array and ensure that it is valid task ids - only add valid ones
            my @ntasks;
            foreach (@{$assigns->{$key}}) {
               my $task=$_;

               if (ref(\$task) ne "SCALAR") { next; }

               if (($db->existsEntity($task)) && ($db->getEntityType($task) == ($db->getEntityTypeIdByName("TASK"))[0])) { 
                  # only add if entity id (dependent upon type) has the TASK_EXECUTE permission on the task in question
                  my $ok=MethodsGeneral::hasPerm($db,$id,$task,["TASK_EXECUTE"],"ALL","ANY",undef,1,undef,1);
                  if (!$ok) {
                     if (!defined $ok) {
                        # something failed with database operation
                        $content->value("errstr","Unable to check your permissions on task $task: ".$db->error()." Unable to fulfill the request.");
                        $content->value("err",1);
                        return 0;
                     }
                     # not the right permission - fail
                     $content->value("errstr","Entity $id do not have the TASK_EXECUTE-permission on TASK $task. Unable to fulfill request.");
                     $content->value("err",1);
                     return 0;
                  } 

                  # user has permission - add task to assignment
                  push @ntasks,$task;
               }
            }
            # add only valid tasks and non-empty lists
            if (@ntasks > 0) { $cassigns{$key}=\@ntasks; }
         }
      }
   }

   # convert assignments to metadata
   my $mdc=MetadataCollection->new(base=>$SysSchema::MD{"task.assigns"},depth=>2);
   my $md=$mdc->hash2Metadata(\%cassigns);

   my $tr=$db->useDBItransaction();
   if (defined $tr) {
      # first delete all old task assignment metadata
      if (!$db->deleteEntityMetadata($id,[$SysSchema::MD{"task.assigns"}.".*"])) {
         $content->value("errstr","Unable to delete task assignments before assigning new ones: ".$db->error());
         $content->value("err",1);
         return 0;
      }

      # ready to set task assignments
      if ($db->setEntityMetadata($id,$md)) {
         # success
         $content->value("assignments",\%cassigns);
         $content->value("errstr","");
         $content->value("err",0);
         return 1;
      } else {
         $content->value("errstr","Unable to set task assignments: ".$db->error());
         $content->value("err",1);
         return 0;
      }
   } else {
      # failed to start db transaction
      $content->value("errstr","Unable to set start db-transaction: ".$db->error());
      $content->value("err",1);
      return 0;
   } 
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<MethodsReuse> Module with shared REST-server methods that are reused by the various Methods-files.

=cut

=head1 SYNOPSIS

   use MethodsReuse;

=cut

=head1 DESCRIPTION

Collection of shared REST-server methods that are reused by the various Methods-files. 

=cut

=head1 METHODS

=head2 addEntityMember()

=cut

=head2 deleteEntity()

Deletes a given entity

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on 
by the caller).

This method uses these parameters from query input: id, type. Id is entity ID from the AURORA database. Type is the textual entity type 
that the entity Id must fulfill in order to be allowed to delete. It is also used to check the TYPE_DELETE-permission on 
the entity.

Returns a HASH-reference with the success/data from the method as any other REST-method.

=cut

=head2 enumEntities()

Enumerate entities of a given type.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: type, perm. Type is the textual entity type of the entity-types 
you want to enumerate. Perm is the permission that the user in the userid-input above must fulfill on the entities 
being enumerated.

Returns a HASH-reference with the success/data from the method as any other REST-method.

=cut

=head2 enumPermTypesByEntityType()

Enumerate permission types for a given entity type.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: type. Type is the entity type to enumerate the permission types for.

Returns a HASH-reference with the success/data from the method as any other REST-method.

=cut

=head2 getEntitiesByPermAndType()

Get entities by permission- and type.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: root, perm, permtype, entitytype. Root is the entity id of where to start 
in the entity tree to find entities. Perm is the LIST-reference of textual permission types to match. Permtype is the logical 
operator to use on the Perm-parameter - either "ANY" (logical OR) or "ALL" (logical AND).

Returns a HASH-reference with the success/data from the method as any other REST-method.

=cut

=head2 getEntityAggregatedPerm()

Get an entity's aggregated permissions.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: id, user, type, Id is the entity to get the aggregated perms on. User 
is the user entity id from the AURORA database that the we want the aggregated permissions to be valid for. If none is given or 
the user id is invalid, it will default to the id in userid (logged in user in the REST-server). Type is the texatual entity type 
to get permissions on (used for checking type, messages etc.).

Returns a HASH-reference with the success/data from the method as any other REST-method.

=cut

=head2 getEntityMembers()

Get members of an entity.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: id, type. Id is the entity ID from the AURORA database to get the members of. 
Type is the textual entity type that the Id is to conform to (used for checking type, messages etc).

Returns a HASH-reference with the success/data from the method as any other REST-method.

=cut

=head2 getEntityMetadataByPerm()

Get an entity's metadata if permission is fulfilled.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: id, perm, permtype. Id is the entity ID from the AURORA database to get 
the metadata of. Perm is a LIST-reference of the permission(s) that must be fulfilled by the userid-input for metadata 
to be returned. Permtype is the logical operator to use on the permission(s) set in the Perm-parameter. It defaults to "ALL". 
Valid values are "ALL" (logical AND) or "ANY" (logical OR).

Returns a HASH-reference with the success/data from the method as any other REST-method.

=cut

=head2 getEntityName()

Get an entity's display name.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: id, type. Id is the entity ID from the AURORA database that one wants 
to get the display name of. Type is the textual entity type that the Id-parameter must fulfill (used for checking, messages 
etc.).

Returns a HASH-reference with the success/data from the method as any other REST-method.

=cut

=head2 getEntityPerm()

Get a users permissions on an entity.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: id, user, type. Id is the entity ID from the AURORA database that one wants 
to get the permissions on. User is the entity ID from the AURORA database that one wants to check the permissions of. If 
not specified or invalid, it will default to the userid-input (logged on user in the REST-server. Type is the textual 
entity type that the Id-parameter must fulfill (used for checking, messages etc.).

Returns a HASH-reference with the success/data from the method as any other REST-method. The returned permission(s) are 
in the keys "grant" and "deny".

=cut

=head2 getEntityPermsOnObject()

Get entities permission(s) on an object.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: id, type. Id is the entity ID from the AURORA database that one wants 
to get the permission(s) of (object). Type is the textual entity type that the Id-parameter must fulfill (used for checking, messages 
etc.). This method returns all permission of an object on all entities that have permission(s) set on it.

Returns a HASH-reference with the success/data from the method as any other REST-method. 

The return structure comes in the sub-hash called "perms" as follows:

   perms => (
              entityid1 => { 
                             inherit => ["PERMISSIONa" .. "PERMISSIONz"],
                             grant => ["PERMISSIONa" .. "PERMISSIONz"],
                             deny => ["PERMISSIONa" .. "PERMISSIONz"],
                             perm => ["PERMISSIONa" .. "PERMISSIONz"]
                           },
              .
              .
              entityidN => { .. }
            )

=cut

=head2 getEntityTaskAssignments()

Get task assignments of a given entity on COMPUTER-entities.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: id, type. Id is the entity ID from the AURORA database that one wants 
to get the assignments on. Type is the textual entity type that the Id-parameter must fulfill (used for checking, messages etc.).

Returns a HASH-reference with the success/data from the method as any other REST-method. 

The return structure has the following format:

   assignments => (
                    COMPUTERID1 => [TASKIDa .. TASKIDz]                    
                    .
                    .
                    COMPUTERIDN => [TASKIDa .. TASKIDz]
                  )

=cut

=head2 moveEntity()

Move an entity in the entity tree.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: id, parent, type, parenttype. Id is the entity ID from the AURORA 
database that one wants to move. Parent is the entity ID from the AURORA database which is to be the new parent of the 
entity. Type is the textual entity type that the Id-parameter must fulfill (used for checking, messages etc.). 
Parenttype is the textual entity type that the parent-parameter must fulfill (used for checking, messages etc.).

In order for this method to success the user in userid must have the [type]_MOVE-permission on the current parent and the 
[parenttype]_CREATE-permission on the new parent that the entity is being moved to.

Returns a HASH-reference with the success/data from the method as any other REST-method. Returns 1 upon success, 0 upon failure (err).

=cut

=head2 removeEntityMember()

Remove member(s) from a given entity.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: object, subject, type. Object is the entity id from the AURORA database of 
which to remove member(s) from. Subject is the LIST-reference of entity(ies) Id from the AURORA database to remove as members 
of the given object. Type is textual type that the object must meet (used for checking, messages etc.).

In order for the method to work, the user in userid needs to have the [type]_MEMBER_ADD-permission on the object-entity.

Returns a HASH-reference with the success/data from the method as any other REST-method. Returns 1 upon success, 0 upon failure (err).

=cut

=head2 setEntityName()

Sets the entity's display name.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: id, type, name, duplicates. Id is the entity id from the AURORA database of which one 
wants to set the display name of. Type is the textual entity type that the entity id must fulfill (used for checking, messages etc.). Name 
is the display name that one wants to set on the entity. Duplicates decides if it is allowed with duplicate names on the given 
entity type. Valid values for duplicates are undef (no duplicates in entire tree), 0 (no duplicates within same group) or 1 (duplicates ok).

Returns a HASH-reference with the success/data from the method as any other REST-method. Returns 1 upon success, 0 upon failure (err). The 
new and cleaned name is returned in the "name" key.

=cut

=head2 setEntityPerm()

Sets an entity's permissions.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: id, user, grant, deny, operation, type. Id is the entity id from the AURORA database of which one 
wants to set the permissions on (object). User is the entity id of the subject of which to set the permission(s) for. If invalid or none is 
specified, it will default to userid (logged in user of the REST-server). Grant is a LIST-reference of the textual permission(s) to grant. Deny is 
a LIST-reference of the textual permission(s) to deny. Operation is applying logic to use when setting the permission(s). Valid values are: 
replace, append or remove. Append is default. Type is the textual entity type of the entity to set the permissions on (used for checking, 
messages etc.)

In order for the method to succeed the user needs to have the [type]_PERM_SET-permission on the entity in question and he needs to have all 
the permissions that he is trying to set himself on that entity (either directly or through inheritance). One can only give away what one 
oneself has.

Returns a HASH-reference with the success/data from the method as any other REST-method. Returns 1 upon success, 0 upon failure (err). The 
resulting permissions set are returned in the keys "grant" and "deny" as LIST-references of textual permissions.

=cut

=head2 setEntityTaskAssignments()

Set assignments of tasks on computers for a given entity.

Accepts the following input: content, query, db, userid, cfg, log (these comes from the REST-server and are just passed on
by the caller).

This method uses these parameters from query input: id, type, assigns. Id is the entity id from the AURORA database of which one wants 
to set the task assignments of. Type is the textual entity type that the entity must fulfill (for checking, message etc.). Assigns is a 
HASH-reference of task assignments for computers to set on the given entity. See the getEntityTaskAssignments()-method for its structure.

In order for the method to succeed the user in userid needs to have the [type]_CHANGE-permission on the entity in question. Please also 
note that this method is destructive and all existing assignments are replaced with the new one(s).

Returns a HASH-reference with the success/data from the method as any other REST-method. Returns 1 upon success, 0 upon failure (err). The 
set assignments are returned in the key "assignments".

=cut

