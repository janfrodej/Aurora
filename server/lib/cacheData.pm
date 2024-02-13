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
package cacheData;

use strict;
use sectools;

sub new {
   my $class=shift;
   my $self={};
   bless($self,$class);

   my %opt=@_;
   if (!exists $opt{id}) { $opt{id}=sectools::randstr(32); }
   if (!exists $opt{data}) { set(); }

   # save options
   $self->{options}=\%opt;

   return $self;
}

sub set {
   my $self=shift;
   my $data=shift;

   $self->{options}{data}=$data;

   return 1;
}

sub get {
   my $self=shift;

   my $data=$self->{options}{data};

   if (ref($data) eq "SCALAR") { return $$data; }
   else { return $data; }
}

sub id {
   my $self=shift;
   
   return $self->{options}{id};
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<cacheData> - Class to hold and work with a piece of data for the cacheHandler-class.

=cut

=head1 SYNOPSIS

   use cacheData;

   # instantiate the class
   my $d=cacheData->new();

   # set the data of the instance
   my %h;
   $h{whatever}="somedata";
   $h{thisandthat}="someotherdata";
   $d->set(\%h);

   # get the data of the instance
   my $data=$d->get();
   
=cut

=head1 DESCRIPTION

A class to work with a piece of data in the cacheHandler-class. It support setting and getting the data, including adding an identifier 
for the data.

=cut

=head1 CONSTRUCTOR

=head2 new()

Constructor. Instantiate a cacheData-class.

Input accepts the following parameters:

=over

=item

B<id> Sets the unique ID of the cacheData-instance. The ID has no meaning to the class and should be used by the caller to uniquly 
identify the piece of data that the instance contains. SCALAR. Optional. If not specified will default to a random string of 32 characters.

=cut

=item

B<data> Sets the piece of data that the cacheData-instance stores. SCALAR or a variable-reference. Optional. If not set, it can be set 
later by calling the set()-method on the instance.

=cut

=back

Returns an instance of the class upon success.

=cut

=head1 METHODS

=head2 set()

Sets the piece of data that the instance contains.

It only accepts one parameter which is the data to store. The data can either be a SCALAR or 
a variable-reference.

Returns 1.

=cut

=head2 get()

Gets the piece of data that the instance contains.

If the piece of data returned was a reference to a SCALAR, the SCALAR itself is returned. 
If the data is anything else, the method just returns the piece of data.

=cut

=head2 id()

Returns the unique ID of the instance.

No parameters accepted.

The returned ID is a SCALAR.

=cut
