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
# NTNU : GroupInfo-class to get group info from NTNU-ldap
#
package GroupInfo::NTNU;
use parent 'GroupInfo';
use strict;
use LDAPInfo;

our $SERVER="at.ntnu.no";
our $UBASE="ou=people,dc=ntnu,dc=no";
our $GBASE="ou=groups,dc=ntnu,dc=no";

# get AURORA relevant groups that user is a member of
sub getGroups {
   my $self=shift;
   my $email=shift||"dummy\@localhost";

   # get groups and store information, including their IDs
   # in the $self->{groups}-hash.
   # $self->{groups}{GROUPNAME}{id}=XYZ;
   my $ldap=LDAPInfo->new(server=>$SERVER);
   if ($ldap->bind()) {
      # search for a user and get his fg-groups
      my $search=$ldap->search($UBASE,"(mail=$email)");
      if (defined $search) {
         # get user uid, so we can search for his groups
         if (keys %{$search} == 1) {
            # get uid
            my $uid=$search->{0}{uid}||"";
            if ($uid) {
               # search for groups
               my $search2=$ldap->search($GBASE,"(memberUid=$uid)");
               if (defined $search2) {
                  my @grps;
                  my $groups=$self->{groups};
                  foreach (keys %{$search2}) {
                     my $no = $_;
                     my $group=$search2->{$no}{cn}||"";
                     my $id=$search2->{$no}{gidNumber};
                     $id=(defined $id ? $id : undef);
                     # only collect research groups
                     if ($group =~ /^fg\_.*$/) { 
                        push @grps,$group;
                        # store more info to the instance
                        $groups->{$group}{name}=$group;
                        $groups->{$group}{id}=$id;
                     }
                  }
                  # return whatever we found, if any
                  return \@grps;
               } else {
                  $self->{error}="Unable to search LDAP-server: ".$ldap->error();
               }
            } else {
               $self->{error}="Unable to find users username. Cannot continue...";
               return undef;
            }
         } else {
            $self->{error}="Email-address is ambigeous. Got multiple hits on same address: $email";
            return undef;
         }
      } else {
         $self->{error}="Unable to search LDAP-server: ".$ldap->error();
         return undef;
      }
   } else {
      $self->{error}="Unable to connect to LDAP-server: ".$ldap->error();
      return undef;
   }
}

# get a groups location in a hierarcy/tree
sub getGroupPath {
   my $self=shift;
   my $group=shift||"MYGROUP";

   my @path;

   my $us=0;
   while ($group =~ /^([a-zA-Z0-9]+\_)?([a-zA-Z0-9]+)([\-]?)(.*)$/) {
      my $ou=$2;
      my $px=$3||"";
      $group=$4;
      if (($px eq "-") || (($px eq "_") && ($us))) { push @path,$ou; $us=1; }
   }  

   # return path as a LIST-ref with item 0 being at the top going down towards the group itself
   return \@path;
}

sub namespace {
   my $self=shift;

   return "system.group.groupinfo.id.ntnu";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<GroupInfo::NTNU> - Class to retrieve research group-memberships of a user in NTNUs LDAP-catalogue

=cut

=head1 SYNOPSIS

   use GroupInfo::NTNU;

   # instantiate
   my $gi=GroupInfo::NTNU->new();

   # get users groups
   my $groups=$gi->getGroups("john.doe@ntnu.no");

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

Class to retrieve research group-memberships of a user in NTNUs LDAP-catalogue.

This class is inherited from the GroupInfo-class. Please see the class-documentation of the 
GroupInfo-class for more in-depth information.

=cut

=head1 METHODS

=head2 getGroupPath()

This function returns the path to the group in question in AURORA.

This method is specific to group-admin at NTNU. It parses the group-name to retrieve the 
path where the group is to be placed.

See the GroupInfo-class for more information on this method.

=cut

=head2 getGroups()

Get the groups at NTNU that a specific user are a member of at NTNU.

Uses LDAP to get the relevant group-memberships.

See the GroupInfo-class for more information on this method.

=cut

=head2 namespace()

Returns the AURORA namespace location for the ID of this sub-class.

See the GroupInfo-class for more information on this method.

=cut
