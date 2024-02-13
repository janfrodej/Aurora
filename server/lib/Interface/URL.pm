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
# Interface::URL: Class that defines an interface for a dataset in AURORA to an URL
#
package Interface::URL;
use parent 'Interface';

use strict;

sub new {
   my $class=shift;
   # invoke parent
   my $self=$class->SUPER::new(@_);

   # define settings
   my $o=$self->{options};
   $o->{"base"}{format}="[URL]";
   $o->{"base"}{regex}="[^\000]+";
   $o->{"base"}{length}=4096;
   $o->{"base"}{mandatory}=1;
   $o->{"base"}{default}="https://some.domain/datasets";
   $o->{"base"}{description}="External URL base for accessing the AURORA dataset data";

   # set type. not application/tar or similar, but
   # the MIME return is the URL link to the tar-set.
   $self->{type}="text/uri-list";

   return $self;
}

sub doRender {
   my $self=shift;
   my $id=shift || 0;
   my $userid=shift || 0;
   my $paths=shift;

   # get write handler
   my $write=$self->{write};

   # we are doing the rendering
   print $write time()." MERENDERING 1\n";


   # get options
   my $options=$self->options();

   # get URL base
   my $base=$self->{pars}{"base"} || $options->{"base"}{default};
   # remove trailing slashes
   $base=~s/^(.*)\/$/$1/g;

   # get information from fileinterface
   my $fi=FileInterfaceClient->new();

   # ensure we have dataset and that it can be viewed
   if ($fi->mode($id) eq "ro") {
      # unable to start process
      my @sterr;
      my $err="";
      @sterr=$fi->yell(">"); 
      if (@sterr > 0) { $err=": @sterr"; }
      # print error messages
      print $write time(). " ERROR Unable to read dataset source$err\n";
      return;
   }

   # get source path - just the cookie-part?
   my $source=$fi->datapath($id) || "DUMMY";
   # remove trailing slashes
   $source=~s/^(.*)\/$/$1/g;

   foreach (@{$paths}) {
      my $path=$_;
      # remove singular dot
      $path=($path eq "." ? "" : $path);
      # remove trailing slashes
      $path=~s/^(.*)\/$/$1/g;
      # send a MIME-result
      print $write time()." MIME $base/$source/$path\n";
   }

   # signal success
   print $write time()." SUCCESS 0\n";

   return;
}

sub doUnrender {
   my $self=shift;
   my $id=shift || 0;
   my $userid=shift || 0;
   my $paths=shift;

   # nothing to do really
   my $write=$self->{write};

   # we are doing the unrendering
   print $write time()." MERENDERING 1\n";
   # send the invalid mime-result and signal success
   print $write time()." MIME INVALID\n";
   print $write time()." SUCCESS 0\n";

   return;
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Interface::URL> Interface renderer for URL links to data.

=cut

=head1 SYNOPSIS

   use Interface::URL;

   # instantiate
   my $i=Interface::URL->new();

This class is used in the same way as the Interface-class. See documentation there for more information 
about the use of this class. 

=cut

=head1 DESCRIPTION

Interface renderer for URL links. It is based on the Interface-class and most of the methods are 
documented there as well as their use.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the class.

Takes no additional parameters except those defined in the Interface-class. Please see there for more 
information on this method.

Returns an instance of the class.

=cut

=head1 METHODS

=head2 doRender()

Performs the rendering of the URL links.

This method is inherited from the Interface-class and please see there for more information 
on its use and functioning.

This method is not to be called by the user.

=cut

=head2 doUnrender

Performs the unrendering of the URL links.

This method is inherited from the Interface-class and please see there for more information 
on its use and functioning.

This method is not to be called by the user.

=cut
