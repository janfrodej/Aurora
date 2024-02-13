#!/usr/bin/perl -w
#
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
# Notification: a class to handle one, specific Notification and its events
#
package Notification;

use strict;
use YAML::XS qw(Dump Load);
use Time::HiRes qw (time);
use sectools;
use ISO8601;

our $MESSAGE = 1;
our $ESCALATION = 2;
our $NOTICE = 3;
our $ACK = 4;
our $FIN = 5; # fin event to void any race-conditions
my $TYPES_TOTAL = 5;

# constructor
sub new {
   # instantiate  
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # set defaults if not specified      
   if (!exists $pars{folder}) { $pars{folder}="/local/app/aurora/notification"; }
   if (!exists $pars{id}) { $pars{id}=sectools::randstr(32); } # if not existing, create a new

   # save parameters
   $self->{pars}=\%pars;

   # get folder and id
   my $folder=$pars{folder};
   my $id=$pars{id};
   # set mask and save old
   my $omask = umask 0;

   # create the folder structure. Quick and dirty
   mkdir ("$folder/$id",0771);

   # set old mask again   
   umask $omask;

   # define notification types structure
   my %types;
   $types{$MESSAGE}{name}="message";
   $types{$MESSAGE}{required}=["event","timestamp","type","about","from","message"];
   $types{$MESSAGE}{regex}=["[a-z]+","[\\d+\\.]+","[a-z0-9\.]+","\\d+","\\-?\\d+",".*"];

   $types{$ESCALATION}{name}="escalation";
   $types{$ESCALATION}{required}=["event","timestamp","level","who"];
   $types{$ESCALATION}{regex}=["[a-z]+","[\\d+\\.]+","\\d+","\\-?\\d+"];

   $types{$NOTICE}{name}="notice";
   $types{$NOTICE}{required}=["event","timestamp","class","rid","whom","votes","status","message"];
   $types{$NOTICE}{regex}=["[a-z]+","[\\d+\\.]+","[a-zA-Z0-9\\:]+","[a-zA-Z0-9]{32}","\\d+","\\-?\\d+","\\d{1}",".*"];

   $types{$ACK}{name}="ack";
   $types{$ACK}{required}=["event","timestamp","rid"];
   $types{$ACK}{regex}=["[a-z]+","[\\d+\\.]+","[a-zA-Z0-9]{32}"];

   $types{$FIN}{name}="fin";
   $types{$FIN}{required}=["event","timestamp"];
   $types{$FIN}{regex}=["[a-z]+","[\\d+\\.]+"];

   # save the structure definitions
   $self->{types}=\%types;

   return $self;
}

# add an event to this
# notification
sub add {
   my $self = shift;
   my $data = shift;

   my $type=$data->{event} || 0;

   if (($type !~ /^\d+$/) || ($type < 1) || ($type > $TYPES_TOTAL)) {
      $self->{error}="Invalid or missing event type ($type). Unable to add event.";
      return 0;
   }

   if ((!defined $data) || (ref($data) ne "HASH")) {
      $self->{error}="Data parameter not defined or not a HASH. Unable to add event.";
      return 0;
   }

   # get types structure
   my $types=$self->{types};

   # set global parameters
   $data->{event}=$types->{$type}{name};
   if (!exists $data->{timestamp}) { $data->{timestamp}=time(); }

   # check the integrity of the data
   my $req=$types->{$type}{required};
   my @failed;
   for (my $i=0; $i < @{$req}; $i++) {
      # get data for this required key if any
      my $name=$req->[$i];
      my $value=$data->{$name};
      # if no value has been set, we set it to blank
      if (!defined $value) { $value = ""; }
      my $qregex=qq(@{$types->{$type}{regex}}[$i]);

      if ($value !~ /^$qregex$/s) {
         push @failed,"$name ($value)";
      }
   }

   # check if we have any failed keys
   if (@failed > 0) {
      $self->{error}="You have failed keys [".join(",",@failed)."] that failed their regex in your data. Unable to add event.";
      return 0;
   }

   # so far, so good and all of that

   # convert timestamp to readable form
   my $time=$data->{timestamp};
   $data->{timestamp}=time2iso($time);

   # convert data structure to YAML
   my $err;
   my $y;
   local $@;
   eval { $y=Dump($data); };
   $@ =~ /nefarious/;
   $err = $@;

   if ($err ne "") {
      # an error occured
      $self->{error}="Unable to convert data into YAML: $err.";
      return 0;
   }

   # create file and write data
   my $id=$self->id();
   my $folder=$self->folder();
   my $typestr=$types->{$type}{name};

   # make a tmp-file
   my $fname=".".sectools::randstr(32); 
   
   if (!open FH,">","$folder/$fname") {
      # failed
      $self->{error}="Unable to open tmp-file $folder/$fname for writing: $!";
      return 0;
   }
  
   # attempt to write YAML content of file
   if (!print FH $y) {
      $self->{error}="Failed to write data to tmp-file $folder/$fname: $!";
      return 0,
   }

   # close file
   if (!close (FH)) {
      $self->{error}="Unable to close tmp-file $folder/$fname: $!";
      return 0;
   }

   # rename file - atomic
   if (rename ("$folder/$fname","$folder/$id/${id}_${time}_${typestr}")) { return 1; }
   else { $self->{error}="Unable to rename tmp-file $folder/$fname to $folder/$id/${id}_${time}_${typestr}: $!"; return 0; }
}

