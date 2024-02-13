#!/usr/bin/perl -Tw
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
# sectools - package with security tools
package sectools;

use strict;
use Digest::MD5;
use Digest::SHA;
use Bytes::Random::Secure;

# Location of the xxhash binary
# xxhash package must be installed on system
my $XXHSUM = "/usr/bin/xxhsum";

# create a random string of n chars
sub randstr {
   # size of random string
   my $size = shift || 32;

   # string to contain the random chars
   my $str="";

   # generate random string
   my $r=Bytes::Random::Secure->new(Bits=>64, NonBlocking=>1);
   $str = $r->string_from("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",$size);
 
   # taint check the values
   $str=~/([a-zA-Z0-9]+)/;
   $str=$1;

   return $str;
}

sub sha256sum {
   my $data = shift || "dummy";

   my $sha256 = Digest::SHA->new(256);

   # add data/string to sum
   $sha256->add($data);

   # return hex value digest
   return $sha256->hexdigest();
}

sub sha256sum_file {
   my $name = shift || "./dummy";

   # make MD5 object
   my $sha = Digest::SHA->new(256);
   
   # attempt to open file
   my $FH;
   if (open ($FH,"$name")) {
      # file has been opened - pass handle to md5->addfile()
      my $nsha;
      # this might croak, so eval the processing of the file.
      my $err;
      eval { binmode ($FH); $nsha = $sha->addfile($FH); };
      $@ =~ /nefarious/;
      $err = $@;
      # close file 
      eval { close ($FH); };
      if ($err eq "") {
         # md5sum'ing file was a success
         if (defined $nsha) { return $nsha->hexdigest(); }
         else { return "Error! Unable to retrieve checksum of file \"$name\""; }
      } else {
         return "Error! Unable to checksum file \"$name\": $err";
      }
   } else {
      # not able to find file to calculate sum
      return "Error! Unable to open file \"$name\" to checksum it: $!";
   }
}

# create md5 equiv. of string
sub md5sum {
   # we can't allow blank md5 strings, now can we?
   my $str = shift || "Hello World!";

   # make MD5 object
   my $md5 = Digest::MD5->new();
   $md5->add($str);
   
   # return md5 hex-equivalent
   return $md5->hexdigest();
}

sub md5sum_file {
   my $name = shift || "./dummy";

   # make MD5 object
   my $md5 = Digest::MD5->new();
   
   # attempt to open file
   my $FH;
   if (open ($FH,"$name")) {
      # file has been opened - pass handle to md5->addfile()
      my $nmd5;
      # this might croak, so eval the processing of the file.
      my $err;
      eval { binmode ($FH); $nmd5 = $md5->addfile($FH); };
      $@ =~ /nefarious/;
      $err = $@;
      # close file 
      eval { close ($FH); };
      if ($err eq "") {
         # md5sum'ing file was a success
         if (defined $nmd5) { return $nmd5->hexdigest(); }
         else { return "Error! Unable to retrieve checksum of file \"$name\""; }
      } else {
         return "Error! Unable to checksum file \"$name\": $err";
      }
   } else {
      # not able to find file to calculate sum
      return "Error! Unable to open file \"$name\" to checksum it: $!";
   }
}

sub xxhsum_file {
   my $name=shift||"";
   my $type=shift||"128";

   $type=($type == 32 || $type == 64 || $type == 128 ? $type : 128);

   # check that file exists
   if (-f "$name") {
      # pass along filename to xxhash and attempt check
      my $res=qx($XXHSUM -H$type $name);
      if ($? == 0) {
         # successfully checked checksum - return result
         $res=~/([a-z0-9]+)\s+.*/;
         my $sum=$1||"Error! Unable to find checksum for file \"$name\"";
         # return checksum
         return $sum;
      } else {
         # execution failed for some reason
         return "Error! Unable to checksum file \"$name\": $res";
      }
   } else {
      # not able to find file to calculate sum
      return "Error! File \"$name\" does not exist. Unable to checksum it: $!";
   }
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<sectools> Module with security related functions.

=cut

=head1 SYNOPSIS

   use sectools;

   # create truly random string of N characters
   my $random=sectools::randstr(64);

   # create a sha256 sum of SCALAR
   my $sum=sectools::sha256sum("SomethingIWantTheSumOf");

   # create a md5sum of SCALAR
   my $sum=sectools::md5sum("SomethingIWantTheSumOf");

   # create a 128-bit xxhash sum of SCALAR
   my $sum=sectools::xxhsum_file("MY_FILE_NAME");

=cut

=head1 DESCRIPTION

Collection of functions related to security, such as truly random strings and sha256- and md5- sums.

=cut

=head1 CONSTRUCTOR

No constructor in this module - separate functions.

=cut

=head1 METHODS

=head2 randstr()

Create a random string of N characters.

Accepts the following input: size. SCALAR. Optional. Defaults to 32. It sets how 
many random characters to generate.

The random string will only consists of charaters in a-z, A-Z and 0-9.

Returns the random SCALAR.

=cut

=head2 sha256sum()

Creates the sha256-sum of the specified SCALAR.

Accepts one input: data. SCALAR. Required. Defines the data to create a sha256 sum of.

Returns the SHA256-sum as a hex-digest.

=cut

=head2 sha256sum_file()

Creates the sha256-sum of the specified filename (SCALAR).

Accepts one input: filename with path. SCALAR. Required. Defines the file to open and calculate the sha256sum of.

Returns the sha256sum as a hex-digest or a string starting with "Error!" upon failure.

=cut

=head2 md5sum()

Creates the md5-sum of the specified SCALAR.

Accepts one input: data. SCALAR. Required. Defines the data to create a md5sum sum of.

Returns the md5-sum as a hex-digest.

=cut

=head2 md5sum_file()

Creates the md5-sum of the specified filename (SCALAR).

Accepts one input: filename with path. SCALAR. Required. Defines the file to open and calculate the md5sum of.

Returns the md5sum as a hex-digest or a string starting with "Error!" upon failure.

=cut

=head2 xxhsum_file()

Creates the xxhash-sum of the specified filename (SCALAR).

Accepts two inputs: filename (required) and type (optional). Filename must be specified 
with path. SCALAR. Required. Defines the file to get the xxhash of. Type defines the 
xxhash-version to use generating the xxhash. Valid versions are 32, 64 and 128. 128 is the 
default if not specified.

Returns the xxhash sum upon success or a string starting with "Error!" upon failure.

=cut
