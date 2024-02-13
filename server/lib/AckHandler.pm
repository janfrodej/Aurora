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
# AckHandler: a class to handle ack-files in the ack-folder of the notification-service
#
package AckHandler;
use strict;

# constructor
sub new {
   # instantiate  
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # set defaults if not specified      
   if (!exists $pars{folder}) { my $p=$ENV{"AURORA_PATH"} || "/local/app/aurora"; $p=$p."/notification/Ack"; $pars{folder}=$p; }

   # save parameters
   $self->{pars}=\%pars;

   # get folder 
   my $folder=$pars{folder};

   # set mask and save old
   my $omask = umask 0;

   # create ack-folder quick and dirty
   mkdir ("$folder",01730);

   # set old mask again   
   umask $omask;

   return $self;
}

# create an ack file, if not exists already
# if it exists, we avoid touching mtime by
# just skipping creating it
sub add {
   my $self=shift;
   my $id=shift || "";
   my $rid=shift || "";

   my $folder=$self->folder();

   # create ack-file if not exists already
   if (!-e "$folder/${id}_${rid}") {
      if (!open FH,">","$folder/${id}_${rid}") {
         # failed
         return 0;
       }
   } else { return 1; } # ack-file already exists
   # file is open, we just need to close it
   eval { close (FH); };
   return 1;
}

# remove ack file, if it exists
sub remove {
   my $self=shift;
   my $id=shift || "";
   my $rid=shift || "";

   my $folder=$self->folder();

   if (-e "$folder/${id}_${rid}") {
      # attempt to unlink ack-file
      if (!unlink ("$folder/${id}_${rid}")) {
         $self->{error}="Unable to remove ack-file ${id}_${rid}: ".$!;
         return 0;
      } else {
         return 1;
      }
   }

   return 1;
}

# touch ack-file
sub touch {
   my $self=shift;
   my $id=shift;
   my $rid=shift;

   my $folder=$self->folder();

   # open file for writing in order to touch it
   if (!open FH,">","$folder/${id}_${rid}") {
      # failed
      $self->{error}="Unable to touch file: $!";
      return 0;
   }
   eval { close (FH); };

   return 1; 
}

# get mtime of ack-file
sub mtime {
   my $self=shift;
   my $id=shift;
   my $rid=shift;

   my $folder=$self->folder();

   # check that file exists first
   if ($self->exists($id,$rid)) {
      # stat file
      my $mtime=(stat("$folder/${id}_${rid}"))[9];
      # return datetime
      return $mtime;
   } else {
      $self->{error}="Ack-file ${id}_${rid} does not exist. Cannot get mtime.";
      return undef;
   }
}

# check if an ack-file exists
sub exists {
   my $self=shift;
   my $id=shift;
   my $rid=shift;

   my $folder=$self->folder();

   if (-f "$folder/${id}_${rid}") {
      return 1; # exists
   } else { 
      return 0; # do not exists
   }
}

sub folder {
   my $self=shift;

   return $self->{pars}{folder} || "";
}

sub error {
   my $self=shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<AckHandler> - Class to handle ack-files in the ack-folder of the notification-service

=cut

=head1 SYNOPSIS

   use AckHandler;

   # create instance
   my $ah=AckHandler->new();

   # add ack-file
   $ah->add($id,$rid);

   # touch ack-file
   $ah->touch($id,$rid);

   # get ack-file mtime
   my $mtime=$ah->mtime($id,$rid);

   # remove ack-file
   $ah->remove($id,$rid);

   # get last error
   my $err=$ah->error();

=cut

=head1 DESCRIPTION

A class to handle ack-files in the ack-folder of the notification-service.

The class enables ack-files to be added, removed, touched and retrieved mtime of.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates class.

The method takes one optional input: folder. It specifies the folder where the AURORA Notification-service saves its 
ack-files.

Returns an instance upon success.

=cut

=head1 METHODS

=head2 add()

Adds an ack-file to the Notification-services ack-folder.

Takes two parameters in the following order:

=over

=item

B<id> The notification ID. See the Notification-class for more information.

=cut

=item

B<rid> The RID to create the ack-file for. See the Notification-class for more information.

=cut

=back

Returns 1 upon success, 0 upon failure. It will also return 1 if the file already exists. To get more information 
on a potential error call the error()-method.

=cut

=head2 remove()

Remove an ack-file from the Notification-services ack-folder.

Takes two parameters in the following order:

=over

=item

B<id> The notification ID. See the Notification-class for more information.

=cut

=item

B<rid> The RID to remove the ack-file for. See the Notification-class for more information.

=cut

=back

Returns 1 upon success, 0 upon failure. It will also return 1 if the file doesnt exist. To get more information on a 
failure, call the error()-metod.

=cut

=head2 touch()

Touches the mtime of an ack-file in the Notification-services ack-folder.

Takes these parameters in the following order:

=over

=item

B<id> The notification ID. See the Notification-class for more information.

=cut

=item

B<rid> The RID of the ack-file to touch. See the Notification-class for more information.

=cut

=back

Returns 1 upon success, 0 upon failure. Check the error()-method for more information upon a failure.

=cut

=head2 mtime()

Get an ack-file's mtime.

Takes these parameters in the following order:

=over

=item

B<id> The notification ID. See the Notification-class for more information.

=cut

=item

B<rid> The RID of the ack-file to get the mtime for. See the Notification-class for more information.

=cut

=back

Returns 1 upon success, undef upon failure. Check the error()-method for more information upon a failure.

=cut

=head2 exists()

Checks if an ack-file exists or not.

Takes these parameters in the following order:

=over

=item

B<id> The notification ID. See the Notification-class for more information.

=cut

=item

B<rid> The RID of the ack-file to check if exists or not. See the Notification-class for more information.

=cut

=back

Returns 1 upon success, 0 upon failure. Check the error()-method for more information upon a failure.

=cut

=head2 error()

Gets the last error of the module, if any.

No input accepted.

Returns the last error message generated by the module, if any at all.

=cut

