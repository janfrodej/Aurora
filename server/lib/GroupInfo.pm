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
# GroupInfo : class to get groupinfo on a user
#
package GroupInfo;
use strict;

# instantiate class
sub new {
   my $class=shift;
   my $self={};
   bless ($self,$class);

   my %pars=@_;
   # set defaults
#   if (!$pars{whatever}) { $pars{whatever}=""; }

   $self->{pars}=\%pars;

   my %groups;
   $self->{groups}=\%groups;

   return $self;
}

# get AURORA relevant groups that user is a member of
sub getGroups {
   my $self=shift;
   my $email=shift||"dummy\@localhost";

   # get groups and store information, including their IDs
   # in the $self->{groups}-hash.
   # $self->{groups}{GROUPNAME}{id}=XYZ;

   # return LIST-ref with textual names
   return [];
}

# get a group IDs name
sub getGroupName {
   my $self=shift;
   my $id=shift||undef;

   if (defined $id) {
      my $result;
      my $groups=$self->{groups};
      foreach (keys %{$groups}) {
         my $name=$_;

         if ($groups->{$name}{id} eq $id) {
            $result=$name; last;
         }
      }
      if ($result) { return $result; }
      else { return undef; }
   } else { return undef; }
}

# get a specific groups ID
sub getGroupID {
   my $self=shift;
   my $group=shift||"MYGROUP";

   # get ID from already saved data
   my $groups=$self->{groups};
   my $id=(defined $groups->{$group} ? $groups->{$group}{id} : undef);

   # return a unique identifier for named group or undef if not found
   return $id;
}

# get a groups location in a hierarcy/tree
sub getGroupPath {
   my $self=shift;
   my $group=shift||"MYGROUP";

   # return path as a LIST-ref with item 0 being at the top going down towards
   # the group itself
   return [];
}

# get AURORA namespace locaton in metadata
# for id
sub namespace {
   my $self=shift;

   return "system.group.groupinfo.id.global";
}

sub error {
   my $self=shift;

   return $self->{error}||"";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<GroupInfo> - Placeholder class that represents ways of retrieving group-memberships on an AURORA-user

=cut

=head1 SYNOPSIS

   use GroupInfo;
    
   # instantiate
   my $gi=GroupInfo->new();

   # get users groups
   my $groups=$gi->getGroups("john.doe@domain.topdomain");

   # get a groups unique ID (whatever works for the sub-class in question)
   my $id=$gi->getGroupID("mygroup");

   # get a groups name from ID
   my $name=$gi->getGroupName ($id);

   # get a groups path (up to inheriting sub-class to define) 
   my $path=$gi->getGroupPath("mygroup");

   # get AURORA metadata namespace location for the group ID
   my $location=$gi->namespace();

=cut

=head1 DESCRIPTION

Placeholder class that represents ways of retrieving group-memberships on an AURORA-user.

This class is meant to be overridden by a sub-class that implements a specific way to retrieve or source of group-information 
for a specific user. The uniting identifier is the users email-address. How this is solved in the sub-class is up to the 
creator of it, but there must be some way to connect email to its belonging groups.

After one has collected the groups with the getGroups()-method, one can retrieve information about the groups in various ways, 
including its unique ID and the path to the group.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the class.

Accepts no input.

Returns the class instance.

=cut

=head1 METHODS

=head2 getGroupID()

Get the unique ID of the group in question.

The method accepts one input: email-address (SCALAR). This is the email address of the user that one wishes to get the groups of.

Upon success the method returns the textual names of the groups in an ARRAY-ref. Undef upon failure. Please 
check the error()-method for more information. 

Also when this method is run it fills the internal information of the GroupInfo-class with the group-information for 
the user, including their unique IDs. This method should be run immediately after instantiating the class to 
ensure that group-information for the user is in the instance when calling the other methods. The internal location of 
the group-information is the $self->{groups}-variable.

This method is to be overridden by the inheriting sub-class. How the group information is retrieved is then up to 
the sub-class in question. Also what constitutes a unique ID for the group is up to the sub-class in question. The 
unique ID is only valid within the context of the method/source of the inheriting class.

If the retrieved ID is to be stored in AURORA metadata, we admonish that the namespace location retrieved with the 
namespace()-method is used.

=cut

=head2 getGroupName()

Get the textual name of a unique group ID.

This method takes one input: group ID (SCALAR). Group ID must be in the format of the inheriting sub-class and fulfills its 
requirements for it.

It returns the textual name from the group ID.

=cut

=head2 getGroupPath()

Get the path of a group name.

This method takes one input: group name (SCALAR). 

Based upon the group name the method must be able to return the path down to the group, if any, and this path can 
then be used to create group-entity structures in AURORA. How this is solved is up to the inheriting class as long as 
it returns a consistent answer.

Upon success returns the path of the group as a ARRAY-ref. The ARRAY may be empty if the group in question does not have any 
path, but when it has a path the order of the ARRAY should be top-down in the tree-structure. It must not include the 
group itself, only the path down to it.

=head2 getGroups()

Get the groups that the user is a member of.

Accepted input is: email-address (SCALAR). 

This method is to be overridden by the inheriting class. It is meant to retrieve all the groups that the given user (in the 
form of his email-address) is a member of. How this is solved is up to the sub-class, but it must be able to receive an 
email address and convert that into groups that the user is a member of. It must also update the $self->{groups}-hash variable 
with the groups and their corresponding unqiue ID. The structure is as follows:

   (  GROUPNAME => { 
                     name => SCALAR,  # GROUP NAME (redundant)
                     id   => SCALAR,  # UNIQUE_ID
                   }
   )

Upon success this method is to return the ARRAY-reference of all the groups that the user is a member of in a 
textual form. The ARRAY-ref may be empty if the user has no group-memberships. Upon failure the return is undef. 
Then check the error()-method for more information.

=cut

=head2 namespace()

Retrieves the group ID namespace location in AURORA.

This defines where in the AURORA namespace the unique ID of the group can be stored (if used). This method is to be 
overridden by the inheriting class.

returns the textual namespace location (SCALAR).

=cut
