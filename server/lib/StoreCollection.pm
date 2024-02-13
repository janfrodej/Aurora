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
package StoreCollection;
use Schema;

sub new {
   my $class=shift;
   my $self={};
   bless($self,$class);

   my %pars=@_;

   if (!defined $pars{base}) { $pars{base}="system.storecollection"; }
   else { 
      # set the new base
      my $base=$pars{base};
      $pars{base}=$self->base($base); # set new value
   } 

   # save pars
   $self->{pars}=\%pars;

   return $self;
}

sub hash2Metadata {
   my $self=shift;
   my $hash=shift;

   my $method=(caller(0))[3];

   # check that it is a hash ref
   if ((!defined $hash) || (ref($hash) ne "HASH")) {
      $self->{error}="$method: input reference is not defined or not a hash.";
      return undef;
   }

   # get base for namespace
   my $base=$self->base();

   # go through hash and create metadata hash that can be saved on entity
   my %md;
   if (exists $hash->{name}) {
      my $scname=$Schema::CLEAN{metadataval}->($hash->{name});
      $md{"$base.name"}=$scname;
   }

   # go through get- and put structures of the hash
   foreach (("get","put","del")) {
      my $method=$_;

      if (ref($hash->{$method}) ne "HASH") { next; } # not a hash, skip it

      foreach (keys %{$hash->{$method}}) {
         my $no=$_;

         if (($no !~ /\d+/) || ($no < 0)) { next; } # skip invalid keys

         if (ref($hash->{$method}{$no}) ne "HASH") { next; } # not a hash, skip it

         # go through each key here, skip param
         foreach (keys %{$hash->{$method}{$no}}) {
            my $key=$_;
            my $nkey=lc($key); # all keys are to be lowercase

            # only allow certain characters in key
            if ($nkey !~ /^[a-z0-9]+$/) { next; } # skip it, since it has illegal name

            if (($nkey ne "param") && ($nkey ne "classparam")) {
               # add key
               $md{"$base.$method.$no.$nkey"}=$Schema::CLEAN{metadataval}->($hash->{$method}{$no}{$key});
            }
         }
            
         if ((exists $hash->{$method}{$no}{classparam}) && (ref($hash->{$method}{$no}{classparam}) eq "HASH")) {
            # go through each parameter and add to array
            foreach (keys %{$hash->{$method}{$no}{classparam}}) {
               my $par=$_;
               my $npar=$SysSchema::CLEAN{scparamname}->($par);
               if ($npar eq "") { next; } # cannot have parameter name that is blank
               # add parameter
               $md{"$base.$method.$no.classparam.$npar"}=$Schema::CLEAN{metadataval}->($hash->{$method}{$no}{classparam}{$par});
            }
         }
         if ((exists $hash->{$method}{$no}{param}) && (ref($hash->{$method}{$no}{param}) eq "HASH")) {
            # go through each parameter and add to array
            foreach (keys %{$hash->{$method}{$no}{param}}) {
               my $par=$_;
               my $npar=$SysSchema::CLEAN{scparamname}->($par);
               if ($npar eq "") { next; } # cannot have parameter name that is blank
               # add parameter
               $md{"$base.$method.$no.param.$npar"}=$Schema::CLEAN{metadataval}->($hash->{$method}{$no}{param}{$par});
            }
         }
      }
   }

   # return the converted metadata hash
   return \%md;
}