# get a named event
sub get {
   my $self = shift;
   my $name = shift || "";

   my $folder=$self->folder();
   my $id=$self->id();

   # try to open file for reading
   if (!open (FH,"<","$folder/$id/$name")) {
      $self->{error}="Unable to open file $folder/$id/$name for reading: $!";
      return undef;
   }

   # file open for reading
   my $y=join("",<FH>);

   # close file
   if (!close(FH)) {
      $self->{error}="Unable to close file $folder/$id/$name: $!";
      return undef;
   }

   # convert YAML to HASH
   my $err;
   my $h;
   local $@;
   eval { $h=Load($y); };
   $@ =~ /nefarious/;
   $err = $@;

   if ($err ne "") {
      $self->{error}="Unable to convert YAML to HASH: $err";
      return undef;
   }

   # content converted - convert time to suitable format
   $h->{timestamp}=iso2time($h->{timestamp});

   # get types structure
   my $types=$self->{types};

   # get message type
   my $type=0;
   foreach (keys %{$types}) {
      my $key=$_;

      if ($h->{event} eq $types->{$key}{name}) {
         # we have a hit
         $type=$key;
         last;
      }
   }

   # ensure it is a valid type
   if (($type < 1) || ($type > $TYPES_TOTAL)) {
      $self->{error}="Invalid or missing event type ($type). Unable to get event.";
      return undef;
   }

   # check the integrity of the data
   my $req=$types->{$type}{required};
   my @failed;
   for (my $i=0; $i < @{$req}; $i++) {
      # get data for this required key if any
      my $name=$req->[$i];
      my $value=$h->{$name};
      my $qregex=qq(@{$types->{$type}{regex}}[$i]);

      if ($value !~ /^$qregex$/s) {
         push @failed,"$name ($value)";
      }
   }

   # check if we have any failed keys
   if (@failed > 0) {
      $self->{error}="You have failed keys [".join(",",@failed)."] that failed their regex in your data. Unable to get event.";
      return undef;
   }

   # convert to the correct type identifier
   $h->{event}=$type;

   # all is a' okay - return the result
   return $h;
}

# update with any last
# events that have arrived
sub update {
   my $self=shift;

   my $folder=$self->folder();
   my $id=$self->id();

   # open folder and read all files
   if (!opendir (DH,"$folder/$id")) {
      $self->{error}="Unable to open folder $folder/$id for listing files: $!";
      return 0;
   }

   # read folder items
   my @f=grep {$_ !~ /^[\.]{1,2}$/ && $_ =~ /^[a-zA-Z0-9]{32}\_[\d\.]+\_[a-z]+$/} readdir DH;

   # sort the files alphanumerically
   my @files=sort {$a cmp $b} @f;

   # close dirhandle
   if (!closedir (DH)) {
      $self->{error}="Unable to close dirhandle for $folder/$id: $!";
      return 0;
   }

   # get current events list
   my $oevents=$self->{events};

   # ensure we have a LIST
   if (!defined $oevents) { $oevents=[]; }

   # only add changes
   if (@files > @{$oevents}) {
      my $pos=@{$oevents};
      if ($pos < 0) { $pos=0; }
      # we have new entries - fetch only them
      my @new;
      for (my $i=$pos; $i < @files; $i++) {
         push @new,$files[$i];
      }
      # add new entries to old list
      my @events=@{$oevents};
      push @events,@new;
      $self->{events}=\@events;
   }
 
   return 1;
}

# reset the reading of events
# to the beginning of the
# events
sub resetNext {
   my $self=shift;

   # reset position in events LIST
   $self->{pos}=0;

   return 1;
}

# get next event in queue
sub getNext {
   my $self=shift;
   
   my $pos=$self->{pos} || 0;

   # ensure we have any events, if they exist
   if (!defined $self->{events}) { $self->update(); } # just to be sure

   my $events=$self->{events};
   
   if ((defined $events) && ($pos < @{$events})) {
      # valid position
      my $name=$events->[$pos];
      # retrieve this events data
      my $data=$self->get($name);
      # increment position if data retrieved successfully
      if (defined $data) { $pos++; $self->{pos}=$pos; }
      # return the data structure
      return $data;
   } else {
      # invalid position - return undef
      return undef;
   }
}

