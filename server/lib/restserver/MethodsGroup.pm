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
# MethodsGroup: Group-entity methods for the AURORA REST-server
#
package MethodsGroup;
use strict;
use RestTools;

sub registermethods {
   my $srv = shift;

   $srv->addMethod("/addGroupMember",\&addGroupMember,"Add member(s) of the given group.");
   $srv->addMethod("/assignGroupTemplate",\&assignGroupTemplate,"Assigns a template LIST to a group valid for a certain entity type.");
   $srv->addMethod("/unassignGroupTemplate",\&unassignGroupTemplate,"Unassigns template(s) of a group valid for a certain entity type.");
   $srv->addMethod("/createGroup",\&createGroup,"Create a group-entity.");
   $srv->addMethod("/deleteGroup",\&deleteGroup,"Delete a group-entity.");
   $srv->addMethod("/enumGroups",\&enumGroups,"Enumerate all group entities.");
   $srv->addMethod("/removeGroupMember",\&removeGroupMember,"Delete member(s) of the given group-entity.");
   $srv->addMethod("/enumGroupPermTypes",\&enumGroupPermTypes,"Enumerate all GROUP permission types.");
   $srv->addMethod("/getGroupAggregatedPerm",\&getGroupAggregatedPerm,"Get aggregated/inherited perm on group.");
   $srv->addMethod("/getGroupMembers",\&getGroupMembers,"Get members of the given group.");
   $srv->addMethod("/getGroupName",\&getGroupName,"Get name of the given group.");
   $srv->addMethod("/getGroupNoticeSubscriptions",\&getGroupNoticeSubscriptions,"Get all notice subscriptions on given group defined for any user.");
   $srv->addMethod("/getGroupPerm",\&getGroupPerm,"Get perms on group itself.");
   $srv->addMethod("/getGroupPerms",\&getGroupPerms,"Get all users perms on a given group.");
   $srv->addMethod("/getGroupsByPerm",\&getGroupsByPerm,"Retrieves the group entities starting from given entity root matched against a bitmask for the user.");
   $srv->addMethod("/getGroupTaskAssignments",\&getGroupTaskAssignments,"Get the task assignments of a group.");
   $srv->addMethod("/getGroupUsersVotes",\&getGroupUsersVotes,"Get the votes for users on a given group.");   
   $srv->addMethod("/moveGroup",\&moveGroup,"Move a group to another parent group.");
   $srv->addMethod("/setGroupFileInterfaceStore",\&setGroupFileInterfaceStore,"Set FI store of group.");
   $srv->addMethod("/setGroupName",\&setGroupName,"Set or change name of group.");
   $srv->addMethod("/setGroupNoticeSubscriptions",\&setGroupNoticeSubscriptions,"Set or change the notice subscriptions of users on a given group.");
   $srv->addMethod("/setGroupPerm",\&setGroupPerm,"Set perm on group.");
   $srv->addMethod("/setGroupTaskAssignments",\&setGroupTaskAssignments,"Set the group task assignments.");
   $srv->addMethod("/setGroupUsersVotes",\&setGroupUsersVotes,"Set or change the votes for users on a given group.");
}

