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
# SmartLog: a smart, circular logging class
#
package SmartLog;

use strict;
use Time::HiRes qw(time);

# constructor
sub new {
   # instantiate  
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # set defaults if not specified      
   # number of lines in buffer. 0=no limit
   if (!exists $pars{bufsize}) { $pars{bufsize}=0; }

   # save parameters
   $self->{pars}=\%pars;

   # create log var
   $self->reset();

   # create error var
   $self->{error}="";   

   return $self;
}

# add a log entry
sub add {
   my $self = shift;

   my $line = shift || "";
   my $time = shift || time();

   # get bufsize
   my $bufsize=$self->{pars}{bufsize};

   # get head
   my $head=$self->{head};
   # get tail
   my $tail=$self->{tail};
   # get ptr
   my $ptr=$self->{ptr};

   # add entry to log
   my @data=($line,$time);
   push @{$self->{LOG}},[@data];

   # remove oldest entry, if applicable
   if (($bufsize > 0) && (@{$self->{LOG}} > $bufsize)) { shift @{$self->{LOG}}; }

   # increase header pos
   $head++;

   # check if we need to move tail
   if (($bufsize > 0) && ($tail < ($head-($bufsize-1)))) { $tail++; }

   # check if ptr has been passed by tail
   if (($bufsize > 0) && ($tail > $ptr)) { $ptr=$tail; }

   # update head and tail
   $self->{head}=$head;
   $self->{tail}=$tail;

   # update ptr
   $self->{ptr}=$ptr;

   # we always have not encountered the head here (new log msg, new head pos)
   $self->{headenc}=0;

   return 1;
}

# get log, start at beginning
sub resetNext {
   my $self = shift;
 
   # set progress status pointer
   # to the tail
   $self->{ptr}=$self->{tail};

   # mark if head has been encountered
   $self->{headenc}=0;
   # mark if tail has been encountered
   $self->{tailenc}=0;

   # set direction
   $self->{direction}=1; # forward

   # next iteration has been reset
   $self->{rstnext}=1;

   return 1;
}

# read log, start at end
sub resetNextReverse {
   my $self = shift;
 
   # set progress status pointer
   # to the head
   $self->{ptr}=$self->{head};

   # mark if head has been encountered
   $self->{headenc}=0;
   # mark if tail has been encountered
   $self->{tailenc}=0;

   # set direction
   $self->{direction}=2; # reverse

   # next iteration has been reset
   $self->{rstnext}=1;

   return 1;
}

# get the next log entry
sub getNext {
   my $self = shift;

   # we have not yet started the
   # nextstatus iteration - fix it
   if (!$self->{rstnext}) {
      $self->resetNext(); # favorize forward direction if none given
   }

   if ((defined $self->{LOG}) &&
       (@{$self->{LOG}} > 0)) { # must be added items to log
      # find next element, if any
      my $dir=$self->{direction};
      my $ptr=$self->{ptr};
      my $head=$self->{head};
      my $tail=$self->{tail};
      my $bufsize=$self->{pars}{bufsize};

      if ( (($dir == 1) && (!$self->{headenc})) || 
           (($dir == 2) && (!$self->{tailenc})) ) {
         # set pointer to ptr
         my $mptr=$ptr;
         # convert ptr to list range
         if (($bufsize > 0) && ($head >= $bufsize)) { $mptr=($bufsize-($head-$ptr))-1; }

         # get list item
         my $list=$self->{LOG}[$mptr];

         # check if head or tail has been encountered and mark accordingly
         if ($ptr == $head) { $self->{headenc}=1; }
         if ($ptr == $tail) { $self->{tailenc}=1; }

         # inc or dec ptr dependant upon direction
         if (($dir == 1) && (!$self->{headenc})) { $ptr++; } # inc (forward)
         if (($dir == 2) && (!$self->{tailenc})) { $ptr--; } # dec (reverse)

         # update pointer
         $self->{ptr}=$ptr;
         # return log message and time
         return $list;
      } else {
         # no more items.
         return undef;
      }
   } else {
      # no items available in array
      return undef;
   }
}

# always gets N first element of log
sub getFirst {
   my $self = shift;
   my $count = shift || 1; 

   # sanity check on count
   $count = ($count =~ /^\d+$/ ? $count : 1);

   # reset next pointer
   $self->resetNext();

   # get items
   my @items;
   my $i=0;
   while (my $l=$self->getNext()) {
      $i++;
      push @items,$l;
      if ($i >= $count) { last; }
   }

   # returns items found or undef
   if (@items > 0) { return \@items; }
   else { return undef; }
}

