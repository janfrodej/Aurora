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
# Notice: a placeholder class for notice methods in the AURORA notification-service.
#
package Notice;

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
   if (!exists $pars{host}) { $pars{host}="localhost"; }

   # save parameters
   $self->{pars}=\%pars;

   return $self;
}

# send a notice - to be overridden
sub send {
   my $self=shift;
   my $from=shift || ""; # the receivers address
   my $to=shift || ""; # senders address
   my $subject=shift || ""; # subject of notice
   my $notice=shift || ""; # the notice to send
   my $threadid=shift || ""; # threadid to use if possible
   my @t;
   my $threadids=shift; # previous threadids, if any
   if (ref($threadids) ne "ARRAY") { my @t; $threadids=\@t; }

   # do whatever needed to send it

   return 1;
}

sub result {
   my $self=shift;

   return $self->{result} || "";
}

sub error {
   my $self=shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Notice> - A placeholder class for notice-methods in the AURORA notification-service

=cut

=head1 SYNOPSIS

   use Notice;

   # create instance
   my $n=Notice->new(host=>"oompaloompa");

   # send a notice
   $n->send("charliebucket193@yahoo.com","willy.wonka@wonka.chocolate","I Won!!","Hi\nPlease know that I have found one of the golden tickets.");

   # get last error
   print $n->error();

   # get last result of send()-method
   print $n->result();

=cut

=head1 DESCRIPTION

A placeholder class for notice-methods in the AURORA notification-service.

The class implements mainly the method send, which is to be overridden.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiate class.

The method takes one input: server. This is just an example in the placeholder. This method is to be overridden by 
the inheriting class in order to define the necessary parameters to setup the Notice sending method properly.

Returns a class instance.

=cut

=head1 METHODS

=head2 send()

Attempts to send a notice through a service of some kind.

It accepts these input parameters in the following order:

=over

=item

B<from> Denotes who the notice is from. This is to be in the format of the Notice-class that implements this method. 
It can also be ignored if that is relevant to the inheriting class.

=cut

=item

B<to> Denotes who the notice is to be sent to. The receivers address in a format relevant to the Notice-class in question.

=cut

=item

B<subject> This is the subject of the notice being sent. This field can be ignored if that is relevant to the inheriting 
class (eg. SMS).

=cut

=item

B<notice> This is the notice to send to the receiver.

=cut

=item

B<threadid> The thread id to use for the notice being sent, if possible (not all message transports support this). SCALAR. Optional.

=cut

=item

B<threadids> Previous thread ids used for reference if usable. LIST-reference. Optional. Empty will be created by default.

=cut

=back

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

This method is to be overridden by the inheriting class. The format and use of the parameters from, to and 
subject is up to that class. The only requirement is that they are to be SCALAR.

=cut

=head2 result()

Returns the last result of the send command or a blank string.

This method will return a message both if the last send()-method invocation 
was successful or not. The result message can be blank if the inheriting class 
do not have any message to return.

It is the task of the inheriting class to set $self->{result} to the relevant message.

=cut

=head2 error()

Returns the last error that has happened (if any).

No input is accepted.

=cut
