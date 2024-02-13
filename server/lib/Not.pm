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
# Class: Not - class to handle a notification easily and quickly
#
package Not;

use strict;
use Notification;

sub new {
   # instantiate
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # check values, set defaults
   if (!$pars{location}) { my $p=$ENV{"AURORA_PATH"} || "/local/app/aurora"; $p=$p."/notification"; $pars{location}=$p; }
   
   # save parameters
   $self->{pars}=\%pars;

   # set last error message
   $self->{error}="";

   # return instance
   return $self;
}

sub send {
   my $self = shift;
   my %pars = @_;

   # we need type, about, from and message.

   # ensure defaults
   $pars{about}=$pars{about} || 0;
   $pars{from}=$pars{from} || 0;
   $pars{message}=$pars{message} || "";
   $pars{event}=$Notification::MESSAGE;
#   $pars{type}=$pars{type} || 0; # invalid type technically

   # create Notification-instance
   my $n=Notification->new(folder=>$self->{pars}{location});
   # get notification id
   my $id=$n->id();

   # attempt to create notification
   if (!$n->add(\%pars)) {
      $self->{error}="Failed to send notification: ".$n->error();
      return 0;
   }

   # success returns the notifications ID
   return $id;
}

sub error {
   my $self = shift;

   # return error message
   return $self->{error} || "";
}

1;

__END__

=head1 NAME

C<Notification> - Class to send notifications by the AURORA-system quickly and effortlessly

=cut

=head1 SYNOPSIS

   use Not;

   my $n=Not->new();

   my $res=$n->send(type=>11,about=>1,from=>-3,message=>"Please note that the dataset is expiring in 1 second. We recommend that you take evasive action.");

   if (!$res) {
      print "Error sending notification: ".$n->error();
   }

=cut

=head1 DESCRIPTION

Class to send notifications by the AURORA-system in a easy and quick way. 

=cut

=head1 CONSTRUCTOR

=head2 new()

Constructor of class.

Returns class instance.

It takes two paramters: location. Location is the path to the notification-folder of the AURORA-system.

No parameters are required. Location will be attempted read from the environment-variable AURORA_PATH and then combined with /notification to signify the path. If no environment parameter is found, location will be set to /local/app/aurora. In other words the location-parameters gives the path to the Aurora-installation.

=cut

=head2 send()

Attempts to send a notification.

Parameters to functions are: timestamp, type, about, from and message.

No parameters are required, but you should set type, about, from and message. Time will be set automatically at the time of adding it to a file.

See the Notification-class and specification for explanation of these field values.

Returns the Notification's ID upon success, 0 upon failure.

The error message upon failure can be read by calling the error()-method.

=cut

=head2 error()

Get the last error message from the Notification-instance.

=cut

