#!/usr/bin/perl -Tw
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
# Class: DataContainer - class to represent a data container and methods on it
#
package DataContainer;

use strict;
use Content;
use ContentCollection;

# datacontainer modes
our $MODE_READ = 1;       # in open terms "<"
our $MODE_READWRITE = 2;  # in open erms "+<"
our $MODE_OVERWRITE = 3;  # in open terms ">"
our $MODE_APPEND = 4;     # in open terms +>>"
our $MODE_TOTAL = 4;

# I: location:scalar, name:scalar
# O: instance of the class
# C: Constructor. All paramters are optional. Location and Name parameters only have meaning to inherting class
sub new {
   # instantiate
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # check values, set defaults
   if (!$pars{location}) { $pars{location}=""; }
   if (!$pars{name}) { $pars{name}=""; }
   if ((!$pars{collection}) || (!$pars{collection}->isa("ContentCollection"))) { $pars{collection}=ContentCollection->new(); }

   # save parameters
   $self->{pars}=\%pars;

   # set last error message
   $self->{error}="";

   # return instance
   return $self;
}

# I: none
# O: 1
# C: Resets the data content
sub reset {
   my $self = shift;
 
   # reset content
   my $c=$self->get();
   $c->reset();
   $self->set($c);

   return 1;
}

sub open {
   my $self = shift;

   return 1;
}

sub opened {
   my $self = shift;

   return $self->{opened} || 0;
}

sub close {
   my $self = shift;

   return 1;
}

# I: contentcollection:a ContentCollection class
# O: 1
# C: Sets the contentcollection of the data container
sub set {
   my $self = shift;
   my $collection= shift || ContentCollection->new();

   if ($collection->isa("ContentCollection")) {
      # save the content object.
      $self->{pars}{collection}=$collection;
      return 1;
   } else {
      $self->{error}="Set Collection is not of the right type! It must be a ContentCollection-class.";
   }
}

# I: none
# O: 1
# C: Gets the contentcollection instance of the data container
sub get {
   my $self = shift;

   return $self->{pars}{collection} || ContentCollection->new();
}

# I: name:scalar
# O: 0 upon failure, 1 upon success
# C: Loads name into the instance. If called without parameters it will attempt to load default name in default location. This method is to be overridden.
sub load {
   my $self= shift;
   my $name = shift || $self->{pars}{name};

   # do whatever loading is required in inheriting class and return 1 upon success, 0 upon failure
   my $collection = $self->{pars}{collection} || ContentCollection->new();
   $collection->resetnext();
   while (my $c=$collection->next()) {
      my $content=$c->decode();
   }

   return 1;
}

# I: name:scalar
# O: 1 - success, 0 = failure
# C: save current contentcollection. All parameters are optional. This method is to be overridden.
sub save {
   my $self = shift;
   my $name = shift || $self->{pars}{name};

   # get content to save
   my $collection = $self->{pars}{collection} || ContentCollection->new();

   # do whatever to save content in inherting class and return 1 upon success, 0 upon failure
   $collection->resetnext();
   while (my $c=$collection->next()) {
      my $converted = $c->encode();
   }

   return 1;
}

# I: name:scalar
# O: 1 on success, 0 on failure
# C: Attempt deletion of data from datacontainer. All parameters are optional and if name is not given, it is taken from the instance. To be overridden bhy inheriting class.
sub delete {
   my $self = shift;

   return 1;
}

# get or set the mode of operation of the DataContainer. Overwrite is default if no other is set-
sub mode {
   my $self = shift;
   
   if (@_) {
      # this is a set
      my $mode=shift || $MODE_OVERWRITE;
      # ensure only integer
      $mode=~s/[^\d]+//g;
      $mode=($mode =~ /^\d+$/ ? $mode : 1);
      if (($mode >= 1) and ($mode <= $MODE_TOTAL)) {
         # within valid range
         $self->{mode}=$mode || $MODE_OVERWRITE;
         # return mode set
         return $mode;
      } else {
         # mode outside bounds
         $self->{error}="Invalid mode specified: $mode. Could not set it.";
         return 0;
      }
   } else {
      # this is a get
      return $self->{mode} || $MODE_OVERWRITE;
   }
}

# I: name:scalar
# O: 1 or the current name
# C: Get or set the current name. If name is omitted, it is a get and vice versa
sub name {
   my $self = shift;
   
   if (@_) {
      # this is a set
      my $name=shift || "";
      $self->{pars}{name}=$name;
      return 1;
   } else {
      # this is a get
      return $self->{pars}{name} || "";
   }
}

# I: location:scalar
# O: 1 or the current location
# C: Get or set the current location. If location is omitted, it is a get and vice versa
sub location {
   my $self = shift;
   
   if (@_) {
      # this is a set
      my $l=shift || "";
      $self->{pars}{location}=$l;
      return 1;
   } else {
      # this is a get
      return $self->{pars}{location} || "";
   }
}

