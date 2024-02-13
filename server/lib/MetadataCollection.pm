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
use strict;
package MetadataCollection;
use Schema;

sub new {
   my $class=shift;
   my $self={};
   bless($self,$class);

   my %pars=@_;

   if (!defined $pars{base}) { $pars{base}=".metadata.collection"; }
   else { 
      # set the new base
      my $base=$pars{base};
      $pars{base}=$self->base($base); # set new value
   } 
   if ((!defined $pars{depth}) || ($pars{depth} !~ /^\d+$/)) { $pars{depth}=0; } # no depth limitation if none specified
   

   # save pars
   $self->{pars}=\%pars;

   return $self;
}

sub hash2Metadata {
   my $self=shift;
   my $hash=shift;
   my $depth=shift;

   my $method=(caller(0))[3];

   sub recursehash {
      my $ref=shift;
      my $md=shift;
      my $name=shift;
      my $depth=shift;
      my $level=shift;

      # increase level
      $level++;

      # only go to certain depth, if depth has been set.
      if (($depth > 0) && ($level > $depth)) { return; }

      if ((ref($ref) eq "HASH") && (keys %{$ref} > 0)) {
         # recurse on each key and downwards
         foreach (%{$ref}) {
            my $key=$_;
            my $nkey=$Schema::CLEAN{metadatakey}->($key);
            my $nname=$name;
            $nname=($name eq "" ? $nkey : "$name.$nkey");
            recursehash ($ref->{$key},$md,$nname,$depth,$level);
         }
      } elsif (ref($ref) eq "ARRAY") {
         my @nlist;
         foreach (@{$ref}) {
            my $item=$_;
            $item=$Schema::CLEAN{metadataval}->($item);
            push @nlist,$item;
         }
         $md->{$name}=\@nlist;
      } elsif (defined $ref) {
         # end of the line - store the value
         $md->{$name}=$Schema::CLEAN{metadataval}->($ref);
      }
   }

   # check that it is a hash ref
   if ((!defined $hash) || (ref($hash) ne "HASH")) {
      $self->{error}="$method: input reference is not defined or not a hash.";
      return undef;
   }

   # get depth setting if none set here
   if (!defined $depth) {
      # get class-depth setting;
      $depth=$self->depth();
   }

   # get base for namespace
   my $base=$self->base();

   # go through hash and create metadata hash that can be saved on entity
   my %md;
   recursehash ($hash,\%md,$base,$depth,0);

   # return the converted metadata hash
   return \%md;
}

sub metadata2Hash {
   my $self = shift;
   my $md = shift;

   my $method=(caller(0))[3];

   sub recursemd {
      my $ref=shift;
      my $parts=shift;
      my $value=shift;

      if (@{$parts} > 0) {
         # more parts to recurse down into
         my $part=shift @{$parts};
         if (@{$parts} == 0) {
            if (ref($value) eq "ARRAY") {
               # add array
               $ref->{$part}=$value;
            } else {
               # just a scalar
               $ref->{$part}=$value;
            }
         } else {
            my %h;
            if (!exists $ref->{$part}) { $ref->{$part}=\%h; }
            recursemd($ref->{$part},$parts,$value);
         }
      } 
   }

   # check that it is a hash ref
   if ((!defined $md) || (ref($md) ne "HASH")) {
      $self->{error}="$method: input reference is not defined or not a hash.";
      return undef;
   }

   # get the namespace base
   my $base=$self->base();
   my $qbase=qq($base);

   # create hash 
   my %hash;

   foreach (keys %{$md}) {
      my $key=$_;
      my $nkey=$key;

      # check that key has base
      if ($key !~ /^$qbase.*$/) { next; } # does not begin with correct base, skip it

      # get everything after the base
      $nkey=~s/^$qbase\.(.*)$/$1/;

      # clean the new key
      $nkey=$Schema::CLEAN{metadatakey}->($nkey);

      # break down key in constituent parts
      # after base
      my @parts=split(/\./,$nkey);

      # start with first part here
      recursemd (\%hash,\@parts,$md->{$key});
   }

   # return the resulting hash of metadata
   return \%hash;
}

sub template2Hash {
   my $self=shift;
   my $templ=shift;

   my $method=(caller(0))[3];

   if ((!defined $templ) || (ref($templ) ne "HASH")) {
      $self->{error}="$method: input reference is not defined or not a hash.";
      return undef;
   }

   # get base
   my $base=$self->base();
   my $qbase=qq($base);

   # create return hash
   my %hash;

   foreach (keys %{$templ}) {
      my $key=$_;
      my $nkey=$key;

      # check that key has base
      if ($key !~ /^$qbase.*$/) { next; } # does not begin with correct base, skip it

      # get everything after the base
      $nkey=~s/^$qbase\.(.*)$/$1/;

      # clean the new key
      $nkey=$Schema::CLEAN{metadatakey}->($nkey);

      # break down key in constituent parts
      # after base
      my @parts=split(/\./,$nkey);

      # start with first part here
      recursemd (\%hash,\@parts,$templ->{$key}{default});
   }

   # return the result hash
   return \%hash;
}

