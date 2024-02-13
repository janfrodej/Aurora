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
# MethodsTask: Task-entity methods for the AURORA REST-server
#
package MethodsTask;
use strict;
use RestTools;
use StoreCollection;

sub registermethods {
   my $srv = shift;

   $srv->addMethod("/createTask",\&createTask,"Create a task-entity.");
   $srv->addMethod("/deleteTask",\&deleteTask,"Delete a task-entity.");
   $srv->addMethod("/enumTasks",\&enumTasks,"Enumerate all task entities.");
   $srv->addMethod("/enumTasksOnEntity",\&enumTasksOnEntity,"Enumerate all tasks on a given entity.");
   $srv->addMethod("/enumTaskPermTypes",\&enumTaskPermTypes,"Enumerate all TASK permission types.");
   $srv->addMethod("/getTask",\&getTask,"Get a task definition.");
   $srv->addMethod("/getTaskAggregatedPerm",\&getTaskAggregatedPerm,"Get aggregated/inherited perm on task.");
   $srv->addMethod("/getTaskName",\&getTaskName,"Get name of the given task.");
   $srv->addMethod("/getTaskPerm",\&getTaskPerm,"Get perms on TASK itself.");
   $srv->addMethod("/getTaskPerms",\&getTaskPerms,"Get all users perms on a given TASK.");
   $srv->addMethod("/getTasksByPerm",\&getTasksByPerm,"Retrieves the TASK entities starting from given entity root matched against a bitmask for the user.");
   $srv->addMethod("/moveTask",\&moveTask,"Move a task to another parent computer, group or user.");
   $srv->addMethod("/setTask",\&setTask,"Set a task definition.");
   $srv->addMethod("/setTaskName",\&setTaskName,"Set or change name of task.");
   $srv->addMethod("/setTaskPerm",\&setTaskPerm,"Set perm on task.");
}

