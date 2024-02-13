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
# Parameter: class to handle binaries and their parameters
#
package Parameter;
use strict;
use sectools;

# placeholder constructor, to be overridden/amended

sub new {
   # instantiate
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   $self->{error}="";

   my %opt=@_;
   if (defined $opt{name}) { $self->name($opt{name}); } else { $self->name(sectools::randstr(32)); } 
   if (defined $opt{quote}) { $self->quote($opt{quote}); } 
   if (defined $opt{escape}) { $self->escape($opt{escape}); }
   if (defined $opt{private}) { $self->private($opt{private}); }

   $self->{opt}=\%opt;

   # objects list
   my @o; # # empty at this time
   $self->{objects}=\@o;

   return $self;
}

sub name {
   my $self=shift;

   if (@_) {
      # set
      my $name=shift;
      $name=~s/[^a-zA-Z0-9]//g;
      $name=(defined $name && $name !~ /^\s+$/ ? $name : sectools::randstr(32));
      $self->{options}{name}=$name;
   }

   # set or get
   return $self->{options}{name};
}

# set or get if object is to be quote
sub quote {
   my $self=shift;
   
   if (@_) {
      # this is a set
      my $value=shift;
      $value=(defined $value && $value =~ /^[01]{1}$/ ? $value : 0);
      $self->{options}{quote}=$value;
   }

   # set or get
   return $self->{options}{quote} || 0;
}

sub escape {
   my $self=shift;
   
   if (@_) {
      # this is a set
      my $value=shift;
      $value=(defined $value && $value =~ /^[01]{1}$/ ? $value : 0);
      $self->{options}{escape}=$value;
   }

   # set or get
   return $self->{options}{escape} || 0;
}

sub private {
   my $self=shift;

   if (@_) {
      # set
      my $priv=shift;
      $priv=(defined $priv && $priv =~ /^[01]{1}$/ ? $priv : 1);
      $self->{options}{private}=$priv;
      return $priv;
   }

   # get or set
   if (!exists $self->{options}{private}) { return 1; }
   else { return $self->{options}{private}; }
}

# placeholder to be overridden
sub toString {
   my $self=shift;

   return "";
}

sub type {
   my $self=shift;

   # return instance type,
   # remember to set in sub-class new
   return $self->{type};
}

# clone yourself
sub clone {
   my $self = shift;

   return bless ({%{$self}},ref ($self));
}

sub error {
   my $self=shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Parameter> - Class to define parameters of eg. a command.

=cut

=head1 SYNOPSIS

This is a placeholder class and are not to be used directly. To use the Parameter-classes, it is natural to instantiate a 
Parameter::Group-class and start from there.

=cut

=head1 DESCRIPTION

Class to define parameters of eg. a command. It defines the common, basic methods and attributes shared by the 
Parameter::Group- and Parameter::Variable-classes. It is only a placeholder class and is not meant to be instantiated.

An overview of concepts:

=over

=item

B<Object> A Parameter-object that can be added to a group. It can be either a Parameter::Group or 
Parameter::Variable-class type.

=cut

=item

B<Parameter> An item returned as a single entity to the user of the Parameter-class. It can consist of one or more 
Parameter::Variable-instances. The Parameter::Group-class decides if a collection of variables and/or sub-groups 
are to be returned as one parameter. Basically anything organized under a sub-group of the main-parameter-group 
will be returned as one parameter for that sub-group.

=cut

=item

B<Group> A collection of sub-groups and/or variables. It has certain attributes that can be set on it, such as 
if it is to be escaped, quoted and/or have no space between its parameters.

=cut

=item

B<Variable> A named value that can be set in a group. It has certain attributes that can be set on it, such as 
if it is to be escaped, quoted, be private or not and so on. Please see the Parameter::Variable-class documentation for 
more info on the Parameter::Variable-type.

=cut

=back

=cut

=head1 CONSTRUCTOR

=head2 new()

Sets up the parameter-classes and returns an instance of the class.

It accepts the following options:

=over

=item

B<name> Sets the name of the parameter-object. Defaults to a random 32-character name if none specified. The name chosen 
must be unique.

=cut

=item

B<quote> Sets if the parameter-class type is to be quoted or not. Defaults to 0. 1 means true, 0 means false.

=cut

=item

B<escape> Sets if the parameter-class type is to be escaped or not. Defaults to 0. 1 means true, 0 means false.

=cut

=item

B<private> Sets if the parameter-class type is to be private or not. Defaults to 1. 1 means true, 0 means false.

=cut

=back

This method returns an instantiated class upon success.

=cut

=head1 METHODS

=head2 clone()

Clones the whole instance

Accepts no input

Returns the reference to the copied object.

=cut

=head2 error()

Get the last error message, if any.

Accepts no input.

Returns the last error message that happened, if any.

=cut

=head2 escape()

Get or set if the instance is to be escaped or not.

In the case of set accepts one input: escape. 1 means true, 0 means false.

Upon either get or set, returns the current setting of the escape-attribute. 
Again, 1 means true, 0 means false.

=cut

=head2 name()

Get or set the name of instance.

In the case of set accepts one input: name. Name can only be in the character set of 
a-z, A-Z and 0-9.

Upon either get or set, returns the current name. 

=cut

=head2 private()

Get or set if the instance is to be private or not.

In the case of set accepts one input: private. 1 means true, 0 means false.

Upon either get or set, returns the current setting of the private-attribute. 
Again, 1 means true, 0 means false.

=cut

=head2 toString()

Convert parameter-instance to a string.

Accepts no input.

This is a placeholder class and is to be overridden by inherting classes.

Returns a string or blank.

=cut

=head2 type()

Returns the type of the Parameter-instance.

Accepts no input.

Returns the type of the Parameter-instance, either "Group" or "Variable". The type-
setting is set in the constructor of the inherited class.

=cut

=head2 quote()

Get or set if the instance is to be quoted or not.

In the case of set accepts one input: quote. 1 means true, 0 means false.

Upon either get or set, returns the current setting of the quote-attribute. 
Again, 1 means true, 0 means false.

=cut
