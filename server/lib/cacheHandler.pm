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
package cacheHandler;
use strict;
use cacheData;
use Content::YAML;
$YAML::XS::LoadBlessed=1;

sub new {
   my $class=shift;
   my $self={};
   bless ($self,$class);

   my %opt=@_;
   if (!exists $opt{location}) { my $p=$ENV{"AURORA_PATH"} || "/local/app/aurora"; $opt{location}=$p; }

   $self->{options}=\%opt;

   # create list
   my %list;
   $self->{list}=\%list;

   # set a default filename
   $self->{options}{filename}="mainsrvc.cache";

   # set updated flag
   $self->{updated}=0;

   return $self;
}

sub add {
   my $self=shift;
   my $d=shift;

   if ((!defined $d) || (!$d->isa("cacheData"))) {
      $self->{error}="This is not a cacheData-instance. Unable to add it.";
      return 0;
   }

   # check if exists
   if (!$self->exists($d)) {
      my $list=$self->{list};
      $list->{$d->id()}=$d;
      # set updated flag
      $self->{updated}=1;
      return 1;
   } else {
      $self->{error}="This cacheData-instance has already been added. Unable to add it again.";
      return 0;
   }
}

sub get {
   my $self=shift;
   my $d=shift; 

   if ($self->exists($d)) {
      my $id=(ref(\$d) eq "SCALAR" ? $d : $d->id());
      return $self->{list}{$id};      
   } else {
      $self->{error}="Data does not exist. Unable to get it.";
      return undef;
   }  
}

sub resetGetNext {
   my $self=shift;

   my %l;
   $self->{nexted}=\%l;
   $self->{nextedcomplete}=0;

   return 1;
}

sub getNext {
   my $self=shift;

   # get list of all data instances
   my $list=$self->{list};
   # get list of all instances already nexted
   my %n;
   my $nexted=$self->{nexted} || \%n;
   my $complete=$self->{nextedcomplete} || 0;
   
   # only continue if there are more keys left in main list
   # compared to what has been next'ed
   if (!$complete) {
      foreach (keys %{$list}) {
         my $d=$list->{$_};
         my $id=$d->id();
         # success if not in nexted list, add to list and return data-instance
         if (!exists $nexted->{$id}) { $nexted->{$id}=1; return $d }
      }
      # we went through list without finding any new one - we are complete
      $self->{nextedcomplete}=1;
      # there is no more
      return undef;
   } else {
      return undef; # there is no more
   }
}

sub remove {
   my $self=shift;
   my $d=shift;

   my $n=$self->get($d);

   if (!defined $n) {
      # doesnt exist
      $self->{error}="Unable to locate data for removal. Unable to proceed.";
      return 0;
   } else {
      # exists, remove from list
      my $id=$d->id();
      delete ($self->{list}{$id});
      # remove instance
      $d=undef;
      # set updated flag
      $self->{updated}=1;
      return 1;
   }
}

sub exists {
   my $self=shift;
   my $d=shift;

   my $id="";
   if ((defined $d) && ($d->isa("cacheData"))) {
      $id=$d->id();
   } else {
      if ((defined $d) && (ref(\$d) eq "SCALAR")) {
         $id=$d;
      } elsif ((!defined $d) || (!$d->isa("cacheData"))) {
         $self->{error}="This is not a cacheData-instance. Unable to check if it exists.";
         return 0;
      }
   }

   my $list=$self->{list};
   if (exists $list->{$id}) {
      return 1;
   } else {
      return 0;
   }
}

sub load {
   my $self=shift;
   my $loc=shift||"";

   # get location
   $loc=($loc eq "" ? $self->location() : $loc);
   # get filename
   my $name=$self->{options}{filename};
   # get list
   my $list=$self->{list};   

   # attempt to get cache data from file
   if (open (FH,"<","$loc/$name")) {
      my $y=join("",<FH>);
      eval { close (FH) };
  
      # try to convert file YAML into a list HASH
      my $c=Content::YAML->new();
      my $r=$c->decode($y);
      if (defined $r) {
         # decoding  was a success - put it into list
         my $l=$c->get();
         # overwrite old list content
         $self->{list}=$l;
         return 1;
      } else {
         # an error occured
         $self->{error}="Unable to load cache from file because of converter error: ".$c->error();
         return 0;
      }
 
   } else {
      $self->{error}="Unable to open cache-file \"$loc/$name\" for reading: $!";
      return 0;
   }
}

sub save {
   my $self=shift;
   my $loc=shift||"";

   # only do save if updated
   if ($self->updated()) {
      # get location
      $loc=($loc eq "" ? $self->location() : $loc);
      # get filename
      my $name=$self->{options}{filename};

      my $list=$self->{list};
      # try to convert list into YAML
      my $c=Content::YAML->new();
      my $y=$c->encode($list);
      if (defined $y) {
         # encoding was a success - save it
         if (open (FH,">","$loc/$name")) {
            print FH $y;
            eval { close (FH) };
            # set updated to false again
            $self->{updated}=0;
         } else {
            $self->{error}="Unable to open cache-file \"$loc/$name\" for writing: $!";
            return 0;
         }
      } else {
         # an error occured
         $self->{error}="Unable to save cache to file because of converter error: ".$c->error();
         return 0;
      }
   }

   # already saved - return 1
   return 1;
}

