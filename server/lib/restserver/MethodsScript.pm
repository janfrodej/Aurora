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
# MethodsScript: Script-entity methods for the AURORA REST-server
#
package MethodsScript;
use strict;
use RestTools;
use MetadataCollection;

sub registermethods {
   my $srv = shift;

   $srv->addMethod("/createScript",\&createScript,"Create a script-entity.");
   $srv->addMethod("/deleteScript",\&deleteScript,"Delete a script-entity.");
   $srv->addMethod("/enumScripts",\&enumScripts,"Enumerate all script entities.");
   $srv->addMethod("/enumScriptsOnEntity",\&enumScriptsOnEntity,"Enumerate all scripts on a given entity.");
   $srv->addMethod("/enumScriptPermTypes",\&enumScriptPermTypes,"Enumerate all script permission types.");
   $srv->addMethod("/getScript",\&getScript,"Get a scripts code.");
   $srv->addMethod("/getScriptName",\&getScriptName,"Get name of the given script.");
   $srv->addMethod("/getScriptPerm",\&getScriptPerm,"Get perms on a script itself.");
   $srv->addMethod("/getScriptPerms",\&getScriptPerms,"Get all users with perms on a script.");
   $srv->addMethod("/moveScript",\&moveScript,"Move a script to another parent computer, group or user.");
   $srv->addMethod("/setScript",\&setScript,"Set a script definition.");
   $srv->addMethod("/setScriptName",\&setScriptName,"Set or change name of script.");
   $srv->addMethod("/setScriptPerm",\&setScriptPerm,"Set perm on script.");
}