sub metadata2Hash {
   my $self = shift;
   my $md = shift;

   my $method=(caller(0))[3];

   # check that it is a hash ref
   if ((!defined $md) || (ref($md) ne "HASH")) {
      $self->{error}="$method: input reference is not defined or not a hash.";
      return undef;
   }

   # get the namespace base
   my $base=$self->base();
   my $qbase=qq($base);

   # get store collection name
   my $scname=$Schema::CLEAN{metadataval}->($md->{"$base.name"} || "UNKNOWN");

   # create hash 
   my %hash;

   # add overall name if it exists
   if (exists $md->{"$base.name"}) { $hash{name}=$Schema::CLEAN{metadataval}->($md->{"$base.name"}); }

   # treat metadata hash as a hash and just go through the structure
   # without too much preconcievments, just skipping irrelevant parts
   # and allowing skips in numbering (to properly allow for inheritance)
   foreach (keys %{$md}) {
      my $key=$_;

      # only follow key if it is get or put something and a number
      if ($key =~ /^$qbase\.(get|put|del)\.(\d+)\..*$/) {
         # we have a get or put, get method and number
         my $method=$1;
         my $no=$2;

         if ($no < 0) { next; } # only allow number above and including 0 

         # check that this is *not* a subkey of some kind
         if ($key =~ /^$qbase\.(get|put|del)\.(\d+)\.([a-z0-9]+)$/) {
            # ensure that it is not called param, even if not subkey
            my $name=lc($3);
            if (($name ne "param") && ($name ne "classparam")) {
               # add it to hash
               $hash{$method}{$no}{$name}=$Schema::CLEAN{metadataval}->($md->{$key});
            }
         } elsif ($key =~ /^$qbase\.(get|put|del)\.(\d+)\.classparam\.(.*)$/) {
            my $pname=$3;

            # clean the parameter name
            my $cname=$SysSchema::CLEAN{scparamname}->($pname);
            if ($cname eq "") { next; } # skip parameter names that are blank
            $hash{$method}{$no}{classparam}{$cname}=$Schema::CLEAN{metadataval}->($md->{$key});
         } elsif ($key =~ /^$qbase\.(get|put|del)\.(\d+)\.param\.(.*)$/) {
            my $pname=$3;

            # clean the parameter name
            my $cname=$SysSchema::CLEAN{scparamname}->($pname);
            if ($cname eq "") { next; } # skip parameter names that are blank
            $hash{$method}{$no}{param}{$cname}=$Schema::CLEAN{metadataval}->($md->{$key});
         }

         # ensure we have a param, even if empty
         if (!exists $hash{$method}{$no}{classparam}) {
            my %param;
            $hash{$method}{$no}{classparam}=\%param;
         }
         # ensure we have a param, even if empty
         if (!exists $hash{$method}{$no}{param}) {
            my %param;
            $hash{$method}{$no}{param}=\%param;
         }
      }
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

   # check if we have a overall name
   if (exists $templ->{"$base.name"}) {
      # set overall name in return hash
      $hash{name}=$templ->{"$base.name"}{default};
   }

   # we have a template hash - go through each key and create a hash.
   foreach (keys %{$templ}) {
      my $key=$_;

      if ($key =~ /^$qbase\.(get|put|del)\.(\d+)\..*$/) {
         # we have a get or put, get method and number
         my $method=$1;
         my $no=$2;

         if ($no < 0) { next; } # only allow number above and including 0 

         # check that this is *not* a subkey of some kind
         if ($key =~ /^$qbase\.(get|put|del)\.(\d+)\.([a-z0-9]+)$/) {
            # ensure that it is not called param, even if not subkey
            my $name=lc($3);
            if (($name ne "param") && ($name ne "classparam")) {
               # add it to hash
               $hash{$method}{$no}{$name}=$Schema::CLEAN{metadataval}->($templ->{$key}{default});
            }
         } elsif ($key =~ /^$qbase\.(get|put|del)\.(\d+)\.classparam\.(.*)$/) {
            my $pname=$3;

            # clean the parameter name
            my $cname=$SysSchema::CLEAN{scparamname}->($pname);
            if ($cname eq "") { next; } # skip parameter names that are blank
            $hash{$method}{$no}{classparam}{$cname}=$Schema::CLEAN{metadataval}->($templ->{$key}{default});
         } elsif ($key =~ /^$qbase\.(get|put|del)\.(\d+)\.param\.(.*)$/) {
            my $pname=$3;

            # clean the parameter name
            my $cname=$SysSchema::CLEAN{scparamname}->($pname);
            if ($cname eq "") { next; } # skip parameter names that are blank
            $hash{$method}{$no}{param}{$cname}=$Schema::CLEAN{metadataval}->($templ->{$key}{default});
         }

         # ensure we have a param, even if empty
         if (!exists $hash{$method}{$no}{classparam}) {
            my %param;
            $hash{$method}{$no}{classparam}=\%param;
         }
         # ensure we have a param, even if empty
         if (!exists $hash{$method}{$no}{param}) {
            my %param;
            $hash{$method}{$no}{param}=\%param;
         }
      }
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
   my %hash;
   foreach (@hs) {
      my $h=$_;

      if (exists $h->{name}) { $hash{name}=$Schema::CLEAN{metadataval}->($h->{name}); }

      foreach (("get","put")) {
         my $method=$_;

         if (exists $h->{$method}) {
            # go through keys and skip ones that are not a number
            foreach (keys %{$h->{$method}}) {
               my $no=$_;

               if (($no !~ /^\d+$/) || ($no < 0)) { next; } # skip this one if it is not a number, or below 0 

               # go through each key - skip param
               foreach (keys %{$h->{$method}{$no}}) {
                  my $key=$_;
                  my $nkey=lc($key);

                  # only allow certain characters in key
                  if ($nkey !~ /^[a-z0-9]+$/) { next; } # skip it, since it has illegal name
       
                  if (($nkey ne "param") && ($nkey ne "classparam")) {
                     # add/overwrite
                     $hash{$method}{$no}{$nkey}=$Schema::CLEAN{metadataval}->($h->{$method}{$no}{$key});
                  }
               }

               # check if params exists and add or replace those params that does
               if ((exists $h->{$method}{$no}{classparam}) && (ref($h->{$method}{$no}{classparam}) eq "HASH")) {
                  foreach (keys %{$h->{$method}{$no}{classparam}}) {
                     my $pname=$_;

                     # clean var name 
                     my $cname=$SysSchema::CLEAN{scparamname}->($pname);

                     if ($cname eq "") { next; } # must be non-blank param name

                     # replace or add
                     $hash{$method}{$no}{classparam}{$cname}=$SysSchema::CLEAN{scparamval}->($h->{$method}{$no}{classparam}{$pname});
                  }
               }
               # check if params exists and add or replace those params that does
               if ((exists $h->{$method}{$no}{param}) && (ref($h->{$method}{$no}{param}) eq "HASH")) {
                  foreach (keys %{$h->{$method}{$no}{param}}) {
                     my $pname=$_;

                     # clean var name 
                     my $cname=$SysSchema::CLEAN{scparamname}->($pname);

                     if ($cname eq "") { next; } # must be non-blank param name

                     # replace or add
                     $hash{$method}{$no}{param}{$cname}=$SysSchema::CLEAN{scparamval}->($h->{$method}{$no}{param}{$pname});
                  }
               }
            }
         }
      }
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

sub error {
   my $self=shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<StoreCollection> - A collection of stores and their name and parameters, including methods to convert to a from 
metadata representation.

=cut

=head1 SYNOPSIS

   use StoreCollection;

   # instantiate
   my $sc=StoreCollection->new();

   # get metadata hash from hash
   my $md=$sc->hash2Metadata($hash);

   # get hash from metadata
   my $md=$sc->metadata2Hash($metadata);

   # merge/inherit values from several hashes
   my $result=$sc->mergeHash($hash1,$hash2,$hash3...$hashn);

=cut

=head1 DESCRIPTION

Class to manage a Store-collection in hash- and metadata version and conversions between the two, including 
merging/inheritance functionality. It also cleans and ensures compliance with the AURORA StoreCollection structural 
format.

A Store-collection when stored in the AURORA database are represented thus:

   system.storecollection.name = SCALAR
   system.storecollection.get.1.name = SCALAR
   system.storecollection.get.1.store = ID (store-entity id)
   system.storecollection.get.1.whatever = SCALAR
   system.storecollection.get.1.classparam.p1 = SCALAR
   system.storecollection.get.1.param.p1 = SCALAR
   system.storecollection.get.1.param.p2 = SCALAR
   system.storecollection.get.1.param.p3 = SCALAR
   system.storecollection.get.1.param.p4 = SCALAR
   system.storecollection.get.1.param.pN = SCALAR
   system.storecollection.get.2.name = SCALAR
   system.storecollection.get.2.store = ID
   system.storecollection.get.2.param.p1 = SCALAR
   system.storecollection.get.2.param.pN = SCALAR
   .
   .
   system.storecollection.put.1.name = SCALAR
   system.storecollection.put.1.store = ID
   system.storecollection.put.1.whatever = SCALAR
   system.storecollection.put.1.classparam.p1 = SCALAR
   system.storecollection.put.1.param.p1 = SCALAR
   system.storecollection.put.1.param.p2 = SCALAR
   system.storecollection.put.1.param.pN = SCALAR
   .
   .
   system.storecollection.put.N.name = SCALAR 
   .
   .
   system.storecollection.del.1.name = SCALAR
   system.storecollection.del.1.store = ID
   system.storecollection.del.1.classparam.p1 = SCALAR
   system.storecollection.del.1.param.p1 = SCALAR
   system.storecollection.del.1.param.pN = SCALAR
   .
   .
   system.storecollection.del.2.name = SCALAR   
   .
   .
   etc..

This AURORA metadata namespace representation is converted to a normal HASH thus:

   (
     name => SCALAR,
     get => { 1 => { name => SCALAR,
                     store => ID,
                     whatever => SCALAR,
                     classparam => { p1 => SCALAR,
                                   },
                     param => { p1 => SCALAR,
                                p2 => SCALAR,
                                p3 => SCALAR,
                                p5 => SCALAR,
                                pN => SCALAR,
                              }
                   }
              2 => { name => SCALAR,
                     store => ID,
                     param => { p1 => SCALAR, pN => SCALAR }
                   }
     put => { 1 => { name => SCALAR,
                     store => ID,
                     whatever => SCALAR,
                     classparam => { p1 => SCALAR,
                                   },
                     param => { p1 => SCALAR,
                                p2 => SCALAR,
                                pN => SCALAR,
                              }
                   }
              N => { name => SCALAR,
                   }
            }
     del => { 1 => { name => SCALAR,
                     store => ID,
                     classparam => { p1 => SCALAR,
                                   },
                     param => { p1 => SCALAR,
                                .
                                pN => SCALAR,
                              }
                   }
              2 => { name => SCALAR,
                   }
            }
   )

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the StoreCollection-class.

It takes the following parameters

=over

=item

B<base> Sets the namespace base for converting back- and forth from the AURORA metadata namespace. If none is given it 
defaults to "system.storecollection".

=cut

=back

Returns the instantiated class.

=cut

=head1 METHODS

=head2 hash2Metadata()

This method turns the hash-format structure into a AURORA metadata structure (see DESCRIPTION).

Input is a hash reference to the structure to convert into a metadata structure.

Name- and store can be left non-existent in the hash reference that is given for conversion. It will then only convert 
potential param-values. But the hash-structure has to contain the starting keys of get and/or put and the subkeys has to be numbered to be accepted. The returned metadata hash might then only contain a parameter subkey setting, even 
an empty array if none is specified. This functionality is to allow for easy inheritance of param-values, where templates 
further down in the hierachy does not need to set any name or store entity id, only which parameters that are to be 
overridden/changed.

It returns a metadata hash reference upon success, undef upon failure. Please check the error()-method for more 
information on a potential error.

=cut

=head2 metadata2Hash()

This method converts an AURORA metadata hash into a hash-format structure (see DESCRIPTION).

As with hash2Metadata, the name- and store settings can be non-existent. It will always return a param-setting for any
existing, numbered get- or put setting. The param-setting may be non-existing as well.

It takes a AURORA metadata hash reference as input.

The method returns the hash-format reference upon success, undef upon failure. Please check the error()-method upon any 
failure.

=cut

=head2 mergeHash()

This method merges two or more hash-format references into one hash.

It takes any number of hash-reference as input in the form of a hash reference LIST.

The hash-structures references will be iterated over in the order that they were input into the method. The last 
hash-structure to be checked will override any previous hash-structure setting, so that last in the list has precedence.

It returns a resulting hash-reference to a hash-format structure upon success, undef upon failure. Please check the 
error()-method for more information upon failure.

This method can also be used to a clean a hash that is of uncertain format and content. Since the method just iterates 
over the hash-references specified as input, by specifying just one hash reference to the method it will just clean 
that one and return the result (and valid keys and data).

=cut

=head2 template2Hash()

This method converts a template as returned from AuroraDB into a hash-format structure of store-collection definitions 
(if any exists).

It takes the template hash-reference from AuroraDB as input.

The method works similarily to the metadata2Hash()-method. See that method for more information. Instead of that method it takes 
the "default"-setting of the template and sets it as values for name, store and/or param.

It returns the finished converted hash or undef upon failure. Please check the error()-method upon failure.

=cut

=head2 base()

This method returns or sets the AURORA database metadata base namespace for the store-collections used by this module for 
conversion. See the "base" option in the new()-method for more information.

Upon set takes the base namespace as parameter (SCALAR). Upon get it takes no parameters.

Returns the base namespace as a SCALAR.

=cut

=head2 error()

Returns the last error from the StoreCollection-class, if any.

No input taken.

Returns a SCALAR with the error message if any (blank if none).

=cut

