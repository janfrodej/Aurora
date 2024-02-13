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
# StoreProcess::Shell: class for a shell command and its progress
#
package StoreProcess::Shell;
use parent 'StoreProcess';

use strict;
use IPC::Open3;
use Symbol 'gensym';

# constructor
sub new {
   my $class = shift;

   my $self=$class->SUPER::new(@_);

   return $self;
}

# this is the overridden 
# startprocess sub for a
# shell command
sub execute_startprocess {
   my $self = shift;

   if (!$self->isrunning()) {
      # set line remainder to blank
      $self->{line}="";

      my $command=$self->{pars}{pars} || Parameter::Group->new();
      # get binary
      my $binary=$command->getFirstParameter();
      my @options;
      while (1) {
         my $val=$command->getNextParameter();
         if (!defined $val) { last; }
         push @options,$val;
      }

      my $read=gensym;
      if ($binary ne "") {
         my $pid;
         if ($pid=open3(undef,$read,$read,$binary,@options)) {
            # process has started - save handler
            $self->{execute_fh}=$read;
            # save execute process pid
            $self->{execute_pid}=$pid;
            # get ctime
            my $ctime=(stat "/proc/$pid/stat")[10] || 0;
            # save it
            $self->{execute_ctime}=$ctime;
            return 1;
         } else {
            $self->{error}="Failed to run command: ".$!;
            return 0;
         }
      } else {
         $self->{error}="Command cannot be an empty string.";
         return 0;
      }
   } else {
      $self->{error}="A command is running already.";
      return 0;
   }
}

# this is the overridden 
# cleanup sub for a 
# shell command
sub execute_cleanup {
   my $self = shift;

   # get the file handler
   my $FH=$self->{execute_fh};

   if ($FH) {
      close ($FH);
   }

   return 1;
}

# specific storeprocess cease
# no checking is necessary. That is handled by
# cease.
sub execute_cease {
   my $self = shift;

   # get the file handler
   my $FH=$self->{execute_fh};

   # end shell process, quickly and without checking status
   if ($FH) { close ($FH); }

   return 1;
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<StoreProcess::Shell> - Class for a StoreProcess that is run as a shell-command.

=cut

=head1 SYNOPSIS

This class is used in the same way as the StoreProcess-class. Please see the StoreProcess-class for more info.

=cut

=head1 DESCRIPTION

Class for a StoreProcess that is run as a shell-command.

The class is used in the same way as the StoreProcess-class. Please seee the StoreProcess-class for more information.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the constructor of the class.

It is inherited from the StoreProcess-class and takes the same parameteres (see the StoreProcess-class for more information).

In addition it takes the parameter:

=over

=item

B<echocmd> The command or binary to use to print something to the screen in the shell. It is used for internal mechanisms of the 
execution of the shell-command. It defaults to /bin/echo.

=cut

=item

B<redirerr> Set if STDERR is to be redirected to standard output or not. Valid settings are 1 for true, 0 for false. It defaults to 1 (true).

=cut

=item

B<redirect> Set the redirect STDERR to STDOUT command. If not specified will default to "2>&1".

=cut

=back

Returns the StoreProcess-instance.

=cut

=head1 METHODS

=head2 execute_startprocess()

Starts the shell-process and runs command specified in the pars-option of new (see the StoreProcess-class).

This method is inherited from the StoreProcess-class. Please see the StoreProcess-class for more information.

The method is not to be called by the user and is for internal use.

=cut

=head2 execute_cleanup()

Cleans up after the shell-process when it ends.

This method is inherited from the StoreProcess-class. Please see the StoreProcess-class for more information.

The method is for internal use and is not to be called by the user.

=cut

=head2 execute_cease()

Stops the shell-process running.

This method is inherited from the StoreProcess-class. Please see the StoreProcess-class for more information.

The method is for internal use and is not to be called by the user.

=cut
