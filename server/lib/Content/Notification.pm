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
# Class: Content::Notification - class to represent a content class of type Notification and methods on it
#
package Content::Notification;
use parent 'Content';

use strict;
use Time::HiRes qw(time); # only use higres time here
use MIME::Base64;
#use Encode;

sub encode {
   my $self = shift;
   my $content=shift || $self->{content};

    # try to convert content into coded notification
    if (ref($content) eq "HASH") {
       # check that all necessary keys are present - type,id,message
       if ((exists $content->{entity}) &&
           (exists $content->{message})) {
          # set time to current time if not set
          my $entity=$content->{entity}||0;
          $content->{entity}=$entity;
          my $time=$content->{time}||time();
          $content->{time}=$time;
          my $msg=$content->{message}||"";
          $content->{message}=$msg;
          # check parameter types and bounds
          if ($content->{time} !~ /^[-+]?[0-9]*\.?[0-9]+$/) {
             $self->{error}="Parameter \"time\" (".$content->{time}.") is of wrong format and required to be a float.";
             return undef;
          }
          if ($content->{entity} !~ /\d+/) {
             $self->{error}="Parameter \"entity\" (".$content->{entity}.") is of wrong format and required to be an integer.";
             return undef;
          }
          # base64 encode fields
          $entity=MIME::Base64::encode_base64(Encode::encode_utf8($entity));
          $time=MIME::Base64::encode_base64(Encode::encode_utf8($time));
          $msg=MIME::Base64::encode_base64(Encode::encode_utf8($msg));
          # ready create joined string
          my $encoded=join($self->delimiter(),$time,$entity,$msg);
          # return result
          return $encoded;
       } else {
          $self->{error}="Missing parameter to encode method. You need entity and message.";
          return undef;
       }
   } else {
      $self->{error}="Input to method needs to be a hash.";
      return undef;
   }
}

sub decode {
   my $self = shift;
   my $content=shift || "";

   if ($content ne "") {
      # get values 
      my ($time,$entity,$message,$remainder)=grep { $_=MIME::Base64::decode_base64($_) } split($self->delimiter(),$content,4);
      # ensure that remainder is either a value or a blank
      $remainder=(defined $remainder ? $remainder : "");

      # check input
      if ($time !~ /^[-+]?[0-9]*\.?[0-9]+$/) {
         $self->{error}="Parameter \"time\" ($time) is of wrong format and required to be a float.";
         return undef;
      }
      if ($entity !~ /\d+/) {
         $self->{error}="Parameter \"entity\" ($entity) is of wrong format and required to be an integer.";
         return undef;
      }
   
      # convert to hash
      my %c;
      $c{time}=$time || 0;
      $c{entity}=$entity || 0;
      $c{message}=$message||"";
    
      # set instance content
      $self->{content}=\%c;
  
      # return remainder
      return $remainder;
   } else {
      # no decoding happened
      $self->{error}="Unable to decode empty data. Please input some data to this method.";
      return undef;
   }
}

sub type {
   my $self = shift;

   return "application/notification";
}

sub delimiter {
   my $self = shift;

   return ";";
}

sub fields {
   my $self = shift;

   # return array of field names for the Content or if empty return at least one field name
   return ("time","entity","message");
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Content::Notification> - Class to encode and decode Notification data to and from a HASH.

=cut

=head1 SYNOPSIS

Used in the same way as the placeholder class Content. See Content-class for more information.

=cut

=head1 DESCRIPTION

Class to encode and decode Log data to and from a HASH. Is inherited from the Content-class, so see the Content-class for 
more information on the use of the general methods not described here.

=head1 CONSTRUCTOR

same as for the Content placeholder-class. See the Content-class for more information.

=cut

=head1 METHODS

=head2 encode()

Inherited from the Content-class, but in this case encodes a HASH into Notification data and returns the encoded Notification data.

Input is the optional HASH reference to be encoded. If no HASH-reference is given, it will use the one internally to the
Content-class and that are set by the set()-method.

It will return the Log data upon success, undef upon failure. Please check the error()-method for more information.

=cut

=head2 decode()

Inherited from the Content-class, but in this case decodes Notification data into a Perl HASH. It sets the internal 
HASH to the decoded result upon success.

Input is a SCALAR with the Notification data. If no input is specified it will default to a blank string.

It returns a blank string upon success or if there is remainder data after one record it returns the remainder string (which
can be used again to decode the next record).

Undef is returned upon failure. Check the error()-method for more information on the failure.

=cut