sub location {
   my $self=shift;

   if (@_) {
      my $loc=shift;
      $self->{options}{location}=$loc;
   } else {
      return $self->{options}{location};
   }
}

# check if updated since last 
# actual save
sub updated {
   my $self=shift;

   return $self->{updated} || 0;
}

sub error {
   my $self=shift;

   return $self->{error}||"";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<cacheHandler> - Class to handle cache data for an AURORA application and load- and save to file.

=cut

=head1 SYNOPSIS

   use cacheHandler;
   use cacheData;

   # instantiate the class
   my $h=cacheHandler->new();
   my $d=cacheData->new();
   
   # add cacheData to handler
   $h->add($d);

   # remove cachedata from handler
   $h->remove($d);

   # get a cacheData-instance
   my $cdi=$h->get("myID");

   # reset iterating over list of cacheData-instances
   $h->resetGetNext();

   # get next cacheData-instance in list until end of list
   while (my $cdi=$h->getNext()) {
      print "My cacheData ID: ".$cdi->id()."\n";
   }

   # check if cacheData-instance exists in list or not
   if ($h->exists("MyID")) { print "Exists!\n"; }

   # load saved cache into cacheHandler-instance
   $h->load();

   # save cache in cacheHandler-instance to file
   $h->save();

   # check if cacheData has been updated in handler
   if ($h->updated()) { print "List has been updated!\n"; }

   # get last error message
   my $msg=$h->error();

=cut

=head1 DESCRIPTION

Class to handle a list of cacheData-instances that contain data that an AURORA application needs to keep. Enables one to add, remove,
check for existence, get and load- and save the cache to/from a file.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the class.

Accepts the following parameters:

=over

=item

B<location> Sets the location or path of the cache-file that the class writes. SCALAR. Optional. If not specified, it defaults to the contents 
of the environment-variable "AURORA_PATH" and if that is not specified it is set to "/local/app/aurora".

=cut

=back

The filename of the cache-file is set to "mainsrvc.cache".

Returns the class-instance.

=cut

=head1 METHODS

=head2 add()

Adds a cacheData-object to the cacheHandler.

Accepts only one parameters: data. The data-parameter must be a reference to a cacheData-instance or else 
this method fails.

Sets the updated-attribute of the class to 1 upon success signalling that the data contained in the handler has 
changed.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

=cut

=head2 get()

Gets a specific cacheData-object.

Accepts only one parameter: id. ID is the textual unqiue ID of the cacheData-instance to fetch if it is in the 
cacheHandler at all.

Returns the cacheData-instance upon success, undef upon failure. Please check the error()-method for more information 
upon failure.

=cut

=head2 resetGetNext()

Resets the getting next cacheData-instance from the class's list of data.

Resets the pointer in the class list of cacheData-instances and starts from the beginning again.

No input is accepted. Always returns 1.

=cut

=head2 getNext()

Gets the next cacheData-instance in the list.

No input is accepted.

Returns the cacheData-instance upon success, or undef if there are no more instances to fetch.

=cut

=head2 remove()

Removes a cacheData-instance from the list of the class.

One input parameter is accepted: either cacheData- ID or instance. 

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon 
failure.

=cut

=head2 exists()

Checks if a cacheData-instance exists or not in the class list?

Accepts one input: either cacheData ID or instance.

Returns 1 if the cacheData-instance in question are in the class list, or 0 if not.

=cut

=head2 load()

Loads cached data from a file.

Accepts one parameter: location. SCALAR. Optional. If not specified will use the location-setting from 
the new()-method or set through the location()-method (see the new()-method).

Attempts to load the saved cache from a file. The file format is YAML and it will attempt to 
convert the YAML data into perl data structures.

It will overwrite any cache that are already present in the cacheHandler-instance.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information 
upon failure.

=cut

=head2 save()

Saves the cacheData list of the cacheHandler to a file.

Accepts only one input: location. SCALAR. Optional. If not specified will use the location-setting from
the new()-method (see the new()-method).

The method will only save the data if the data has changed. It checks this by calling the 
updated()-method to see if the cacheHandler-instance data has changed (either by add or remove). 
After the data has been successfully written to file it resets the updated-status to false. This mechanism 
makes it possible to more often and repeatedly call the save()-method without it actually 
triggering unnecessary I/O-operations.

The cacheData-list of the cacheHandler is saved in YAML-format.

This method returns 1 upon success, 0 upon failure. Please check the error()-method for more 
information upon failure.

=cut

=head2 location()

Get or set the location of the cache-file.

Accepts one input if is a set-operation: location. SCALAR. Required if set-operation. Sets the 
location of where the cache-file resides, which are used by the load()- and save()-methods.

Returns the location-setting upon a set-operation.

=cut

=head2 updated()

Checks if the data in the cacheHandler-instance has been updated or not?

No input accepted.

Returns 1 if updated, 0 if not.

=cut

=head2 error()

Get the last error from the class.

No input is accepted.

Returns a SCALAR with the last error message, if any.

=cut
