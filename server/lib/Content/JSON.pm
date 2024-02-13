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
# Class: Content::JSON - class to represent a content class of type JSON and methods on it
#
package Content::JSON;
use parent 'Content';

use strict;
use JSON;

sub encode {
   my $self = shift;
   my $content=shift || $self->{content};

    # try to convert content into JSON
   my $err;
   my $j;
   local $@;
   eval { my $a=JSON->new(); $j=$a->encode ($content); };
   $@ =~ /nefarious/;
   $err = $@;

   if ($err eq "") {
      # encoding was a success - return JSON
      return $j;
   } else {
      # an error occured
      $self->{error}="Unable to convert content into ".$self->type().": $err.";
      return undef;
   }
}

sub decode {
   my $self = shift;
   my $content=shift || "";

   my $err;
   my $h;
   local $@;
   eval { my $a=JSON->new(); $h=$a->decode ($content); };
   $@ =~ /nefarious/;
   $err=$@;

   if ($err eq "") {
      # decoding was a success - return structure it was converted into and set instance content
      $self->{content}=$h;
      # in this class the return is always blank
      return "";
   } else {
      # an error occured
      $self->{error}="Unable to decode content of type ".$self->type().": $err";
      return undef;
   }
}

sub type {
   my $self = shift;

   return "application/json";
}

sub delimiter {
   my $self = shift;

   return "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Content::JSON> - Class to encode and decode JSON data to and from a HASH.

=cut

=head1 SYNOPSIS

Used in the same way as the placeholder class Content. See Content-class for more information.

=cut

=head1 DESCRIPTION

Class to encode and decode JSON data to and from a HASH. It uses the JSON::XS module to decode and encode to and from JSON 
data. 

=head1 CONSTRUCTOR

same as for the Content placeholder-class. See the Content-class for more information.

=cut

=head1 METHODS

=head2 encode()

Inherited from the Content-class, but in this case encodes a HASH into JSON data and returns the JSON data.

Input is the optional HASH reference to be encoded. If no HASH-reference is given, it will use the one internally to the
Content-class and that are set by the set()-method.

It will return the JSON data upon success, undef upon failure. Please check the error()-method for more information.

=cut

=head2 decode()

Inherited from the Content-class, but in this case decodes JSON data into a Perl HASH. It sets the internal 
HASH to the decoded result upon success.

Input is a SCALAR with the JSON data. If no input is specified it will default to a blank string.

It returns a blank string upon success, undef upon failure. Check the error()-method for more information on the failure.

=cut
