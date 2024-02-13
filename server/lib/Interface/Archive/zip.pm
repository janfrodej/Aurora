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
# Interface::Archive::zip - Class for rendering zip-archives to AURORA datasets
#
package Interface::Archive::zip;
use parent 'Interface::Archive';

use strict;
use POSIX;
use IPC::Open3;
use Symbol 'gensym';

sub new {
   my $class=shift;
   # invoke parent
   my $self=$class->SUPER::new(@_);   

   # set binary
   my $pars=$self->{pars};
   # add parameter for location of binary
   if (!exists $pars->{binary}) { $pars->{binary}="/usr/bin/zip"; }
   
   # set format 
   $self->{format}="zip";

   return $self;
}

sub startArchiving {
   my $self=shift;
   my $id=shift || 0;
   my $userid=shift || 0;
   my $paths=shift;
   my $source=shift;
   my $destination=shift;
   my $endmarker=shift;

   my $oldfolder = getcwd();
   $oldfolder =~ /(.*)/;
   $oldfolder = $1;

   # change to folder to be backed up
   if ($source eq "/") {
      pipe (my $read, my $write);
      $self->{aread}=$read;
      $self->{apid}=0;
      $self->{actime}=0;
      print $write "Source folder invalid ($source). Not allowed to proceed of security reasons.\n";
      return;
   }

   if (!chdir ("$source")) {
      pipe (my $read, my $write);
      $self->{aread}=$read;
      $self->{apid}=0;
      $self->{actime}=0;
      print $write "Unable to change directory to source folder ($source): $!\n";
      return;
   }

   # get binary 
   my $binary=$self->{pars}{binary};

   my $read=gensym;
   my $err;
   my $pid=open3(undef,$read,$read,$binary,"-r",$destination,@{$paths});
   if (defined $pid) {
      # parent - do nada
   } else {
      # error comes in $!
      pipe (my $read, my $write);
      $self->{apid}=$pid;
      $self->{actime}=0;
      $self->{aread}=$read;
      print $write "Unable to run zip-archiving command: $!\n";
      chdir ($oldfolder);
      return;
   }
   # process running in background - store info
   $self->{apid}=$pid;
   $self->{actime}=(stat ("/proc/$pid/stat"))[10] || 0;
   # save pipe
   $self->{aread}=$read;
   chdir ($oldfolder);
   return;
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Interface::Archive::zip> - Class for generating zip-sets of AURORA dataset data.

=cut

=head1 SYNOPSIS

   use Interface::Archive::zip;

   # instantiate
   my $i=Interface::Archive::zip->new(location=>"/somewhere/overhere",script=>"https://domain/mydownloadscript.pl");

This class is used in the same way as the Interface-class. Please see the Interface-class for more documentation.

=cut

=head1 DESCRIPTION

Class for generating zip-sets of AURORA dataset data.

It inherits from the Archive-class, which again inherits from the Interface-class.

It makes it possible to generate a zip-set of all or parts of the AURORA dataset data and then make a MIME URL as return value telling where the
generated it can be fetched.

See the Archive-class for more information.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the class.

Inherits from the Archive-class and then sets the format ("zip") and binary location for the zip-command (if no override by user
has been specified).

Returns the instantiated class.

=cut

=head1 METHODS

=head2 startArchiving()

Starts the archiving-process using the zip-command.

See the startArchiving()-method documentation in the Archive-class for more information.

=cut