sub createTask {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $name=$SysSchema::CLEAN{entityname}->($query->{name}); # if name is set in metadata, it will override this parameter
   my $metadata=$SysSchema::CLEAN{metadata}->($query->{metadata}); # clean away system-metadata

   # check that parent is a computer, group or user
   if ((!$db->existsEntity($parent)) || (($db->getEntityType($parent) != ($db->getEntityTypeIdByName("COMPUTER"))[0]) &&
                                         ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0]) &&
                                         ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("USER"))[0]))) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a COMPUTER-, GROUP- or USER-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$parent,["TASK_CREATE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the TASK_CREATE permission on the parent $parent. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # get name from metadata if it is there, ignoring what is set in name-parameter
   if (exists $metadata->{$SysSchema::MD{name}}) { $name=$SysSchema::CLEAN{entityname}->($metadata->{$SysSchema::MD{name}}); }

   # check name
   if ((!defined $name) || ($name eq "")) {
      # name does not fulfill minimum criteria
      $content->value("errstr","Task name is missing and does not fulfill minimum requirements. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # add name to metadata (again if already there)
   $metadata->{$SysSchema::MD{name}}=$name;
   # we are ready to create group, start transaction already out here
   my $trans=$db->useDBItransaction();
   my $id=$db->createEntity($db->getEntityTypeIdByName("TASK"),$parent);

   if (defined $id) {
      # task created
      $metadata->{$SysSchema::MD{"entity.id"}}=$id;
      $metadata->{$SysSchema::MD{"entity.parent"}}=$parent;
      $metadata->{$SysSchema::MD{"entity.type"}}=($db->getEntityTypeIdByName("TASK"))[0];

      # set name (and other stuff)
      my $res=$db->setEntityMetadata($id,$metadata);

      if ($res) {
         # succeeded in setting name - return the task id and resulting name after cleaning
         $content->value("id",$id);
         $content->value("name",$name);
         $content->value("errstr","");
         $content->value("err",0);
         return 1;
      } else {
         # some error
         $content->value("errstr","Unable to create task: ".$db->error());
         $content->value("err",1);
         return 0;
      }
   } else {
      # some error
      $content->value("errstr","Unable to create task: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub deleteTask {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="TASK";
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

sub enumTasks {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="TASK";
   MethodsReuse::enumEntities($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("tasks",$mess->value("tasks"));
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

sub enumTasksOnEntity {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that entity is valid
   if ((!$db->existsEntity($id)) || (($db->getEntityType($id) != ($db->getEntityTypeIdByName("COMPUTER"))[0]) &&
                                     ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0]) &&
                                     ($db->getEntityType($id) != ($db->getEntityTypeIdByName("USER"))[0]))) {
      # does not exist 
      $content->value("errstr","Entity $id does not exist or is not a COMPUTER-, GROUP- or USER-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   my $children=$db->getEntityChildren($id,[$db->getEntityTypeIdByName("TASK")]);
   if (defined $children) {
      # get the name of all children
      my $names=$db->getEntityMetadataList($SysSchema::MD{name},$children);
      # go through each child and create hash return structure
      my %tasks;
      foreach (@{$children}) {
         my $child=$_;
         $tasks{$child}=$names->{$child} || "N/A";
      }
      # success 
      $content->value("tasks",\%tasks);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr","Unable to get children of entity: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub enumTaskPermTypes {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="TASK";
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

sub getTask {
   my ($content,$query,$db,$userid,$cfg,$log,$override)=@_;

   # clean entity id
   my $id=$Schema::CLEAN{entity}->($query->{id});

   # decide if we can override perms requirements or not?
   $override=$override || 0;

   # check existence and type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("TASK"))[0])) {
      # does not exist 
      $content->value("errstr","Task $id does not exist or is not a TASK-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["TASK_CHANGE","TASK_READ"],"ALL","ANY",1,1,undef,1);
   # override flag, which can only be used internally overrides need to have permissions to read the task (used by the system)
   if ((defined $allowed) && (!$allowed) && ($override)) { $allowed=1; }
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the TASK_READ or TASK_CHANGE permission on the task $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # get all of entities metadata
   my $md=$db->getEntityMetadata($id);

   if (defined $md) {
      # we got metadata - get the task definition
      my $sc=StoreCollection->new(base=>$SysSchema::MD{"storecollection.base"});
      # convert metadata to storecollection hash
      my $task=$sc->metadata2Hash($md);

      # we have the name, get it
      my $name=$md->{$SysSchema::MD{name}} || "UNDEFINED";

      # return the hash
      $content->value("task",$task);
      $content->value("name",$name);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # something failed
      $content->value("errstr","Unable to fetch task definition: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getTaskAggregatedPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # task to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="TASK";   
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

sub getTaskName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="TASK";
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

sub getTaskPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # task to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="TASK";   
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

sub getTaskPerms {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # group to get perms on

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{type}="TASK";
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

sub getTasksByPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{root}=$query->{root};
   $opt{perm}=$query->{perm};
   $opt{permtype}=$query->{permtype};
   $opt{entitytype}=["TASK"];
   MethodsReuse::getEntitiesByPermAndType($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success - get entities
      my @tasks=@{$mess->value("entities")};
      # go through each group and get its name
      my $m=$db->getEntityMetadataList($SysSchema::MD{name},\@tasks);
      if (!defined $m) {
         # something failed
         $content->value("errstr","Cannot get metadata of tasks: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      }

      # build return hash just in case name(s) are missing for tasks.
      my %tasks;
      foreach (@tasks) {
         my $task=$_;

         $tasks{$task}=$m->{$task} || "";
      }
      # set return values
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("tasks",\%tasks);
      return 1;
   } else {
      # failure
      $content->value("errstr","Unable to fetch groups: ".$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub moveTask {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check ids type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("TASK"))[0])) {
      # does not exist 
      $content->value("errstr","Task $id does not exist or is not a TASK entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check parents type
   if ((!$db->existsEntity($parent)) || (($db->getEntityType($parent) != ($db->getEntityTypeIdByName("COMPUTER"))[0]) &&
                                         ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0]) &&
                                         ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("USER"))[0]))) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a COMPUTER-, GROUP- or USER-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # get TASKS name
   my $res=$db->getEntityMetadata($id,$SysSchema::MD{name});
   if (!defined $res) {
      # something failed
      $content->value("errstr","Cannot get metadata of TASK $id: ".$db->error().". Unable to fulfill request.");
      $content->value("err",1);
      return 0;      
   }
   my $name=$res->{$SysSchema::MD{name}} || "NOT DEFINED";

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{parent}=$parent;
   $opt{type}="TASK";
   my $ptyp=$db->getEntityTypeName($parent);
   if (!defined $ptyp) {
      # something failed
      $content->value("errstr","Cannot get type name of PARENT $parent: ".$db->error().". Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }
   $opt{parenttype}=$ptyp;
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

sub setTask {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get task id to change definition on
   my $id=$Schema::CLEAN{entity}->($query->{id});
   # the new definition to set (overwriting old)
   my $task=$query->{task};
   # add name, optional
   my $name=$query->{name};

   # check existence and type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("TASK"))[0])) {
      # does not exist 
      $content->value("errstr","Task $id does not exist or is not a TASK-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["TASK_CHANGE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the TASK_CHANGE permission on the task $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # check that task is a HASH-ref
   if ((!defined $task) || (ref($task) ne "HASH")) {
      # wrong type, failure
      $content->value("errstr","Task is not defined or is not a HASH. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # start transaction mode
   my $trans=$db->useDBItransaction();

   # attempt to set task name, if defined
   if (defined $name) {
      my $class=ref($content);
      my $mess=$class->new();
      my %opt;
      $opt{id}=$query->{id};
      $opt{duplicates}=1;
      $opt{type}="TASK";
      $opt{name}=$name;
      # attempt to set name
      MethodsReuse::setEntityName($mess,\%opt,$db,$userid,$cfg,$log);

      # check result
      if ($mess->value("err") != 0) {
         # failure
         $trans->rollback();
	 $content->value("errstr","Unable to set task $id: ".$mess->value("errstr"));
         $content->value("err",1);
         return 0;
      }
   }

   # convert task to metadata
   my $sc=StoreCollection->new(base=>$SysSchema::MD{"storecollection.base"});
   # convert task hash to actual metadata
   my $md=$sc->hash2Metadata($task);
   # convert metedata result back to a StoreCollection HASH
   my $nscoll=$sc->metadata2Hash($md);

   # first remove all existing storecollection metadata on entity
   my $delete=$SysSchema::MD{"storecollection.base"}.".*";
   if (!defined $db->deleteEntityMetadata($id,\@{[$delete]})) {
      # something failed removing storecollection metadata
      $trans->rollback();
      $content->value("errstr","Existing task metadata could not be deleted: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # set storecollection-metadata on entity
   if ($db->setEntityMetadata($id,$md)) {
      # success - return the storecollection that was set
      $content->value("task",$nscoll);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # something failed
      $trans->rollback();
      $content->value("errstr","Unable to set task metadata: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub setTaskName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{duplicates}=1;
   $opt{type}="TASK";
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

sub setTaskPerm {
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
   $opt{type}="TASK";   
   # attempt to set task perm
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

=head1 TASK METHODS

=head2 createTask()

Create a new task.

Input parameters:

=over

=item

B<metadata> The metadata to set upon creating the task. HASH. Optional. If this is needed is dependant upon any 
templates that might be in effect. It can also be used to override the name-parameter if the key for an entity's name 
is filled in through the metadata (it will then take precedence over the name-parameter).

=cut

=item

B<name> The display name of the new task. STRING. Optional/Required. It is optional and will be ignored if specified 
through the metadata hash. If not specified in the metadata hash, it is required. It is not allowed with blank names or
just spaces.

=cut

=item

B<parent> Entity ID from the database of the entity that is the parent of the new task being created. INTEGER. 
Required. The parent can either be a COMPUTER, GROUP or USER entity.

=cut

=back

The method requires that the user has the TASK_CREATE permission on the parent of the task being created.

The method will fail to create the task, if any template(s) in effect for the task are not compliant.

Upon success will return the following values:

  id => INTEGER # task entity ID of the newly created task.
  name => STRING # the resulting (after cleaning) textual name of the newly created task.

=cut

=head2 deleteTask()

Delete a task.

Input parameters:

=over

=item

B<id> The task entity ID from the database of the task to delete. INTEGER. Required.

=cut

=back

This method requires the user to have the TASK_DELETE permission on the task being deleted.

=cut

=head2 enumTaskPermTypes()

Enumerate the task permissions types.

No input is accepted.

Upon success returns the following HASH-structure:

  types => ARRAY of STRING # name(s) of the task permission types.

=cut

=head2 enumTasks()

Enumerate all the tasks that exists.

No input parameters are accepted.

Upon success will return the following HASH-structure:

  tasks => (
              TASKIDa => STRING # key->value, where key is the task entity ID and the value is the display name of the task.
              .
              .
              TASKIDx => STRING
            )

=cut

=head2 getTask()

Gets a task definition.

Input parameter is:

=over

=item

B<id> Task entity ID from database to get the definition of. INTEGER. Required.

=cut

=back

This method requires that the user has either the TASK_READ or TASK_CHANGE permission on the task in question.

Upon success returns the same structure as input to the setTask-method (see setTask()-method for more information).

=cut

=head2 getTaskAggregatedPerm()

Get inherited/aggregated permission(s) on the task for a user.

Input parameters:

=over

=item

B<id> Task entity ID from database to get the aggregated permission(s) of. INTEGER. Required.

=cut

=item

B<user> User entity ID from database that identifies who the permission(s) are valid for. INTEGER. Optional. If not specified 
it will default to the currently authenticated user on the REST-server.

=cut

=back

Upon success this method will return the following value:

  perm => ARRAY of STRING # textual names of the permimssion(s) the user has on the given task.

=cut

=head2 getTaskName()

Get the display name of the task.

Input parameters:

=over

=item

B<id> Task entity ID of the task to get the name of. INTEGER. Required.

=cut

=back

Upon success returns the following value:

  name => STRING # the textual name of the task entity specified.

=cut

=head2 getTaskPerm()

Get task permission(s) for a given user.

Input parameters:

=over

=item

B<id> Task entity ID from database of the task to get permission on. INTEGER. Required.

=cut

=item

B<user> User entity ID from database of the user which the permission(s) are valid for. INTEGER. Optional. If none 
is specified it will default to the authenticated user itself.

=cut

=back

Upon success returns the following structure:

  perm => (
            grant => ARRAY of STRING # permission(s) that have been granted on this task.
            deny => ARRAY of STRING # permission(s) that have been denied on this task.
          )

Please note that when these permissions are used by the system, what it finds for deny is applied before the grant-part 
is applied when it comes to effective permissions.

=cut

=head2 getTaskPerms()

Gets all the permission(s) on a given task entity, both inherited and what has been set and the effective perm for each 
user who has any permission(s).

Input parameters:

=over

=item

B<id> Task entity ID from database of the group to get the permissions of. INTEGER. Required.

=cut

=back

Upon success the resulting structure returned is:

  perms => (
             USERa => (
                        inherit => [ PERMa, PERMb .. PERMn ] # permissions inherited down on the task from above
                        deny => [ PERMa, PERMb .. PERMn ] # permissions denied on the given task itself.
                        grant => [ PERMa, PERMb .. PERMn ] # permissions granted on the given task itself. 
                        perm => [ PERMa, PERMb .. PERMn ] # effective permissions on the given task (result of the above)
                      )
             .
             .
             USERn => ( .. )
           )

USERa and so on are the USER entity ID from the database who have permission(s) on the given task. An entry for a user 
only exists if that user has any permission(s) on the task. The sub-key "inherit" is the inherited permissions from above 
in the entity tree. The "deny" permission(s) are the denied permission(s) set on the task itself. The "grant" permission(s) are 
the granted permission(s) set on the task itself. Deny is applied before grant. The sub-key "perm" is the effective or 
resultant permission(s) after the others have been applied on the given task.

The permissions that users has through groups on a given task are not expanded. This means that a group will be listed 
as having permissions on the task and in order to find out if the user has any rights, one has to check the membership of 
the group in question (if the user is listed there).

Permission information is open and requires no permission to be able to read. PERMa and so on are the textual permission 
type that are set on one of the four categories (inherit, deny, grant and/or perm). These four categories are ARRAYS of 
STRING. Some of the ARRAYS can be empty, although not all of them (then there would be no entry in the return perms for 
that user).

The perms-structure can be empty if no user has any permission(s) on the task.

=cut

=head2 getTasksByPerm()

Get list of tasks based upon a set of permissions.

Input parameters are:

=over

=item

B<perm> A set of permissions that has to exist on the task entities returned. ARRAY. Optional. If no values are specified 
all task entitites are returned.

=cut

=item

B<permtype> The matching criteria to use with the permissions specified in the "perm"-parameter. Valid values are: ALL (logical 
and) or ANY (logical or). STRING. Optional. If not specified will return all task entities.

=cut

=item

B<root> Entity ID of where to start in the entity tree (matching everything from there and below). INTEGER. Optional. If not 
specified will default to 1 (ROOT).

=cut

=back

The return structure upon success is:

  tasks => (
              INTEGERa => STRING,
              INTEGERb => STRING,
              .
              .
              INTEGERn => STRING,
            )

where INTEGER is the task id from the database and STRING is the display name of the computer.

=cut

=head2 moveTask()

Moves a group entity to another part of the enitty tree.

Input is:

=over

=item

B<id> Task entity ID from the database of the task to move. INTEGER. Required.

=cut

=item

B<parent> Parent entity ID from the database of the entity which will be the new parent of the task. INTEGER. 
Required. The parent entity can either be a COMPUTER-, GROUP- or USER-entity.

=cut

=back

The method requires the user to have the TASK_MOVE permission on the task being moved and [COMPUTER|GROUP|USER]_CREATE on the 
parent it is being moved to.

=cut

=head2 setTask()

Sets the task definition.

Input parameters are:

=over

=item

B<id> Task entity ID from database to set the definition of. INTEGER. Required.

=cut

=item

B<name> Task name. STRING. Optional. If not specified will continue to use existing name. If specified will 
attempt to update the name. The name does not need to be unique.

=cut

=item

B<task> The task definition to set. HASH. Required.

=cut

=back

The task HASH structure is as follows:

  name => STRING # name of task itself
  task => (
             get  => (      # all the get-operations to run on computer
                       1 => (
                              name => STRING
                              store => INTEGER
                              classparam => (
                                              someparam => STRING,
                                              someotherparam => STRING,
                                            )
                              param => (
                                         param1 => STRING,
                                         param2 => STRING,
                                       )
                            )
                       .
                       .
                       N = ( ... )

                     )
             put  => ( ... )     # all the put-operations to run on computer
          )

The task definition basically defines the set of get- and put- operations to run on a computer when it archives. Manual 
datasets only utilizes the "put"-part of the task, since the data in that type of dataset is put in place
manually by the user. When it comes to automated datasets, the "get"-part is run first in order to fetch the data. The 
"get"-part can contain several Store-types to fetch data and various parameters. Both the "get" and "put" part of the 
task has the same structure and can contain several elements or operations numbered 1 to N.

When the "get"-process is finished successfully, if run at all as with manual datasets, the "put"-processes are run. The 
put-process is basically triggered by the dataset being closed.

Be aware also that tasks can be run manually by the user.

This method required the user to have the TASK_CHANGE permission on the task having its definition set.

=cut

=head2 setTaskName()

Set/edit the display name of a task.

Input accepts the following parameters:

=over

=item

B<id> Task entity ID from the database of the task to set name of. INTEGER. Required.

=cut

=item

B<name> New name of the task entity in question. STRING. Required. It does not accept blanks as a name.

=cut

=back

This method requires that the user has the TASK_CHANGE permission on the task specified.

=cut

=head2 setTaskPerm()

Set permission(s) on the given task for a user.

Input parameters are:

=over

=item

B<id> Task entity ID from database of task to set perm on. INTEGER. Required.

=cut

=item

B<user> User entity ID from the database of the user to set permission for. INTEGER. Optional. If 
not specified will default to set permission for the user authenticated on the REST-server.

=cut

=item

B<operation> How to set the permissions on the task in question. STRING. Optional. If not 
specified will default to "APPEND". Accepted values are: "APPEND", "REPLACE" or "REMOVE".

=cut

=item

B<grant> The grant permission(s) to set on the task. ARRAY of STRING. Optional.

=cut

=item

B<deny> The deny permission(s) to set on the task. ARRAY of STRING. Optional.

=cut

=back

This method requires the user to have the TASK_PERM_SET permission.

Upon success will return the following structure:

  perm => (
            grant => ARRAY    # STRINGs of permissions set
            deny => ARRAY     # STRINGs of permissions set
          )

This will be the grant- and deny- permissions that have ended up being set.

=cut

