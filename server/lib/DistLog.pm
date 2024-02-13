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
# DistLog - routines for creating a valid distribution log entry.
#
package DistLog;
use strict;
use Exporter 'import';
use Content::JSON;
use SysSchema;

our @EXPORT = qw(createDistLogEntry parseDistLogEntry);

sub createDistLogEntry {
   my %pars=@_;

   # set default, if none given
   if (!defined $pars{event})        { $pars{event}="TRANSFER"; }
   if (!defined $pars{sc})           { $pars{sc}=0; }

   if (!defined $pars{from})         { $pars{from}="FILEINTERFACE"; }
   if (!defined $pars{fromid})       { $pars{fromid}=$SysSchema::FROM_FILEINTERFACE; }
   if (!defined $pars{fromhost})     { $pars{fromhost}=""; }
   if (!defined $pars{fromhostid})   { $pars{fromhostid}=0; }
   if (!defined $pars{fromhostname}) { $pars{fromhostname}=""; }
   if (!defined $pars{fromloc})      { $pars{fromloc}=0; }

   if (!defined $pars{to})           { $pars{to}="FILEINTERFACE"; } 
   if (!defined $pars{toid})         { $pars{toid}=$SysSchema::FROM_FILEINTERFACE; }
   if (!defined $pars{tohost})       { $pars{tohost}=""; }
   if (!defined $pars{tohostid})     { $pars{tohostid}=0; }
   if (!defined $pars{tohostname})   { $pars{tohostname}=""; }   
   if (!defined $pars{toloc})        { $pars{toloc}=0; }

   if (!defined $pars{uid})          { $pars{uid}=0; }

   # uppercase event
   $pars{event}=uc($pars{event});

   # output correct formatted string
   my $str;
   if ($pars{event} eq "TRANSFER") {
      $str="$pars{event}|$pars{sc}|$pars{from} ($pars{fromid})|$pars{fromhost} ($pars{fromhostid} $pars{fromhostname})|$pars{fromloc}|$pars{to} ($pars{toid})|$pars{tohost} ($pars{tohostid} $pars{tohostname})|$pars{toloc}|$pars{uid}";
   } elsif ($pars{event} eq "REMOVE") {
      $str="$pars{event}|$pars{sc}|$pars{from} ($pars{fromid})|$pars{fromhost} ($pars{fromhostid} $pars{fromhostname})|$pars{fromloc}||||$pars{uid}";
   } elsif ($pars{event} eq "RESURRECT") {
      $str="$pars{event}|$pars{sc}|$pars{from} ($pars{fromid})|$pars{fromhost} ($pars{fromhostid} $pars{fromhostname})|$pars{fromloc}|$pars{to} ($pars{toid})|$pars{tohost} ($pars{tohostid} $pars{tohostname})|$pars{toloc}|$pars{uid}";
   } else {
      # invalid event type
      $str="";
   }

   # create JSON-content
   my @list;
   push @list,$str;
   push @list,\%pars;

   # create JSON-instance
   my $json=Content::JSON->new();

   if (!$json) { return ""; }

   # encode list to JSON
   my $res=$json->encode(\@list);   
  
   if (!defined $res) { return ""; }
 
   # return resulting JSON data
   return $res;
}

