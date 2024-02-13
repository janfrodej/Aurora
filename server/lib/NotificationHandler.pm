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
# NotificationHandler: a class to handle several notification instances in a folder
#
package NotificationHandler;

use strict;
use Notification;
use File::Path qw (remove_tree);
use File::Copy qw(mv);

# constructor
sub new {
   # instantiate  
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # set defaults if not specified      
   if (!exists $pars{folder}) { my $p=$ENV{"AURORA_PATH"} || "/local/app/aurora"; $p=$p."/notification"; $pars{folder}=$p; }

   # save parameters
   $self->{pars}=\%pars;

   # get folder 
   my $folder=$pars{folder};

   # set mask and save old
   my $omask = umask 0;

   # create root-folder quick and dirty
   mkdir ("$folder",0771);

   # create ack-folder quick and dirty
   mkdir ("$folder/Ack",01730);

   # set old mask again   
   umask $omask;

   # reset getting next notification
   $self->resetNext();

   return $self;
}

# update list of notifications
sub update {
   my $self=shift;
   my $force=shift || 0; # force a complete update 

   my $folder=$self->folder();

   if (!opendir DH,"$folder") {
      $self->{error}="Unable to open folder $folder for listing notifications: $!";
      return 0;
   }

   # get items
   my @items=grep {$_ =~ /^[a-zA-Z0-9]{32}$/ && -d "$folder/$_"} readdir(DH);

   # close dir listing
   closedir (DH);

   # get current items
   my $onots=$self->{nots};

   # ensure we have a LIST
   if (!defined $onots) { $onots=[]; }

   # find new instances
   my @new;
   foreach (@items) {
      my $item=$_;

      my $found=0;
      foreach (@{$onots}) {
         my $not=$_;

         # check if we have this items instance already
         if ($not->id() eq $item) { $found=1; last; }
      }
 
      # add new notification we do not have already
      if (!$found) { my $not=Notification->new(id=>$item); push @new,$not; }
   }

   # add new to old
   push @{$onots},@new;

   $self->{nots}=$onots;

   return 1;
}

# reset get next notification
sub resetNext {
   my $self=shift;

   $self->{pos}=0;

   return 1;
}


# get next notification
sub getNext {
   my $self=shift;
   
   my $pos=$self->{pos} || 0;

   # ensure we have notifications, if they exist
   if (!defined $self->{nots}) { $self->update(); } # just to be sure

   my $nots=$self->{nots};
   
   if ((defined $nots) && ($pos < @{$nots})) {
      # valid position
      my $not=$nots->[$pos];
      # increment position if data retrieved successfully
      if (defined $not) { $pos++; $self->{pos}=$pos; }
      # return the notification instance
      return $not;
   } else {
      # invalid position - return undef
      return undef;
   }
}

# delete a specific notification
# and clean up
sub delete {
   my $self=shift;
   my $not=shift;

   if ((!defined $not) || (!$not->isa("Notification"))) {
      # failed to fulfill requirements
      $self->{error}="Notification instance not defined or invalid class-type. It needs to be a Notification-class. Unable to delete notification.";
      return 0;
   }

   # get notification ID
   my $id=$not->id();

   # ready to remove notification events
   if (!$not->delete()) {
      $self->{error}="Unable to delete notification events: ".$not->error();
      return 0;
   }

   if (!$self->evacuate($not,1)) {
      $self->{error}="Unable to evacuate notification, cannot delete it: ".$self->{error};
      return 0;
   }

   # get notification root-folder
   my $folder=$self->folder();

   # notification is deleted - clean up folder
   eval { remove_tree("$folder/$id", { error => \my $err }); };

   # we have cleaned up
   return 1;
}

# move a notification to another folder 
# and forget about it.
sub move {
   my $self=shift;
   my $not=shift;
   my $folder=shift||"";

   if ((!defined $not) || (!$not->isa("Notification"))) {
      # failed to fulfill requirements
      $self->{error}="Notification instance not defined or invalid class-type. It needs to be a Notification-class. Unable to delete notification.";
      return 0;
   }

   # get notification ID
   my $id=$not->id();

   # check that new folder exists
   if (!-d "$folder") {
      $self->{error}="Folder \"$folder\" to move notification $id to does not exist. Unable to move notification.";
      return 0;
   }

   # get notification root-folder
   my $root=$self->folder();

   # move notification, if move does not success, it attempts copy
   if (!mv ("$root/$id","$folder/$id")) {
      $self->{error}="Unable to move notification $id from \"$root\" to \"$folder\": $!";
      return 0;
   }

   # evacuate the notification from the list and remove the instance
   if (!$self->evacuate ($not,1)) {
      $self->{error}="Folder for notification $id was moved, but the evacuation from the list failed: ".$self->{error};
      return 0;
   }

   # we have cleaned up
   return 1;
}