# always get N last elements of log
sub getLast {
   my $self = shift;
   my $count = shift || 1; 

   # sanity check on count
   $count = ($count =~ /^\d+$/ ? $count : 1);

   # reset next pointer
   $self->resetNextReverse();

   # get items
   my @items;
   my $i=0;
   while (my $l=$self->getNext()) {
      $i++;
      push @items,$l;
      if ($i >= $count) { last; }
   }

   # reverse items list
   my @ritems=reverse @items;

   # returns items found or undef
   if (@items > 0) { return \@ritems; }
   else { return undef; }
}

# returns first N log entries as string
sub getFirstAsString {
   my $self = shift;
   my $count = shift;
   my $format = shift || "%t: %m ";

   my $items=$self->getFirst($count);

   if (defined $items) {
      # go over list and return as a concatenated string
      my $str="";
      foreach (@{$items}) {
         my $l=$_;
         # convert entry into string
         my $line=$self->entryAsString($l,$format);
         # add to line
         $str.=$line;
      }
      return $str;
   } else { return undef; }
}

# return last N log entries as string
sub getLastAsString {
   my $self = shift;
   my $count = shift;
   my $format = shift || "%t: %m ";

   my $items=$self->getLast($count);

   if (defined $items) {
      # go over list and return as a concatenated string
      # remember that last log entry is in first place, so we
      # go through the list in reverse order
      my $str="";
      foreach (@{$items}) {
         my $l=$_;
         # convert entry into string
         my $line=$self->entryAsString($l,$format);
         # add to line
         $str.=$line;
      }
      return $str;
   } else { return undef; }
}

sub entryAsString {
   my $self=shift;
   my $entry=shift;
   my $format=shift || "%t: %m";

   if ((defined $entry) && (ref($entry) eq "ARRAY") && (@{$entry} == 2) && ($entry->[1] =~ /^[\d\.]+$/)) {
      # entry defined, is an array, has two elements and second entry is a decimal/time
      my $msg=$entry->[0];
      # escape percentage signs
      $msg=~s/\%/\\\%/g;
      # quote message
      my $qmsg=qq($msg);
      # quote time
      my $qtime=qq($entry->[1]);

      # replace in format string
      my $line=$format;
      $line=~s/\%t/$qtime/g;
      $line=~s/\%m/$qmsg/g;

      # remove escaping
      $line=~s/\\\%/\%/g;
 
      # return the result
      return $line;
   } else { return undef; }
}

# reset log
sub reset {
   my $self = shift;

   $self->{error}="";

   $self->{LOG}=();
   $self->{head}=-1;
   $self->{tail}=0;

   # set the log pointer
   $self->{ptr}=0;
   $self->{rstnext}=0;
   
   # head has not been encountered
   $self->{headenc}=0;
   # tail has not been encountered
   $self->{tailenc}=0;
   # direction
   $self->{direction}=1; # forward

   return 1;
}

# get log hash
sub getLog {
   my $self = shift;

   # return a copy of the buffer
   return %{$self->{LOG}}; 
}

# return last time 
# log was updated
sub updated {
   my $self = shift;

   if (@{$self->{LOG}} > 0) {
      # return timestamp of last update
      return $self->{LOG}[$self->{head}][1] || 0;
   } else {
      return undef;
   }
}

# return size of log (count of log entries)
sub count {
   my $self = shift;

   if (defined $self->{LOG}) {
      return @{$self->{LOG}} || 0;
   } else { return 0; }
}

