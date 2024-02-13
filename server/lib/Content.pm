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
# Class: Content - class to represent a content class and methods on it
#
package Content;

use strict;
use MIME::Base64;
use Encode ();

sub new {
   # instantiate
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # check values, set defaults

   # save parameters
   $self->{pars}=\%pars;

   # initiate content
   $self->reset();

   # set last error message
   $self->{error}="";

   # return instance
   return $self;
}

sub reset {
   my $self = shift;
 
   # reset content
   my %h;
   $self->set(\%h);

   # reset counter
   $self->{counter}=0;
   $self->{encoded}="";
   $self->{fields}=["dummy"];

   return 1;
}

sub set {
   my $self = shift;
   my $content = shift || "";

   if (ref($content) eq "HASH") {
      # set the content
      $self->{content}=$content;
      return 1;
   } else { 
      # wrong type
      $self->{error}="Wrong type. It needs to be a pointer to a hash.";
      return 0;
   }
}

sub get {
   my $self = shift;

   my %h;
   return $self->{content} || \%h;
}

sub value {
   my $self = shift;
   my $name = shift;

   if (@_) {
      # set value
      my $value=shift;
      $self->{content}{$name}=$value;
      return 1;  
   } else {
      # return value if it exists
      if (exists $self->{content}{$name}) {
         return $self->{content}{$name};
      } else {
         # does not exist
         $self->{error}="Unable to get value for key \"$name\" since it does not exist";
         return undef;
      }
   }
}

sub encode {
   my $self = shift;

   return 1;
}

sub decode {
   my $self = shift;

   return 1;
}

sub type {
   my $self = shift;

   return "application/octet-stream";
}

sub delimiter {
   my $self = shift;

   # return default delimiter
   return ";"; 
}

sub fields {
   my $self = shift;
   
   # return array of field names for the Content or if empty return at least one field name
   return ("data");
}

sub resetnext {
   my $self = shift;

   my $data;

   if ($data=$self->encode()) {
      # data encoded - store for later use by next()
      $self->{encoded}=$data;
      $self->{counter}=0;
      return 1;
   } else {
      # failed to encode - error already set
      return 0;
   }
}

sub next {
   my $self = shift;

   my $pos=$self->{counter} || 0;
   my $data=$self->{encoded} || "";

   # get element, dependant upon delimiter type
   if ($self->delimiter() =~ /\d+\,/g) {
      # numbered field sizes where there are no delimiters
      # this mode also do not base64 encode data
      my @mpos=split(",",$self->delimiter());
      if ($pos < @mpos) {
         my $start=$mpos[0]-1 || 0;
         my $stop=$mpos[1]-1 || length($data)-1;
         if ($pos < @mpos) { $pos++;}
         $self->{counter}=$pos;
         return substr($data,$start,($stop-$start)) || "";
      } else { 
         return undef;
      }
   } elsif ($self->delimiter() ne "") {
      # delimiter type data
      # data is base64 encoded, so decode after splitting the data
#      my @fields=grep { $_=MIME::Base64::decode_base64($_) } split($self->delimiter(),$data);
      my @fields=grep { $_=Encode::decode("UTF-8",MIME::Base64::decode_base64($_)) } split($self->delimiter(),$data);
      if ($pos < @fields) {
         my $ret=$fields[$pos] || "";
         $pos++;
         $self->{counter}=$pos;
         return $ret;
      } else {
         # end of the line
         return undef;
      }
   } else {
      # no delimiter - all data as one field
      # but only return value once, then return undef
      if ($pos == 0) {
         $pos++;
         $self->{counter}=$pos;
         return $data;
      } else {
         # end of the line
         return undef;
      }
   }  
}

sub error {
   my $self = shift;

   # return error message
   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Content> - Placeholder class to represent a content of some format and methods to encode and decode between it and a HASH-structure.

=cut

=head1 SYNOPSIS

   my $c=Content::new();

   $c->encode();

   $c->decode();

=cut

=head1 DESCRIPTION

A class to define content-formats and methods to encode and decode between them and a HASH-structure. It can handle formats with delimiters or with 
numbered field sizes. It enables the abstraction of the underlying storage format with the manipulation in Perl of a HASH-structure.

=head1 CONSTRUCTOR

=head2 new()

Constructor of the class.

It requires no input and the return value is the instance.

=cut

=head1 METHODS

=head2 reset()

Resets the data content of the instance. 

The return value is always 1 (success).

=cut

=head2 set()

Sets the content of the Content-class. 

The input must be a pointer to a hash. The return value is 0 upon failure and 1 upon success.

=cut

=head2 get()

Gets the content of the class. 

Returns a pointer to a hash.

=cut

=head2 encode()

Encodes the content of the class into the format of the Content-class. 

It takes no input and the return values are undef upon failure and upon success the encoded data (usually a scalar).

Upon failure the error message can be read by calling the error()-method.

If the delimiter-type of the class in question is a character type (see the delimiter()-method), then the 
data between the delimiter is to be Base64-encoded.

This class is to be overridden by the inheriting Content-class.

=cut

=head2 decode()

Decodes the formatted input to the method and puts it into a hash.

It takes the format of the Content-class as input and then return undef upon failure or the remainder of the input if any (scalar). Upon success it sets the content of the Content-class to the hash.

To retrieve the decoded data call the get()-method upon success.

To get the error message after a failure call the error()-method.

If the delimiter-type of the class in question is a character type (see the delimiter()-method), then the 
data between the delimiter is to be Base64-decoded.

This class is to be overridden by the inheriting Content-class.
=cut

=head2 type()

Returns the MIME type of the Content-class.

The method takes no input and returns a scalar as the MIME type.

This method is to be overridden by the inheriting Content-class
=cut

=head2 delimiter()

Return the delimiter of the encoded format of the Content-class

The method takes no input and returns the delimiter in one of the following variants:

=over 2

=item

As a blank (""), which means it has no delimiter. It is basically just one field.

=cut

=item

As a character (eg. ";").

=cut

=item

As an array of numbers (eg. 1,6,20)

=cut

=back

The numbers signifies where one field starts, so in the example above the first field starts at the beginning of
the encoded data (position 1, not 0) and the next data field after that starts at 6, then after that at 20 and so on.

The next()-method returns fields of data from the encoded data based on this delimiter setting in the Content-class,
with the exception of classes where a hash is returned by others libraries directly (more advanced parsing). That is
up to the inheriting Content-class to decide. In cases where the delimiter setting is not used, the delimiter shall be blank ("").

This method is to be overridden by the inheriting class to deliver the right delimiter as feedback.
=cut

=head2 fields()

Returns an array of the field names of the Content-class.

The output will also be an array when getting the field names.

It will always return at least one field name. In cases where the Content is just a converted bulk of data one shall only use one field name. In cases where the content is decoded by a function returning a hash also just set one field name.

Field names should only be set by inheriting Content-class by overriding this class.

=cut

=head2 resetnext()

Resets he next element iteration of the encoded content of the Content-class. The iteration counter is set to the first element for subsequent calls by
the next-method.

The method returns 1 upon success and 0 upon failure.
=cut

=head2 next()

Gets the next element of the encoded data of the Content-class. The iteration counter is incremented, so that subsequent calls 
get the next element.

The element is returned based upon the setting of the delimiter-method. If no delimiter is set it will typically just return the whole encoded record.

=cut

=head2 error()

Gets the last error message from the Content-class.

No input required and the return messages is of type scalar.

=cut