# I: none
# O: message:scalar
# C: gets the last error message of the instance
sub error {
   my $self = shift;

   # return error message
   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

B<DataContainer> - Placeholder class to represent various ways of loading and storing data.

=cut

=head1 SYNOPSIS

   use DataContainer;

   my $dc=DataContainer->new();

   $dc->load("whatever");

   $dc->save("something");

=cut

=head1 DESCRIPTION

A collection of functions to handle the conversion to and from unixtime and iso8601-time.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the class

The method supports the following parameters:

=over

=item

B<location> The location of the data. SCALAR. Only has meaning to the inheriting class.

=cut

=item

B<name> The name of the data container. SCALAR. Only has meaning to the inheriting class.

=cut

=item

B<collection> The collection instance to use for this DataContainer. See the ContentCollection-class's documentation.

=cut

=back

Returns an instanciated class upon success.

=cut

=head1 METHODS

=head2 reset()

Reset the data that has been loaded into the DataContainer.

No input accepted.

Returns 1.

=cut

=head2 open()

Open the DataContainer for reading and/or saving.

Accepts only one parameter "name". SCALAR. Optional. If it is specified it overrides 
the name specified to the constructor. Name only has meaning to the overriding sub-class.

Return 1 upon success, 0 upon failure. Please check the error()-method upon failure.

This is a placeholder method that is to be overridden and given meaning by the inheriting 
sub-class.

=cut

=head2 opened()

Returns if the DataContainer has been opened or not?

Accepts no input parameters.

Returns 1 if opened, 0 if not.

=cut

=head2 close()

Close the DataContainer.

Accepts only one optional parameter "name" SCALAR. If it is specified it overrides 
the name specified to the constructor. Name only has meaning to the overriding/
inheriting class.

Returns 1 upon success, 0 upon failure. Please check the error()-method upon failure.

This is a placeholder method that is to be overridden and given meaning by the 
inheriting sub-class.

=cut

=head2 set()

Sets the ContentCollection instance of the object.

Input is the ContentCollection instance to set.

Returns 1 upon success, 0 upon failure.

=cut

=head2 get()

Get the ContentCollection instance for the object.

No input is accepted.

Returns the ContentCollection-instance. If it has not been 
set at any point it returns a new ContentCollection-instance.

=cut

=head2 load()

Load data into the DataContainer using the ContentCollection-instance.

Accepts one parameter "name". SCALAR. Optional. If not specified defaults to 
the name-parameter of the constructor. The meaning of "name" is up to the inheriting 
sub-class.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more 
information upon failure.

This is a placeholder class and is to be overridden by the inheriting sub-class.

=cut

=head2 save()

Save data to the DataContainer using the ContentCollection-instance.

Accepts one parameter "name". SCALAR. Optional. If not specified defaults to 
the name-parameter of the constructor. The meaning of "name" is up to the inheriting 
sub-class.

Returns 1 upon success, 0 upon failure. Please check the error()-method upon failure.

This is a placeholder class and is to be overridden by the inheriting sub-class.

=cut

=head2 delete()

Delete data from the DataContainer.

Accepts one parameter "name". SCALAR. Optional. If not specified defaults to the 
name-parameter of the constructor. The meaning of "name" is up to the inheriting 
class.

Returns 1 upon success, 0 upon failure. Please check the error()-method upon failure.

This is a placeholder class and is to be overridden by the inheriting sub-class.

=cut

=head2 mode()

Get or set the mode of the DataContainer.

Accepted input is the parameter "mode" that specifies the mode to set.

The following mode-constants are acceptable:

=over

=item

B<$MODE_READ> (only reading allowed)

=cut

=item

B<$MODE_READWRITE> (read/write allowed)

=cut

=item

B<$MODE_OVERWRITE> (overwrite any existing file)

=item

B<$MODE_APPEND> (add data to the DataContainer, do not overwrite)

=cut

=back

Returns the value of the mode set if success, 0 upon failure. Please check the 
error()-method for more information upon any failure.

=cut

=head2 name()

Get or set the name of the DataContainer.

Accepts only one parameter. SCALAR. Optional. If one parameter is specified, it will be interpreted as a set-operation.

Returns 1 upon success setting the name, or the name of the DataContainer upon success getting it.

=cut

=head2 location()

Gets or sets the location parameter.

Accepts only one parameter. SCALAR. Optional. If a parameter is specified, it will be interpreted as a set-operation.

Returns 1 upon success setting the location, or the location of the DataContainer upon success getting it.

=cut

=head2 error()

Gets the last error that the package/instance did.

Accepts no input.

Upon success returns the last known error as a SCALAR.

=cut
