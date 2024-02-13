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
# param2Hash - Module to handle conversion to/from param and Hash.
#
package paramHash;

use strict;
use Exporter 'import';
our @EXPORT = qw(param2Hash hash2Html);

sub param2Hash {
   my $c=shift; # cgi instance
   my $base=shift || ""; # base that all values start with
   my $qbase=qq($base);
   my $arr=shift;
   if (!defined $arr) { $arr=1; } # default enabled

   sub recurse_par {
      my $h=shift;
      my $key=shift;
      my $value=shift;
      my $arr=shift;
      if (!defined $arr) { $arr=1; } # default enabled

      if ($key =~ /^([^\_]+)\_(.+)$/) {
         # we have more subkeys
         my $subkey=$1;
         my $remainder=$2;
         if (($remainder !~ /^\d+$/) || (!$arr)) {
            if (!exists $h->{$subkey}) {
               my %v;       
               $h->{$subkey}=\%v;
            }
            recurse_par($h->{$subkey},$remainder,$value);
         } else {
            if (defined $h->{$subkey}) {
               # we have value(s) here from before
               my @values;
               if (ref($h->{$subkey}) eq "ARRAY") {
                  # we already have several values here
                  push @values,@{$h->{$subkey}};
               } else {
                  # only one value from before
                  push @values,$h->{$subkey};
               }
               # add new value
               push @values,$value;
               # update with all values
               $h->{$subkey}=\@values;
            } else {
               # no value(s) from before, just add the new one
               $h->{$subkey}=$value;
            }
         }
      } else {
         # end of the road....
         $h->{$key}=$value;
      }
   }

   # only get params that are in the base and sort them in correct order.
   my @pars;
   if (defined $c->param()) {
      @pars=sort { $a cmp $b } grep { /^$qbase\_(.*)$/ } $c->param();
   }

   # parse the params and create a hash from them.
   my %hash;

   foreach (@pars) {
      my $name=$_;
      my $value=$c->param($name);
      my $key=$name;
      $key=~s/^$qbase\_(.*)$/$1/;
      recurse_par(\%hash,$key,$value,$arr);
   }

   return \%hash;
}

sub hash2Html {
   my $hash=shift;
   my $base=shift || ""; # base that all values start with

   sub recurse_Hash {
      my $h=shift;
      my $base=shift;
      my $html=shift;

      my $ref=ref($h);

      if ($ref eq "HASH") {
         # go through hash
         foreach (keys %{$h}) {
            my $key=$_;
            my $ref=ref($h->{$key});

            if (($ref eq "HASH") || ($ref eq "ARRAY")) {
               recurse_Hash ($h->{$key},"${base}_$key",$html)
            } else { # we assume SCALAR
               my $value=$h->{$key};
               $value=(!defined $value ? "" : $value);
               $$html .= "<INPUT TYPE=\"HIDDEN\" NAME=\"${base}_$key\" VALUE=\"$value\">\n";
            }
         }
      } elsif ($ref eq "ARRAY") {
         # go through ARRAY
         my $no=0;
         foreach (@{$h}) {
            my $item=$_;
            my $ref=ref($item);
            $no++;

            if (($ref eq "HASH") || ($ref eq "ARRAY")) {
               recurse_Hash ($item,"${base}_$no",$html)
            } else { # we assume SCALAR
               $item=(!defined $item ? "" : $item);
               $$html .= "<INPUT TYPE=\"HIDDEN\" NAME=\"${base}_$no\" VALUE=\"$item\">\n";
            }
         }
      } else {}
   }

   # start recursing the Hash-ref
   my $html="";
   recurse_Hash($hash,$base,\$html);

   # return finished html
   return $html;
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<paramHash> Module with functions to convert to/from CGI-params and a HASH.

=cut

=head1 SYNOPSIS

   use paramHash;
   use CGI;

   my $c=CGI->new();

   my $h=param2Hash($c,"PARAMSSTARTWITHTHIS");

   my $html=hash2Html($h,"STARTPARAMSWITHTHIS");

=cut

=head1 DESCRIPTION

Module that offers conversion functions to/from CGI-param and a HASH.

All functions are exported by default, so no need to instantiate, import or 
refer to module (besides a Use-statement);

CGI parameter names should be just characters (a-zA-Z) and/or numbers (0-9) and no 
special characters. Please also be aware that underscore ("_") is not allowed in the 
CGI parameter name, since that is reserved as hierarchical separator for keys in 
the hash when transformed into HTML hidden-statements.

=cut

=head1 METHODS

=head2 param2Hash()

Converts CGI-params to a HASH.

The method takes these parameters in the following order: CGI-reference, base, array. The CGI-reference is the 
reference to the CGI-instance that are used in order to be able to fetch params coming in from the 
web-browser. The "base" defines the start-string from how the data in the web application are encoded. The 
"array" parameter sets if the last characters after an underscore "_" in a parameter name is only digits if 
that is to be intepreted as a element number in an array or not? The default is true which interprets this as 
element numbers in an array and puts the value-part of the param into an array. If the "array" parameter is set 
to false, the last characters after an underscore in the parameter name is interpreted as a subkey.

Upon success returns a HASH with the key and values of the params starting with the specified base.

=cut

=head2 hash2Html()

Convert a HASH into HTML hidden input statements.

The function takes the following parameters in this order: HASH-reference, base. 

The HASH-reference is the HASH to convert to HTML hidden input statements. The base-
parameter specified what the hidden input statements are to start with.

Upon success returns the HTML-encoded version of the HASH-reference. This text can be 
included in forms in order to contain/remember all values involved.

=cut
