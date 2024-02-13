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
# MethodsTemplate: Template-entity methods for the AURORA REST-server
#
package MethodsTemplate;
use strict;
use RestTools;

sub registermethods {
   my $srv = shift;

   $srv->addMethod("/enumTemplates",\&enumTemplates,"Enumerate all templates.");
   $srv->addMethod("/createTemplate",\&createTemplate,"Create a template.");
   $srv->addMethod("/checkTemplateCompliance",\&checkTemplateCompliance,"Check if metadata is compliant with template for an entity.");
   $srv->addMethod("/deleteTemplate",\&deleteTemplate,"Delete a template.");
   $srv->addMethod("/enumTemplateFlags",\&enumTemplateFlags,"Enumerate all TEMPLATE flags.");
   $srv->addMethod("/enumTemplatePermTypes",\&enumTemplatePermTypes,"Enumerate all TEMPLATE permission types.");
   $srv->addMethod("/getEntityTemplateAssignments",\&getEntityTemplateAssignments,"Get template assignments on an entity.");
   $srv->addMethod("/getTemplateAggregatedPerm",\&getTemplateAggregatedPerm,"Get aggregated/inherited perm on template.");
   $srv->addMethod("/getTemplatePerm",\&getTemplatePerm,"Get perms on template itself.");
   $srv->addMethod("/getTemplatePerms",\&getTemplatePerms,"Get all users perms on template.");
   $srv->addMethod("/getAggregatedTemplate",\&getAggregatedTemplate,"Get a template that is valid for an entity based upon an optional type and path.");
   $srv->addMethod("/getTemplate",\&getTemplate,"Get a specific template with a specific template id.");
   $srv->addMethod("/getTemplateAssignments",\&getTemplateAssignments,"Get which entities a template is assigned to.");
   $srv->addMethod("/moveTemplate",\&moveTemplate,"Move template to another group.");
   $srv->addMethod("/setTemplate",\&setTemplate,"Set a template's constraints.");
   $srv->addMethod("/setTemplateName",\&setTemplateName,"Set/change name of template.");
   $srv->addMethod("/setTemplatePerm",\&setTemplatePerm,"Set perm on template.");
}