sub mergeHash {
   my $self=shift;

   my $method=(caller(0))[3];

   # get the list of HASH references, if any
   my @hs=grep { ref($_) eq "HASH" } @_;

   # go through hash LIST and merge, last hash in list has precedence 
   my %hash=();
   foreach (@hs) {
      my $h=$_;

      # merge existing values with new hash
      %hash=(%hash,%{$h});
   }

   # return merged hash
   return \%hash;
}

sub base {
   my $self=shift;

   if (@_) {
      # this is a set
      my $base=shift || "";
      $base=$Schema::CLEAN{metadatakey}->($base); # general clean
      $base=~s/\.*$//; # remove any trailing dot(s)
      $self->{pars}{base}=$base; # set new value
      return $self->{pars}{base};
   } else {
      # this is a get
      return $self->{pars}{base};
   }
}

sub depth {
   my $self=shift;

   if (@_) {
      # this is a set
      my $depth=shift;
      if ($depth =~ /^\d+$/) { $self->{pars}{depth}=$depth; }
   } else {
      return $self->{pars}{depth};
   }
}

sub error {
   my $self=shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<MetadataCollection> - A class to convert a collection of metadata that belongs together from/to hashes, metadata and templates.

=cut

=head1 SYNOPSIS

   use MetadataCollection;

   # instantiate
   my $mc=MetadataCollection->new();

   # get metadata hash from hash
   my $md=$mc->hash2Metadata($hash);

   # get hash from metadata
   my $hash=$mc->metadata2Hash($metadata);

   # get hash from template
   my $hash=$mc->template2Hash($template);

   # merge/inherit values from several hashes
   my $result=$mc->mergeHash($hash1,$hash2,$hash3...$hashn);

=cut

=head1 DESCRIPTION

A class to convert a collection of AURORA database metadata that belongs together from/to hashes, metadata and templates.

Please see the AURORA-system documentation for information on metadata format.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the StoreCollection-class.

It takes the following parameters

=over

=item

B<base> Sets the namespace base for converting back- and forth from the AURORA metadata namespace. If none is given it 
defaults to "system.collection". When converting from metadata/template to hash the base is first removed, so that 
the resulting hash does not include the base, but only the collection of key->values under the base. When converting 
from a hash to metadata, the base is added to the hash keys.

=cut

=item

B<depth> Sets the maximum allowed depth on hashes that are converted into metadata or template. SCALAR. Optional. If not 
set it will default to 0, which means no depth restriction. If set, the hash2Metadata()-method will only go to the depth 
specified in the HASH. This is a global setting, which can be overridden by specifying depth to the hash2Metadata()-method 
itself (see the hash2Metadata()-method for more information).

=cut

=back

Returns the instantiated class.

=cut

=head1 METHODS

=head2 hash2Metadata()

This method turns the hash-format version of AURORA database metadata (see DESCRIPTION).

Input is a hash reference to the structure to convert into a metadata structure. Optional second input is the "depth"-parameter 
that specifies the maximum depth that the method will allow in the HASH (everything below is ignored in the conversion).

When converting the HASH into metadata, the base specified to the class is added to the keys.

It returns a metadata hash reference upon success, undef upon failure. Please check the error()-method for more 
information on a potential error.

=cut

=head2 metadata2Hash()

This method converts an AURORA metadata hash into a HASH structure (see DESCRIPTION).

It takes a AURORA metadata hash reference as input.

When converting the metadata into a HASH, the base specified to the class is removed from the keys first.

The method returns the hash-format reference upon success, undef upon failure. Please check the error()-method upon any 
failure.

=cut

=head2 template2Hash()

This method converts a template metadata as returned from AuroraDB into a hash-format structure.

It takes the template hash-reference from AuroraDB as input.

The method works similarily to the metadata2Hash()-method. See that method for more information. Instead of that method it takes 
the "default"-setting of the template and sets it as values for the keys.

It returns the finished converted hash or undef upon failure. Please check the error()-method upon failure.

=cut

=head2 mergeHash()

This method merges two or more hash-format references into one hash.

It takes any number of hash-reference as input in the form of a hash reference LIST.

It returns a resulting hash-reference to a hash-format structure upon success, undef upon failure. Please check the 
error()-method for more information upon failure.

=cut

=head2 base()

This method returns or sets the AURORA database metadata base namespace for the metadata-collection used by this module for 
conversion. See the "base" option in the new()-method for more information.

Upon set takes the base namespace as parameter (SCALAR). Upon get it takes no parameters.

Returns the base namespace as a SCALAR.

=cut

=head2 depth()

Get or set the depth setting of the instance.

If input is specified it is assumed to be as set and if the value specified is a 
number it is saved as the new depth-setting for the instance.

If no input is specified it is assumed to be a get-operation and the current depth-
setting of the instance is returned.

=cut

=head2 error()

Returns the last error, if any.

No input taken.

Returns a SCALAR with the error message if any (blank if none).

=cut

