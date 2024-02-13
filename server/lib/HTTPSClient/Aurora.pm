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
# Class: HTTPSClient::Aurora - a HTTPSClient library to use with an Aurora REST-server
#
package HTTPSClient::Aurora;
use parent 'HTTPSClient';
use strict;

# DESTROY and autoloader is all we need to call methods on the REST-server

sub DESTROY {
   my $self = shift;
}

sub AUTOLOAD {
   my $self = shift;
   my $response = shift;
   my %options = @_;

   our $AUTOLOAD;
   # get method name
   (my $method=$AUTOLOAD) =~ s/^.*://;

   # call method by using lazydo
   if ($self->lazydo ($method,$response,%options)) {
      # success
      return 1;
   } else {
      # failure
      return 0;
   }
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<HTTPSClient::Aurora> - A HTTPS-client to connect to the AURORA REST-server.

=cut

=head1 SYNOPSIS

Is used in the same way as the HTTPSClient class. See HTTPSClient for more information.

Module makes it possible to execute any method-name on the HTTPS-server by taking the method-name you call and wrapping it as a servermethod-call through the
AUTOLOAD-mechanism.

   use HTTPSClient::Aurora;

   # after instantiation - see HTTPSClient documentation for that
   my %resp;
   my %parameters;
   $parameters{resourcetype}="whatever";
   if ($h->getServerResources (\%resp,%parameters)) {
      use Data::Dumper;
      print "RESULT: ".Dumper(\%resp);
   } else {
      print "ERROR: ".$h->error();
   }

=cut

=head1 DESCRIPTION

A HTTPS-client to connect to the AURORA REST-server. It is basically a wrapper that inherits from the HTTPSClient-class and implements the AUTOLOAD 
mechanism in order to call any server-method that are called on it by using the lazydo()-method.

=cut

=head1 CONSTRUCTOR

Inherits from the HTTPSClient-class. See the HTTPSClient-class for more information.

=cut

=head1 METHODS

=head2 DESTROY

Standard Perl DESTROY-method that has to be defined in order to avoid a call to it calling the AUTOLOAD-mechanism.

=cut

=head2 AUTOLOAD

Standard AUTOLOAD mechanism that makes it possible to execute any method on the HTTPS-server and have it wrapped in a lazydo()-call.

See AUTOLOAD for more documentation.

=cut
