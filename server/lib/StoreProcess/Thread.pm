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
# StoreProcess::Thread: class to run a detached thread
#
package StoreProcess::Thread;
use parent 'StoreProcess';

use strict;
use threads;

# constructor
sub new {
   my $class = shift;

   my $self=$class->SUPER::new(@_);

   # set defaults if not specified
   # set threadptr
   if (!exists $self->{pars}{funcptr}) { $self->{pars}{funcptr}=\&mydonothing; }

   return $self;
}

# this is the overridden 
# startprocess sub 
sub execute_startprocess {
   my $self = shift;

   if (!$self->isrunning()) {
      # get endmarker
      my $endmarker=$self->{execute_endmarker};

      # set line remainder to blank
      $self->{line}="";

      my $params=$self->{pars}{pars} || Parameter::Group->new();

      # the StoreProcess::Thread expect one of the parameters 
      # to be threadptr which points to the function to invoke
      my $func=$self->{pars}{funcptr} || \&mydonothing;      

      # create a pipe for comm
      pipe (my $r, my $w);      

      # save read pipe
      $self->{execute_read}=$r;

      # create the thread, pass on info and start it
      my $thr = threads->create($func,$w,$endmarker,$params);

      # save thread
      $self->{thread_ref}=$thr;          
      # save dummy execute pid and ctime
      $self->{execute_pid}=0;
      $self->{execute_ctime}=0;
   } else {
      $self->{error}="A command is running already.";
      return 0;
   }
}

# this is the overridden 
# cleanup sub 
sub execute_cleanup {
   my $self = shift;

   return 1;
}

sub execute_cease {
   my $self = shift;

   # exit threads
   threads->exit();

   # return 1 as true (usually number of arguments sent with signal)
   return 1;
}

sub mydonothing {
   # get write handler
   my $write = shift;
   # get endmarker
   my $endmarker = shift;
   # get params
   my $params = shift;

   # print end of data right away - we do nothing...
   print $write "We do nothing!\n";

   # we are finished - close write handler
   close ($write);

   threads->exit();   

   return 1;
}

sub DESTROY {
   my $self = shift;

   threads->exit();
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<StoreProcess::Thread> - Class for a StoreProcess that is run in a thread.

=cut

=head1 SYNOPSIS

This class is used in the same way as the StoreProcess-class. Please see the StoreProcess-class for more info.

=cut

=head1 DESCRIPTION

Class for a StoreProcess that is run in a thread.

The class is used in the same way as the StoreProcess-class. Please seee the StoreProcess-class for more information.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the constructor of the class.

It is inherited from the StoreProcess-class and takes the same parameteres (see the StoreProcess-class for more information).

In addition it takes the parameter:

=over

=item

B<funcptr> Reference to a function to run in the thread being executed. The parameters is required. If not specified it will run a 
no-do dummy process (see the mydonothing()-method).

=cut

=back

Returns the StoreProcess-instance.

=cut

=head1 METHODS

=head2 execute_startprocess()

Starts the thread'ed process and runs the function specified as the funcptr-parameter to the new()-method.

This method is inherited from the StoreProcess-class. Please see the StoreProcess-class for more information.

The method is not to be called by the user and is for internal use.

=cut

=head2 execute_cleanup()

Cleans up after the thread'ed process when it ends.

This method is inherited from the StoreProcess-class. Please see the StoreProcess-class for more information.

The method is for internal use and is not to be called by the user.

=cut

=head2 execute_cease()

Stops the thread'ed function-process running.

This method is inherited from the StoreProcess-class. Please see the StoreProcess-class for more information.

The method is for internal use and is not to be called by the user.

=cut

=head2 mydonothing()

Does nothing. Placeholder for a function-reference.

Does nothing and directly writes the exitcode of the function before exiting itself. It is mean as a replacement for a missing 
funcptr-option in the new()-method (see the new()-method for more information).

Always returns 1.

The method is for internal use and is not to be called by the user.

=cut

