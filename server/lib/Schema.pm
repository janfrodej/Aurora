#!/usr/bin/perl -w
# Copyright (C) 2019-2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
# Copyright (C) 2019-2024 Bård Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway
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
# Schema - package for checking/cleaning Aurora DB field values
#
package Schema;
use strict;
use POSIX;

# CLEANING DAD related values/schema
our %CLEAN_GLOBAL=(
   # calculate number of digits
   digits       => sub { my $n=shift || 2**8; return (floor(log($n) / log(10))+1); },
   # db bigint
   bigint       => sub { my $n=shift || 0; $n=substr($n,0,20); $n=~s/[^\d]//g; if ($n !~ /^\d+$/) { $n=0; } if (($n < 0) || ($n > 2**64-1)) { $n=0; } return $n; },
   trueint      => sub { my $n=shift || ''; $n =~ /^(\-?\d+)(\.\d+)?$/; return $1; },
   # db tinyint - used as true/false
   boolean      => sub { my $b=shift || 0; $b=substr($b,0,1); $b=~s/[^\d]//g; $b=($b =~ /^[01]{1}$/ ? $b : 0); return $b; },
   'int'        => sub { my $i=shift || 0; $i=substr($i,0,10); $i=~s/[^\d]//g; if ($i !~ /^\d+$/) { $i=0; } if (($i < 0) || ($i > 2**32-1)) { $i=0; } return $i; },
   # unix time hires
   datetime     => sub { my $dt=shift || 0; $dt=substr($dt,0,26); $dt=~s/[^\d\.]//g; if ($dt !~ /^[\d\.]+$/) { $dt=0; } if (($dt < 0) || ($dt > 2**64-1)) { $dt=0; } return $dt; },
   # RFC 1035 etc.
   domain       => sub { my $str=shift || "dummy.domain.topdomain"; $str=substr($str,0,255); $str=~s/[^a-zA-Z0-9\.\-]//g; if ($str !~ /^[a-zA-Z]+.*$/) { $str="dummy.domain.topdomain"; } return $str; },
   # email, see RFC5322 and RFC1035
   email        => sub { my $str=shift || ""; $str=substr($str,0,255); $str=~s/[^a-zA-Z0-9\.\!\#\$\%\%\&\'\*\+\-\/\=\?\^\_\`\{\|\}\~\@]//g; if ($str !~ /^[a-zA-Z]{1}[a-zA-Z0-9\.\!\#\$\%\%\&\'\*\+\-\/\=\?\^\_\`\{\|\}\~]*\@[a-zA-Z0-9\-\.]+$/) { $str=undef; } return $str; },
   # hash with depth cleaning
   hash         => sub { my $h=shift; my $d=shift; if ((defined $h) && (ref($h) eq "HASH")) { 
                            sub r { 
                               my $a=shift; my $l=shift || 0; my $m=shift; 
                               if (ref($a) eq "HASH") { 
                                  $l++;
                                  foreach (keys %{$a}) {
                                     my $k=$_; 
                                     if ((defined $m) && (($l) > $m)) { delete ($a->{$k}); return; } 
                                     r($a->{$k},$l,$m); 
                                  } 
                               }
                            }
                            r($h,0,$d);
                            return $h;
                         }
                         return undef;
                       },
   # bigint db id's
   id           => sub { my $id=shift || 0; $id=substr($id,0,20); $id=~s/[^\d]//g; if ($id !~ /^\d+$/) { $id=0; } if (($id < 0) || ($id > 2**64-1)) { $id=0; } return $id; },
   # RFC 4291 etc.
   ip           => sub { my $str=shift || "0.0.0.0"; $str=substr($str,0,39); $str=~s/[^a-fA-F0-9\:\.\-]//g; if ($str !~ /^[a-fA-F0-9\:\.\-]+$/) { $str="0.0.0.0"; } return $str; },
   lifespan     => sub { my $lifespan=shift; if (!defined $lifespan) { $lifespan=0; } $lifespan=substr($lifespan,0,20); $lifespan=~s/[^\d]//g; if ($lifespan !~ /^\d+$/) { $lifespan=0; } if (($lifespan < 0) || ($lifespan > 2**64-1)) { $lifespan=0; } return $lifespan; },
   # unsigned int with specific bounds and default value
   niceint      => sub { my $i=shift; my $max=shift || 255; my $def=shift || 0; my $l=floor(log($max) / log(10))+1; if (!defined $i) { $i=$def; } $i=substr($i,0,$l); $i=~s/[^\d]//g; if ($i !~ /^\d+$/) { $i=$def; } if (($i < 0) || ($i > $max)) { $i=$def; } return $i; },
   # string without ctrl-characters
   nicestring   => sub { my $str=shift; if (!defined $str) { $str=""; } my $l=shift || 255; $str=substr($str,0,$l); $str=~s/[\000-\037\177]//g; return $str; },
   sid          => sub { my $sid=shift || -1; $sid=substr($sid,0,3); $sid=~s/^([\d]+)$/$1/; if ($sid !~ /^\d+$/) { $sid=-1; } if (($sid < 0) || ($sid > 255)) { $sid=-1; } return $sid; },
   # widest definition allowable - POSIX
   target       => sub { my $target=shift || ""; $target=substr($target,0,4096); $target=~s/[\000]//g; return $target },
   text         => sub { my $t=shift || ""; $t=substr($t,0,(2**16-1)); return $t; },
   username     => sub { my $str=shift || "dummy"; $str=substr($str,0,32); $str=~s/[^a-zA-Z0-9\_]//g; if ($str !~ /^[a-zA-Z]+.*$/) { $str="dummy"; } return $str; },
);

our %CLEAN=(
   'boolean'                => sub { my $b=shift; if (defined $b) { $b=($b ? 1 : 0); } else { $b=0; } return $b; },
   'datetimestr'            => sub { my $d=shift||"19700101000000"; $d=~s/[\r\n]//g; $d=substr($d,0,14); for (my $i=length($d); $i <= 14; $i++) { $d.="0"; }
                                     my $y=substr($d,0,4); my $m=substr($d,4,2); my $dy=substr($d,6,2); 
                                     my $h=substr($d,8,2); my $mi=substr($d,10,2); my $s=substr($d,12,2); 
                                     $y=($y < 1970 ? 1970 : $y);                   # year
                                     $m=($m < 1 ? "01" : ($m > 12 ? 12: $m));      # month
                                     $dy=($dy < 1 ? "01" : ($dy > 31 ? 31 : $dy)); # day
                                     $h=($h < 0 ? "00" : ($h > 23 ? 23 : $h));     # hour
                                     $mi=($mi < 0 ? "00" : ($mi > 59 ? 59 : $mi)); # min
                                     $s=($s < 0 ? "00" : ($s > 59 ? 59 : $s));     # sec
                                     return "$y$m$dy$h$mi$s";
                                   },
   'depth'                  => sub { my $d=shift; my $m=shift; my $df=shift; return $CLEAN_GLOBAL{niceint}->($d,$m,$df); },
   'entity'                 => sub { my $e=shift; return $CLEAN_GLOBAL{id}->($e); },
#   'entityname'		    => sub { my $n=shift; if (!defined $n) { return $n; } $n=$CLEAN_GLOBAL{nicestring}->($n,255); $n=~s/^[\t\s]+|[\t\s]+$//g; return $n; },
   'entitytype'             => sub { my $t=shift; return $CLEAN_GLOBAL{id}->($t); },
   'entitytypename'         => sub { my $n=shift || ""; $n=substr($n,0,255); $n=uc($n); $n=~s/[^A-Z]//g; return $n; },

   'metadatakey'            => sub { my $k=shift; if (!defined $k) { $k=""; } my $w=shift || 0; if ($w) { $w=qq("\\*"); } else { $w=qq(""); } $k=substr($k,0,1024); $k=~s/[^a-zA-Z0-9\.\-$w]//g; return $k; }, 
   'metadatakeyw'           => sub { my $k=shift; if (!defined $k) { $k=""; } my $w=1; if ($w) { $w=qq("\\*"); } else { $w=qq(""); } $k=substr($k,0,1024); $k=~s/[^a-zA-Z0-9\.\-$w]//g; return $k; },
   'metadataval'            => sub { my $v=shift; if (defined $v) { $v=substr($v,0,1024); } else { $v=""; } return $v; },
#   'metadatakeyval'         => sub { my $k=shift; my $v=shift; if (defined $v) { $v=substr($v,0,1024); } else { $v=""; } return $v; },
   'bitmask'                => sub { my $b=shift; $b='' unless defined $b; $b=substr($b,0,255); return $b; },
   'permtype'               => sub { my $t=shift || "ALL"; $t=substr($t,0,3); $t=uc($t); if (($t ne "ALL") && ($t ne "ANY")) { $t="ALL"; } return $t; }, 
   'permvalue'              => sub { my $v=shift; return $CLEAN_GLOBAL{niceint}->($v,2**64-1,0); },
   'permname'               => sub { my $n=shift || ""; $n=substr($n,0,255); $n=uc($n); $n=~s/[^A-Z\_]//g; return $n; }, 
#   'templateid'             => sub { my $i=shift; return $CLEAN_GLOBAL{niceint}->($i,2**64-1,0); },
#   'templatename'           => sub { my $n=shift || ""; return $CLEAN_GLOBAL{nicestring}->($n,255); },
   'tableopt'               => sub { my $o=shift || 0; if ($o =~ /^[0-1]{1}$/) { return $o; } else { return 0; } },
   'tmplcondefval'          => sub { my $v=shift; if (ref($v) eq "ARRAY") { my @a; foreach (@{$v}) { my $x=$_; if (defined $x) { $x=$CLEAN_GLOBAL{nicestring}->($x,1024); } push @a,$x; } return \@a; } else { if (defined $v) { return $CLEAN_GLOBAL{nicestring}->($v,1024); } else { return undef; } } },
   'tmplconregex'           => sub { my $r=shift; if (defined $r) { return $CLEAN_GLOBAL{nicestring}->($r,2**8-1); } else { return ".*"; } },
   'tmplconflags'           => sub { my $f=shift; if (!defined $f) { return undef; } $f=substr($f,0,(2**8-1)); return $f; },
   'tmplconmin'             => sub { my $m=shift; return $CLEAN_GLOBAL{niceint}->($m,2**64-1,0); },
   'tmplconmax'             => sub { my $m=shift; return $CLEAN_GLOBAL{niceint}->($m,2**64-1,1); },
   'tmplconcom'             => sub { my $c=shift; if (defined $c) { return $CLEAN_GLOBAL{nicestring}->($c,255); } else { return undef; } },

   'templateflag'           => sub { my $f=shift; return $CLEAN_GLOBAL{nicestring}->($f,(2**32-1)); },
   'templateflagname'       => sub { my $n=shift; return $CLEAN_GLOBAL{nicestring}->($n,2**5-1); },

   'loglevelname'           => sub { my $n=shift || ""; $n=substr($n,0,32); $n=~s/[^a-zA-Z]//g; return $n; },
   'loglevel'               => sub { my $l=shift; return $CLEAN_GLOBAL{niceint}->($l,2**8-1,0); },
   'logtag'                 => sub { my $t=shift || "NONE"; $t=substr($t,0,64); $t=~s/[^0-9A-Za-z\_\-\s\.]//g; $t=$t||"NONE"; return $t; },
   'logtime'                => $CLEAN_GLOBAL{datetime},
   'logmess'                => sub { my $m=shift; return $CLEAN_GLOBAL{nicestring}->($m,1024); },

   'offset'                 => sub { my $o=shift; $o=$CLEAN_GLOBAL{niceint}->($o,2**64-1,1); if ($o < 1) { $o=1; } return $o; },
   'offsetcount'            => sub { my $c=shift; my $mx=(2**64-1); my $m=shift || $mx; if (($m > $mx) || ($m < 1)) { $m=$mx; } $c=$Schema::CLEAN_GLOBAL{niceint}->($c,$m,$m); if ($c < 1) { $c=$m; } return $c; },
   'operation'              => sub { my $o=shift; if (defined $o) { $o=substr($o,0,1); } if ((!defined $o) || ($o == 0) || ($o == 1)) { return $o } else { return undef; } },
   'order'                  => sub { my $o=shift || "ASC"; if (($o ne "ASC") && ($o ne "DESC")) { $o="ASC"; } return $o; },
   'orderby'                => sub { my $o=shift || "system.dataset.time.created"; $o=~s/[^a-zA-Z\.]//g; return $o; },
   'sorttype'               => sub { my $t=shift || 0; $t=~s/[^\d]//g; $t=($t =~ /^[0-2]$/ ? $t : 0); return $t; },
   'recursive'              => sub { my $r=shift; return $CLEAN_GLOBAL{boolean}->($r); },

   'table'                  => sub { my $t=shift; $t =~ /^([a-zA-Z0-9_]+)$/; return $1; },
    
   );

our %CHECK=(
   # detect if there are utf8 wide characters present
   'utf8wide'               => sub { my $s=shift||""; if (($s =~ /[\xC2-\xDF]{1}[\x80-\xBF]{1}/s)||
                                                          ($s =~ /\xE0[\xA0-\xBF]{1}[\x80-\xBF]{1}/s)||
                                                          ($s =~ /[\xE1-\xEC]{1}[\x80-\xBF]{1}[\x80-\xBF]{1}/s)||
                                                          ($s =~ /\xED[\x80-\x9F]{1}[\x80-\xBF]{1}/s)) { return 1; } else { return 0; }},

   );

1;

__END__

=encoding UTF-8

=head1 NAME

C<Schema> Module to check and clean values entered into AuroraDB methods.

=cut

=head1 SYNOPSIS

   use Schema;

   # clean value
   my $entity="WhateverIsHere";
   $entity=$Schema::CLEAN{entity}->($entity);

=cut

=head1 DESCRIPTION

Module to check and clean values entered into AuroraDB-methods or for users that 
uses the AuroraDB-class.

Will also set default-values if input value is wrong in some way or missing.

This module is used everywhere in the AuroraDB-module when cleaning and checking of 
values are needed, so that the definition of it is in one place. The module is also 
used by the various parts of the AURORA-system when handling these kinds of values.

=cut