sub createScript {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $name=$SysSchema::CLEAN{entityname}->($query->{name}); # if name is set in metadata, it will override this parameter
   my $metadata=$SysSchema::CLEAN{metadata}->($query->{metadata}); # clean away system-metadata

   # check that parent is a GROUP
   if ((!$db->existsEntity($parent)) || ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$parent,["SCRIPT_CREATE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the SCRIPT_CREATE permission on the parent $parent. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # get name from metadata if it is there, ignoring what is set in name-parameter
   if (exists $metadata->{$SysSchema::MD{name}}) { $name=$SysSchema::CLEAN{entityname}->($metadata->{$SysSchema::MD{name}}); }

   # check name
   if ((!defined $name) || ($name eq "")) {
      # name does not fulfill minimum criteria
      $content->value("errstr","Script name is missing and does not fulfill minimum requirements. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # add name to metadata (again if already there)
   $metadata->{$SysSchema::MD{name}}=$name;
   # we are ready to create script, start transaction already out here
   my $trans=$db->useDBItransaction();
   my $id=$db->createEntity($db->getEntityTypeIdByName("SCRIPT"),$parent);

   if (defined $id) {
      # script created
      $metadata->{$SysSchema::MD{"entity.id"}}=$id;
      $metadata->{$SysSchema::MD{"entity.parent"}}=$parent;
      $metadata->{$SysSchema::MD{"entity.type"}}=($db->getEntityTypeIdByName("SCRIPT"))[0];

      # set name (and other stuff)
      my $res=$db->setEntityMetadata($id,$metadata);

      if ($res) {
         # succeeded in setting name - return the script id and resulting name after cleaning
         $content->value("id",$id);
         $content->value("name",$name);
         $content->value("errstr","");
         $content->value("err",0);
         return 1;
      } else {
         # some error
         $content->value("errstr","Unable to create script: ".$db->error());
         $content->value("err",1);
         return 0;
      }
   } else {
      # some error
      $content->value("errstr","Unable to create script: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub deleteScript {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="SCRIPT";
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

sub enumScripts {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="SCRIPT";
   MethodsReuse::enumEntities($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("scripts",$mess->value("script"));
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

sub enumScriptsOnEntity {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that entity is valid
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Entity $id does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   my $children=$db->getEntityChildren($id,[$db->getEntityTypeIdByName("SCRIPT")]);
   if (defined $children) {
      # get the name of all children
      my $names=$db->getEntityMetadataList($SysSchema::MD{name},$children);
      # go through each child and create hash return structure
      my %scripts;
      foreach (@{$children}) {
         my $child=$_;
         $scripts{$child}=$names->{$child} || "N/A";
      }
      # success 
      $content->value("scripts",\%scripts);
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

sub enumScriptPermTypes {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="SCRIPT";
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

sub getScript {
   my ($content,$query,$db,$userid,$cfg,$log,$override)=@_;

   # clean entity id
   my $id=$Schema::CLEAN{entity}->($query->{id});

   # decide if we can override perms requirements or not?
   $override=$override || 0;

   # check existence and type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("SCRIPT"))[0])) {
      # does not exist 
      $content->value("errstr","Script $id does not exist or is not a SCRIPT-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["SCRIPT_CHANGE","SCRIPT_READ"],"ALL","ANY",1,1,undef,1);
   # override flag, which can only be used internally overrides need to have permissions to read the script (used by the system)
   if ((defined $allowed) && (!$allowed) && ($override)) { $allowed=1; }
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the SCRIPT_READ or SCRIPT_CHANGE permission on the script $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # get all of entities metadata
   my $md=$db->getEntityMetadata($id);

   if (defined $md) {
      # we got metadata

      # we have the name, get it
      my $name=$md->{$SysSchema::MD{name}} || "UNDEFINED";

      # get the code in metadataval-length chunks
      my $mc=MetadataCollection->new(base=>$SysSchema::MD{"script.code"});
      # convert metadata into chunks
      my $chunks=$mc->metadata2Hash($md);

      # assemble chunks into one string/document
      my @clist=sort {$a <=> $b} keys %{$chunks};
      my $code="";
      foreach (@clist) {
         my $no=$_;

         # add current chunk to code already retrieved
         $code .= $chunks->{$no};
      }

      # return the hash
      $content->value("script",$code);
      $content->value("name",$name);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # something failed
      $content->value("errstr","Unable to fetch script: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getScriptName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="SCRIPT";
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

sub getScriptPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # script to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="SCRIPT";   
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

sub getScriptPerms {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # script to get perms on

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{type}="SCRIPT";
   # attempt to get script perms
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

sub moveScript {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check ids type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("SCRIPT"))[0])) {
      # does not exist 
      $content->value("errstr","Script $id does not exist or is not a SCRIPT entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check parents type
   if ((!$db->existsEntity($parent)) ||  ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # get script name
   my $res=$db->getEntityMetadata($id,$SysSchema::MD{name});
   if (!defined $res) {
      # something failed
      $content->value("errstr","Cannot get metadata of SCRIPT $id: ".$db->error().". Unable to fulfill request.");
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
   $opt{type}="SCRIPT";
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

sub setScript {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get script id to change definition on
   my $id=$Schema::CLEAN{entity}->($query->{id});
   # the new script code to set (overwriting old)
   my $script=$SysSchema::CLEAN{"script.code"}=$query->{script};
   # add name, optional
   my $name=$query->{name};

   # check existence and type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("SCRIPT"))[0])) {
      # does not exist 
      $content->value("errstr","Script $id does not exist or is not a SCRIPT-entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["SCRIPT_CHANGE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the SCRIPT_CHANGE permission on the script $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # check that script is a SCALAR/string
   if ((!defined $script) || (ref(\$script) ne "SCALAR")) {
      # wrong type, failure
      $content->value("errstr","Script is not defined or is not a string. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # start transaction mode
   my $trans=$db->useDBItransaction();

   # attempt to set script name, if defined
   if (defined $name) {
      my $class=ref($content);
      my $mess=$class->new();
      my %opt;
      $opt{id}=$query->{id};
      $opt{duplicates}=1;
      $opt{type}="SCRIPT";
      $opt{name}=$name;
      # attempt to set name
      MethodsReuse::setEntityName($mess,\%opt,$db,$userid,$cfg,$log);

      # check result
      if ($mess->value("err") != 0) {
         # failure
         $trans->rollback();
	 $content->value("errstr","Unable to set name of SCRIPT $id: ".$mess->value("errstr"));
         $content->value("err",1);
         return 0;
      }
   }

   # convert script to actual metadata
   # start with splitting script into 1024 byte chunks or less
   my @chunks;
   while ($script =~ /^(.{1,1024})(.*)/s) {
      my $chunk=$1;
      $script=$2;
      push @chunks,$chunk;
   }
   # construct the metadata hash based on the chunks
   my $no=1;
   my %md;
   foreach (@chunks) {
      my $chunk=$_;

      $md{$SysSchema::MD{"script.code"}.".$no"}=$chunk;

      $no++;
   }

   # add the name to the metadata
   $md{$SysSchema::MD{"name"}}=$name;
   # first remove all existing script code metadata on entity
   my $delete=$SysSchema::MD{"script.code"}.".*";
   if (!defined $db->deleteEntityMetadata($id,\@{[$delete]})) {
      # something failed removing script metadata
      $trans->rollback();
      $content->value("errstr","Existing script metadata could not be deleted: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # set script and name metadata on entity
   if ($db->setEntityMetadata($id,\%md)) {
      # success - return the metadata that was set
      $content->value("script",$script);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # something failed
      $trans->rollback();
      $content->value("errstr","Unable to set script metadata: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub setScriptName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{duplicates}=1;
   $opt{type}="SCRIPT";
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

sub setScriptPerm {
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
   $opt{type}="SCRIPT";   
   # attempt to set script perm
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

=head1 SCRIPT METHODS

=head2 createScript()

Create a new script.

Input parameters:

=over

=item

B<metadata> The metadata to set upon creating the script. HASH. Optional. If this is needed is dependant upon any 
templates that might be in effect. It can also be used to override the name-parameter if the key for an entity's name 
is filled in through the metadata (it will then take precedence over the name-parameter).

=cut

=item

B<name> The display name of the new script. STRING. Optional/Required. It is optional and will be ignored if specified 
through the metadata hash. If not specified in the metadata hash, it is required. It is not allowed with blank names or
just spaces.

=cut

=item

B<parent> Entity ID from the database of the entity that is the parent of the new script being created. INTEGER. 
Required. The parent can only be a GROUP entity.

=cut

=back

The method requires that the user has the SCRIPT_CREATE permission on the parent of the script being created.

The method will fail to create the script, if any template(s) in effect for the script are not compliant.

Upon success will return the following values:

  id => INTEGER # script entity ID of the newly created script.
  name => STRING # the resulting (after cleaning) textual name of the newly created script.

=cut

=head2 deleteScript()

Delete a script.

Input parameters:

=over

=item

B<id> The script entity ID from the database of the script to delete. INTEGER. Required.

=cut

=back

This method requires the user to have the SCRIPT_DELETE permission on the script being deleted.

=cut

=head2 enumPermTypes()

Enumerate the script permissions types.

No input is accepted.

Upon success returns the following HASH-structure:

  types => ARRAY of STRING # name(s) of the script permission types.

=cut

=head2 enumScripts()

Enumerate all the scripts that exists.

No input parameters are accepted.

Upon success will return the following HASH-structure:

  scripts => (
              SCRIPTa => STRING # key->value, where key is the script entity ID and the value is the display name of the script.
              .
              .
              SCRIPTx => STRING
            )

=cut

=head2 getScript()

Gets a script's definition.

Input parameter is:

=over

=item

B<id> Script entity ID from database to get the definition of. INTEGER. Required.

=cut

=back

This method requires that the user has either the SCRIPT_READ or SCRIPT_CHANGE permission on the script in question.

Upon success returns the same structure as input to the setScript-method (see setScript()-method for more information).

=cut

=head2 getScriptName()

Get the display name of the script.

Input parameters:

=over

=item

B<id> Script entity ID of the script to get the name of. INTEGER. Required.

=cut

=back

Upon success returns the following value:

  name => STRING # the textual name of the script entity specified.

=cut

=head2 getScriptPerm()

Get script permission(s) for a given user.

Input parameters:

=over

=item

B<id> Script entity ID from database of the script to get permission on. INTEGER. Required.

=cut

=item

B<user> User entity ID from database of the user which the permission(s) are valid for. INTEGER. Optional. If none
is specified it will default to the authenticated user itself.

=cut

=back

Upon success returns the following structure:

  perm => (
            grant => ARRAY of STRING # permission(s) that have been granted on this script.
            deny => ARRAY of STRING # permission(s) that have been denied on this script.
          )

Please note that when these permissions are used by the system, what it finds for deny is applied before the grant 
is applied when it comes to effective permissions.

=cut

=head2 getScriptPerms()

Gets all the permission(s) on a given script entity, both inherited and what has been set and the effective perm for each 
user who has any permission(s).

Input parameters:

=over

=item

B<id> Script entity ID from database of the group to get the permissions of. INTEGER. Required.

=cut

=back

Upon success the resulting structure returned is:

  perms => (
             USERa => (
                        inherit => [ PERMa, PERMb .. PERMn ] # permissions inherited down on the script from above
                        deny => [ PERMa, PERMb .. PERMn ] # permissions denied on the given script itself.
                        grant => [ PERMa, PERMb .. PERMn ] # permissions granted on the given script itself. 
                        perm => [ PERMa, PERMb .. PERMn ] # effective permissions on the given script (result of the above)
                      )
             .
             .
             USERn => ( .. )
           )

USERa and so on are the USER entity ID from the database who have permission(s) on the given script. An entry for a user 
only exists if that user has any permission(s) on the script. The sub-key "inherit" is the inherited permissions from above 
in the entity tree. The "deny" permission(s) are the denied permission(s) set on the script itself. The "grant" permission(s) are 
the granted permission(s) set on the script itself. Deny is applied before grant. The sub-key "perm" is the effective or 
resultant permission(s) after the others have been applied on the given script.

The permissions that users has through groups on a given script are not expanded. This means that a group will be listed 
as having permissions on the script and in order to find out if the user has any rights, one has to check the membership of 
the group in question (if the user is listed there).

Permission information is open and requires no permission to be able to read. PERMa and so on are the textual permission 
type that are set on one of the four categories (inherit, deny, grant and/or perm). These four categories are ARRAYS of 
STRING. Some of the ARRAYS can be empty, although not all of them (then there would be no entry in the return perms for 
that user).

The perms-structure can be empty if no user has any permission(s) on the script.

=cut

=head2 moveScript()

Moves a script entity to another part of the entity tree.

Input is:

=over

=item

B<id> Script entity ID from the database of the script to move. INTEGER. Required.

=cut

=item

B<parent> Parent entity ID from the database of the entity which will be the new parent of the script. INTEGER. 
Required. The parent entity must be a GROUP-entity.

=cut

=back

The method requires the user to have the SCRIPT_MOVE permission on the script being moved and GROUP_CREATE on the 
parent it is being moved to.

=cut

=head2 setScript()

Sets the script definition.

Input parameters are:

=over

=item

B<id> Script entity ID from database to set the code of. INTEGER. Required.

=cut

=item

B<name> Script name. STRING. Optional. If not specified will continue to use existing name. If specified will 
attempt to update the name. The name does not need to be unique.

=cut

=item

B<script> The script definition to set. String. Required. Maximum length og script code is 16K, or 16384 characters. All 
characters beyond this length will be cut from the input.

=cut

=back

The script code is the raw code of the script itself, with all special characters, new lines etc.

This method required the user to have the SCRIPT_CHANGE permission on the script having its code and/or name set.

=cut

=head2 setScriptName()

Set/edit the display name of a script.

Input accepts the following parameters:

=over

=item

B<id> Script entity ID from the database of the script to set name of. INTEGER. Required.

=cut

=item

B<name> New name of the script entity in question. STRING. Required. It does not accept blanks as a name.

=cut

=back

This method requires that the user has the SCRIPT_CHANGE permission on the script specified.

=cut

=head2 setScriptPerm()

Set permission(s) on the given script for a user.

Input parameters are:

=over

=item

B<id> Script entity ID from database of script to set permissions on. INTEGER. Required.

=cut

=item

B<user> User entity ID from the database of the user to set permission for. INTEGER. Optional. If 
not specified will default to set permission for the user authenticated on the REST-server.

=cut

=item

B<operation> How to set the permissions on the script in question. STRING. Optional. If not 
specified will default to "APPEND". Accepted values are: "APPEND", "REPLACE" or "REMOVE".

=cut

=item

B<grant> The grant permission(s) to set on the script. ARRAY of STRING. Optional.

=cut

=item

B<deny> The deny permission(s) to set on the script. ARRAY of STRING. Optional.

=cut

=back

This method requires the user to have the SCRIPT_PERM_SET permission.

Upon success will return the following structure:

  perm => (
            grant => ARRAY    # STRINGs of permissions set
            deny => ARRAY     # STRINGs of permissions set
          )

This will be the grant- and deny- permissions that have ended up being set.

=cut

