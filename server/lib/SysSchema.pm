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
# SysSchema - package for defining AURORA system related cleaning, constants etc.
#
package SysSchema;
use strict;
use POSIX;

# define sources
our $FROM_UNKNOWN       =  0;
our $FROM_REST          = -1;
our $FROM_MAINTENANCE   = -2;
our $FROM_NOTIFICATION  = -3;
our $FROM_LOG           = -4;
our $FROM_STORE         = -5;
our $FROM_FILEINTERFACE = -6;
our $FROM_MANUAL        = -7;

# define notification types
our %NTYP = (
   'user.create' => { 
      name => "user.create",
      votes => 0,
      subject => "AURORA create user",
                    },
   'dataset.close' => { 
      name => "dataset.close",
      votes => 2,
      subject => "AURORA close dataset",
                    },
   'dataset.info' => { 
      name => "dataset.info",
      votes => 0,
      subject => "AURORA dataset information",
                    },
   'dataset.remove' => {
      name => "dataset.remove",
      votes => 2,
      subject => "AURORA remove dataset",
                       },
   'dataset.expire' => { 
      name => "dataset.expire",
      votes => 0,
      subject => "AURORA dataset expiring",
                    },
   'distribution.acquire.failed' => {
      name => "distribution.acquire.failed",
      votes => 0, 
      subject => "AURORA acquire failed",
                             },                                   
   'distribution.acquire.success' => {
      name => "distribution.acquire.success",
      votes => 0, 
      subject => "AURORA acquire successful",
                                     },
   'distribution.distribute.failed' => {
      name => "distribution.distribute.failed",
      votes => 0, 
      subject => "AURORA distribute failed",
                                       },
   'distribution.distribute.success' => {
      name => "distribution.distribute.success",
      votes => 0, 
      subject => "AURORA distribute successful",
                                        },
   'distribution.delete.failed' => {
      name => "distribution.delete.failed",
      votes => 0,
      subject => "AURORA delete failed",
                                   },
   'distribution.delete.success' => {
      name => "distribution.delete.success",
      votes => 0,
      subject => "AURORA delete successful",
                                   }
);

# hash for internal constants
our %C=(
   "dataset.man"         => "MANUAL",
   "dataset.auto"        => "AUTOMATED",
   "status.open"         => "OPEN",
   "status.closed"       => "CLOSED",
   "status.failed"       => "FAILED",

   "phase.init"         => "INITIALIZED",
   "phase.acquire"      => "ACQUIRING",
   "phase.dist"         => "DISTRIBUTING",
   "phase.delete"       => "DELETING",
   "phase.failed"       => "FAILED",
);

