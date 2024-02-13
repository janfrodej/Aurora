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
# NotificationParser: module to parse a notification and update its state
#
package NotificationParser;

use strict;
use Notification;
use AuroraDB;

sub new {
      # instantiate
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # input notification types that exists
   if (!defined $pars{nottypes}) { my %t; $pars{nottypes}=\%t; }
   if (!defined $pars{db}) { my $db=AuroraDB->new(); $pars{db}=$db; }

   # update pars
   $self->{pars}=\%pars;

   my %parse;
   my %event;
   $self->{state}=\%parse;
   $self->{id}=0;
   $self->{event}=\%event;
   $self->{eventtype}=0;
   $self->{messagetype}="";

   return $self;
}

sub parse {
   my $self=shift;
   my $not=shift || Notification->new();
   my $state=shift;

   if ((defined $state) && (ref($state) ne "HASH")) { return undef; } # state must be a HASH-ref

   sub addValues {
      my $source=shift;
      my $state=shift;
      my @omit=@_;

      # map omits to hash
      my %except=map { $_ => 1 } @omit;
      
      foreach (keys %{$source}) {
         my $key=$_;

         # if key is to be omitted, go to next
         if (exists $except{$key}) { next; }
         # do not include undefined values
         if (!defined $source->{$key}) { next; }
         # do not include hashes
         if (ref($source->{$key}) eq "HASH") { next; }

         # update state
         $state->{$key}=$source->{$key};
      }
   }

   # get id
   my $id=$not->id() || 0;
   $self->{id}=$id;
   # create state if not present
   if (!defined $state) { my %s; $state=\%s; }
   # get db instance
   my $db=$self->{pars}{db};

   # update if new events have arrived
   $not->update();
   my %event;
   # get next notification event, if any
   while (my $e=$not->getNext()) {
      my $type=$e->{event};
      $self->{eventtype}=$type;
      my $timestamp=$e->{timestamp};

      if ($state->{fin}) { last; } # state of Notification is already set to ended, stop parsing

      %event=%{$e}; # retain this event outside this loop
#      $L->log ("ID $id new event discovered","INFO");

      # determine if basis message-event already exist in parse-structure
      my $evexist=(exists $state->{message} ? 1 : 0);

      if (($type == $Notification::MESSAGE) &&
          (!$evexist)) { # we are not allowed to overwrite message with a new one
         # this is a MESSAGE-event
#         $L->log ("ID $id notification type is ".$e->{type},"INFO");
         $self->{messagetype}=$e->{type};
         $state->{type}=$e->{type}; # type of message event
         $state->{about}=$e->{about}; # who is this message about - entid
         $state->{abouttype}=$db->getEntityType($e->{type}); # what entitytype is this entid?
         $state->{from}=$e->{from}; # who sent the message?
         $state->{message}=$e->{message}; # the message itself
         $state->{level}=$e->{about}; # set the escalate level to the entity itself
         $state->{expire}=$e->{expire} || 0; # set the expire date, if there
         $state->{disabled}=0; # set disabled flag to 0
         $state->{fin}=0; # set end flag to 0
         # a creator of a new notification may have included threads from other notifications, if so include them
         if ((exists $e->{threadids}) && (defined $e->{threadids}) && (ref($e->{threadids}) eq "ARRAY")) {
            $state->{threadids}=$e->{threadids};
         }
         # add any remaining values to this event, allowing dynamic inclusion of new information
         addValues ($e,$state,"type","about","abouttype","from","message","level","expire","disabled","fin","threadids","votes","cast");

#         $L->log("Message-event discovered on notification $id","INFO");

         # get global votes-settings for this message type
         my $libvotes=$SysSchema::NTYP{$e->{type}}{votes} || "";
         my %types=%{$self->{pars}{nottypes}};
         my $cfgvotes=$types{$e->{type}}{votes} || "";

         # set the correct number of votes for this message type
         if ($cfgvotes =~ /^\d+$/) { $state->{votes}=$cfgvotes; }
         elsif ($libvotes =~ /^\d+$/) { $state->{votes}=$libvotes; }
         else { $state->{votes}=0; } # default to 0 (not votes needed)
         # set cast to votes
         $state->{cast}=$state->{votes};
      } elsif (($type == $Notification::NOTICE) && ($evexist)) {
         # this is a NOTICE-event
         my $rid=$e->{rid};
         my $class=$e->{class};

#         $L->log ("Notice-event discovered on notification $id. RID: $rid CLASS: $class","INFO");

         $state->{notice}{timestamp}=$timestamp; # last notice-event
 
         if (!exists $state->{notice}{rid}{$rid}) {
            $state->{notice}{rid}{$rid}{timestamp}=$timestamp; # first time rid is seen, post ack-file creation
            $state->{notice}{rid}{$rid}{whom}=$e->{whom};
            $state->{notice}{rid}{$rid}{rid}=$e->{rid}; # a bit of redundancy
            $state->{notice}{rid}{$rid}{votes}=$e->{votes};
         }

         $state->{notice}{rid}{$rid}{class}{$class}{timestamp}=$timestamp; # timestamp of this notice-class
         $state->{notice}{rid}{$rid}{class}{$class}{status}=$e->{status};  # status of sending with notice-class
         $state->{notice}{rid}{$rid}{class}{$class}{message}=$e->{message};# possible message upon error
         # update threadids
         if (exists $e->{threadid}) {
            my $thid=$e->{threadid};
            my @t;
            if (defined $state->{threadids}) { @t=@{$state->{threadids}}; }
            my $found=0;
            foreach (@t) {
               if ($_ eq $thid) { $found=1; last; }
            }
            # add the threadid if it is not there already
            if (!$found) { push @t,$thid; $state->{threadids}=\@t; }
         }
      } elsif (($type == $Notification::ESCALATION) && ($evexist)) {
         # this is an ESCALATION-event
         my $level=$e->{level}; # escalate from which level?
         my $who=$e->{who}; # who is asking to escalate?
#         $L->log ("Escalation-event discovered LEVEL: $level WHO: $who","DEBUG");
         # get ancestors of level
         my @ancestors=$db->getEntityPath($level);
#         $L->log ("Ancestors of $id found: @ancestors","DEBUG");
         if (@ancestors < 2) { # ensure we have somewhere to escalate
            # nowhere to escalate, we have a dead notification
#            $L->log ("There are no more entity levels to escalate to. We have a lame duck notification for $id.","ERR");
            my $nlevel=$ancestors[0];
            $state->{lameduck}=1;
            next;
         } else {
            # escalation is approved, but need to bring with me votes from previous level
            # only existing rid entries in hash still have leftover votes
            foreach (keys %{$state->{notice}{rid}}) {
               my $rid=$_;

               # who is this?
               my $who=$state->{notice}{rid}{$rid}{whom};
               # get votes in this rid
               my $votes=$state->{notice}{rid}{$rid}{votes};
               # accumulate votes
               my $curvotes=$state->{stragglers}{$who} || 0;
               $state->{stragglers}{$who}=$curvotes+$votes;
               # remove rid entry in hash
               delete ($state->{notice}{rid}{$rid});
            }
            # get new level
            my $nlevel=$ancestors[@ancestors-2];
            # everything is ok, update main part of parse-structure
            $state->{cast}=$state->{votes}; # reset cast votes when escalating
            $state->{level}=$nlevel; # new level we are at
            $state->{threadids}=$e->{threadids}; # get threadids from previous level(s)
#            $L->log ("Successfully escalated notification $id to level $nlevel","INFO");
         }
      } elsif (($type == $Notification::ACK) && ($evexist)) {
         # this is an ACK-event - get rid of ack
         my $rid=$e->{rid};
#         $L->log ("Ack-event discovered on notification $id. RID: $rid","INFO");
         # only ack if notice is valid - check both notice and notice-rid to avoid
         # hash sub-level being created
         if ((exists $state->{notice}) && (exists $state->{notice}{rid}) && (exists $state->{notice}{rid}{$rid})) {
            # this is a valid ack, get votes
            my $votes=$state->{notice}{rid}{$rid}{votes};
            # adjust main cast
            my $cast=$state->{cast};
            # add votes (usually minus votes)
            $cast=$cast+$votes;
            # ensure the cast doesnt go negative
            $cast=($cast >= 0 ? $cast : 0);
            # update cast
            $state->{cast}=$cast;
            # ensure we save who cast the vote and the number of votes
            my $who=$state->{notice}{rid}{$rid}{whom};
            my $sofar=$state->{voting}{$who} || 0;
            $state->{voting}{$who}=$sofar-$votes; # subtract, because we need positive number
            # remove rid from notice-hash
            delete ($state->{notice}{rid}{$rid});
#            $L->log ("This is a valid ack. User votes: $votes Cast now stands at: $cast","INFO");
         } else {
#            $L->log ("This is not a valid ack. RID: $rid. Skipping it.","INFO");
         }
      } elsif (($type == $Notification::FIN) && ($evexist)) {
         # this is a FIN-event - disable parsing and mark end
#         $L->log ("Fin-event discovered on notification $id.","INFO");
         $state->{disabled}=1;
         $state->{fin}=1;
         $state->{cancel}=$e->{cancel} || 0;
         $state->{lameduck}=$e->{lameduck} || 0;
         my @empty;
         $state->{threadids}=$e->{threadids} || \@empty;
         # add dynamic values
         # add any remaining values to this event, allowing dynamic inclusion of new information
         addValues ($e,$state,"disabled","fin","cancel,","lameduck","threadids");

         # end parsing loop
         last;
      }
   }

   # save whole of last event, if it contains something
   $self->{event}=(keys %event > 0 ? \%event : $self->{event});

   # save the state
   $self->{state}=$state;

   # return current state
   return $state;
}


