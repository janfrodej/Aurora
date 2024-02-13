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
# MethodsUser: User-entity methods for the AURORA REST-server
#
package MethodsUser;
use strict;
use RestTools;
use UnicodeTools;

sub registermethods {
   my $srv = shift;

   $srv->addMethod("/createUser",\&createUser,"Creates a user.");
   $srv->addMethod("/deleteUser",\&deleteUser,"Delete/anonymize (GDPR) a user");
   $srv->addMethod("/enumUsers",\&enumUsers,"Enumerate all users.");
   $srv->addMethod("/getUserAggregatedPerm",\&getUserAggregatedPerm,"Get aggregated/inherited perm on user.");
   $srv->addMethod("/getUserTaskAssignments",\&getUserTaskAssignments,"Get a user's task assignments");
   $srv->addMethod("/getUserEmail",\&getUserEmail,"Fetch a Users email address/username");
   $srv->addMethod("/getUserId",\&getUserId,"Fetch a USER id based upon its email address/username");
   $srv->addMethod("/getUserFullname",\&getUserFullname,"Fetch a Users full name.");
   $srv->addMethod("/getUserPerm",\&getUserPerm,"Get perms on user itself.");
   $srv->addMethod("/getUserPerms",\&getUserPerms,"Get all users perms on a given user.");
   $srv->addMethod("/moveUser",\&moveUser,"Move user to another group.");
   $srv->addMethod("/setUserTaskAssignments",\&setUserTaskAssignments,"Set a user's task assignments");
}

