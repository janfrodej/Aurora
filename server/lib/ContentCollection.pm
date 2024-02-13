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
# Class: ContentCollection - class for a Collection of content instances and methods on it
#
package ContentCollection;

use strict;
use Content;

sub new {
   # instantiate
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # check values, set defaults
   if ((!$pars{type}) || (!$pars{type}->isa("Content"))) { $pars{type}=Content->new(); }

   # save parameters
   $self->{pars}=\%pars;

   # reset content
   $self->reset();

   # set last error message
   $self->{error}="";

   # return instance
   return $self;
}

sub reset {
   my $self = shift;

   if (@_) {
      # new Content type has been specified
      my $c=shift;
      $self->{pars}{type}=$c;
      if (!$self->{pars}{type}->isa("Content")) { $self->{pars}{type}=Content->new(); }
   }

   # set an empty list
   my @l;
   $self->{list}=[];

   # reset pos
   $self->resetnext();

   # return success
   return 1;
}

sub add {
   my $self=shift;

   if (@_) {
      my $c=shift;
      if ($c->isa($self->type())) {
         # right type - add to end of list
         push @{$self->{list}},$c;
         return 1;
      } else {
         # wrong class type
         $self->{error}="Wrong class-type. It needs to be a ".ref($self->{pars}{type})."-class.";
         return 0;
      }
   } else {
      # missing parameter
      $self->{error}="Missing parameter Content-class instance.";
      return 0;
   }
}

sub remove {
   my $self = shift;

   if (@_) {
      my $c=shift;
      if ($c->isa(ref($self->{pars}{type}))) {
         # go through each member and remove the one specified
         my @l=$self->{list};
         my @l2;
         foreach (@l) {
            my $n=$_;
 
            # only remove if the instance is the same
            if ($n == $c) {
               # found - do not include
               next();
            } else {
               # add to list
               push @l2,$n;
            }
         }
         # set new list
         $self->{list}=@l2;
         return 1;
      } else {
         # wrong type
         $self->{error}="Wrong type, it should be a ".ref($self->{pars}{type})."-class. Cannot remove this from collection.";
         return 0;
      }
   } else {
      # missing parameter
      $self->{error}="Missing parameter for Content-class instance.";
      return 0;
   }
}

sub type {
   my $self = shift;

   return ref($self->{pars}{type});
}

sub resetnext {
   my $self = shift;

   # set pointer to first element of list
   $self->{pos}=0;
   
   return 1;
}

sub next {
   my $self = shift; 

   my $pos=$self->{pos} || 0;

   if ($pos < $self->size()) {
      my $c=$self->{list}[$pos];
      $pos++;
      $self->{pos}=$pos;
      return $c;
   } else {
      # out of bounds - return undef
      return undef;
   }
}

sub size {
   my $self = shift;

   my $size=@{$self->{list}};

   return $size;
}

sub error {
   my $self = shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<ContentCollection> - Class to hold a collection of Content-instances and manipulation of that collection.

=cut

=head1 SYNOPSIS

   my $content=Content::JSON->new();
   my $coll=ContentCollection->new(type=>$content);

   $coll->resetnext();
   while (my $c=$coll->next()) {
      my $hash=$c->decode();
   }

   $coll->size();
   $coll->type();

=cut

=head1 DESCRIPTION

A class to hold a collection of Content-instances of a given type (no mixing). The type is set upon instantiation. It has 
methods to iterate over the contents of the collection and add- or remove from it.

=cut

=head1 CONSTRUCTOR

=head2 new()

Constructor of ContentCollection-class.

Input is type-parameter that sets the Content-class type to use in the collection. The type parameter must be a Content-class.

Creates ContentCollection instance. If wrong or no type of content-instance is specified, an empty Content-class is created.

After Content-class type has been saved it is expected that all additions of Content-classes are of the same type. If one wants to change type one needs to call the reset()-method (see description).

Return value is the instance of ContentCollection.

=cut

=head1 METHODS

=head2 reset()

Resets the ContentCollection list of Content-instances.

No input is required, but if one wants one can add an instance of a Content-class. The ContentCollection will then expect all future classes that are added to be of this type.

If no Content-class is specified the reset()-method keeps the already set Content-class type.

Return value is 1 for success.

=cut

=head2 add()

Adds a Content-class instance to the ContentCollection list.

Return value is 1 upon success and 0 upon failure. Please check the error()-method to establish exact reason.

=cut

=head2 remove()

Removes a Content-class instance from the ContentCollection list.

A parameter that gives the Content-class instance is expected as input. If no input is given or wrong Content-class type it will result in failure.

Return valyes are 1 upon success and 0 upon failure. Please call the error()-method to establish the full reason.

=cut

=head2 type()

Returns the Content-class type that the ContentCollection consists of or expects to be used.

No input required.

=cut

=head2 resetnext()

Resets the next()-methods position counter, so that one can start giving out Content-class from the beginning of the list.

Return value is 1 for success.

=cut

=head2 next()

Retrives the next Content-class instance from the ContentCollection list.

Return the Content-class instance upon success and undef upon failure.

=cut

=head2 size()

No input needed. Returns the number of Content-class elements in the collection.

=cut

=head2 error()

Returns the last error message from the ContentCollection-class.

No input is required.

=cut