# remove all events 
# cleaning away folder structure is
# not this classes job
sub delete {
   my $self=shift;

   # get location info
   my $folder=$self->folder();
   my $id=$self->id();

   # update event list
   $self->update();

   # get event list
   my $events=$self->{events};

   # unlink all events
   foreach (@{$events}) {
      my $name=$_;

      unlink ("$folder/$id/$name");
   }

   # reset next as well
   $self->resetNext();

   # return success
   return 1;
}

# get id of notification
sub id {
   my $self=shift;

   return $self->{pars}{id};
}


# get absolute notification-folder root
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

C<Notification> - Class to handle a notification and its events.

=cut

=head1 SYNOPSIS

   use Notification;
   use SysSchema;

   # create instance
   my $n=Notification->new();

event","timestamp","type","about","from","message"

   # define event hash
   my %e;
   $e{event}=$Notification::MESSAGE;
   $e{type}=$SysSchema::NTYP{"user.create"}{id};
   $e{about}=1234;
   $e{from}=$SysSchema::FROM_REST;
   $e{message}="Hello\nA user account has been created for you. Here are the details etc...\n";

   # add event
   if (!$n->add(\%e)) {
      print "ERROR: ".$n->error()."\n";
   }
  
   # get a named event (file name without folder must be provided)
   my $h=$n->get("012345678901234567890123456789CB_1234567890.12345_message");
 
   # update known events
   $n->update();

   # reset getnext event
   $n->resetNext();

   # get next event
   # that we know of (see update())
   my $h=$n->getNext();
 
   # delete/remove all events
   $n->delete();
 
   # get notification id
   my $id=$n->id();

   # get absolute folder path of 
   # notification
   my $folder=$n->folder();

   # get last error
   print $n->error();

=cut

=head1 DESCRIPTION

A class to handle the AURORA-systems notifications. The class specifically handles the notification-folder and its events.

The class enables events to be added and to be read, as well as iterated over in correct and timestamped-order. It also 
can remove all events (eg. prior to a cleanup/removal).

Please see the AURORA notification-service documentation for more information about events and the structure of the service.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiate class.

The method takes two inputs: id and folder. Id specifies the notification ID to use. If none is specified it creates a random one 
for you. Folder specifies the absolute path to the AURORA main/root notification-folder. If not specified it will default to 
"/local/app/aurora/notification".

Returns a class object.

=cut

=head1 METHODS

=head2 add()

Adds an event to the notification.

Input is a HASH-reference with the necessary key->value definitions for the various event-types. The input is mandatory.

Valid event types are:

  $Notification::MESSAGE    - message-event (typically starts a notification).
  $Notification::NOTICE     - notice-event (generated each time a notice is sent with a notice-class)
  $Notification::ESCALATION - escalation-event (generated when timeout reaching people has been reached and no confirmation from any user(s))
  $Notification::ACK        - ack-event (generated when someone confirms/acknowledge a notice-event)
  $Notification::FIN        - fin-event (marks that one is finished parsing this Notification)

The following are the required keys for the various event types:

  MESSAGE ("event","timestamp","type","about","from","message")
  NOTICE ("event","timestamp","class","rid","whom","votes","status","message")
  ESCALATION ("event","timestamp","level","who")
  ACK ("event","timestamp","rid")
  FIN ("event","timestamp");

All events share the keys "event" and "timestamp", which defines the type of event and timedate respectively of the event.

The key "event" is to be filled with one of the constant mentioned above ($Notification::MESSAGE, $Notification::ACK etc.). 
"timestamp" can be omitted and then it will be filled with current time. If specified it should use HiRes-time.

Please see AURORA Notification-specification for more information on the various key-values. 

Returns 0 upon failure or 1 upon success. Please check the error()-method for more information upon failure.

=cut

=head2 get()

Get an event of the notification.

Mandatory input is the name of the event-file. The event-file name is in the following format:

NOTID_TIMESTAMP_EVENTTYPE

NOTID is the notification id of 32 random characters (a-zA-Z0-9). Timestamp is the HiRes-timestamp of when the event happened and
EVENTTYPE is the type of event (eg. "message"). The EVENTTYPE is always specified in lowercase.

Returns a HASH-reference with the event data upon success, undef upon failure. Please check the error()-method for more 
information upon failure.

=cut

=head2 resetNext()

Resets the next pos pointer for reading out notification events.

No input accepted. Always returns 1.

=cut

=head2 getNext()

Gets the next event in the event list of the notification.

No input is accepted. 

Returns the HASH-reference to the event data upon success, undef upon failure. Please check the error()-method for more 
information upon failure.

=cut

=head2 delete()

Deletes all events of the notification.

No input is accepted.

It attempts to unlink all event-files in the Notification-folder of the specific notification. If there are other files 
there than event-files, it does not touch these.

Always returns 1.

=cut

=head2 id()

Returns the notification ID of the instance.

No input is accepted.

Returns the notification ID.

=cut

=head2 folder()

Returns the absolute folder path of the notification root-folder.

No input is accepted.

Returns the absolute folder path of the notification root-folder.

=cut

=head2 error()

Returns the last error that has happened (if any).

No input is accepted.

=cut