sub createUser {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $parent=$Schema::CLEAN{entity}->($query->{parent});
   my $user=$SysSchema::CLEAN{email}->($query->{username});
   my $name=$SysSchema::CLEAN{name}->($query->{fullname});
   my $sorted=$Schema::CLEAN_GLOBAL{boolean}->($query->{balanced});
   # define includes as including username and fullname
   my @includes=($SysSchema::MD{username},$SysSchema::MD{fullname});
   my $metadata=$SysSchema::CLEAN{metadata}->($query->{metadata},\@includes);

   # check that parent group exists
   if ((!$db->existsEntity($parent)) || ($db->getEntityType($parent) != ($db->getEntityTypeIdByName("GROUP"))[0])) {
      # does not exist 
      $content->value("errstr","Parent $parent does not exist or is not a GROUP entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   } 

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$parent,["USER_CREATE"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the USER_CREATE permission on the GROUP $parent. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # get user and name from metadata if there, overriding parameters username and fullname
   if (exists $metadata->{$SysSchema::MD{username}}) { $user=$SysSchema::CLEAN{email}->($metadata->{$SysSchema::MD{username}}); }
   if (exists $metadata->{$SysSchema::MD{fullname}}) { $name=$SysSchema::CLEAN{name}->($metadata->{$SysSchema::MD{fullname}}); }

   if ((!defined $user) || ($user eq "") || ($user =~ /^zombie\_\d+\@localhost$/i)) {
      # name does not fulfill minimum criteria
      $content->value("errstr","Username is missing and/or does not fulfill minimum requirements. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   if ((!defined $name) || ($name eq "")) {
      # name does not fulfill minimum criteria
      $content->value("errstr","Fullname is missing and/or does not fulfill minimum requirements. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check if username exists already
   my %mdata;
   $mdata{$SysSchema::MD{"username"}}{"="}=$user;
   # try to fetch entity
   my @type=($db->getEntityTypeIdByName("USER"));
   my $ids=$db->getEntityByMetadataKeyAndType(\%mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);

   if (!defined $ids) {
      # something failed
      $content->value("errstr","Unable to search for potential users with same username \"$user\": ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # check if we have already existing entities
   if (@{$ids} > 0) {
      # we have user with same name already - duplicate not allowed of tidyness reasons
      $content->value("errstr","Another user has the username \"$user\" already. Duplicates not allowed. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # we are ready to create user, start transaction already out here
   my $trans=$db->useDBItransaction();

   # check if user creation is to be sorted or not
   if ($sorted) {
      # user creation is to be sorted and balanced on the tree under the given
      # parent. Sorting is based on the first letter in the users first name.
      # we also assume that if user has user create permissions on parent, he will also
      # be granted so on the sub-groups.
      my $letter=uc(map2azmath(map2az(substr($name,0,1))));
      my $chldr=$db->getEntityChildren($parent,[$db->getEntityTypeIdByName("GROUP")],0);
      if (!defined $chldr) {
         $content->value("errstr","Unable to get parent entity ${parent}\'s children: ".$db->error());
         $content->value("err",1);

         return 0;
      }
      my $children=$db->getEntityMetadataList($SysSchema::MD{name},$chldr);
      if (!defined $children) {
         $content->value("errstr","Unable to get names of parent entity ${parent}\'s children: ".$db->error());
         $content->value("err",1);

         return 0;
      }
      my $found=0;
      foreach (keys %{$children}) {
         my $c=$_;
         if ($children->{$c} eq $letter) { $found=$c; last; }
      }
      # if 
      if ($found) { $parent=$found; }
      else {
         # sub-group does not exist already - create it
         my $grp=$db->createEntity($db->getEntityTypeIdByName("GROUP"),$parent);
         if (!defined $grp) {
            $content->value("errstr","Unable to create sub-group of parent $parent: ".$db->error());
            $content->value("err",1);

            $trans->rollback();
            return 0;
         }
         my %md;
         $md{$SysSchema::MD{name}}=$letter;
         if (!$db->setEntityMetadata($grp,\%md)) {
            $content->value("errstr","Unable to set sub-group name when creating user: ".$db->error());
            $content->value("err",1);

            $trans->rollback();
            return 0;
         } else { $parent=$grp; }
      }
   }

   my $id=$db->createEntity($type[0],$parent);

   if (defined $id) {
      # user created - generate random pw
      my $pw=sectools::randstr(8);
      # instantiate AuroraID
      my $aid=Authenticator::AuroraID->new(db=>$db,cfg=>$cfg);
      # generate AuroraID authstr
      my $authstr=$aid->generate("$user,$pw");
      if ((!defined $authstr) || ($authstr eq "")) {
         # do rollback
         $trans->rollback();
         # notify about error
         $content->value("errstr","Unable to generate AuroraID authstr: ".$aid->error());
         $content->value("err",1);
         return 0;
      }
      # get AuroraID namespace
      my $loc=$aid->locations();
      # set the authstr and expire locations in namespace
      my $ans=$loc->{"authstr"};
      my $ens=$loc->{"expire"};
      # set relevant metadata
      $metadata->{$ans}=$authstr;
      # create a short expire time on the account
      my $expire=time()+(86400*2); # set a couple of days expire time
      $metadata->{$ens}=$expire;
      # also set entity name to email and fullname (for viewing purposes)
      my $displayname=(defined $name ? "$user ($name)" : $user);
      $metadata->{$SysSchema::MD{name}}=$displayname;
      $metadata->{$SysSchema::MD{username}}=$user;
      $metadata->{$SysSchema::MD{fullname}}=$name;

      # set id, parent etc.
      $metadata->{$SysSchema::MD{"entity.id"}}=$id;
      $metadata->{$SysSchema::MD{"entity.parent"}}=$parent;
      my $utyp=($db->getEntityTypeIdByName("USER"))[0];
      if (!defined $utyp) {
         $content->value("errstr","Unable to get entity type id of entity type USER: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      }
      $metadata->{$SysSchema::MD{"entity.type"}}=$utyp;

      # attempt set user metadata
      my $res=$db->setEntityMetadata($id,$metadata);

      if ($res) {
         # succeeded in setting metadata, now add task permissions (user gets all on his own tasks)
         my @taskperms=grep { $_ =~ /^TASK\_.*$/ } $db->enumPermTypes();
         my $perms=$db->createBitmask($db->getPermTypeValueByName(@taskperms));
         if (!$db->setEntityPermByObject($userid,$id,$perms,undef,1)) {
            # something failed
            $content->value("errstr","Unable to set perms: ".$db->error().". Unable to fulfill request.");
            $content->value("err",1);
            return 0;
         }
      
         # notify newly created user
         my $not=Not->new();
         $not->send(type=>"user.create",about=>$id,from=>$SysSchema::FROM_REST,
                    message=>"Hi $name,\n\nWe have just created a new user $user for you in the AURORA-system:\n\n".
                    $cfg->value("system.www.base")."\n\nYour temporary password is:\n\n$pw\n\nPlease login and change your password ".
                    "as soon as possible.\n\nBest regards,\n\n   Aurora System");
         # Return entity id and username
         $content->value("id",$id);
         $content->value("username",$user);
         $content->value("errstr","");
         $content->value("err",0);
         return 1;
      } else {
         # some error 
         $content->value("errstr","Unable to set user metadata: ".$db->error());
         $content->value("err",1);
         return 0;
      }
   } else {
      # some error
      $content->value("errstr","Unable to create user: ".$db->error());
      $content->value("err",1);
      return 0;
   }
}

sub deleteUser {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get id or default to user him-/herself
   my $id=$query->{id} || $userid;
   # get where to move zombie, if at all
   my $retire=$Schema::CLEAN_GLOBAL{boolean}->($query->{retire});
   # clean the user id
   $id=$Schema::CLEAN{entity}->($id);

   # check permissions - user is allowed to anonymize himself
   my $allowed=hasPerm($db,$userid,$id,["USER_DELETE"],"ALL","ANY",1,1,undef,1) || ($userid == $id);
   if (!$allowed) {
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         # user is not allowed to do this - notify
         $content->value("errstr","You do not have the USER_DELETE permission on the USER $id. Unable to proceed.");
         $content->value("err",1);
         return 0;
      }
   }

   # start transaction
   my $trans=$db->useDBItransaction();

   # we are ready to GDPR - get metadata
   my $md=$db->getEntityMetadata ($id);
   if (!defined $md) {
      # something failed
      $content->value("errstr","Something failed getting the metadata of USER $id: ".$db->error().". Unable to proceed.");
      $content->value("err",1);
      return 0;
   }
   # we have the md - anonymize email, name and fullname
   $md->{$SysSchema::MD{username}}="zombie_${id}\@localhost"; # email/username
   $md->{$SysSchema::MD{fullname}}="Zombie_$id";
   $md->{$SysSchema::MD{name}}="Zombie_$id (zombie_${id}\@localhost)";
   $md->{"system.authenticator.oauthaccesstoken.user"}="zombie_${id}"; # this needs to change with GDPR-methods for Authenticator-modules
   # add timedate for when user was anonymized
   $md->{$SysSchema::MD{"user.deleted"}}=time();

   # set new values in metadata, thereby severing any connection or use the user has on this account anymore.
   if (!$db->setEntityMetadata($id,$md)) {
      $content->value("errstr","Something failed anonymizing metadata of USER $id: ".$db->error().". Unable to proceed.");
      $content->value("err",1);
      return 0;
   }

   # remove perm and member set for user, do not remove others permissions on user
   if (!$db->removeEntityPermsAndRoles($id,0)) {
      $content->value("errstr","Failed removing permissions and memberships of USER $id: ".$db->error().". Unable to proceed.");
      $content->value("err",1);
      return 0;
   }
  
   # check if we are to move the GDPRed user
   if ($retire) {
      # get the system settings for where to retire, so that every user can
      # ensure that he is move to retire-group after deletion
      my $retire=$cfg->value("system.user.retiregroup") || 0;
      my $parent=$db->getEntityParent($id) || 0;
      # ensure we have sane values
      if (($retire > 0) && ($parent > 0) && ($retire != $parent)) {
         # lets move the entity
         if (!$db->moveEntity($id,$retire)) {
            $content->value("errstr","Failed to move USER $id to GROUP $retire: ".$db->error());
            $content->value("err",1);
            return 0;
         }
         # set new parent location in the response
         $content->value("parent",$retire);
      }
   }

   # success!
   $content->value("errstr","");
   $content->value("err",0);

   return 1;
}

sub enumUsers {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="USER";
   $opt{namespace}=$SysSchema::MD{fullname};
#   $opt{perm}="USER_READ";
   MethodsReuse::enumEntities($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("users",$mess->value("users"));
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

sub getUserAggregatedPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # user to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="USER";   
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

sub getUserTaskAssignments {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="USER";
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

sub getUserEmail {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get id or default to user him-/herself
   my $id=$query->{id} || $userid;
   # clean it
   $id=$Schema::CLEAN{entity}->($id);

   # attempt to get users metadata
   my $md=$db->getEntityMetadata ($id);

   my $email=$md->{$SysSchema::MD{email}} || "";

   if ($email ne "") {
      # set return values
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("email",$email);

      return 1;
   } else {
      # failure
      $content->value("errstr","Unable to retrieve the users email.");
      $content->value("err",1);
      return 0;
   }
}

sub getUserId {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get email to translate to id
   my $email=$query->{email} || "";
   # clean it
   $email=$SysSchema::CLEAN{email}->($email);

   # set the metadata for the search, email is the unique identifier
   my @mdata; # use LIST so the values are or'ed together.
   push @mdata,"AND"; # must specify what to do with array, even if just one
   push @mdata,{$SysSchema::MD{"username"} => { "=" => $email }};
   # try to fetch entity
   my @type=($db->getEntityTypeIdByName("USER"));
   my $ids=$db->getEntityByMetadataKeyAndType(\@mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);

   if (defined $ids) {
      if (@{$ids} == 1) {
         # entity located - success
         my $id=$ids->[0] || 0;
         # set return values
         $content->value("errstr","");
         $content->value("err",0);
         $content->value("id",$id);

         return 1;
      } elsif (@{$ids} > 1) {
         # Multiple hits, something is wrong
         $content->value("errstr","Unable to get id of user $email. Multiple ids returned. Please contact an administrator.");
         $content->value("err",1);

         return 0;
      } else {
         # no hits
         $content->value("errstr","Unable to find id of user $email.");
         $content->value("err",1);

         return 0;
      }
   } else {
      # failure
      $content->value("errstr","Unable to retrieve the id of user $email: ".$db->error());
      $content->value("err",1);

      return 0;
   }
}

sub getUserFullname {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get id or default to user him-/herself
   my $id=$query->{id} || $userid;
   # clean it
   $id=$Schema::CLEAN{entity}->($id);

   # attempt to get users metadata
   my $md=$db->getEntityMetadata ($id);

   my $fullname=$md->{$SysSchema::MD{fullname}} || "";

   if ($fullname ne "") {
      # set return values
      $content->value("errstr","");
      $content->value("err",0);
      $content->value("fullname",$fullname);

      return 1;
   } else {
      # failure
      $content->value("errstr","Unable to retrieve the users fullname.");
      $content->value("err",1);

      return 0;
   }
}

sub getUserPerm {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # user to get perm on
   my $user=$query->{user}; # subject which perm is valid for

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{user}=$user;
   $opt{type}="USER";   
   # attempt to get perm
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

sub getUserPerms {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$query->{id}; # user to get perms on

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$id;
   $opt{type}="USER";
   # attempt to get perm
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

sub moveUser {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{parent}=$query->{parent};
   $opt{type}="USER";
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

sub setUserTaskAssignments {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{assignments}=$query->{assignments};
   $opt{type}="USER";
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

1;

__END__

=encoding UTF-8

=head1 USER METHODS

=head2 createUser()

Create a user.

Input parameters:

=over

=item

B<balanced> Enable if the creation of the user is to be balanced on the tree. BOOLEAN. Optional. Defaults to 0. 
Valid values are 0 (false) and 1 (true). If enabled the method will attempt to create sub-groups to put the 
new user in to avoid having too many user in the parent-group itself.

=cut

=item

B<parent> Group entity ID from database that the user is to be created on. INTEGER. Required.

=cut

=item 

B<username> Username of the user to create. STRING. Optional/Required. The username of the user is his 
email address. It is required if username (system.user.username) has not been set in the metadata. If set in 
metadata it is optional and metadata will take precedence.

=cut

=item

B<fullname> Full textual name of the user being created. STRING. Optional/Required. The fullname of the user is 
his first name and last name. Fullname cannot be a blank string/empty. It is required if the fullname 
(system.user.fullname) has not been set in the metadata. If set in the metadata it is optional and metadata 
will take precedence.

=cut

=item

B<metadata> Metadata to set on the user when he is created. HASH. Optional. When specified can also set the 
username and fullname of the user instead of using the separate parameters to the method. All metadata entered 
here must be within the open namespace of the metadata (starting with "."). The only exception are the username 
and fullname. The structure of the metadata is as follows:

  metadata => (
                KEYa => STRING
                KEYb => STRING
                .
                .
                KEYz => STRING
              )

Where the all entries are key->value pairs for the metadata to set.

=cut

=back

This method requires that the user has the USER_CREATE permission on the group that is the parent. Please note 
that it is assumed that if the user has this permission on the parent, he is also allowed to create sub-groups 
in the event of the balanced-parameter being true.

The balancing scheme works as follows: the first letter of a users first name is used to determine what sub-group 
the user should be put in. If the group does not exist, it will be created. Furthermore, if the first letter contains 
a character outside the ASCII-table, it is changed to a letter within A-Z (lower cases are uppercased). This is done by 
first converting any character that is a variant upon A-Za-z, such as Ä, ë, ô etc and they are changed to their base 
character (A, e and o in this case). If this does not change the first letter within A-Z, it is changed algorithmatically 
by placing it somewhere within A-Z. The last enforcement might not be logical based upon the original character, 
but is done to ensure that only the sub-groups A-Z are created and used.

It is not allowed for more than one user having one, specific email-address in the entire entity tree. Also note that attempting to 
create a user with the email: zombie_[N]@localhost, where N is a number, is not allowed. These email addresses are reserved for 
accounts that are deleted/GDPRed.

Upon success returns the following HASH structure:

  id => INTEGER # database entity ID of the newly created user.
  username => STRING # the username used (email) of the created user after cleaning.

When this method is successful it is also sent a message to the new user with a temporary password and information 
about the account creation in AURORA.

=cut

=head2 deleteUser()

Anonymize (GDPR) a USER account.

Input parameters are:

=over

=item

B<id> User entity ID from the database of the user to anonymize. INTEGER. Required.

=cut

=item

B<retire> Sets if the USER is to be move to retirement-group for cleanup purposes. BOOLEAN. Optional. Valid values are 
0 (false) and 1 (true). Defaults to 0. If no value is set the user is not moved to another group.

=cut

=back

This method requires the user to either have the USER_DELETE permission on the USER entity in question or be the user 
that is to be anonymized.

Where the user is moved in the event of setting the retire-parameter to true is defined in the system settings file. 
This enables all users to say that they wished to be moved after being GDPR'ed/deleted.

If the user himself or herself it calling this method, please remember that there is something about 
sawing off the branch of the tree one is sitting on and might lead to unplanned and unwanted encounters with 
gravity and pesky login-pages.

=cut

=head2 enumUsers()

Enumerates all user entities in the database.

No input is accepted.

The return structure is as follows:

  users => (
             IDa => STRING,
             IDb => STRING,
             .
             .
             IDz => STRING
           (

where IDa and so on is the entity id from the database and STRING is the textual display name of the user.

=cut

=head2 getUserAggregatedPerm()

Get inherited/aggregated permission(s) on the user for a user.

Input parameters:

=over

=item

B<id> User entity ID from database to get the aggregated permission(s) of. INTEGER. Required.

=cut

=item

B<user> User entity ID from database that identifies who the permission(s) are valid for. INTEGER. Optional. If not specified 
it will default to the currently authenticated user on the REST-server.

=cut

=back

Upon success this method will return the following value:

  perm => ARRAY of STRING # textual names of the permimssion(s) the user has on the given user

=cut

=head2 getUserTaskAssignments()

Gets a user's task assignments.

Input parameters are:

=over

=item

B<id> User ID from database to get the task assignments of. INTEGER. Required.

=cut

=back

Returns a HASH of task IDs assignments upon success. See the setUserTaskAssignments()-method for more information upon 
its structure.

=cut

=head2 getUserEmail()

Gets a users email address

Input parameters:

=over

=item

B<id> User entity ID from the database of the user to get the email of. INTEGER. Optional. If not given will it default to 
the user entity ID of the user logged into the REST-server.

=cut

=back

This method requires that the user has the USER_READ or USER_CHANGE permissions.

Upon success the following structure is returned:

  email => STRING # the email of the user

=cut

=head2 getUserFullname()

Get a users full name (first name and last name)

Input parameters:

=over

=item

B<id> User entity ID from the database of the user one wish to know the full name of. INTEGER. Required.

=cut

=back

Upon success returns the following structure:

  fullname => STRING # the full name of the user entity ID specified on input 

=cut

=head2 getUserId()

Get a users entity ID based on email/username.

Input parameters:

=over

=item

B<email> Email address of the user to get the user entity ID of. STRING. Required.

=cut

=back

Upon success and the email address is valid will return the following structure:

  id => INTEGER # the user entity ID of the email specified in the input.

=cut

=head2 getUserPerm()

Get user permission(s) for a given user.

Input parameters:

=over

=item

B<id> User entity ID from database of the user to get permission on. INTEGER. Required.

=cut

=item

B<user> User entity ID from database of the user which the permission(s) are valid for. INTEGER. Optional. If none 
is specified it will default to the authenticated user itself.

=cut

=back

Upon success returns the following structure:

  perm => (
            grant => ARRAY of STRING # permission(s) that have been granted on this user.
            deny => ARRAY of STRING # permission(s) that have been denied on this user.
          )

Please note that when these permissions are used by the system, what it finds for deny is applied before the grant-part 
is applied when it comes to effective permissions.

=cut

=head2 getUserPerms()

Gets all the permission(s) on a given user entity, both inherited and what has been set and the effective perm for each 
user who has any permission(s).

Input parameters:

=over

=item

B<id> User entity ID from database of the user to get the permissions of. INTEGER. Required.

=cut

=back

Upon success the resulting structure returned is:

  perms => (
             USERa => (
                        inherit => [ PERMa, PERMb .. PERMn ] # permissions inherited down on the user from above
                        deny => [ PERMa, PERMb .. PERMn ] # permissions denied on the given user itself.
                        grant => [ PERMa, PERMb .. PERMn ] # permissions granted on the given user itself. 
                        perm => [ PERMa, PERMb .. PERMn ] # effective permissions on the given user (result of the above)
                      )
             .
             .
             USERn => ( .. )
           )

USERa and so on are the USER entity ID from the database who have permission(s) on the given user. An entry for a user 
only exists if that user has any permission(s) on the user. The sub-key "inherit" is the inherited permissions from above 
in the entity tree. The "deny" permission(s) are the denied permission(s) set on the user itself. The "grant" permission(s) are 
the granted permission(s) set on the user itself. Deny is applied before grant. The sub-key "perm" is the effective or 
resultant permission(s) after the others have been applied on the given user.

The permissions that users has through groups on a given user are not expanded. This means that a group will be listed 
as having permissions on the user and in order to find out if the user has any rights, one has to check the membership of 
the group in question (if the user is listed there).

Permission information is open and requires no permission to be able to read. PERMa and so on are the textual permission 
type that are set on one of the four categories (inherit, deny, grant and/or perm). These four categories are ARRAYS of 
STRING. Some of the ARRAYS can be empty, although not all of them (then there would be no entry in the return perms for 
that user).

The perms-structure can be empty if no user has any permission(s) on the user.

=cut

=head2 moveUser()

Moves a user entity to another part of the entity tree.

Input is:

=over

=item

B<id> User entity ID from the database of the user to move. INTEGER. Required.

=cut

=item

B<parent> Parent group entity ID from the database of the group which will be the new parent of the user. INTEGER. 
Required.

=cut

=back

The method requires the user to have USER_MOVE permission on the user being moved and USER_CREATE on the parent 
group it is being moved to.

=cut

=head2 setUserTaskAssignments()

Sets a user's task assignments.

Input parameters are:

=over

=item

B<id> User ID from database to set the task assignments of. INTEGER. Required.

=cut

=item

B<assignments> HASH of task IDs from database of the assignments to set. HASH. Required. This HASH sets which task ids to assign for every 
computer id mentioned in the HASH. It is required that the user that is to have the assignments have the TASK_READ permission the task(s) 
being assigned. Or else they cannot be used. If a task id is listed in the assignments that the user does not have the TASK_READ permission 
on it is omitted from the assignment.

=cut

=back

This method requires that the user has the USER_CHANGE permission on the user having its 
assignments set (typically every user has this permission on themselves). Furthermore it requires that 
the user has the TASK_EXECUTE-permission on the task(s) being assigned to computers.

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