sub parseDistLogEntry {
   my $entry=shift;

   # remove !DISTLOG
   $entry=~s/^\!DISTLOG\s+(.*)$/$1/;

   # create JSON instance
   my $json=Content::JSON->new();

   # decode JSON-string into perl ref
   my $res=$json->decode($entry);

   if (!defined $res) { return undef; }

   # return decoded result
   return $json->get();
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<DistLogEntry> Module to manipulate distribution log entries.

=cut

=head1 SYNOPSIS

   use DistLog;

   my $entry=createDistLogEntry(event=>"REMOVE",
                                from=>"Store::RSyncSSH",
                                fromid=>1234,
                                fromhost=>1.2.3.4,
                                fromhostid=>0,
                                fromhostname=>"MyStorageServer";
                                fromloc=>"/somewhere/over/the/rainbow",
                                uid=>56
                               );

   my $ref=parseDistLogEntry($entry);

=head1 DESCRIPTION

Module creating and manipulating distribution log entries in the correct way. createDistLogEntry is exported as default.

=cut

=head1 FUNCTIONS

=head2 createDistLogEntry()

create a proper distribution log entry based upon a set of parameter input.

Possible parameters are:

=over

=item

B<event> Defines the event-type of the log entry. SCALAR. Optional. Defaults to "TRANSFER". Valid values are "TRANSFER", "REMOVE" and "RESURRECT".

=cut

=item

B<sc> StoreCollection entity ID. SCALAR. Optional. Defaults to 0 (unknown/invalid).

=cut

=item

B<from> From-class of the event. SCALAR. Optional. Defaults to "FILEINTERFACE". This should be the textual name of the Store-class that 
was used for the event. Some special class-names are allowed: FILEINTERFACE and UNKNOWN. FILEINTERFACE is not a Store-class, but signifies 
the local fileinterface of AURORA. UNKNOWN means that the from-class of the event is unknown, typically only used in the case of manual 
datasets were the data is put in place manually by the user.

=cut

=item

B<fromid> The entity id of the from-class of the event. SCALAR. Optional. Defaults to -6 (FILEINTERFACE). Valid values are usually 
anything above 0 that corresponds with an entity in the AURORA database. Lower values than zero are only used to signify special 
from-entities that are not Store-classes, such as FILEINTERFACE (-6) and UNKNOWN (0).

=cut

=item

B<fromhost> Host-address/DNS of the from-host that the event is working with. SCALAR. Optional. Defaults to blank string.

=cut

=item

B<fromhostid> Entity ID of the from-host, if any. SCALAR. Optional. Defaults to 0 (UNKNOWN). Valid values are entity IDs over 
0 from the AURORA database.

=cut

=item

B<fromhostname> The textual name of the from-host, if any. SCALAR. Optional. Defaults to blank string.

=cut

=item

B<fromloc> The location that the event worked with on the from-host. SCALAR. Optional. Defaults to 0. The location string only 
have meaning for the from-class being used. It can be an integer or a string, depending upon circumstance.

=cut

=item

B<to> The to-class being used with the event. SCALAR. Optional. Defaults to FILEINTERFACE. This should be the textual name of the Store-class in the 
to-point. Some special class-names are allowed: FILEINTERFACE.

=cut

=item

B<toid> The entity id of the to-class of the event. SCALAR. Optional. Defaults to -6 (FILEINTERFACE). Valid values are usually
anything above 0 that corresponds with an entity in the AURORA database. Lower values than zero are only used to signify special
to-entities that are not Store-classes, such as FILEINTERFACE (-6).

=cut

=item

B<tohost> Host-address/DNS of the to-host that the event is working with. SCALAR. Optional. Defaults to blank string.

=cut

=item

B<tohostid> Entity ID of the to-host, if any. SCALAR. Optional. Defaults to 0 (UNKNOWN). Valid values are entity IDs over 
0 from the AURORA database.

=cut

=item

B<tohostname> The textual name of the to-host, if any. SCALAR. Optional. Defaults to blank string.

=cut

=item

B<toloc> The location that the event worked with on the to-host. SCALAR. Optional. Defaults to 0. The location string only 
have meaning for the to-class being used. It can be an integer or a string, depending upon circumstance.

=cut

=back

Returns a ready formatted string of the distribution log entry that can be given to the Log-service of AURORA upon 
success. Blank string upon failure.

The formatted string is in JSON format and looks like this:

   [
      STRING, (SHORT-FORM INFO of the distlog event)
      {HASH} (HASH with all the key-value pairs of the event)
   ]

=cut

=head2 parseDistLogEntry()

Parses a textual distlog entry that has been created with the createDistLogEntry()-method.

Input parameter: DistLog-string

Returns the parsed JSON-data as a ARRAY-reference upon success, undef upon failure.

The format of the ARRAY-reference is the same as the JSON format, mentioned in createDistLogEntry.

=cut