sub enumTemplates {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="TEMPLATE";
   MethodsReuse::enumEntities($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("templates",$mess->value("templates"));
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

sub setTemplate {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $tmpl=$query->{template};
   my $name=$query->{name};
   if (defined $name) { $name=$SysSchema::CLEAN{entityname}->($name); }
   my $reset=$query->{reset};

   # check that id is a template
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("TEMPLATE"))[0])) {
      # does not exist 
      $content->value("errstr","Template $id does not exist or is not a TEMPLATE entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["TEMPLATE_CHANGE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the TEMPLATE_CHANGE permission on the TEMPLATE $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # check name
   if ((defined $name) && ($name eq "")) {
      # name does not fulfill minimum criteria
      $content->value("errstr","Template name is blank and does not fulfill minimum requirements. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check that name does not exist already if defined
   my %search;
   $search{$SysSchema::MD{name}}=$name;
   if (defined $name) {
      my @type=($db->getEntityTypeIdByName("TEMPLATE"))[0];
      my $ids=$db->getEntityByMetadataKeyAndType(\%search,undef,undef,$SysSchema::MD{name},undef,undef,\@type);

      if (!defined $ids) {
         # something failed
         $content->value("errstr","Unable to search for potential templates with same name \"$name\": ".$db->error());
         $content->value("err",1);
         return 0;
      }

      # check if we have match that says we have other template with same name
      if ((@{$ids} > 0) && ($ids->[0] != $id)) {
         # we have template with same name already - duplicate not allowed of tidyness reasons
         $content->value("errstr","Another template has the same name as \"$name\" already. Duplicates not allowed. Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      }
   } 

   # retrieve existing name
   my $md=$db->getEntityMetadata($id,$SysSchema::MD{name});
   if (!defined $md) {
      # something failed
      $content->value("errstr","Unable to retrieve metadata of template $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
   # metadata retrieved - set name variable to retrieved data
   my $mdname=$md->{$SysSchema::MD{name}};

   # convert flags to bitmask
   foreach (keys %{$tmpl}) {
      my $key=$_;

      if ((!defined $tmpl->{$key}{flags}) || (ref($tmpl->{$key}{flags}) ne "ARRAY")) { delete($tmpl->{$key}{flags}); next; }

      $tmpl->{$key}{flags}=arrayToFlags($db,$tmpl->{$key}{flags});
   }

   # we are ready to change template, start transaction already out here.
   my $trans=$db->useDBItransaction();
   # first change template, then set name (if defined)
   if ($db->setTemplate($id,$tmpl,$reset)) {
      # success - only attempt to set name if it is defined and different than already (changed)
      if ((defined $name) && ($name ne $mdname)) {
         my $res=$db->setEntityMetadata($id,\%search);

         if ($res) {
            # succeeded in setting name - return the templates id and resulting name after cleaning  
            $content->value("id",$id);
            $content->value("name",$name);
            $content->value("errstr","");
            $content->value("err",0);
            return 1;
         } else {
            # some error
            $content->value("errstr","Unable to set template name: ".$db->error());
            $content->value("err",1);
            return 0;
         }
      }
      # no name defined or changed, return success
      $content->value("id",$id);
      $content->value("name",$mdname);
      $content->value("errstr","");
      $content->value("err",0);
      return 1;      
   } else {
      # some error
      $content->value("errstr","Unable to change template: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub createTemplate {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $name=$SysSchema::CLEAN{entityname}->($query->{name});
   my $tmpl=$query->{template}; # keep all, also system
   my $metadata=$SysSchema::CLEAN{metadata}->($query->{metadata}); # clean away system-metadata

   # check that parent is a group
   if ((!$db->existsEntity($parent)) || ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$parent,["TEMPLATE_CREATE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the TEMPLATE_CREATE permission on the GROUP $parent. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # get name from metadata if it is there, ignoring what is set in name-parameter
   if (exists $metadata->{$SysSchema::MD{name}}) { $name=$SysSchema::CLEAN{entityname}->($metadata->{$SysSchema::MD{name}}); }

   # check name
   if ((!defined $name) || ($name eq "")) {
      # name does not fulfill minimum criteria
      $content->value("errstr","Template name is missing and does not fulfill minimum requirements. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check that name does not exist already
   my %search;
   $search{$SysSchema::MD{name}}=$name;
   my @type=($db->getEntityTypeIdByName("TEMPLATE"))[0];
   my $ids=$db->getEntityByMetadataKeyAndType(\%search,undef,undef,$SysSchema::MD{name},undef,undef,\@type);

   if (!defined $ids) {
      # something failed
      $content->value("errstr","Unable to search for potential templates with same name \"$name\": ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # check if we have match that says we have other template with same name
   if (@{$ids} > 0) {
      # we have template with same name already - duplicate not allowed of tidyness reasons
      $content->value("errstr","Another template has the same name as \"$name\" already. Duplicates not allowed. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # convert flags to bitmask
   foreach (keys %{$tmpl}) {
      my $key=$_;

      if ((!defined $tmpl->{$key}{flags}) || (ref($tmpl->{$key}{flags}) ne "ARRAY")) { delete($tmpl->{$key}{flags}); next; }

      $tmpl->{$key}{flags}=arrayToFlags($db,$tmpl->{$key}{flags});
   }

   # we are ready to create template, start transaction already out here
   my $trans=$db->useDBItransaction();
   my $id=$db->createTemplate($parent,$tmpl);

   if ($id) {
      # template created
      # add name to metadata (again if already there)
      $metadata->{$SysSchema::MD{name}}=$name;
      # some other system metadata needed for the template
      $metadata->{$SysSchema::MD{"entity.id"}}=$id;
      $metadata->{$SysSchema::MD{"entity.parent"}}=$parent;
      $metadata->{$SysSchema::MD{"entity.type"}}=($db->getEntityTypeIdByName("TEMPLATE"))[0];

      # set metadata by using metadata HASH.
      my $res=$db->setEntityMetadata($id,$metadata);

      if ($res) {
         # succeeded in setting name - return the templates id and resulting name after cleaning
         $content->value("id",$id);
         $content->value("name",$name);
         $content->value("errstr","");
         $content->value("err",0);
         return 1;
      } else {
         # some error
         $content->value("errstr","Unable to set template name and metadata: ".$db->error());
         $content->value("err",1);
         return 0;
      }
   } else {
      # some error
      $content->value("errstr","Unable to create template: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub checkTemplateCompliance {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $md=$query->{metadata}; # metadata to check
   my $path=$query->{path};

   # check that entity exists
   if (!$db->existsEntity($id)) {
      # computer does not exist
      $content->value("errstr","Entity $id does not exist. Unable to fulfill request.");
      $content->value("err",1);
      return 0;    
   }

   my $type=(defined $query->{type} ? $Schema::CLEAN{entitytype}->(($db->getEntityTypeIdByName($query->{type}))[0]) : $db->getEntityType($id));

   if ((defined $md) && (ref($md) ne "HASH")) {
      $content->value("errstr","Metadata parameter is not a HASH. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # lets check if it is compliant
   my $res=$db->checkEntityTemplateCompliance ($id,$md,$type,$path);

   if (defined $res) {
      # we have a result - convert flags for each key
      foreach (keys %{$res->{metadata}}) {
         my $key=$_;

         my $flags;
         if (defined $res->{metadata}{$key}{flags}) { 
            $flags=flagsToArray($db,$res->{metadata}{$key}{flags});
         }
         # change flags to new value
         $res->{metadata}{$key}{flags}=$flags;
      }

      # remove everything that does not start with ".".
      my $md;
      if ($type != ($db->getEntityTypeIdByName("USER"))[0]) { $md=$SysSchema::CLEAN{metadata}->($res->{metadata}); }
      else { $md=$res->{metadata}; }

      # return result
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("compliance",$res->{compliance});
      $content->value("noncompliance",$res->{noncompliance});
      $content->value("metadata",$md);
      return 1;
   } else {
      # something failed
      $content->value("errstr","Unable to check template compliance: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub deleteTemplate {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # entity to delete

   # check that id is valid
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("TEMPLATE"))[0])) {
      # does not exist 
      $content->value("errstr","TEMPLATE $id does not exist or is not a TEMPLATE entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["TEMPLATE_DELETE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;      
      } else {
         $content->value("errstr","User does not have the TEMPLATE_DELETE permission on the TEMPLATE $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;      
      }
   }

   # ready to attempt delete
   if ($db->deleteTemplate ($id)) {
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failed
      $content->value("errstr","Unable to delete TEMPLATE $id: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub enumTemplateFlags {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # lets get all template flags
   my @res=$db->enumTemplateFlags();

   if (defined $res[0]) {
      # we have a result - convert each flag bit to textual name
      my @flags=$db->getTemplateFlagNameByBit(@res);

      # return result
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("flags",\@flags);
      return 1;
   } else {
      # something failed
      $content->value("errstr","Unable to get template flags: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub enumTemplatePermTypes {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="TEMPLATE";
   # attempt to enumerate
   MethodsReuseenumPermTypesByEntityType($mess,\%opt,$db,$userid,$cfg,$log);

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

sub getEntityTemplateAssignments {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $type=$query->{type};

   my $typeid;
   if (defined $type) {
      $type=$Schema::CLEAN{entitytypename}->($type);

      # convert from string to id
      $typeid=($db->getEntityTypeIdByName($type))[0];
      if (!$typeid) {
         # invalid type specified
         $content->value("errstr","Specified entity type $type does not exist. Unable to proceed.");
         $content->value("err",1);
         return 0;   
      }
   }

   # check that entity exists
   if (!$db->existsEntity($id)) {
      # does not exist
      $content->value("errstr","Entity $id does not exist. Unable to proceed.");
      $content->value("err",1);
      return 0;
   }

   # get template assignments
   my $assigns=$db->getEntityTemplateAssignments($id,$typeid);

   if (defined $assigns) {
      # we have assignments - convert entity type name(s)
      my %res;
      foreach (keys %{$assigns}) {
         my $tid=$_;

         my $name=($db->getEntityTypeNameById($tid))[0];
         if (!defined $name) {
            # something failed
            $content->value("errstr","Unable to get type name of entity type id $tid: ".$db->error());
            $content->value("err",1);
            return 0;
         }
         $res{$name}=$assigns->{$tid};
      }

      # return results
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("assignments",\%res);
      return 1;    
   } else {
      # something went wrong
      $content->value("errstr","Unable to get template assignments: ".$db->error());
      $content->value("err",1);
      return 0; 
   }
}

sub getTemplateAggregatedPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # template to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="TEMPLATE";   
   # attempt to get perm
   MethodsReusegetEntityAggregatedPerm($mess,\%opt,$db,$userid,$cfg,$log);

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

sub getTemplatePerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # template to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="TEMPLATE";   
   # attempt to get perm
   MethodsReusegetEntityPerm($mess,\%opt,$db,$userid,$cfg,$log);

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

sub getTemplatePerms {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # template to get perms on

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{type}="TEMPLATE";
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

sub getAggregatedTemplate {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $type=$Schema::CLEAN{entitytypename}->($query->{type});
   my $path=$query->{path};

   # check that entity exists
   if (!$db->existsEntity($id)) {
      # does not exist
      $content->value("errstr","Entity does not exist: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # check that template type specified is valid
   if (($type ne "") && (!($db->getEntityTypeIdByName($type))[0])) {
      # does not exist
      $content->value("errstr","Template type $type does not exist. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } elsif ($type eq "") {
      # default to DATASET if not specified
      $type="DATASET";
   }

   if ((defined $path) && (ref($path) ne "ARRAY")) {
      $content->value("errstr","Path parameter is not of type ARRAY. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # start transaction
   my $tr=$db->useDBItransaction();

   if (defined $tr) {
      # transaction started - get the entity's template path
      if (!defined $path) {
         # no path defined, get entity's path
         $path=$db->getEntityTemplatePath($id);
      }
      if (defined $path) {
         # success - get the entity's aggregated template
         my $templ=$db->getEntityTemplate($db->getEntityTypeIdByName($type),@{$path});       
         if (defined $templ) {
            # we have a template - remove system template definitions, except if user
            if ($type ne "USER") { $templ=$SysSchema::CLEAN{metadata}->($templ); }
            #convert flags for each key
            my @l;
            foreach (keys %{$templ}) {
               my $key=$_;

               my $flags=\@l;
               if (defined $templ->{$key}{flags}) {
                  $flags=flagsToArray($db,$templ->{$key}{flags});
               }
               # change flags to new value
               $templ->{$key}{flags}=$flags;
            }
            # return it

            $content->value("errstr","");
            $content->value("err",0);
            $content->value("type",$type);
            $content->value("id",$id);
            $content->value("template",$templ);
            return 1;
         } else {
            # unable to get template
            $content->value("errstr","Unable to get entity's template: ".$db->error());
            $content->value("err",1);
            return 0;
         }
      } else {
         # failed to get path
         $content->value("errstr","Unable to get entity's template path: ".$db->error());
         $content->value("err",1);
         return 0;
      }
   } else {
      # transaction start failed
      $content->value("errstr","Unable instantiate transaction object: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub getTemplate {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});

   # check that entity exists
   if (!$db->existsEntity($id)) {
      # does not exist
      $content->value("errstr","Entity does not exist: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # check that entity is of right type
   if ($db->getEntityType($id) != ($db->getEntityTypeIdByName("TEMPLATE"))[0]) {
      # wrong entity type
      $content->value("errstr","Id $id is not a TEMPLATE entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;    
   }

   # get template
   my $templ=$db->getTemplate($id);

   if (defined $templ) {
      # we have a template - convert flags
      foreach (keys %{$templ}) {
         my $key=$_;

         my $flags;
         if (defined $templ->{$key}{flags}) {
            $flags=flagsToArray($db,$templ->{$key}{flags});
         }
         # change flags to new value
         $templ->{$key}{flags}=$flags;
      }

      # also get name
      my @incl;
      push @incl,$SysSchema::MD{name};
      my $md=$db->getEntityMetadata ($id,@incl);
      if (!defined $md) {
         # something went wrong
         $content->value("errstr","Unable to get template metadata: ".$db->error());
         $content->value("err",1);
         return 0; 
      }

      # we have the name, get it
      my $name=$md->{$SysSchema::MD{name}} || "UNDEFINED";

      # return it
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("template",$templ);
      $content->value("name",$name);
      return 1;    
   } else {
      # something went wrong
      $content->value("errstr","Unable to retrieve template: ".$db->error());
      $content->value("err",1);
      return 0; 
   }
}

sub getTemplateAssignments {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id}); # template id
   my $type=$query->{type};
   my $duplicates=0; # remove duplicates?
   if (defined $query->{duplicates}) { 
      $duplicates=$Schema::CLEAN_GLOBAL{boolean}->($query->{duplicates});
   }

   my $typeid;
   if (defined $type) {
      $type=$Schema::CLEAN{entitytypename}->($type);

      # convert from string to id
      $typeid=($db->getEntityTypeIdByName($type))[0];
      if (!$typeid) {
         # invalid type specified
         $content->value("errstr","Specified entity type $type does not exist. Unable to proceed.");
         $content->value("err",1);
         return 0;   
      }
   }

   # check that entity exists
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("TEMPLATE"))[0])) {
      # does not exist 
      $content->value("errstr","TEMPLATE $id does not exist or is not a TEMPLATE entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # get template assignments
   my $assigns=$db->getTemplateAssignments($id,$typeid,$duplicates);
   if (defined $assigns) {
      # we have assignments - convert entity type name(s)
      my %res;
      $res{all}=$assigns->{all};
      foreach (keys %{$assigns->{types}}) {
         my $tid=$_;

         my $name=($db->getEntityTypeNameById($tid))[0];
         if (!defined $name) {
            # something failed
            $content->value("errstr","Unable to get entity type name for type id $tid: ".$db->error().". Unable to fulfill request.");
            $content->value("err",1);
            return 0; 
         }
         $res{types}{$name}=$assigns->{types}{$tid};
      }

      # return results
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("assignments",\%res);
      return 1;
   } else {
      # something went wrong
      $content->value("errstr","Unable to get template assignments: ".$db->error());
      $content->value("err",1);
      return 0; 
   }
}

sub moveTemplate {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{parent}=$query->{parent};
   $opt{type}="TEMPLATE";
   $opt{parenttype}="GROUP";
   MethodsReusemoveEntity($mess,\%opt,$db,$userid);

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

sub setTemplateName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{duplicates}=undef; # do duplicates in entire tree
   $opt{type}="TEMPLATE";
   $opt{name}=$query->{name};
   # attempt to set name
   MethodsReusesetEntityName($mess,\%opt,$db,$userid,$cfg,$log);

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

sub setTemplatePerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id}; # template to set perm on
   $opt{user}=$query->{user}; # subject which perm is valid for
   $opt{grant}=$query->{grant}; # grant mask to set
   $opt{deny}=$query->{deny}; # deny mask to set
   $opt{operation}=$query->{operation};
   $opt{type}="TEMPLATE";   
   # attempt to set perm
   MethodsReusesetEntityPerm($mess,\%opt,$db,$userid,$cfg,$log);

   # check result
   if ($mess->value("err") == 0) {
      # success
      $content->value("grant",$mess->value("grant"));
      $content->value("deny",$mess->value("deny"));
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

=head1 TEMPLATE METHODS

=head2 createTemplate()

Creates a template with a given name.

Input parameters are:

=over

=item

B<parent> The group entity ID from the database of the group that is the parent of the new template. INTEGER. 
Required.

=cut

=item

B<name> The name of the new template to create. STRING. Required. Cannot be set to blank. It cannot be the same 
as any other name in the entire entity tree.

=cut

=item

B<template> Sets initial constraints for the template being created. HASH. Optional. If set must comply with the 
template structure described in the setTemplate()-method.

=cut

=item

B<metadata> The metadata for the template, including its name. HASH. Optional. If the name of the template is set through 
metadata it takes precedence over the "name"-parameter. Any metadata set here will also have to comply with 
any template in effect (template of template nonetheless).

=cut

=back

This method requires that the user has the TEMPLATE_CREATE permission on the parent group in question.

Upon success returns the following structure:

  id => INTEGER # template entity ID from the database of the newly created template.
  name => STRING # the actual name that was set for the newly created template (after cleaning).

=cut

=head2 checkTemplateCompliance()

Checks the compliance of the template with the metadata input.

Valid parameters are:

=over

=item

B<id> Entity ID from the database of the entity to check template compliance for. INTEGER. Required.

=cut

=item

B<metadata> The metadata to check the compliance of with the entity ID given. HASH. Required.

=cut

=item

B<path> The path in the entity tree to use for aggregating template for the compliance check. Optional. If not 
specified will default to the path down to the entity being specified in the parameter "id" from ROOT(1).

=cut

=item

B<type> Specifies the entity type to check template for. STRING. Optional. If not specified will default to the 
entity type of the entity id specified. Valid values are: DATASET, GROUP, COMPUTER etc.

=cut

=back

The metadata-parameter HASH needs to be structured as follows:

   metadata => (
                 NAMEa => STRING,
                 NAMEb => STRING,
                 .
                 .
                 NAMEc => STRING
               )

The metadata HASH is basically a key->value collection of the metadata keys and its values to check against the 
aggregated template of the entity in question.

Upon success will return the following HASH-structure:

   compliance => INTEGER # Overall compliance, 0 for non-compliant, 1 for compliant.
   noncompliance => ARRAY of STRING # names of the metadata key(s)/template key(s) that are non-compliant, if any.
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

The compliance flag on each metadata key signals if that particular key is in compliance or not. 0 means 
non-compliant, 1 means compliant. If a key is not compliant the "reason"-value above will be filled in with the 
textual reason for why it failed?

For a more exhaustive explanation of the template constraint values, see the setTemplate()-method.

=cut

=head2 deleteTemplate()

Deletes a template.

Input parameters are:

=over

=item

<id> Template entity ID from the database to delete. INTEGER. Required.

=cut

=back

This method requires that the user has the TEMPLATE_DELETE permission on the template in question.

=cut

=head2 enumTemplateFlags()

Enumerate all template flag types.

No input accepted.

Returns an ARRAY structure as follows upon success:

  flags => ["FLAGNAME1" .. "FLAGNAMEn"]

=cut

=head2 enumTemplatePermTypes()

Enumerate the template permission types.

Accepts no input.

Upon success will return the following ARRAY:

   types => (
               PERMISSIONa
               PERMISSIONb
               .
               .
               PERMISSIONz
            )

where PERMISSIONa and so on is the name of the template permission (STRING).

=cut

=head2 enumTemplates()

Enumerates all the templates.

No input is accepted.

Upon success will return the following HAHS-structure:

  templates => (
                 IDa => STRING
                 IDb => STRING
                 .
                 .
                 IDz => STRING
               )

where IDa and so on is the template entity ID from the database (INTEGER) and the STRING is the name 
of the template.

=cut

=head2 getEntityTemplateAssignments()

Get the template assignment(s) on an entity.

Input parameters are:

=over

=item

B<id> Entity ID from the database to get template assignments of. INTEGER. Required.

=cut

=item

B<type> Textual name of the entity type that the assignments are valid for. STRING. Optional. If not specified it will default to 
fetching all assignments of all entity types on the entity in question. If specified it will only return the assignments for the 
given type on the entity.

=cut

=back

Upon success returns the following HASH-structure:

  assignments = (
                  TYPEa = [TEMPLATEID1,TEMPLATEID2 .. TEMPLATEIDn]
                  .
                  .
                  TYPEz = [ .. ]                         
                )

TYPEa and so on are the textual name of the type that the templates are assigned as. All template assignments in the AURORA-system 
are assigned to an entity with the type that it is to have effect as. A template of itself is entity type neutral until it is 
assigned. If no assignments are found, the structure will be empty. Each type point to an ARRAY of template entity IDs that are 
assigned to that type. The order of the array denotes the order in which the templates have effect from element 1 to N.

=cut

=head2 getAggregatedTemplate()

Gets the aggregated template of an entity.

Input parameters are:

=over

=item

B<id> Entity ID from database of the entity to get the aggregated template of. INTEGER. Required.

=cut

=item

B<type> Entity type name of the entity type to aggregate template for. STRING. Optional. If not specified it will 
default to the entity type "DATASET". Valid values are eg. "DATASET", "GROUP" and so on.

=cut

=item

B<path> Entity tree path to use for aggregating the template. ARRAY of INTEGER. Optional. The INTEGER values are 
the entity IDs in the entity tree. If not specified it will default to the path from root (1) down to the entity 
specified by the parameter "id".

=cut

=back

Upon success returns the following HASH-structure:

   id => INTEGER # id of the entity that the aggregated template was retrieved for
   type => STRING # the textual entity type that we aggregated a template for (after cleaning)
   template => (
                 KEYa => (
                           default => STRING or ARRAY of STRING
                           flags => ARRAY of STRING
                           regex => STRING
                           min => INTEGER
                           max => INTEGER
                           comment => STRING
                         )
                 KEYb => ( ... )
                 .
                 .
                 KEYz => ( ... )
               )

Please see the setTemplate()-method for more information upon the structure of the constraints.

This method aggregates together templates of a given type down the entity tree and then returns one template 
definition for each key in question that is the result. It also defaults values that has defaults defined, since 
an aggregate is what is being used to determine the validitiy of values saved into the metadata of the AURORA-
system and as such need them. Regex defaults to ".*", min defaults to 0, max to 1, flags to empty ARRAY (no flags 
set), comment to undef.

=cut

=head2 getTemplate()

Gets a specific template's defined constraints.

Input parameters:

=over

=item

B<id> Template entity ID from database of the template to get the constraints of. INTEGER. Required.

=cut

=back

This method gets the non-aggregated and specified template definition from the database. Upon success 
the method returns the following HASH-structure:

   name => STRING
   template => (
                 KEYa => (
                           default => STRING or ARRAY of STRING
                           flags => ARRAY of STRING
                           regex => STRING
                           min => INTEGER
                           max => INTEGER
                           comment => STRING
                         )
                 KEYb => ( ... )
                 .
                 .
                 KEYz => ( ... )
               )

Please see the setTemplate()-method for more exhaustive explanation of the various parts of this structure.

As opposed to the getAggregatedTemplate()-method, this method only returns the specific template asked for. There 
is no aggregate here. Because of this the various constraints in the template (default, flags, regex etc.) can 
be undefined, since that is how it was defined.

=cut

=head2 getTemplateAssignments()

Get a templates assignment(s) on entities (if any).

Input parameters are:

=over

=item

B<id> Template ID from the database to get assignments of. INTEGER. Required.

=cut

=item

B<type> Textual name of the entity type that the assignments are valid for. STRING. Optional. If not specified it will default to 
fetching all assignments of all entity types on the template in question. If specified it will only return the assignments for the 
given type on the template. Valid types are DATASET, GROUP, USER etc.

=cut

=item

B<duplicates> Remove duplicate entity IDs for a given entity type or not? BOOLEAN. Optional. If not specified will default to 
being false (do not remove duplicates). Valid values are 1 for true, 0 for false. It is possible to assign the same template 
several times on the same entity for the same entity type. This option enables one to get only unique entity IDs that the 
template are assigned to for any given entity type (eg. DATASET, GROUP, COMPUTER etc.).

=cut

=back

Upon success returns the following HASH-structure:

  assignments = (
                  all => [ENTITYID1,ENTITYID2 .. ENTITYIDn]
                  types => (
                             TYPEa = [ENTITYID1,ENTITYID2 .. ENTITYIDn]
                             .
                             .
                             TYPEz = [ .. ] 
                           )
                )


The top keys of the returned values are "all" and "types". The "all" key contains all unique entity IDs that are assigned to the 
given template, while "types" shows the distribution of assignments on various entity types. TYPEa and so on are the textual 
name of the type that the template is assigned as. All template assignments in the AURORA-system are assigned to an entity with 
the type that it is to have effect as. A template of itself is entity type neutral until it is assigned. If no assignments are 
found, the structure will be empty. Each type point to an ARRAY of entity IDs that are assigned to that type for the template 
in question. 

=cut

=head2 getTemplateAggregatedPerm()

Gets the inherited/aggregated permissions on a template for a user.

Input parameters are:

=over

=item

B<id> Template entity ID from the database to get the inherited permission(s) of. INTEGER. Required.

=cut

=item

B<user> User entity ID from the database of the user that the inherited permissions are valid for. INTEGER. 
Optional. If not specified will default to the authenticated user on the AURORA REST-server.

=cut

=back

Upon success this method will return the following value:

  perm => ARRAY of STRING # textual names of the permimssion(s) the user has on the given template.

=cut

=head2 getTemplatePerm()

Get template permission(s) for a given user.

Input parameters:

=over

=item

B<id> Template entity ID from database of the template to get permission on. INTEGER. Required.

=cut

=item

B<user> User entity ID from database of the user which the permission(s) are to be valid for. INTEGER. Optional. 
If none is specified it will default to the authenticated user itself.

=cut

=back

Upon success returns the following structure:

  perm => (
            grant => ARRAY of STRING # permission(s) that have been granted on this template.
            deny => ARRAY of STRING # permission(s) that have been denied on this template.
          )

Please note that when these permissions are used by the system, what it finds for deny is applied before the grant-part
is applied when it comes to effective permissions.

=cut

=head2 getTemplatePerms()

Gets all the permission(s) on a given template entity, both inherited and what has been set and the effective perm 
for each user who has any permission(s).

Input parameter is:

=over

=item

B<id> Template entity ID from the database that one wishes to get the permissions on. INTEGER. Required.

=cut

=back

Upon success the resulting structure returned is:

  perms => (
             USERa => (
                        inherit => [ PERMa, PERMb .. PERMn ] # permissions inherited down on the template from above
                        deny => [ PERMa, PERMb .. PERMn ] # permissions denied on the given template itself.
                        grant => [ PERMa, PERMb .. PERMn ] # permissions granted on the given template itself. 
                        perm => [ PERMa, PERMb .. PERMn ] # effective permissions on the given template (result of the above)
                      )
             .
             .
             USERn => ( .. )
           )

USERa and so on are the USER entity ID from the database who have permission(s) on the given template. An entry for a user
only exists if that user has any permission(s) on the template. The sub-key "inherit" is the inherited permissions from above
in the entity tree. The "deny" permission(s) are the denied permission(s) set on the template itself. The "grant" permission(s) are
the granted permission(s) set on the template itself. Deny is applied before grant. The sub-key "perm" is the effective or
resultant permission(s) after the others have been applied on the given template.

The permissions that users has through groups on a given template are not expanded. This means that the group will be listed
as having permissions on the template and in order to find out if the user has any rights, one has to check the membership of
the group in question (if the user is listed there).

Permission information is open and requires no permission to be able to read. PERMa and so on are the textual permission
type that are set on one of the four categories (inherit, deny, grant and/or perm). These four categories are ARRAYS of
STRING. Some of the ARRAYS can be empty, although not all of them (then there would be no entry in the return perms for
that user).

The perms-structure can be empty if no user has any permission(s) on the template.

=cut

=head2 moveTemplate()

Moves a template entity to another part of the entity tree.

Input is:

=over

=item

B<id> Template entity ID from the database of the template to move. INTEGER. Required.

=cut

=item

B<parent> Parent group entity ID from the database of the group which will be the new parent. INTEGER. 
Required.

=cut

=back

The method requires the user to have TEMPLATE_MOVE permission on the template being moved and TEMPLATE_CREATE on the parent 
group it is being moved to.

=cut

=head2 setTemplate()

Set template constraints.

Input parameters:

=over

=item

B<id> Template entity ID from database of template to set. INTEGER. Required.

=cut

=item

B<name> Display name of template. STRING. Optional. If specified will override existing name. If not specified, the old 
name will be retained. It is not allowed to specify a blank name.

=cut

=item

B<template> Template constraints to set. HASH. Required.

=cut

=item

B<reset> Reset the template's constraints or not before changing any. BOOLEAN. Optional. This decides if 
all the existing constraints are to be removed before new ones are added. It can even be used alone 
without any template definitions in order to reset all definitions without setting new ones. It is 
enough that the value in this option evaluates to true or false.

=cut

=back

This method requires that the user has the TEMPLATE_CHANGE permission on the template in question.

The input template HASH structure must have the following layout:

  template => (
                KEYNAMEa => (
                              default => STRING or ARRAY of STRING # defines the default values for this key.
                              regex => STRING # defines the regex that is going to check the value(s) of this key
                              flags => ARRAY of STRING # the template flags set on this key
                              min => INTEGER # the minimum number of values that has to be set.
                              max => INTEGER # the maximum number of values that can be set.
                              comment => STRING # textual explanation of what is needed to satisfy the regex
                            )
                .
                .
                KEYNAMEx => ( ... )
              )

KEYNAMEa and so on is the textual name of the metadata key in the namespace to set a template constraint for 
(eg. ".system.entity.name"). 

B<Default> sub-key defines the default value(s) that will be chosen if no value has been specified. The default 
value(s) can also be used to specify a list of choices if using the flags SINGULAR or MULTIPLE (see further 
down for explanation of flags). The default value can be either a STRING (if its just one value) or an 
ARRAY of STRING (multiple values).

B<Regex> is the regex that is used to check the value(s) entered when applying the template. If there are multiple 
values entered, the same regex will be used on all values. Please also note that a beginning (^) and end sign ($) 
will be applied around the regex entered, so that it represents something that needs to be matched within the 
beginning and end of the string being checked.

B<Flags> are various markers for how the template key is to be used or applied. The flags are set as an ARRAY of 
STRING. Valid flag values are:

=over

=item

B<MANDATORY> The key in question has to be answered with a value. If no value was entered and a default exists, 
the default will be chosen.

=cut

=item

B<NONOVERRIDE> The template definition for the key in question cannot be overridden. It is enforced down the 
entity tree. 

=cut

=item

B<SINGULAR> The key in question must be answered with a single value from the default(s)-definition of the 
template. This basically enables dropdown menu choices with a selection set from the default(s). The value 
entered will be checked against the default(s). SINGULAR cannot be used as the same time as the MULTIPLE-flag. 
SINGULAR takes precedence if both have been set.

=cut

=item

B<MULTIPLE> The key in question must be answered with one or more values from the defaults-definition of the 
template. This is like eg. tick boxes, where multiple values can be selected. All values entered will be checked 
against the default(s). MULTIPLE cannot be used at the same time as the SINGULAR-flag. MULTIPLE takes antecedence 
if both have been set.

=cut

=item

B<OMIT> The template definition for the key in question are not to be included in the aggregated templates. In 
other words it is omitted or removed. This is a way of hiding definitions that can be set, but are chosen not 
to be used yet.

=cut

=item

B<PERSISTENT> The value in the key defined by this template definition cannot be overwritten once it has been set.

=cut

=back

B<Min> sets the minimum number of value(s) to be entered for the key in question. 0 means no minimum and 
everything above 0 means that that number is the minimum, so that the user needs to enter that number of 
value(s) or more. Default value if none is set here is 0 for aggregated templates.

B<Max> sets the maximum number of value(s) that can be entered for the key in question. 0 means no maximum and 
everything above 0 means that that number is the maximum. Default values if none is set here is 1 for aggregated 
templates.

B<Comment> sets the textual explanation of the regex and what this key expects to be filled in.

=cut

=head2 setTemplateName()

Set/change the name of the template.

Input parameters:

=over

=item

B<id> Template entity ID from the database of the template to change name. INTEGER. Required.

=cut

=item

B<name> The new template name to set. STRING. Required. Does not accept blank string and the new name must not
conflict with any existing template name on the entire entity tree (including itself).

=cut

=back

Method requires the user to have the TEMPLATE_CHANGE permission on the entities in question.

=cut

=head2 setTemplatePerm()

Set permissions on a template.

Input parameters are:

=over

=item

B<id> Template entity ID from the database of the template to set permissions on. INTEGER. Required.

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

B<grant> The grant permission(s) to set on the template. ARRAY of STRING. Optional.

=cut

=item

B<deny> The deny permission(s) to set on the template. ARRAY of STRING. Optional.

=cut

=back

This method requires the user to have the TEMPLATE_PERM_SET permission.

Upon success will return the following structure:

  perm => (
            grant => ARRAY    # STRINGs of permissions set
            deny => ARRAY     # STRINGs of permissions set
          )

This will be the grant- and deny- permissions that have ended up being set.

=cut