# get last error message
sub error {
   my $self = shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<SmartLog> - A Smart log that is either limited (circular) or of unspecified length (unbounded, not circular).

=cut

=head1 SYNOPSIS

   use SmartLog;

   # instantiate
   my $log=SmartLog->new();
   # add a log entry
   $log->add("message",time());
   # start iteration over log elements in forward order
   $log->resetNext();
   # iterate
   while (my @data=$log->getNext()) {
      my $message=$data[0];
      my $time=$data[1];

      print "$time: $message\n";
   }
   # start iteration over log elements in reverse order
   $log->resetNextReverse();
   # get first N log entry(ies)
   my $items=$log->getFirst (10);
   # get last N log entry(ies);
   my $items=$log->getLast (11);
   # get first N log entry(ies) as a string
   my $str=$log->getFirstAsString (10);
   # get last N log entry(ies) as a string
   my $str=$log->getLastAsString (11,"%m ");
   # convert a log entry to a string in given format
   my $str=$log->entryAsString($entry,"%m (%t)");
   # reset the log instance and its contents
   $log->reset();

=cut

=head1 DESCRIPTION

A pseudo circular log that is either limited (circular) or of unspecified length (unbounded, not circular in effect). 
In other words it is a circular list where the size is optionally set.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the class.

No input is required, but accepts the following parameter:

=over

=item

B<bufsize> Sets the size of the circular log to be bounded. By default it is set to 0, which means it is unbounded.

=cut

=back

Returns the instantiated class.

=cut

=head1 METHODS

=head2 add()

Adds a log entry to the instance.

Accepts these parameters in the following order:

=over

=item

B<message> The message to be added to the log. If not given it will default to a blank string.

=cut

=item

B<time> The timestamp of the log message. If not given it will default to now-time.

=cut

=back

Returns 1 upon completion (always successful).

=cut

=head2 resetNext()

Resets the iteration over the items in the circular log. It resets a pointer to where it is in the 
log to the first and oldest item (tail).

=cut

=head2 resetNextReverse()

Resets the iteration over items in the circular log. It sets the pointer to the head of the log and
marks the iteration to go in reverse.

=cut

=head2 getNext()

Gets the next item in the circular log. If resetNext() or resetNextReverse() have not been called at 
any time since instantiation or a call to the reset()-method, it will call resetNext() for you (it 
favorizes a forward direction iteration.

Returns a LIST-reference upon success. The LIST-structure is as follows:

   [ MESSAGE. TIME ]

So that the log item message comes first and then the timestamp of the message.

Returns undef upon failure (no items or no more items).

=cut

=head2 getFirst()

Get first N log entries as a list pointer.

It accepts one input and that is the number of entries to return. This parameters is optional and if 
none is given it will default to 1. 

Remember that the method always resets the getNext()-counter like when calling the resetNext()-method.

It returns a LIST-reference upon success, undef if no entries.

The LIST-reference structure is like this:

  [ [message,time],
    [message,time],
    [message,time],
  ]

=cut

=head2 getLast()

Get last N log entries as a list pointer.

It accepts one input and that is the number of entries to return. This parameters is optional and if 
none is given it will default to 1. 

Remember that the method always resets the getNext()-counter like when calling the resetNextReverse()-method.

It returns a LIST-reference upon success, undef if no entries.

The LIST-reference structure is like this:

  [ [message,time],
    [message,time],
    [message,time],
  ]

The order of the list will be in first to last, so the last log message of the log will come last in the list.

=cut

=head2 getFirstAsString()

Gets the first N log entries as a string.

It accepts two input parameters. The first is the number of log entries to return, the second is the format of 
the string to return them in. Both parameters are optional and will default to 1 and "time: message " respectively.

For the structure of the format-parameter see the entryAsString()-method.

The returned string will be a concatenation of all the log entries in the given format, so remember to add some 
kind of spacing at the end (between each entry in other words). 

It returns the string of the log entries upon success, or undef if no log entries could be retrieved.

=cut

=head2 getLastAsString()

Gets the last N log entries as a string.

It accepts two input parameters. The first is the number of log entries to return, the second is the format of 
the string to return them in. Both parameters are optional and will default to 1 and "time: message " respectively.

For the structure of the format-parameter see the entryAsString()-method.

The returned string will be a concatenation of all the log entries in the given format, so remember to add some 
kind of spacing at the end (between each entry in other words).

It returns the string of the log entries upon success, or undef if no log entries could be retrieved.

=cut

=head2 entryAsString()

Convert a single log entry into a string of given format.

It accepts two parameters in the following order: entry, format.

Entry is an ARRAY-reference to the log entry in question. Format is the string format to use when converting the 
entry. Format is optional and will default to "%t: %m".

The format can be specified as a string in the following way:

  "Time: (%t) Message: (%m)"

Where %t is designated as the time part of the log entry and %m as the message part. You can repeat %t and %m as 
many times as you like in the string or omit one or both (if you like to shoot yourself in the leg, go ahead).

It returns the converted string upon success or undef upon failure (missing or wrong entry format).

=cut

=head2 reset()

Reset the log entries and getNext()-pointers so that the log entry collection can start anew.

=cut

=head2 getLog()

Returns a copy of the log HASH at that moment in time.

No input is accepted.

Return value is a HASH of the entire log-data, including circular list pointers, head- and tail positions etc.

=cut

=head2 updated()

Returns the timestamp of the last log entry update (head) or undef if no updates yet.

=cut

=head2 count()

Returns the number of log entries.

=cut

=head2 error()

Returns the last error message of the log instance.

=cut
