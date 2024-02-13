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
# UnicodeTools: Module to handle unicode tasks
#
package UnicodeTools;

use strict;
use charnames ':full';
use Exporter 'import';
our @EXPORT = qw(map2az map2azmath);

sub map2az {
   my $str=shift||"";

   my $nstr="";
   foreach (split("",$str)) {
      my $c=$_;
      my $name=charnames::viacode(ord($c));
      if ($name =~ /^(LATIN (SMALL|CAPITAL) LETTER [A-Z]{1}).*$/) {
         $name=$1;
      }
      $nstr.=charnames::string_vianame($name);
   }
   # return converted string
   return $nstr;
}

sub map2azmath {
   my $str=shift||"";

   my $nstr="";
   foreach (split("",$str)) {
      my $c=$_;
      $c = substr($_,0,1); $c = chr(97 + ord($c) % 26) unless $c =~ /^[a-zA-Z]$/;
      $nstr.=$c;
   }

   # return converted string
   return $nstr;
}


1;

__END__

=encoding UTF-8

=head1 NAME

C<UnicodeTools> - Module for handling unicode tasks

=cut

=head1 SYNOPSIS

   use UnicodeTools;

   # convert string to A-Za-z letters where relevant
   my $str=map2az($str);
   # convert string to A-Za-z letter mathematically where relevant
   $str=map2azmath($str);

=cut

=head1 DESCRIPTION

A collection of functions to handle various unicode tasks.

=cut

=head1 CONSTRUCTOR

This class does not have an instantiator/constructor. Methods are exporeted by default.

=cut

=head1 METHODS

=head2 map2az()

Converts string characters to their ASCII a-zA-Z equivalents by looking at the 
base unicode name.

Accepts these parameters in the following order:

=over

=item

B<str> The string to be mapped to a-zA-Z. SCALAR. Required.

=cut

=back

The method ignores characters that do not start with "LATIN [CAPITAL|SMALL LETTER] [A-Z]" and preserve them 
as they are in the string. The rest is converted to its a-zA-Z equivalent.

Returns the mapped/converted string.

=cut

=heda2 map2azmath()

Converts string characters to their ASCII a-zA-Z equivalents by applying a straight-forward 
mathematical algorithm.

Accepts these parameters in the following order:

=over

=item

B<str> The string to be mapped to a-zA-Z. SCALAR. Required.

=cut

=back

The method mathematically forces characters to be converted to the a-ZA-Z space in the ASCII-table. Characters that 
are already a-zA-Z are ignored. It is "unintelligent" in comparison to the map2az-method.

One option is to run map2az first and then run the map2azmath afterwards to pick up those characters that where not 
handled intelligently by the map2az-method, thus forcing all characters into the a-zA-Z space of the ASCII-table.

Returns the mapped/converted string.

=cut