our %CLEAN = (
   'authtype'               => sub { my $t=shift || ""; $t=substr($t,0,255); $t=~s/[^a-zA-Z0-9]//g; return $t; },

   'bool'                   => sub { my $b=shift; return $Schema::CLEAN_GLOBAL{boolean}->($b); },

   'createtype'             => sub { my $t=shift || "AUTOMATED"; $t=substr($t,0,9); $t=uc($t); if (($t ne "MANUAL") && ($t ne "AUTOMATED")) { $t="AUTOMATED"; } return $t; }, 

   'datasetstatus'          => sub { my $s=shift; $s=uc($s); $s=~s/[^A-Z]//g; if (($s ne C{"status.open"}) && ($s ne C{"status.closed"})) { return undef; } return $s; },

   'datasetToken'           => sub { my $t=shift; $t =~ /^(\d+\-[a-zA-Z0-9\-]+)$/; return $1; }, 

   'duplicates'             => sub { my $d=shift; if (defined $d) { $d=($d =~ /^[01]{1}$/ ? $d : undef); } return $d; },

   'entityname'             => sub { my $n=shift; if (ref($n) eq "ARRAY") { $n=$n->[0] || undef; } $n=$Schema::CLEAN_GLOBAL{nicestring}->($n,1024); $n=~s/^\s+|\s+$//; return $n; },

   'email'                  => sub { my $e=shift; return $Schema::CLEAN_GLOBAL{email}->($e); },

   'fi.store'               => sub { my $n=shift||""; $n=$Schema::CLEAN_GLOBAL{nicestring}->($n,1024); return $n; },

   'gk.script'              => sub { my $s=shift || ""; $s=~s/[\000]//g; return $s; },
   'gk.keyfile'             => sub { my $k=shift || ""; $k=~s/\.\.//g; $k=~s/[\/\<\>\*\?\[\]\`\$\|\;\&\(\)\#\\]//g; $k=$k||""; if ($k !~ /^.*\.gk\_keyfile$/) { return "DONTEXIST"; } return $k; },
   'gk.protocol'            => sub { my $p=shift || ""; $p=~s/[^\a-zA-Z]//g; $p=$p||""; $p=uc($p); return $p; },
   'gk.forceipv4'           => sub { my $f=shift; $f=(!defined $f ? 1 : $f); $f=($f =~ /^[01]{1}$/ ? $f : 1); return $f; },

   'host'                   => sub { my $h=shift; if ((defined $h) && (($h =~ /^\d+\.\d+\.\d+\.\d+$/) || ($h =~ /^\[a-fA-F0-9]+\:{1,2}[a-fA-F0-9\:\.\-]+$/))) { return $Schema::CLEAN_GLOBAL{ip}->($h); } return $Schema::CLEAN_GLOBAL{domain}->($h); },

   'lop'                    => sub { my $o=shift || "="; $o=~s/[^\=\>\<\|\&]//g; if ($o !~ /^[\|\&]{0,1}[\=\>\<]+$/) { $o="="; } return $o; },

   'metadata'               => sub { my $m=shift; my $i=shift; if (ref($m) ne "HASH") { return undef; } if ((defined $i) && (ref($i) ne "ARRAY")) { return undef; } my @k=grep { $_ =~ /^\..*$/ } keys %{$m}; if (defined $i) { push @k,grep { exists $m->{$_} } @{$i}; } my %nm; foreach (@k) { $nm{$_}=$m->{$_}; } return \%nm; },
   'metadatalist'           => sub { my $m=shift; if (ref($m) ne "ARRAY") { return undef; } my @k=grep { $_ =~ /^\..*$/ } @{$m}; return \@k; },
   'metadatamode'           => sub { my $m=shift || "UPDATE"; $m=uc($m); if (($m ne "UPDATE") && ($m ne "REPLACE")) { $m="UPDATE"; } return $m; },
   'metadatasql'            => sub { my $m=shift; my $i=shift||[]; my $c=0; my $p=0; if ((ref($m) ne "HASH") && (ref($m) ne "ARRAY")) { return undef; } if ((defined $i) && (ref($i) ne "ARRAY")) { return undef; } my %hi=map { $_ => 1 } @{$i}; 
                                     sub recurse { 
                                        my $s=shift; 
                                        my $hi=shift;
                                        my $p=shift;
                                        my $c=shift;
                                        if (ref($s) eq "ARRAY") { 
                                           for (my $i=1; $i < @{$s}; $i++) { if ((ref($s->[$i]) eq "HASH") || (ref($s->[$i]) eq "ARRAY"))  { recurse($s->[$i],$hi,undef,$c); } }
                                        } elsif (ref($s) eq "HASH") {
                                           foreach (keys %{$s}) { 
                                              my $k=$_;
                                              if (($k !~ /^\..*$/) && (!exists $hi->{$k}) && ($k !~ /^[\<\>\=\!\-\|\&\^]+$/)) { delete $s->{$k}; $$c=1; } 
                                              else { if ($k =~ /^(parent\..*|table\..*)$/) { $$p=1; } recurse($s->{$k},$hi,undef,$c); }
                                           }
                                        }
                                     }
                                     recurse ($m,\%hi,\$p,\$c); return $p,$m,$c; # return both if parent key present and cleaned hash, retain backwards compability 
                                   },
   'metadatasystem'         => sub { my $m=shift; my $i=shift; if (ref($m) ne "HASH") { return undef; } if ((defined $i) && (ref($i) ne "ARRAY")) { return undef; } my @k; if (defined $i) { push @k,grep { exists $m->{$_} } @{$i}; } my %nm; foreach (@k) { $nm{$_}=$m->{$_}; } return \%nm; },

   'notificationid'         => sub { my $i=shift || ""; $i=~s/([a-zA-Z0-9]{32})/$1/; if ($i =~ /^[a-zA-Z0-9]{32}$/) { return $i; } else { return ""; } },

   'name'                   => sub { my $n=shift; $n=$Schema::CLEAN_GLOBAL{nicestring}->($n,1024); $n=~s/^\s+|\s+$//; return $n; },

   'oauthaudience'          => sub { my $a=shift; return $Schema::CLEAN_GLOBAL{nicestring}->($a,4096); },

   'password'               => sub { my $p=shift; return $Schema::CLEAN_GLOBAL{nicestring}->($p,32); },
   'path'                   => sub { my $p=shift; return $Schema::CLEAN_GLOBAL{target}->($p); },
   'pathsquash'             => sub { my $ps=shift || ""; $ps=$Schema::CLEAN_GLOBAL{target}->($ps); $ps=~s/\.\.\//\//g; $ps=~s/\/\.\.\/\///g; $ps=~s/\\/\//g; $ps=~s/\/\//\//g; return $ps; },
   'permmatch'              => sub { my $m=shift; if ((defined $m) && ($m !~ /^[01]{1}$/)) { $m=undef; } return $m; },
   'permop'                 => sub { my $o=shift || "APPEND"; $o=uc($o); my $no=1; if ($o eq "REPLACE") { $no=undef; } elsif ($o eq "REMOVE") { $no=0; } return $no; }, 
   'port'                   => sub { my $p=shift || 0; $p=~s/[^\d]//g; return $p || 0; },

   'realbool'               => sub { my $b=shift; if (defined $b) { $b=($b ? 1 : 0); } else { $b=0; } return $b; },

   'rid'                    => sub { my $r=shift || ""; $r=~s/([a-zA-Z0-9]{32})/$1/; if ($r =~ /^[a-zA-Z0-9]{32}$/) { return $r; } else { return ""; } },

   'scparamname'            => sub { my $n=shift || ""; $n=~s/[^A-Za-z0-9]//g; $n=$n||""; return $n; },
   'scparamval'             => sub { my $v=shift || ""; $v=$Schema::CLEAN_GLOBAL{nicestring}->($v,255); return $v; },

   'script.code'            => sub { my $c=shift || ""; $c=substr($c,0,16384); return $c; },

   'username'               => sub { my $u=shift; return $Schema::CLEAN_GLOBAL{username}->($u); },   

   'envvalue'               => sub { my $ev=shift || ""; $ev=$Schema::CLEAN_GLOBAL{nicestring}->($ev,128); return $ev; },
);

# hash for metadata fields names
our %MD=(
   "computer.id"          => "system.computer.id",
   "computer.host"        => ".system.task.param.host",
   "computer.port"        => ".system.task.param.port",
   "computer.username"    => ".system.task.param.username",
   "computer.authmode"    => ".system.task.classparam.authmode",
   "computer.path"        => ".computer.path",
   "computer.publickey"   => ".system.task.param.knownhosts",
   "computer.useusername" => ".computer.useusername",
   "computer.task.base"   => ".system.task",

   "dataset.userpath"          => "system.dataset.userpath",
   "dataset.status"            => "system.dataset.status",
   "dataset.distbase"          => "system.distribution",
   "dataset.created"           => "system.dataset.time.created",
   "dataset.progress"          => "system.dataset.time.progress",
   "dataset.closed"            => "system.dataset.time.closed",
   "dataset.expire"            => "system.dataset.time.expire",
   "dataset.lifespan"          => "system.dataset.lifespan",
   "dataset.extendmax"         => "system.dataset.extendmax",
   "dataset.extendlimit"       => "system.dataset.extendlimit",
   "dataset.open.lifespan"     => "system.dataset.open.lifespan",
   "dataset.open.extendmax"    => "system.dataset.open.extendmax",
   "dataset.open.extendlimit"  => "system.dataset.open.extendlimit",
   "dataset.close.lifespan"    => "system.dataset.close.lifespan",
   "dataset.close.extendmax"   => "system.dataset.close.extendmax",
   "dataset.close.extendlimit" => "system.dataset.close.extendlimit",
   "dataset.tokenbase"         => "system.dataset.token",

   "dataset.removed"         => "system.dataset.time.removed",
   "dataset.archived"        => "system.dataset.time.archived",
   "dataset.retry"           => "system.dataset.retry",
   "dataset.type"            => "system.dataset.type",
   "dataset.creator"         => "system.dataset.creator",
   "dataset.computer"        => "system.dataset.computerid",
   "dataset.computername"    => "system.dataset.computername",
   "dataset.size"            => "system.dataset.size",
   "dataset.intervals"       => "system.dataset.notification.intervals",
   "dataset.notified"        => "system.dataset.notification.notified",

   # Dublin Core - see also https://www.dublincore.org/specifications/dublin-core/dcmi-terms/
   "dc.creator"           => ".Creator",       # An entity primarily responsible for making the resource.
   "dc.contributor"       => ".Contributor",   # An entity responsible for making contributions to the resource.
   "dc.publisher"         => ".Publisher",     # An entity responsible for making the resource available.
   "dc.title"             => ".Title",         # A name given to the resource.
   "dc.date"              => ".Date",          # A point or period of time associated with an event in the lifecycle of the resource. ISO8601-1
   "dc.language"          => ".Language",      # A language of the resource. Non-literal from controlled voc., eg. ISO 639-2, 639-3
   "dc.format"            => ".Format",        # The file format, physical medium, or dimensions of the resource. Controlled vocabulary, eg. MIME-type for files.
   "dc.subject"           => ".Subject",       # A topic of the resource. URI, string, preferrably controlled vocabulary
   "dc.description"       => ".Description",   # An account of the resource. Abstract, TOC, graphical repres. or freetext.
   "dc.identifier"        => ".Identifier",    # An unambiguous reference to the resource within a given context. String conforming to identification system
   "dc.relation"          => ".Relation",      # A related resource. Pref. URI or string conforming to identification system.
   "dc.source"            => ".Source",        # A related resource from which the described resource is derived, non-literal, URI or string in identification system
   "dc.type"              => ".Type",          # The nature or genre of the resource, controlled vocabulary if possible
   "dc.coverage"          => ".Coverage",      # The spatial or temporal topic of the resource, spatial applicability of the resource, or jurisdiction under which the resource is relevant. Controlled voc. - see link above.
   "dc.rights"            => ".Rights",        # Information about rights held in and over the resource. Statment of property/intellectual rights

   "entity.parent"            => "system.entity.parentid",
   "entity.parentname"        => "system.entity.parentname",
   "entity.id"                => "system.entity.id",
   "name"                     => ".system.entity.name",
   "entity.type"              => "system.entity.typeid",
   "entity.typename"          => "system.entity.typename",

   "fi.store"             => "system.fileinterface.store",

   "gk.base"              => "system.gatekeeper",

   "interface.class"      => "system.interface.class",
   "interface.parbase"    => "system.interface.classparam",

   "notice.base"          => "system.notice",
   "notice.subscribe"     => "system.notice.subscribe",
   "notice.votes"         => "system.notice.votes",

   "store.class"          => "system.store.class",
   "storecollection.base" => "system.task.definition",

   "script.code"          => "system.script.code",

   "task.assigns"         => "system.task.assignments",

   "user.deleted"         => "system.user.time.deleted",

   "lastlogontime"        => "system.user.lastlogon",
   "email"                => "system.user.username",
   "username"             => "system.user.username",
   "fullname"             => "system.user.fullname",
   "oauthname"            => "system.authenticator.oauthaccesstoken.user",
   "crumbsbase"           => "system.authenticator.crumbs",
   "crumbsuuid"           => "system.authenticator.crumbs.uuid",
);

our %MDPUB = (
   "DATASET" => [
      $MD{"dataset.status"},
      $MD{"dataset.created"},
      $MD{"dataset.closed"},
      $MD{"dataset.expire"},
      $MD{"dataset.size"},
      $MD{"dataset.removed"},
      $MD{"dataset.type"},
      $MD{"dataset.creator"},
      $MD{"dataset.computer"},
      $MD{"dataset.computername"},
      $MD{"entity.id"},
      $MD{"entity.type"},
      $MD{"entity.typename"},
      $MD{"entity.parent"},
      $MD{"entity.parentname"}
   ],
   "ALL" => [
      $MD{"entity.id"},
      $MD{"entity.type"},
      $MD{"entity.typename"},
      $MD{"entity.parent"},
      $MD{"entity.parentname"},
      $MD{"name"},
      $MD{"fi.store"},
   ],
);

our %MDPRESETS = (
   $MD{"dc.creator"} => "Dublin Core Creator",
   $MD{"dc.contributor"} => "Dublin Core Contributor",
   $MD{"dc.publisher"} => "Dublin Core Publisher",
   $MD{"dc.title"} => "Dublin Core Title",
   $MD{"dc.date"} => "Dublin Core Date",
   $MD{"dc.language"} => "Dublin Core Language",
   $MD{"dc.format"} => "Dublin Core Format",
   $MD{"dc.subject"} => "Dublin Core Subject",
   $MD{"dc.description"} => "Dublin Core Description",
   $MD{"dc.identifier"} => "Dublin Core Identifier",
   $MD{"dc.relation"} => "Dublin Core Relation",
   $MD{"dc.source"} => "Dublin Core Source",
   $MD{"dc.type"} => "Dublin Core Type",
   $MD{"dc.coverage"} => "Dublin Core Coverage",
   $MD{"dc.rights"} => "Dublin Core Rights",
);

# hash for config settings
our %CFG=(
   "sshlocation"        => "system.binary.ssh.location",
   "sshprivatekey"      => "system.computer.privatekey",
);

1;

__END__


=encoding UTF-8

=head1 NAME

C<SysSchema> Module to check and clean values coming into the AURORA-system and defining metadata namespace.

=cut

=head1 SYNOPSIS

   use SysSchema;

   # clean value
   my $email="john.doe@somedomain.top";
   $email=$SysSchema::CLEAN{email}->($email);

   # get metadata namespace
   my $usernamelocation=$SysSchema::MD{username};

   # get constant
   my $setcreated=$SysSchema::C{"status.open"};

=cut

=head1 DESCRIPTION

Module to check and clean values entered into the AURORA-system, but also to get 
namespace locations of specific metadata that are often used in some way.

This module is used everywhere in the AURORA-system when cleaning and checking of 
values are needed, so that the definition of it is in one place. The only exception 
is AuroraDB who has its own schema-module (Schema.pm).

It also contains a constant-section.

The various data-structures in order of appearance are:

=over

=item

B<NTYP> HASH that defines notification types and their voting defaults.

=cut

=item

B<C> HASH that defines Constants.

=cut

=item

B<CLEAN> HASH that defines cleaning for various values used by the AURORA-system and their defaults.

=cut

=item

B<MD> HASH that contains metadata namespace definitions of where often used information is located.

=cut

=item

B<MDPUB> HASH that contains metadata namespace locations that are considered public metadata that can 
be handed out, even though it is located in the non-public part of the metadata (not starting with ".").

=cut

=item

B<CFG> HASH that defines where in the AURORA configuration file that various values are set.

=cut

=back

In addition to these structures, the SysSchema-module also contains a definition of sources for 
various Notifications. Valid definitions are: $FROM_UNKNOWN, $FROM_REST, $FROM_MAINTENANCE, 
$FROM_NOTIFICATION, $FROM_LOG and $FROM_STORE.

Beyond this have a look in the SysSchema-module itself for more information about what is 
defined within the various structures themselves.

=cut

