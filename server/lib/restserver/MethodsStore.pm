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
# MethodsStore: Store-entity methods for the AURORA REST-server
#
package MethodsStore;
use strict;
use RestTools;

sub registermethods {
   my $srv = shift;

   $srv->addMethod("/deleteStore",\&deleteStore,"Delete a store.");
   $srv->addMethod("/enumStoreRequiredParameters",\&enumStoreRequiredParameters,"Enumerate required parameters to use a store.");
   $srv->addMethod("/enumStores",\&enumStores,"Enumerate all stores.");
   $srv->addMethod("/moveStore",\&moveStore,"Move store to another group.");
   $srv->addMethod("/setStoreName",\&setStoreName,"Set/change the store name.");
}

sub deleteStore {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="STORE";
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

sub enumStoreRequiredParameters {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $id=$Schema::CLEAN{entity}->($query->{id});
   my $classparam=$Schema::CLEAN_GLOBAL{hash}->($query->{classparam},1);

   # check if id exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("STORE"))[0])) {
      # does not exist 
      $content->value("errstr","Store $id does not exist or is not a STORE entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   if ((defined $classparam) && (ref($classparam) ne "HASH")) {
      # wrong classparam type (must be a HASH)
      $content->value("errstr","Classparam-parameter is not a HASH. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # get store metadata
   my $md=$db->getEntityMetadata($id);

   if (!defined $md) {
      # something failed
      $content->value("errstr","Unable to get metadata of store $id: ".$db->error().". Unable to fulfill request.");
      $content->value("err",1);
      return 0; 
   }

   # success - get class name of store
   my $class=$md->{$SysSchema::MD{"store.class"}};

   # attempt to instantiate class
   my $store;
   if (defined $classparam) { eval { $store=$class->new(%{$classparam}); }; }
   else { eval { $store=$class->new(); }; }

   if (!defined $store) {
      # unable to instantiate store - abort
      $content->value("errstr","Unable to instantiate store $id of class \"$class\". Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # success - lets get required params
   my %req=$store->paramsRequired();

   # return the result
   $content->value("parameters",\%req);
   $content->value("errstr","");
   $content->value("err",0);
   return 1;
}

sub enumStores {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="STORE";
   MethodsReuse::enumEntities($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("stores",$mess->value("stores"));
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

sub moveStore {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{parent}=$query->{parent};
   $opt{type}="STORE";
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

sub setStoreName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{duplicates}=undef; # do duplicates in entire tree
   $opt{type}="STORE";
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

=head1 STORE METHODS

=head2 deleteStore()

Delete a store entity.

Input parameters:

=over

=item

B<id> Store entity ID from the database of the store to delete. INTEGER. Required.

=cut

=back

This method requires that the user has the STORE_DELETE permission on the store in question.

=cut

=head2 enumStoreRequiredParameters()

Enumerate all parameters required by a store.

Input parameters are:

=over

=item

B<id> Entity ID from the database of the store to get the required parameters of. INTEGER. Required.

=cut

=item

B<classparam> Parameters to the instantiation of the Store-class. HASH. Optional. It can be used to 
specify parameters that are going to be used when instantiating a class-instance, which again can affect 
which required parameters are asked for. It only accept 1 depth hashes, so only key->value pairs.

=cut

=back

Upon success returns the following HASH-structure:

    parameters = (
                   PARAMETER1 = (
                                  value = STRING # current value
                                  private = INTEGER # is the parameter private to the class or not (0/1)?
                                  regex = STRING # regex to check the value against
                                  escape = INTEGER # is the value to be escaped (0/1)?
                                  required = INTEGER # is the value required or not (0/1)? Obviously always 1 here.
                                  name = STRING # name of the parameter
                                )
                   .
                   .
                   PARAMETERn = ( ... )
                 )

=cut

=head2 enumStores()

Enumerates all the store entities in the database.

No input accepted.

Upon success the return structure is as follows:

  stores => (
              STOREIDa => STRING # key->value, where key is the store entity ID and STRING is the display name of the store-entity.
              .
              .
              STOREIDx => STRING
            )

STOREIDa and so on is the store entity ID from the database (INTEGER).

=cut

=head2 moveStore()

Move store to another group parent.

Input parameters:

=over

=item

B<id> Store entity ID from the database of the store to move. INTEGER. Required.

=cut

=item

B<parent> Parent group entity ID from the database of the group which will be the new parent of the store. INTEGER. 
Required.

=cut

=back

The method requires the user to have STORE_MOVE permission on the notice being moved and STORE_CREATE on the parent 
group it is being moved to.

=cut

=head2 setStoreName()

Set/change the display name of a store.

Input parameters:

=over

=item

B<id> Store entity ID from the database of the store to change its name. INTEGER. Required.

=cut

=item

B<name> The new store name to set. STRING. Required. Does not accept blank string and the new name must not 
conflict with any existing store name in the entire tree (including itself).

=cut

=back

Method requires the user to have the STORE_CHANGE permission on the store changing its name.

=cut
