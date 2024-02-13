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
# Class: Settings - class to handle settings from YAML-files.
#
package Settings;

use strict;
use DataContainer::File;
use Content::YAML;
use ContentCollection;

sub new {
   # instantiate
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # check values, set defaults
   if (!$pars{path}) { my $p=$ENV{"AURORA_CONFIG"} || "/etc/aurora.d"; $pars{path}=$p; }
   if (!$pars{aurorapath}) { my $p=$ENV{"AURORA_PATH"} || "/local/app/aurora"; $pars{aurorapath}=$p; }
   if ((!$pars{container}) || (!$pars{container}->isa("DataContainer"))) { my $c=Content::YAML->new(); my $coll=ContentCollection->new(type=>$c); $pars{container}=DataContainer::File->new(collection=>$coll); }

   # save parameters
   $self->{pars}=\%pars;

   # initiate settings hash
   $self->reset();

   # set last error message
   $self->{error}="";

   # set an empty settings hash
   my %s=();
   $self->{settings}=\%s;

   # return instance
   return $self;
}

sub reset {
   my $self = shift;

   my %h=();
   $self->{settings}=\%h;
   # set new content in content class
   my $coll=$self->{pars}{container}->get();
   $coll->resetnext();

   return 1;
}

sub load {
   my $self = shift;

   my $apath=$self->{pars}{aurorapath};

   my @cfiles;
   # add old config file for backwards-compability
   push @cfiles,"$apath/settings/system.yaml";

   # add default settings from usr/local/lib
   push @cfiles,"/usr/local/lib/aurora/config.yaml";

   my $loaded=0; # at least one file found and loaded flag

   # go through config folder and get files present, if possible
   my $cpath=$self->{pars}{path};
   if (opendir (DH,"$cpath/")) {
      # read folder contents
      my @items=grep { /^.*\.yaml$/i } readdir (DH);
      # add items in alphanumerical order, ignoring case
      foreach (sort {$a cmp $b} @items) {
         push @cfiles,"$cpath/$_";
      }
      closedir (DH);
   }

   # go through each file and read settings
   foreach (@cfiles) {
      my $fname=$_;
      # get the datacontainer
      my $container=$self->{pars}{container};
      # set container location
      $container->location("");
      # set the containers name parameter
      $container->name($fname);

      $container->mode($DataContainer::MODE_READ);

      # open the datacontainer
      if (!$container->open()) {
         # something failed - skip to next
         next;
      }
 
      # try loading data from container
      if ($container->load()) {
         # loading was a success - merge with settings hash, new ones has precedence
         my $coll=$container->get();
         $coll->resetnext();
         my $c=$coll->next();
         my $n=$c->get();
         my %s=(%{$self->{settings}},%{$n});
         $self->{settings}=\%s;
         $loaded=1;
      } 

      # close datacontainer
      $container->close();
   }

   # return if we managed to
   # load at least one config-file or not
   return $loaded;
}

sub value {
   my $self = shift;
   my $name = shift || "";

   if ($name ne "") {
      # check if name exists
      if (exists $self->{settings}{$name}) {
         # key exists - get value
         my $val=$self->{settings}{$name};
         if (!defined $val) { $val=""; }
         return $val;
      } else {
         # the given key does not exist
         $self->{error}="Given key name does not exist in settings.";
         return undef;
      }
   } else {
      # name was empty - return the whole hash
      return $self->{settings};
   }
}

sub exists {
   my $self = shift;
   my $name = shift || "";

   if ($name ne "") {
      # check of given name exists
      if (exists $self->{settings}{$name}) {
         return 1;
      } else {
         return 0;
      } 
   } else {
      # name cannot be blank
      $self->{error}="Cannot check if blank key name exists.";
      return 0;
   }
}

sub error {
   my $self = shift;

   # return error message
   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Settings> - Class to handle a settings store

=head1 SYNOPSIS

   use Settings;

   # instantiate
   my $s=Settings->new();

   # load settings into hash
   $s->load();

   # get a settings value
   my $dbname=$s->value("dbname");
   # get another one
   my $name=$s->value("this.is.a.name.setting");
   # get a hash-reference
   my $h=$s->value("myhash");
   # get a list-reference
   my $l=$s->value("mylist");

   # reset contents hash, new load is required
   $s->reset();

=cut

=head1 DESCRIPTION

Class to handle a settings store in a easy and quick way to be used by the AURORA-environment.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the class.

It takes the following input parameters:

=over

=item

B<aurorapath> Path to where the main aurora-folder resides. SCALAR. Optional. Will default to "/local/app/aurora" if not set, or default to the environment variable AURORA_PATH if that has been set.

=cut

=item 

B<path> Path to where the config.d folder resides. SCALAR. Optional. Defaults to "/etc/aurora.d" if not set, or if the environment variable AURORA_CONFIG has been set, it will default to that.

=cut

=item

B<container> The datacontainer instance to use for storing the settings. It is required to be of type DataContainer. If wrong type or not set, it will default to DataContainer::File using a DataCollection with Content-type Content::YAML.

=cut

=back

The return result is the instantiated class.

=cut

=head1 METHODS

=head2 reset()

Resets the settings contents of the Settings instance.

Always returns 1.

=cut

=head2 load()

Loads settings from multiple config files into the internal HASH.

No input is accepted.

The method will attempt to read configuration settings from files in the following order:

1. /usr/local/lib/aurora/aurora.yaml (default settings template from distribution)
2. /etc/aurora.d or env $AURORA_CONFIG or if "path" is specified to the new()-method, that will be 
preferred (it will read all files in this folder in alphanumerical order, case-sensitive). Only 
files that end in ".yaml" will be processed.

Configuration settings from multiple files will be merged into the internal HASH-structure. New settings with 
the same key-name will overwrite old ones.

It returns 1 upon success, 0 upon failure. Check the error()-method for more information upon failure.

=cut

=head2 value()

Gets a specific value from the internal HASH or the whole HASH-reference.

It takes one parameter as input and that is the name of the setting to return. If the name is set to blank or undef it will return
the whole HASH-structure of the settings (all settings).

It will return undef if the value does not exist.

=cut

=head2 exists()

Checks to see if a given key exists in the loaded settings.

Input is the key-name to check for.

It returns 1 if it exists or 0 if does not or if the key-name was blank.

=cut

=head2 error()

Returns the last error message from the class.

=cut

