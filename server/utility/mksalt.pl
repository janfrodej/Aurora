#!/usr/bin/perl -w
#
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
use strict;
use Bytes::Random::Secure;

sub generate_salt {
   my $size = shift || 16;

   # string to contain the random chars
   my $str="";

   # generate random string
   my $r=Bytes::Random::Secure->new(Bits=>64, NonBlocking=>1);
   $str = $r->string_from("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\.\/",$size);
 
   # taint check the values
   $str=~/([a-zA-Z0-9\.\/]+)/;
   $str=$1;

   return $str;
}

# generate a salt
my $salt=generate_salt(16);

print "SALT: \$6\$".$salt."\$\n";
