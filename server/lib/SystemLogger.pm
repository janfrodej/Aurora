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
# SystemLogger: a module to send logging to Syslog in an easy way
#
package SystemLogger;
use strict;
use Sys::Syslog;

sub new {
   my $class=shift;
   
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # check values, set defaults
   if (!$pars{ident}) { $pars{ident}="DUMMY: "; } # identifier to use
   if (!$pars{facility}) { $pars{facility}=$Sys::Syslog::LOG_DAEMON; } # facility to use
   if (!$pars{priority}) { $pars{priority}="ERR"; } # log from this priority and up

   # ensure sensible priority
   $pars{priority}=$self->int2Prio($self->prio2Int($pars{priority}));

   # save pars
   $self->{pars}=\%pars;

   # set some defaults
   $self->{error}="";
   $self->{open}=0;

   return $self;
}

sub open {
   my $self=shift;

   my $ident=$self->{pars}{ident};
   my $facility=$self->{pars}{facility};

   if (!$self->isOpen()) {
      if (openlog ($ident,"nofatal,pid",$facility)) {
         $self->{open}=1;
         return 1;
      } else {
         $self->{error}="Unable to open syslog: $!";
         return 0;
      }
   } else {
      $self->{error}="Unable to open syslog: it is already open";
      return 0;
   }
}

sub log {
   my $self=shift;
   my $msg=shift || "";
   my $priority=shift || "INFO";

   if ($self->isOpen()) {
       # convert prio to integer
      my $gprio=$self->prio2Int($self->{pars}{priority});
      my $lprio=$self->prio2Int($priority);

      # only syslog if at right priority.
      if ($lprio >= $gprio) {
         # notify in syslog
         if (syslog($self->int2Prio($lprio),"%s",$msg)) {
            return 1;
         } else {
            $self->{error}="Unable to log: $!";
            return 0;
         }
      }
      # return success, even if not at right priority
      return 1;
   } else {
      $self->{error}="Unable to log: syslog has not been opened yet";
      return 0;
   }
}

sub prio2Int {
   my $self=shift;
   my $priority=shift || "ERR";

   # ensure sensible content
   $priority=~s/([a-zA-Z]+)/$1/;
   $priority=$priority || "ERR";
   $priority=uc($priority);

   if ($priority eq "DEBUG") { return 0; }
   elsif (($priority eq "INFO") || ($priority eq "INFORMATION")) { return 1; }
   elsif (($priority eq "WARN") || ($priority eq "WARNING")) { return 2; }
   elsif (($priority eq "ERR") || ($priority eq "ERROR")) { return 3; }
   elsif (($priority eq "CRIT") || ($priority eq "CRITICAL")) { return 4; }
   else { return 1; }
}

sub int2Prio {
   my $self=shift;
   my $int=shift;

   $int=~s/(\d+)/$1/;
   if (!defined $int) { $int=1; }

   if ($int == 0) { return "DEBUG"; }
   elsif ($int == 1) { return "INFO"; }
   elsif ($int == 2) { return "WARNING"; }
   elsif ($int == 3) { return "ERR"; }
   elsif ($int == 4) { return "CRIT"; }
   else { return "INFO"; }
}

sub close {
   my $self=shift;

   if ($self->isOpen()) {
      closelog();
   }
}

sub isOpen {
   my $self=shift;

   return $self->{open};
}

sub error {
   my $self=shift;

   return $self->{error};
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<SystemLogger> Class for writing to syslog.

=cut

=head1 SYNOPSIS

   use SystemLogger;

   # instantiate
   my $sl=SystemLogger->new(ident=>"MyProcessName",priority=>"DEBUG");

   # attempt to open syslog
   if (!$sl->open()) { die "Unable to open syslog: ".$sl->error(); }

   # log to syslog
   $sl->log("I have a bad feeling about this.","WARNING");

   # close syslog (if open)
   $sl->close();

=cut

=head1 DESCRRIPTION

Class for handling writing to syslog in an easy manner.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the SystemLogger-class.

Accepts the following parameters:

=over

=item

B<facility> This is the facility to syslog to. Optional. Defaults to $Sys::Syslog::LOG_DAEMON;

=cut

=item

B<ident> This is the identifier to use when syslogging. SCALAR. Optional (but rather recommended). 
defaults to "DUMMY".

=cut

=item

B<priority> Sets the priority of the logging. SCALAR. Optional. Defaults to "ERR". This sets what 
to write to the syslog. If set to a certain level, such as "WARNING" it will syslog everything from level 
"WARNING" and up to and including "CRIT". Valid levels are in correct order: DEBUG, INFO, WARNING, 
ERR and CRIT. DEBUG is the most "talkative" level, while "CRIT" is the least.

=cut

=back

Returns a SystemLogger instance.

=cut

=head1 METHODS

=head2 open()

Open syslog for use.

No input parameters accepted.

Attempts to open syslog for use.

Returns 1 upon success, 0 upon failure. Please check the error()-
method to find out more about a potential failure.

=cut

=head2 log()

Writes a log entry to syslog.

Accepted input is in the following order: message, priority.

Message is the message to write to syslog. SCALAR. Required.

Priority is the message priority. SCALAR. Optional. Defaults to 
"INFO". Valid levels are: DEBUG, INFO, WARNING, ERR and CRIT.

Only messages that are at the priority-level set in the constructor or 
higher will be written to syslog. Other messages are just dropped and 
method still returning success.

Returns 1 upon success, 0 upon failure. Please check the error()-method for 
more information upon failure.

=cut

=head2 prio2Int()

Converts a textual priority to int. 

Accepted input is "priority". SCALAR. Optional. Defaults to "ERR".

Valid priority input: DEBUG, INFO, WARNING, ERR and CRIT.

Returns the int for the specified priority, or 1 if not 
recognized (=INFO).

=cut

=head2 int2Prio()

Convert int to textual priority.

Accepted input is priority int. SCALAR. Optional. Defaults to 1 (INFO).

Valid priority input: 0 (DEBUG), 1 (INFO), 2 (WARNING), 3 (ERR), 4 (CRIT).

Returns the textual priority or "INFO" if not specified or recognized.

=cut

=head2 close()

Closes the syslog.

No input accepted.

No return value set.

=cut

=head2 isOpen()

Return if syslog has been opened or not?

No input accepted.

Returns 1 for open, 0 for not open.

=cut

=head2 error()

Returns last error from the instance.

No input accepted.

Returns the last error or blank if none.

=cut