# evacuate a notification out of the 
# notification list, but not deleting it or 
# removing its data.
sub evacuate {
   my $self=shift;
   my $not=shift;
   my $instance=shift||0;

   if ((!defined $not) || (!$not->isa("Notification"))) {
      # failed to fulfill requirements
      $self->{error}="Notification instance not defined or invalid class-type. It needs to be a Notification-class. Unable to evacuate notification.";
      return 0;
   }

   # get notification ID
   my $id=$not->id();

   # evacuate from notification list
   my $old=$self->{nots};
   my @new;
   my $dpos=0;
   for (my $i=0; $i < @{$old}; $i++) {
      my $n=$old->[$i];

      # add to new list if not equal in id to the one being evacuated
      if ($n->id() ne $id) { push @new,$n; }
      else { $dpos=$i; } # this is the position of the evacuated instance
   }
   # add new list
   $self->{nots}=\@new;

   # check evacuate position against next-pos
   my $pos=$self->{pos} || 0;
   # if we evacuated where we are supposed to get next, check that position is still valid
   # if not set to end of list (no more to read)
   if ($pos == $dpos) { $pos=($pos < @new ? $pos : @new); } 
   # if position was larger than evacuate pos, subtract one if possible
   if ($pos > $dpos) { $pos=($pos-1 >= 0 ? $pos-1 : 0); }
   # update new pos
   $self->{pos}=$pos;

   if ($instance) {
      # destroy instance, if so asked for
      $not=undef;
   }
 
   # we have evacuated the notification
   return 1;
}

# get folder
sub folder {
   my $self = shift;

   return $self->{pars}{folder};
}

sub error {
   my $self=shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<NotificationHandler> - Class to handle several notifications in a folder.

=cut

=head1 SYNOPSIS

   use NotificationHandler;

   # create instance
   my $nh=NotificationHandler->new();

   # update notification list
   $nh->update();

   # reset next notification iteration
   $nh->resetNext();

   # get next notification in list
   my $n=$nh->getNext();

   # delete/remove notification
   $n->delete($n);

   # move notification to another folder and forget about it
   $nh->move($n,"/MY/NEW/FOLDER/ROOT");

   # get absolute path of 
   # notification-folder
   my $folder=$nh->folder();

   # get last error
   print $nh->error();

=cut

=head1 DESCRIPTION

A class to handle multiple instances of the AURORA-systems notifications. 

The class manages to iterate over notifications in the AURORA notification root-folder and clean away notifications that are 
to be deleted.

Please see the AURORA notification-service documentation for more information about the structure of the service.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiate class.

The method takes one input: folder. Folder specifies the absolute path to the AURORA main/root notification-folder. 
If not specified or found as a combination of the environment-variable "AURORA_PATH" appended "/notification", it will 
default to "/local/app/aurora/notification".

Returns a class instance.

=cut

=head1 METHODS

=head2 update()

Updates the list of notifications in the root notification-folder. It will only add new notification-instances to 
its list, retaining the old.

Return 1 upon success, 0 upon failure. Upon failure, please check the error()-method for more information.

=head2 resetNext()

Resets the next pos pointer for fetching notification instances.

No input accepted. Always returns 1.

=cut

=head2 getNext()

Gets the next notification in the notification list.

No input is accepted. 

Returns the next notification-instance upon success, or undef upon end of list.

=cut

=head2 delete()

Deletes a notification instance, its events and folder.

One mandatory input: notification-instance reference. There has to be an instance of the Notification-class reference 
specified here that is to be deleted.

It first asks the notification-instance to clean up and then attempts to remove the instance folder.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

=cut

=head2 folder()

Returns the absolute folder path of the notification root-folder.

No input is accepted.

Returns the absolute folder path of the notification root-folder as used by the NotificationHandler instance.

=cut

=head2 move()

Move a notification to another folder and forget about it.

Accepts the following parameters in this order:

=over

=item

B<notification> The instance of the notification to move.

=cut

=item

B<folder> The new folder to put the notification in. It can be either relative or absolute.

=cut

=back

The method will move the notification to the new folder and then evacuate its instance from the 
notificationhandlers internal list and thereby forgetting about it. The method can be used to 
move notifications to another place to avoid them causing issues in the notification handling.

Will return 1 upon success, 0 upon some failure. Please check the error()-method for more information 
upon failure.

=cut

=head2 evacute()

Evacuates a notification from the notificationhandlers list.

Accepts the following parameters in this order:

=over

=item

B<notification> The instance of the notification to evacuate.

=cut

=item

B<deallocate> Decides if the method is to deallocate the notification instance or not after a successful move. An expression evaluating to 
true means yes, while an expression that evaluates to false means no. It will default to false if parameter is not specified.

=cut

=back

Upon success this method return 1, 0 upon failure. Please check the error()-method for more information upon failure.

This method is internal and should not be called by others than the notificationhandler-class itself.

=cut

=head2 error()

Returns the last error that has happened (if any).

No input is accepted.

=cut


