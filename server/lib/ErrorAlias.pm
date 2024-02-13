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
# Package ErrorAlias: defines aliases for error code IDs returned by AURORA
#
package ErrorAlias;

use strict;

# ERROR CODE FORMAT
#
# NNNNSSTTL

# NNNN - Unique incremental ID of error message. Max 1000-9999 ids

# SS - 2 digits for SOURCE (where in REST-server was error raised). Maximum 00-99 sources.
my %SS = (
   10 => "Authenticator",
   11 => "REST-server/Daemon",
   12 => "Computer",
   13 => "Dataset",
   14 => "Group",
   15 => "Interface",
   16 => "Notice",
   17 => "Store",
   18 => "Task",
   19 => "Template",
   20 => "User",
   21 => "General",
);

# TT - 2 digits for TYPE (type and source of error). Maximum 00-99 types:
my %TT = (
   00 => "Server Internal Other",
   01 => "Server Internal Template issue", # caused by content already in database, not input from user
   02 => "Server Internal Database issue", # something wrong with the content, not the contact or use of the database
   03 => "Server Internal Data Processing issue", # encode/decode, data processing etc.

   25 => "Server External Database issue",
   26 => "Server External Storage issue",
   27 => "Server External Interface issue",
   28 => "Server External Store issue",
   29 => "Server External Other",

   50 => "Client Other",
   51 => "Client Input issue",
   52 => "Client Permission issue",
   53 => "Client Authentication issue",
   54 => "Client Transgression issue",
   55 => "Client Template issue",
);

# L - 1 digit for LOCATION (source of the error). Maximum 0-9 locations.
my %L = (
  0 => "Server Internal",
  1 => "Server External",
  2 => "Client",
);

# Mathematical manipulation of the error code
#
# CODE = NNNN x 100000 + SS x 1000 + TT x 10 + L
#
# Example:
#
# NNNN/ID = 1000, SS=13 (dataset), TT=51 (Client Input Issue), L=2
#
# CODE = 1000 x 100000 + 13 x 1000 + 51 x 10 + L = 100013512
#
# To reverse it / read it out:
#
# NNNN/ID = (CODE / 100000) % 10000
# SS = (CODE / 1000) % 100
# TT = (CODE / 10) % 100
# L = CODE % 10
#

our %ERR = (
   # authenticators
   "authwrong"          => 100010532,    # wrong username/password
   "authmissing"        => 100110532,    # Missing authentication information for user
   "authvaltimeout"     => 100210532,    # Authstr has timed out and is no longer valid.
   "authvallifespan"    => 100310532,    # Authstr has timed out on its lifespan and is no longer valid.
   "authvalinvalid"     => 100410532,    # Unable to find any matching user in the system.
   "authvalmultiple"    => 100510020,    # Multiple ids returned for authstr. Please contact an administrator
   "authvalformat"      => 100610512,    # Input string is of wrong format. Format is supposed to be.....

   "authvaldbconn"      => 100710251,    # Unable to connect to database
   "authvalgetmd"       => 100810251,    # Unable to get metadata of user
   "authvalsearch"      => 100910251,    # Unable to search for user
   "authvalquery"       => 101010251,    # Unable to query database
   "authvaldbins"       => 101110251,    # Unable to insert data into database
   "authvalcruser"      => 101210251,    # Unable to create user

   "authvalextother"    => 101310291,    # Error reading from external resource
   "authvalprocjson"    => 101410030,    # Internal server data processing failure, failed decoding JSON
   "authvalaudience"    => 101510291,    # Audience of endpoint is not consistent with expectations. Unable to validate
   "authvalrestricted"  => 101610512,    # Email address $email is restricted/local and you are not allowed to validate with it through this authenticator.
   "authvalconflict"    => 101710020,    # User appears to have changed his oauth username (or more likely his email address). It is a conflict with this account with a possible other account
   "authvalextmissing"  => 101810291,    # User fullname is missing from the resource endpoints.
   "authvalextmisseml"  => 101910291,    # User email-field is missing from the resource endpoints.
   "authvalextconnect"  => 102010291,    # Unable to connect to endpoint $endpoint.

   "authsaveblank"      => 102110000,   # Unable to save blank user or authentication str. Something went wrong in the generation or extraction of the authstr for saving.
   "authsavestorable"   => 102210000,   # This authenticator cannot save its authstr since it is not storable. 
 
   "restinvalidtype"    => 102311532,   # Invalid authentication type XYZ attempted 
   "restmissingpar"     => 102411512,   # Missing input parameter to REST-server
   "restinstfailed"     => 102511000,   # Unable to instantiate Authenticator-class XYZ
);

sub code2ID {
   my $code=shift||0;

   # validity check of input code
   if ($code !~ /^\d{4}\d{2}\d{2}\d{1}$/) { return undef; }

   # return the 
   return (($code / 100000) % 10000);
}

sub code2Source {
   my $code=shift||0;
   # validity check of input code
   if ($code !~ /^\d{4}\d{2}\d{2}\d{1}$/) { return undef; }

   # return the ID
   return (($code / 1000) % 100);
}

sub code2SourceString {
   my $code=shift||0;

   # validity check of input code
   if ($code !~ /^\d{4}\d{2}\d{2}\d{1}$/) { return undef; }

   my $source=code2Source($code);
   return $SS{$source};
}

sub code2Type {
   my $code=shift||0;

   # validity check of input code
   if ($code !~ /^\d{4}\d{2}\d{2}\d{1}$/) { return undef; }

   # return the ID
   return (($code / 10) % 100);
}

sub code2TypeString {
   my $code=shift||0;

   # validity check of input code
   if ($code !~ /^\d{4}\d{2}\d{2}\d{1}$/) { return undef; }

   my $type=code2Type($code);
   return $TT{$type};
}

sub code2Location {
   my $code=shift||0;

   # validity check of input code
   if ($code !~ /^\d{4}\d{2}\d{2}\d{1}$/) { return undef; }

   # return the ID
   return ($code % 10);
}

sub code2LocationString {
   my $code=shift||0;

   # validity check of input code
   if ($code !~ /^\d{4}\d{2}\d{2}\d{1}$/) { return undef; }

   my $location=code2Location($code);
   return $L{$location};
}

sub code2String {
   my $code=shift||0;

   # validity check of input code
   if ($code !~ /^\d{4}\d{2}\d{2}\d{1}$/) { return undef; }

   return "Error ID: ".code2ID($code)." Source: ".code2SourceString($code)." Type: ".code2TypeString($code)." Location: ".code2LocationString($code);
}

1;