sub addGroupMember {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{object}=$query->{id};
   $opt{subjects}=$query->{member};
   $opt{type}="GROUP";
   MethodsReuse::addEntityMember($mess,\%opt,$db,$userid);

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

sub assignGroupTemplate {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $type=$Schema::CLEAN{entitytypename}->($query->{type});
   my $ids=$query->{templates};

   # check that id is a template
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Group $id does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["GROUP_TEMPLATE_ASSIGN"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the GROUP_TEMPLATE_ASSIGN permission on the GROUP $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # check that we have a LIST ref
   if ((defined $ids) && (ref($ids) ne "ARRAY")) {
      # missing template id(s)
      $content->value("errstr","Template ids are not an array. Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   if ((!defined $type) || ($type eq "")) {
      # missing type
      $content->value("errstr","Missing type-parameter. Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   # convert type to type id, if it exists at all
   my $typeid=($db->getEntityTypeIdByName($type))[0];
   if (!defined $typeid) {
      # missing type id
      $content->value("errstr","Type assignment \"$type\" does not exist. Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   # we are ready to attempt assignment
   if ($db->assignEntityTemplate($id,$typeid,@{$ids})) {
      # success
      $content->value("errstr","");
      $content->value("err",0);
      return 1;      
   } else {
      # failed for some reason
      $content->value("errstr","Failed to assign template(s) to group $id of type $type: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub unassignGroupTemplate {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $type=$Schema::CLEAN{entitytypename}->($query->{type});

   # check that id is a template
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Group $id does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["GROUP_TEMPLATE_ASSIGN"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the GROUP_TEMPLATE_ASSIGN permission on the GROUP $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   if ((!defined $type) || ($type eq "")) {
      # missing type
      $content->value("errstr","Missing type-parameter. Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   # convert type to type id, if it exists at all
   my $typeid=($db->getEntityTypeIdByName($type))[0];
   if (!defined $typeid) {
      # missing type id
      $content->value("errstr","Type assignment \"$type\" does not exist. Unable to fulfill the request.");
      $content->value("err",1);
      return 0;
   }

   # we are ready to attempt unassignment
   if ($db->unassignEntityTemplate($id,$typeid)) {
      # success
      $content->value("errstr","");
      $content->value("err",0);
      return 1;      
   } else {
      # failed for some reason
      $content->value("errstr","Failed to unassign template(s) for group $id of type $type: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub createGroup {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $name=$SysSchema::CLEAN{entityname}->($query->{name}); # if name is set in metadata, it will override this parameter
   my $metadata=$SysSchema::CLEAN{metadata}->($query->{metadata}); # clean away system-metadata

   # check that parent is a group
   if ((!$db->existsEntity($parent)) || ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$parent,["GROUP_CREATE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the GROUP_CREATE permission on the GROUP $parent. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # get name from metadata if it is there, ignoring what is set in name-parameter
   if (exists $metadata->{$SysSchema::MD{name}}) { $name=$SysSchema::CLEAN{entityname}->($metadata->{$SysSchema::MD{name}}); }

   # check name
   if ((!defined $name) || ($name eq "")) {
      # name does not fulfill minimum criteria
      $content->value("errstr","Group name is missing and does not fulfill minimum requirements. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # get parent-entitys GROUP-children and check if name exists already
   my @type=($db->getEntityTypeIdByName("GROUP"))[0];
   my $children=$db->getEntityChildren($parent,\@type);
   if (!defined $children) {
      $content->value("errstr","Unable to get children of parent $parent: ".$db->error().". Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }
   my $names;
   if (@{$children} > 0) { $names=$db->getEntityMetadataList($SysSchema::MD{name},$children); }

   # check name case-insensitive
   foreach (keys %{$names}) {
      my $entid=$_;

      if (lc($names->{$entid}||"NOT DEFINED") eq lc($name)) {
         # we already have this name at this level - abort
         $content->value("errstr","Group name already exists as a child of parent $parent. Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      }
   }

   # add name to metadata (again if already there)
   $metadata->{$SysSchema::MD{name}}=$name;
   # we are ready to create group, start transaction already out here
   my $trans=$db->useDBItransaction();
   my $id=$db->createEntity($type[0],$parent);

   if (defined $id) {
      # group created
      $metadata->{$SysSchema::MD{"entity.id"}}=$id;
      $metadata->{$SysSchema::MD{"entity.parent"}}=$parent;
      $metadata->{$SysSchema::MD{"entity.type"}}=($db->getEntityTypeIdByName("GROUP"))[0];

      # set metadata
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
         $content->value("errstr","Unable to create GROUP: ".$db->error());
         $content->value("err",1);
         return 0;
      }
   } else {
      # some error
      $content->value("errstr","Unable to create group: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub deleteGroup {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="GROUP";
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

sub enumGroups {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="GROUP";
   MethodsReuse::enumEntities($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("groups",$mess->value("groups"));
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

sub removeGroupMember {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{object}=$query->{id};
   $opt{subjects}=$query->{member};
   $opt{type}="GROUP";
   MethodsReuse::removeEntityMember($mess,\%opt,$db,$userid);

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

sub enumGroupPermTypes {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="GROUP";
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

sub getGroupAggregatedPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # group to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="GROUP";   
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

sub getGroupMembers {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id};

   # check that parent is a group
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","GROUP $id does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["GROUP_MEMBER_ADD"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the GROUP_MEMBER_ADD permission on the GROUP $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }
   
   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="GROUP";
   MethodsReuse::getEntityMembers($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("members",$mess->value("members"));
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

sub getGroupName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="GROUP";
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

sub getGroupNoticeSubscriptions {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get id of group
   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that id is valid and of type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist or invalid
      $content->value("errstr","GROUP $id does not exist or is not a GROUP-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # ready to get subscriptions
   my @md;
   push @md,$SysSchema::MD{"notice.subscribe"}.".*";
   my $res=$db->getEntityMetadata($id,@md);
   if (defined $res) {
      # success - get all assignments
      my $mdc=MetadataCollection->new(base=>$SysSchema::MD{"notice.subscribe"});
      my $ahash=$mdc->metadata2Hash($res);

      $content->value("subscriptions",$ahash);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed to get default
      $content->value("errstr","Unable to get GROUP $id notice subscriptions: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getGroupPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # group to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="GROUP";   
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

sub getGroupPerms {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # group to get perms on

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{type}="GROUP";
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

sub getGroupsByPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{root}=$query->{root};
   $opt{perm}=$query->{perm};
   $opt{permtype}=$query->{permtype};
   $opt{entitytype}=["GROUP"];
   MethodsReuse::getEntitiesByPermAndType($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success - get entities
      my @groups=@{$mess->value("entities")};
      # go through each group and get its name
      my $m=$db->getEntityMetadataList($SysSchema::MD{name},\@groups);
      if (!defined $m) {
         # something failed
         $content->value("errstr","Unable to get metadata of groups: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      }

      # go through each group and explicitly create return hash
      # in case a group lacks a name
      my %groups;
      foreach (@groups) {
         my $group=$_;

         $groups{$group}=$m->{$group} || "";
      }
      # set return values
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("groups",\%groups);
      return 1;
   } else {
      # failure
      $content->value("errstr","Unable to fetch groups: ".$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub getGroupTaskAssignments {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="GROUP";
   MethodsReuse::getEntityTaskAssignments($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("assignments",$mess->value("assignments"));
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

sub getGroupUsersVotes {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get id of group
   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that id is valid and of type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist or invalid
      $content->value("errstr","GROUP $id does not exist or is not a GROUP-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # ready to get votes
   my @md;
   push @md,$SysSchema::MD{"notice.votes"}.".*";
   my $res=$db->getEntityMetadata($id,@md);
   if (defined $res) {
      # success - get all assignments
      my $mdc=MetadataCollection->new(base=>$SysSchema::MD{"notice.votes"});
      my $ahash=$mdc->metadata2Hash($res);

      $content->value("votes",$ahash);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed to get default
      $content->value("errstr","Unable to get GROUP $id users votes: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub moveGroup {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check ids type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Group $id does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check parents type
   if ((!$db->existsEntity($parent)) || ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Parent group $parent does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # get GROUPS name
   my $res=$db->getEntityMetadata($id,$SysSchema::MD{name});
   if (!defined $res) {
      $content->value("errstr","Unable to get metadata of GROUP $id: ".$db->error().". Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }
   my $name=$res->{$SysSchema::MD{name}} || "NOT DEFINED";

   # get parent-entities GROUP-children and check if name exists already
   my @type=($db->getEntityTypeIdByName("GROUP"))[0];
   my $children=$db->getEntityChildren($parent,\@type);
   if (!defined $children) {
      $content->value("errstr","Unable to get children of parent GROUP $parent: ".$db->error().". Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }
   my $names;
   if (@{$children} > 0) { $names=$db->getEntityMetadataList($SysSchema::MD{name},$children); }

   # check name case-insensitive
   foreach (keys %{$names}) {
      my $entid=$_;

      if (lc($names->{$entid}||"NOT DEFINED") eq lc($name)) {
         # we already have this name at this level - abort
         $content->value("errstr","Group name already exists as a child of parent $parent. Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      }
   }

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{parent}=$query->{parent};
   $opt{type}="GROUP";
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

sub setGroupFileInterfaceStore {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # entity to set FI-store on
   my $name=$SysSchema::CLEAN{"fi.store"}->($query->{store}); # FI store-name to use

   # check that id is valid
   if ((!$db->existsEntity($id) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0]))) {
      # does not exist 
      $content->value("errstr","GROUP $id does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["GROUP_FILEINTERFACE_STORE_SET"],"ALL","ANY",1,1,undef,1);

   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the GROUP_FI_STORE_CHANGE permission on the GROUP $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # everything that is not blank, is to be checked
   if ($name ne "") {
      # open FI and attempt to check if store is acceptable or not?
      my $ev=fiEval->new();
      if (!$ev->success()) {
         # unable to instantiate fiEval
         $content->value("errstr","Unable to instantiate fiEval-instance: ".$ev->error());
         $content->value("err",1);
         return 0;
      }

      # fi instantiated - check if proposed FI-store name is acceptable or not?   
      if (!$ev->evaluate("storewcheck",$name)) {
         # something failed...
         $content->value("errstr","FileInterface store-name was not approved: ".$ev->error());
         $content->value("err",1);
         return 0;
      }
   }

   # ready to attempt to set group fi-store name for group
   my %md;
   # in order to remove something from metadata, we need to pass an empty
   # array.
   my @list;
   if ($name ne "") { push @list,$name; }
   $md{$SysSchema::MD{"fi.store"}}=\@list;
   my $res=$db->setEntityMetadata ($id,\%md);
   if ($res) {
      $content->value("store",$name);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to set FileInterface-store of GROUP $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub setGroupName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{duplicates}=0;
   $opt{type}="GROUP";
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

sub setGroupNoticeSubscriptions {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get id and subscriptions
   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $set=$query->{subscriptions};

   # first check that user has the necessary permissions
   my $allowed=hasPerm($db,$userid,$id,["GROUP_CHANGE"],"ALL","ANY",undef,1,undef,1);
   if (!$allowed) {
      if (!defined $allowed) {
         # something failed with database operation
         $content->value("errstr","Unable to check your permissions on GROUP $id: ".$db->error()." Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      } else {
         # user does not have the required permission
         $content->value("errstr","You do not have the GROUP_CHANGE permission on GROUP $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # check that id is valid and of type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist or invalid
      $content->value("errstr","GROUP $id does not exist or is not a GROUP-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # ensure set is a hash
   if ((!defined $set) || (ref($set) ne "HASH")) {
      $content->value("errstr","Method parameter \"subscriptions\" is not a HASH or is not defined. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # go through set and check it
   my %nset; # new set after check
   foreach (keys %{$set}) {
      my $user=$_;
      $user=$Schema::CLEAN{entity}->($user);

      # check that user is valid and exists
      if (($db->existsEntity($user)) && ($db->getEntityType($user) == ($db->getEntityTypeIdByName("USER"))[0])) {
         # correct format, go through the sub-hash, if any
         if (ref($set->{$user}) eq "HASH") {
            # go through each notice and check that is is valid
            foreach (keys %{$set->{$user}}) {
               my $notice=$_;
               $notice=(defined $notice && $notice == 0 ? 0 : $Schema::CLEAN{entity}->($notice));

               if ( (($db->existsEntity($notice)) && ($db->getEntityType($notice) == ($db->getEntityTypeIdByName("NOTICE"))[0])) || ($notice == 0)) {
                  # this is a valid notice, check that its value is a scalar
                  if (ref(\$set->{$user}{$notice}) eq "SCALAR") {
                     # this is a SCALAR, do a boolean evaluation of its value
                     if ($set->{$user}{$notice}) { $nset{$user}{$notice}=1; }
                     else { $nset{$user}{$notice}=0; }
                  }
               }
            }
         }
      }                              
   }

   # convert new set to metadata
   my $mdc=MetadataCollection->new(base=>$SysSchema::MD{"notice.subscribe"},depth=>3);
   my $md=$mdc->hash2Metadata(\%nset);

   my $tr=$db->useDBItransaction();
   if (defined $tr) {
      # first delete all old task assignment metadata
      if (!$db->deleteEntityMetadata($id,[$SysSchema::MD{"notice.subscribe"}.".*"])) {
         $content->value("errstr","Unable to delete GROUP $id notice subscription before assigning new ones: ".$db->error());
         $content->value("err",1);
         return 0;
      }

      # ready to set subscriptions
      if ($db->setEntityMetadata($id,$md)) {
         # success
         $content->value("subscriptions",\%nset);
         $content->value("errstr","");
         $content->value("err",0);
         return 1;
      } else {
         $content->value("errstr","Unable to set notice subscriptions: ".$db->error());
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

sub setGroupPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # group to set perm on
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
   $opt{type}="GROUP";   
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

sub setGroupTaskAssignments {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{assignments}=$query->{assignments};
   $opt{type}="GROUP";
   MethodsReuse::setEntityTaskAssignments($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("assignments",$mess->value("assignments"));
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

sub setGroupUsersVotes {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get id and subscriptions
   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $set=$query->{votes};

   # first check that user has the necessary permissions
   my $allowed=hasPerm($db,$userid,$id,["GROUP_CHANGE"],"ALL","ANY",undef,1,undef,1);
   if (!$allowed) {
      if (!defined $allowed) {
         # something failed with database operation
         $content->value("errstr","Unable to check your permissions on GROUP $id: ".$db->error()." Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      } else {
         # user does not have the required permission
         $content->value("errstr","You do not have the GROUP_CHANGE permission on GROUP $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # check that id is valid and of type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist or invalid
      $content->value("errstr","GROUP $id does not exist or is not a GROUP-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # ensure set is a hash
   if ((!defined $set) || (ref($set) ne "HASH")) {
      $content->value("errstr","Method parameter \"set\" is not a HASH-reference or is not defined. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # go through set and check it
   my %nset; # new set after check
   foreach (keys %{$set}) {
      my $user=$_;
      $user=$Schema::CLEAN{entity}->($user);

      # check that user is valid and exists
      if (($db->existsEntity($user)) && ($db->getEntityType($user) == ($db->getEntityTypeIdByName("USER"))[0])) {
         # correct format, check that the key value is a SCALAR
         if (ref(\$set->{$user}) eq "SCALAR") {
            # this is a SCALAR, ensure that value is a valid number
            if ($set->{$user} =~ /^\d+$/) {
               # this is a valid number
               $nset{$user}=$set->{$user};
            }
         }
      }
   }

   # convert new set to metadata
   my $mdc=MetadataCollection->new(base=>$SysSchema::MD{"notice.votes"},depth=>2);
   my $md=$mdc->hash2Metadata(\%nset);

   my $tr=$db->useDBItransaction();
   if (defined $tr) {
      # first delete all old task assignment metadata
      if (!$db->deleteEntityMetadata($id,[$SysSchema::MD{"notice.votes"}.".*"])) {
         $content->value("errstr","Unable to delete GROUP $id users votes before assigning new ones: ".$db->error());
         $content->value("err",1);
         return 0;
      }

      # ready to set subscriptions
      if ($db->setEntityMetadata($id,$md)) {
         # success
         $content->value("votes",\%nset);
         $content->value("errstr","");
         $content->value("err",0);
         return 1;
      } else {
         $content->value("errstr","Unable to set users votes: ".$db->error());
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

=head1 GROUP METHODS

=head2 addGroupMember()

Add a member to a group.

Input parameters:

=over

=item

B<id> Group entity ID to add a member to. INTEGER. Required.

=cut

=item

B<member> Entities to add to the group. ARRAY of INTEGER. Required.

=cut

=back

This method requires that the user has the GROUP_MEMBER_ADD permission.

=cut

=head2 assignGroupTemplate()

Assign a templates on a group.

Input parameters:

=over

=item

B<id> Group entity ID from database to assign template on. INTEGER. Required.

=cut

=item

B<templates> The list of templates to assign on the group in desired order. ARRAY of INTEGER. Optional. The array contains 
template entity IDs from the database. If no template ids are specified the method will clear the assignments on the given 
type.

=cut

=item

B<type> The type that the assigned templates are to have on the group. STRING. Required. Denotes the entity type that 
the assigned template(s) will have effect as. Typically the value is: DATASET, GROUP and so on.

=cut

=back

This method requires that the user has the GROUP_TEMPLATE_ASSIGN permission on the group in question.

=cut

=head2 createGroup()

Create a new group.

Input parameters:

=over

=item

B<metadata> The metadata to set upon creating the dataset. HASH. Optional. If this is needed is dependant upon any 
templates that might be in effect. It can also be used to override the name-parameter if the key for an entity's name 
is filled in through the metadata (it will then take precedence over the name-parameter).

=cut

=item

B<name> The display name of the new group. STRING. Optional/Required. It is optional and will be ignored if specified 
through the metadata hash. If not specified in the metadata hash, it is required. It is not allowed with blank names or
just spaces.

=cut

=item

B<parent> Group entity ID from the database of the group that is the parent of the new group being created. INTEGER. 
Required.

=cut

=back

The method requires that the user has the GROUP_CREATE permission on the parent group of the group being created.

The method will fail to create the group, if any template(s) in effect for the group are not compliant.

Upon success will return the following values:

  id => INTEGER # group entity ID of the newly created group.
  name => STRING # the resulting (after cleaning) textual name of the newly created group.

=cut

=head2 deleteGroup()

Delete a group.

Input parameters:

=over

=item

B<id> The group entity ID from the database of the group to delete. INTEGER. Required.

=cut

=back

This method requires the user to have the GROUP_DELETE permission on the group being deleted.

It also requires that there are no children attached to the group being deleted. If so, these must 
either be moved somewhere else or deleted before attempting to delete the group in question.

=cut

=head2 enumGroupPermTypes()

Enumerate the group permissions types.

No input is accepted.

Upon success returns the following HASH-structure:

  types => ARRAY of STRING # name(s) of the group permission types.

=cut

=head2 enumGroups()

Enumerate all the groups that exists.

No input parameters are accepted.

Upon success will return the following HASH-structure:

  groups => (
              GROUPIDa => STRING # key->value, where key is the group entity ID and the value is the display name of the group.
              .
              .
              GROUPIDx => STRING
            )

=cut

=head2 getGroupAggregatedPerm()

Get inherited/aggregated permission(s) on the group for a user.

Input parameters:

=over

=item

B<id> Group entity ID from database to get the aggregated permission(s) of. INTEGER. Required.

=cut

=item

B<user> User entity ID from database that identifies who the permission(s) are valid for. INTEGER. Optional. If not specified 
it will default to the currently authenticated user on the REST-server.

=cut

=back

Upon success this method will return the following value:

  perm => ARRAY of STRING # textual names of the permimssion(s) the user has on the given group.

=cut

=head2 getGroupMembers()

Get the member(s) of a given group.

The following input parameters are accepted:

=over

=item

B<id> The group entity ID from the database of the group entity to get members of. INTEGER. Required.

=cut

=back

This method requires that the user has the GROUP_MEMBER_ADD permission.

Upon success will return the members of the given group in the following structure:

  members => (
               MEMBERa => STRING # textual name of the given member entity.
               .
               .
               MEMBERx => STRING

             )

MEMBERa and so on is the entity ID (INTEGER) of one of the member(s) in the given group.

=cut

=head2 getGroupName()

Get the display name of the group.

Input parameters:

=over

=item

B<id> Group entity ID of the group to get the name of. INTEGER. Required.

=cut

=back

Upon success returns the following value:

  name => STRING # the textual name of the group entity specified.

=cut

=head2 getGroupNoticeSubscriptions()

Get users notice subscriptions on a group.

Accepted parameters are:

=over

=item

B<id> Group ID from database of the group to get notice subscriptions on. INTEGER. Required.

=cut

=back

Upon success this method returns the following structure:

   subscriptions => {
                       USERa => {
                                  NOTICEb => INTEGER # Value must be boolean true/false and will be converted to 0/1.
                                  .
                                  .
                                  NOTICEz => INTEGER
                                }
                       .
                       .
                       USERz => { ... }
                    }

In this return structure "USERa" and so on is the user id from the database of the user that have subscription(s) to 
any of the notice classes. The next level in the HASH is the "NOTICEb" and so on, which is the notice id from the 
database of the notice that the user is subscribing to. Please note that this notice id is allowed to be 0 and will then 
signify that the user subscribes to all available Notice-classes.

=cut

=head2 getGroupPerm()

Get group permission(s) for a given user.

Input parameters:

=over

=item

B<id> Group entity ID from database of the group to get permission on. INTEGER. Required.

=cut

=item

B<user> User entity ID from database of the user which the permission(s) are valid for. INTEGER. Optional. If none 
is specified it will default to the authenticated user itself.

=cut

=back

Upon success returns the following structure:

  perm => (
            grant => ARRAY of STRING # permission(s) that have been granted on this group.
            deny => ARRAY of STRING # permission(s) that have been denied on this group.
          )

Please note that when these permissions are used by the system, what it finds for deny is applied before the grant-part 
is applied when it comes to effective permissions.

=cut

=head2 getGroupPerms()

Gets all the permission(s) on a given group entity, both inherited and what has been set and the effective perm for each 
user who has any permission(s).

Input parameters:

=over

=item

B<id> Group entity ID from database of the group to get the permissions of. INTEGER. Required.

=cut

=back

Upon success the resulting structure returned is:

  perms => (
             USERa => (
                        inherit => [ PERMa, PERMb .. PERMn ] # permissions inherited down on the group from above
                        deny => [ PERMa, PERMb .. PERMn ] # permissions denied on the given group itself.
                        grant => [ PERMa, PERMb .. PERMn ] # permissions granted on the given group itself. 
                        perm => [ PERMa, PERMb .. PERMn ] # effective permissions on the given group (result of the above)
                      )
             .
             .
             USERn => ( .. )
           )

USERa and so on are the USER entity ID from the database who have permission(s) on the given group. An entry for a user 
only exists if that user has any permission(s) on the group. The sub-key "inherit" is the inherited permissions from above 
in the entity tree. The "deny" permission(s) are the denied permission(s) set on the group itself. The "grant" permission(s) are 
the granted permission(s) set on the group itself. Deny is applied before grant. The sub-key "perm" is the effective or 
resultant permission(s) after the others have been applied on the given group.

The permissions that users has through groups on a given group are not expanded. This means that a group will be listed 
as having permissions on the group and in order to find out if the user has any rights, one has to check the membership of 
the group in question (if the user is listed there).

Permission information is open and requires no permission to be able to read. PERMa and so on are the textual permission 
type that are set on one of the four categories (inherit, deny, grant and/or perm). These four categories are ARRAYS of 
STRING. Some of the ARRAYS can be empty, although not all of them (then there would be no entry in the return perms for 
that user).

The perms-structure can be empty if no user has any permission(s) on the group.

=cut

=head2 getGroupsByPerm()

Get list of groups based upon a set of permissions.

Input parameters are:

=over

=item

B<perm> A set of permissions that has to exist on the group entities returned. ARRAY. Optional. If no values are specified 
all group entitites are returned.

=cut

=item

B<permtype> The matching criteria to use with the permissions specified in the "perm"-parameter. Valid values are: ALL (logical 
and) or ANY (logical or). STRING. Optional. If not specified will return all group entities.

=cut

=item

B<root> Entity ID of where to start in the entity tree (matching everything from there and below). INTEGER. Optional. If not 
specified will default to 1 (ROOT).

=cut

=back

The return structure upon success is:

  groups => (
              INTEGERa => STRING,
              INTEGERb => STRING,
              .
              .
              INTEGERn => STRING,
            )

where INTEGER is the group id from the database and STRING is the display name of the computer.

=cut

=head2 getGroupTaskAssignments()

Gets a group's task assignments.

Input parameters are:

=over

=item

B<id> Group ID from database to get the task assignments of. INTEGER. Required.

=cut

=back

Returns a HASH of task IDs assignments upon success. See the setGroupTaskAssignments()-method for more information upon 
its structure.

=cut

=head2 getGroupUsersVotes()

Gets the user(s) votes on a given group (if any).

Accepted input parameters are:

=over

=item

B<id> Group ID from database of group to get the users votes on. INTEGER. Required.

=cut

=back

Upon success this method returns the following HASH-structure:

   votes => {
               USERa => INTEGER
               USERb => INTEGER
               .
               .
               USERz => INTEGER
            }

The "USERa", "USERb" and so on here is the user id from the database and the INTEGER value is the number of votes that 
the user has on the given group.

=cut

=head2 moveGroup()

Moves a group entity to another part of the enitty tree.

Input is:

=over

=item

B<id> Group entity ID from the database of the group to move. INTEGER. Required.

=cut

=item

B<parent> Parent group entity ID from the database of the group which will be the new parent of the group. INTEGER. 
Required.

=cut

=back

The method requires the user to have the GROUP_MOVE permission on the group being moved and GROUP_CREATE on the 
parent group it is being moved to.

=cut

=head2 removeGroupMember()

Remove member(s) of a group.

Input parameters:

=over

=item

B<id> Group entity ID from the database of group to remove member(s) of. INTEGER. Required.

=cut

=item

B<member> Member(s) to remove from given group. ARRAY of INTEGER. Optional. If not specified will remove all
members of the given group.

=cut

=back

The method requires that the user has the GROUP_MEMBER_ADD permission on the group in question.

=cut

=head2 setGroupFileInterfaceStore()

Set the fileinterface(FI) store name on a given group entity.

Input accepts the following parameters:

=over

=item

B<id> ID of the group entity to set the fileinterface store name on. INTEGER. Required.

=cut

=item

B<store> Fileinterface store name to set on the entity group in question. STRING. Required.

=cut

=back

This method requires the user to have the GROUP_FILEINTERFACE_STORE_SET permission on the group in question.

It also requires the store-name to abide with the characters limitations set on such a name by the 
FileInterface(FI) layer. The store must also already exist and have been put in place for it to be used. All 
of this will be checked against the FI-layer before any setting is saved to the group entity.

=cut

=head2 setGroupName()

Set/edit the display name of a group.

Input accepts the following parameters:

=over

=item

B<id> Group entity ID from the database of the group to set name of. INTEGER. Required.

=cut

=item

B<name> New name of the group entity in question. STRING. Required. It does not accept blanks as a name.

=cut

=back

This method requires that the user has the GROUP_CHANGE permission on the group specified.

=cut

=head2 setGroupNoticeSubscriptions()

Sets the users notice subscriptions on a group.

Input parameters:

=over

=item

B<id> Group ID from database of the group to set the users notice subscriptions on. INTEGER. Required.

=cut

=item

B<subscriptions> The notice subscriptions to set on the given group. HASH. Required.

=cut

=back

This methods required that the user has the GROUP_CHANGE-permission on the group in question. Please also note 
that the subscriptions hash must include all previous subscriptions as well as new ones, since this method is 
basically a replace-method.

The subscriptions HASH structure is to be as follows:

   subscriptions => {
                       USERa => {
                                  NOTICEb => INTEGER # Value must be boolean true/false and will be converted to 0/1.
                                  .
                                  .
                                  NOTICEz => INTEGER
                                }
                       .
                       .
                       USERz => { ... }
                    }

In this return structure "USERa" and so on is the user id from the database of the user that have subscription(s) to 
any of the notice classes. The next level in the HASH is the "NOTICEb" and so on, which is the notice id from the 
database of the notice that the user is subscribing to. Please note that this notice id is allowed to be 0 and will then 
signify that the user subscribes to all available Notice-classes. We advise that notice-value is either set to 0 or 1, but 
it will be boolean-evaluated and then converted to 0/1 in any event.

When giving this method a HASH with the subscriptions settings, it will check that it contains valid user-references, 
valid notice-references and it will convert, as mentioned above, the notice value. If any value is not valid, it will 
be omitted from the HASH that is input to the system. This can in the worst case scenario create a situation where all 
current subscriptions on the given group are removed and none is set.

Upon success the method returns the subscriptions hash that was set in the key "subscriptions":

   subscriptions => { ... }

=cut

=head2 setGroupPerm()

Set permission(s) on the given group for a user.

Input parameters are:

=over

=item

B<id> Group entity ID from database of group to set perm on. INTEGER. Required.

=cut

=item

B<user> User entity ID from the database of the user to set permission for. INTEGER. Optional. If 
not specified will default to set permission for the user authenticated on the REST-server.

=cut

=item

B<operation> How to set the permissions on the group in question. STRING. Optional. If not 
specified will default to "APPEND". Accepted values are: "APPEND", "REPLACE" or "REMOVE".

=cut

=item

B<grant> The grant permission(s) to set on the group. ARRAY of STRING. Optional.

=cut

=item

B<deny> The deny permission(s) to set on the group. ARRAY of STRING. Optional.

=cut

=back

This method requires the user to have the GROUP_PERM_SET permission.

Upon success will return the following structure:

  perm => (
            grant => ARRAY    # STRINGs of permissions set
            deny => ARRAY     # STRINGs of permissions set
          )

This will be the grant- and deny- permissions that have ended up being set.

=cut

=head2 unassignGroupTemplate()

Unassign all template(s) of a given type from a group.

Input parameters are:

=over

=item

B<id> Group entity ID from the database of the group to unassign from. INTEGER. Required.

=cut

=item

B<type> Entity type to remove all templates for on given group. STRING. Required. Value is eg.: DATASET, GROUP and so on.

=cut

=back

This method requires that the user has the GROUP_TEMPLATE_ASSIGN permission on the group in
question.

=cut

=head2 setGroupTaskAssignments()

Sets a group's task assignments.

Input parameters are:

=over

=item

B<id> Group ID from database to set the task assignments of. INTEGER. Required.

=cut

=item

B<assignments> HASH of task IDs from database of the assignments to set. HASH. Required. This HASH sets which task ids to assign for every 
computer id mentioned in the HASH. It is required that the group that is to have the assignments have the TASK_READ permission the task(s) 
being assigned. Or else they cannot be used. If a task id is listed in the assignments that the group does not have the TASK_READ permission 
on it is omitted from the assignment.

=cut

=back

This method requires that the user has the GROUP_CHANGE permission on the computer having its 
assignments set. Furthermore, the method requires that the user has the TASK_EXECUTE-permission on the 
task(s) being added to computers.

The HASH-structure of the assignments is as follows:

  assignments => (
                   COMPUTERIDa => [TASKID1, TASKID2 .. TASKIDn]
                   .
                   .
                   COMPUTERIDz => ...
                 )

Returns the assignments actually set upon success in the same structure as setting the assignments.

Please note that the assignments given to this method overrides any previous assignments. To achieve 
append functionality one will need to read the current assignments first and append to that on the 
input to this method.

=cut

=head2 setGroupUsersVotes()

Sets the users votes on a group.

Input parameters:

=over

=item

B<id> Group ID from the database of the group to change the users votes on. INTEGER. Required.

=cut

=item

B<votes> The votes for users to set on the given group. HASH. Required. Please note that this HASH is a replace, so 
if one wants to keep old vote-settings, these needs to be included in addition to new ones.

=cut

=back

This methods requires that the user has the GROUP_CHANGE-permission on the group in question.

The votes-HASH is to have the following structure:

   votes => {
               USERa => INTEGER
               USERb => INTEGER
               .
               .
               USERz => INTEGER
            }

"USERa", "USERb" and so on is the user id from the database of the user to set votes for. The INTEGER-value is 
the number of votes to give that user on the given group in question. Please note that the specified user ids as well as 
the value is checked for sanity and if they are not ok, they will be omitted from the votes-settings actually written to the 
database.

For more information on how the voting-process is working, consult the overview-documentation on the Notification-service.

Upon success, this method returns the votes-HASH that was set:

   votes => { ... }

=cut