# get the whole of the last 
# event
sub lastEvent {
   my $self=shift;

   return $self->{event};
}

sub lastEventType {
   my $self=shift;

   return $self->{eventtype};
}

sub messageType {
   my $self=shift;

   return $self->{messagetype};
}

# get current state
sub state {
   my $self=shift;

   return $self->{state};
}

# notification id of last parsed notification
sub id {
   my $self=shift;

   return $self->{id};
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<NotificationParser> - Class to parse a Notifications events from a Notification-class instance.

=cut

=head1 SYNOPSIS

   use Notification;
   use NotificationHandler;

   my $parser=NotificationParser->new(nottypes=>\%types,db=>$db);

   my $not=Notification->new();
   my $state=$parser->parse($not);

   my $etype=$parser->lastEventType();
   my $mtype=$parser->messageType();

=cut

=head1 DESCRIPTION

Class to parse a Notification class instance's events.

It will go through all events delivered and parse down until it comes to the current state of the Notification. It can 
also be invoked multiple times if the wish is to monitor the notification.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the class.

It takes the following parameters:

=over

=item

B<nottypes> The notification-types HASH-reference structure. See below for the structure.

=cut

=item

B<db> AuroraDB-instance to use when performing database operations.

=cut

=back

The nottypes-structure is to be as follows:

	nottypes = (
                     NOTTYPENAMEa = {
                                       votes: SCALAR
                                       subject: SCALAR
                                    }  
                     .
                     .
                     NOTTYPENAMEn = { ... }
                   )

The NOTTYPENAME is the name to tag the Notification type as. It is just a textual string and can be something like 
"user.create", "dataset.remove" etc. "votes" is the number of votes it takes to agree to the event in question. Most 
event will just have 0 here, since they require no voting. "subject" is the subject-heading to use when sending 
notices to the user (some Notice-classes may not support using it). This structure is defined by the user of the 
NotificationParser-module.

Returns a class instance upon success.

=cut

=head1 METHODS

=head2 parse()

Parses a Notification and delivers its current state to the caller.

The method these parameters in the following order: "notification" and "state".

The "notification" parameter is the Notification-class instance to parse. The "state" is the notifications current state, if 
any (can be omitted). The "state"-parameter is a HASH-reference.

Upon success, the method will return the current state of the Notification in the format of a HASH-reference. 
Undef will be returned upon failure.

=cut

=head2 lastEvent()

Retrieves the latest event that was parsed by this class.

=cut

=head2 lastEventType()

Retrieve the latest events type (MESSAGE, ACK, ESCALATION etc.)

Accepts no input.

Returns the scalar event type (as defined by $Notification::MESSAGE, 
$Notification::Ack and so on).

=cut

=head2 messageType()

Retrieves the message type of the notification that was parsed the last.

Returns the textual message type as a SCALAR.

=cut

=head2 state()

Returns the current Notification-state.

Returns a HASH-reference to the state.

=cut

=head2 id()
  
Returns the id of the last parsed notification.

=cut
