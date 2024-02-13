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
# Class: Content::YAML - class to represent a content class of type YAML and methods on it
#
package Content::YAML;
use parent 'Content';

use strict;
use YAML::XS qw(Dump Load);

sub new {
   my $class = shift;

   my $self=$class->SUPER::new(@_);

   # de-reference deep hash structures if so ordered
   if ((defined $self->{pars}{deref}) && ($self->{pars}{deref} =~ /^1$/)) { $YAML::UseAliases=1; }

   return $self;
}

sub encode {
   my $self = shift;
   my $content=shift || $self->{content};

    # try to convert content into YAML
   my $err;
   my $y;
   eval { $y=Dump($content); };
   $@ =~ /nefarious/;
   $err = $@;

   if ($err eq "") {
      # encoding was a success - return YAML
      return $y;
   } else {
      # an error occured
      $self->{error}="Unable to convert content into ".$self->type().": $err.";
      return undef;
   }
}

sub decode {
   my $self = shift;
   my $content=shift || "";

    # try to convert content from YAML
   my $err;
   my $h;
   eval { $h=Load($content); };
   $@ =~ /nefarious/;
   $err = $@;

   if ($err eq "") {
      # decoding was a success - return structure it was converted into and set instance content
      $self->{content}=$h;
      # return remainder always blank in this class
      return "";
   } else {
      # an error occured
      $self->{error}="Unable to convert content from ".$self->type().": $err.";
      return undef;
   }
}

sub type {
   my $self = shift;

   return "application/yaml";
}

sub delimiter {
   my $self = shift;

   return "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Content::YAML> - Class to encode and decode YAML data to and from a HASH.

=cut

=head1 SYNOPSIS

Used in the same way as the placeholder class Content. See Content-class for more information.

=cut

=head1 DESCRIPTION

Class to encode and decode YAML data to and from a HASH. It uses the YAML::XS module to decode and encode to and from YAML 
data. 

=head1 CONSTRUCTOR

=head2 new()

same as for the Content placeholder-class. See the Content-class for more information.

In addition it has the following parameter(s):

=over

=item

B<deref> Specifies if the HASH-structure that one is decoding/encoding is supposed to use references or not? Optional. Boolean. 
If not specified will default to 0. Valid values are either 1 (true), 0 (false).

=cut

=back

Returns an instance of the class if successful.

=cut

=head1 METHODS

=head2 encode()

Inherited from the Content-class, but in this case encodes a HASH into YAML data and returns the YAML data.

Input is the optional HASH reference to be encoded. If no HASH-reference is given, it will use the one internally to the
Content-class and that are set by the set()-method.

It will return the YAML data upon success, undef upon failure. Please check the error()-method for more information.

=cut

=head2 decode()

Inherited from the Content-class, but in this case decodes YAML data into a Perl HASH. It sets the internal 
HASH to the decoded result upon success.

Input is a SCALAR with the YAML data. If no input is specified it will default to a blank string.

It returns a blank string upon success, undef upon failure. Check the error()-method for more information on the failure.

=cut

