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
# Authenticator: Placeholder class for authentication methods
#
package Authenticator;
use strict;
use AuroraDB;
use SysSchema;
use Settings;
use ErrorAlias;
use Time::HiRes;

sub new {
   my $class=shift;
   my $self={};
   bless ($self,$class);

   my %pars=@_;
   # set defaults
   if (!$pars{db}) { $pars{db}=AuroraDB->new(); }
   if (!$pars{cfg}) { $pars{cfg}=Settings->new(); }

   $self->{pars}=\%pars;
  
   # define class structures
   $self->define();

   return $self;
}

sub define {
   my $self=shift;

   # Authenticator type
   $self->{type}="placeholder";

   # metadata location specifications with short-names to be used elsewhere in the code
   my %MD = (
           "authstr" => "system.authenticator.placeholder.authstr",
           "expire"  => "system.authenticator.placeholder.expire",
         );
   # save it
   $self->{MD}=\%MD;

   # namespace-structure with options/settings
   my %ns=(
            $MD{"authstr"} => {
                                public => 0,
                                storable => 1,
                              },
            $MD{"expire"} => {
                                public => 1,
                                storable => 1,
                              },
          );
   $self->{namespaces}=\%ns;

   # constraints structure
   my @c;
   push @c,"STRING";        # authstr format
   push @c,1024;            # authstr length
   push @c,"([a-zA-Z]+)\,([a-zA-Z0-9]+)";   # authstr acceptable chars
   push @c,(86400*365);     # sets the default longevity of the authstr - can be overridden in config-file
   $self->{constraints}=\@c;  

   return 1;
}

sub validate {
   my $self=shift;
   my $string=shift || "";

   my $db = $self->{pars}{db};
   my $cfg = $self->{pars}{cfg};

   # return user entity id, 0 is an invalid id
   return 0;
}

sub generate {
   my $self=shift;
   my $rawstring=shift;

   # do something
   my $authstr=$rawstring . "dosomethingtothestring";

   return $authstr;
}

# save the given authstr to
# defined namespace set in pos 0. 
sub save {
   my $self=shift;
   my $authstr=shift; # raw authstr before being "worked"
   my $expire=shift;
   $expire=(defined $expire && $expire =~ /^\d+$/ ? $expire : time()+$self->longevity());

   if ($self->storable()) {
      # get MD
      my $MD=$self->{MD};
      # check authstr
      my $check=($self->constraints())[2];
      my $qcheck=qq($check);
      if ((defined $authstr) && ($authstr =~ /^$qcheck$/)) {
         # autstr has the right format, give the string to generate to make it ready for saving
         my $savestr=$self->generate($authstr);
         # extract the part that identifies the user (either id or email)
         my $user=$authstr;
         $user=~s/^$qcheck$/$1/;
         if (($savestr ne "") || ($user ne "")) { # we do not allow blank savestr or user 
            # get db instance
            my $db=$self->{pars}{db};
            my $dbi=$db->getDBI();
            if (defined $dbi) {
               # we have db connection - lets get the user id
               my %mdata;
               $mdata{$SysSchema::MD{"username"}}{"="}=$user;
               # fetch user id
               my @type=($db->getEntityTypeIdByName("USER"));
               my $ids=$db->getEntityByMetadataKeyAndType(\%mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
               if (!defined $ids->[0]) {
                  # could not identify user
                  $self->{error}="Unable to search for user: ".$db->error();
                  $self->{errorcode}=$ErrorAlias::ERR{authvalsearch};
                  return 0;
               } elsif (@{$ids} == 0) {
                  # no hits
                  $self->{error}="Unable to find any matching user in the system";
                  $self->{errorcode}=$ErrorAlias::ERR{authvalinvalid};
                  return 0;
               }
               $user=$ids->[0]; # set user to first discovered user (should be only one)

               my %md;
               $md{$MD->{"authstr"}}=$savestr;
               $md{$MD->{"expire"}}=$expire;
               if (!$db->setEntityMetadata($user,\%md,undef,undef,1)) {
                  # failed to save metadata
                  $self->{error}="Unable to insert data into database: ".$db->error();
                  $self->{errorcode}=$ErrorAlias::ERR{authvaldbins};
                  return 0;
               }
               # if we get to here - success
               return 1;
            } else {
               # some problem with db-connection
               $self->{error}="Unable to connect to database: ".$db->error();
               $self->{errorcode}=$ErrorAlias::ERR{authvaldbconn};
               return 0;
            }                        
         } else {
            # authstr is blank
            $self->{error}="Unable to save blank user or authentication str. Something went wrong in the generation or extraction of the authstr for saving.";
            $self->{errorcode}=$ErrorAlias::ERR{authsaveblank};
            return 0;
         }
      } else {
         $self->{error}="Authstr does not comply with its format. Format is supposed to be: ".($self->constraints())[0]." (".($self->constraints())[2]."). Unable to save authstr.";
         $self->{errorcode}=$ErrorAlias::ERR{authvalformat};
         return 0;
      }
   } else {
      # this authenticator-class is not storable
      $self->{error}="This authenticator cannot save its authstr since it is not storable. Unable to comply.";
      $self->{errorcode}=$ErrorAlias::ERR{authsavestorable};
      return 0;
   }
}

# remove/reset any validation credentials achieved...
sub deValidate {
   my $self=shift;
   my $string=shift||"";

   # return success upon removing credentials, failure if nothing to remove
   return 0;
}

# get the metadata of the namespace keys
sub namespaceData {
   my $self=shift;
   my $str=shift || ""; # authstr

   my $db = $self->{pars}{db};

   if ($db->connected()) {
      # we are connected to the database, lets get the ids metadata
      my $id=$self->validate($str);
      if (defined $id) {
         # got id, lets read metadata
         my $md=$db->getEntityMetadata($id);
         if (!defined $md) {
            # something failed fetching metadata
            $self->{error}="Unable to get metadata of user: ".$db->error();
            $self->{errorcode}=$ErrorAlias::ERR{authvalgetmd};
            return undef;
         }
         # get data namespaces
         my $dn=$self->namespaces();
         my %data;
         foreach (keys %{$dn}) {
            my $key=$_;
            # only return defined values beyond undef
            if ((exists $md->{$key}) && (defined $md->{$key})) { $data{$key}=$md->{$key} };
         }
         # return the data we found, if any
         return \%data;
      } else {
         # something failed - error already set
         return undef;
      }
   } else {
      # db not connected
      $self->{error}="Unable to connect to database";
      $self->{errorcode}=$ErrorAlias::ERR{authvaldbconn};
      return undef;
   }   
}

sub type {
   my $self=shift;

   return $self->{type};
}

sub namespaces {
   my $self = shift;

   my %ns=%{$self->{namespaces}};

   return \%ns;
}

sub locations {
   my $self = shift;

   # make a copy and return
   my %md=%{$self->{MD}};

   return \%md;
}

sub constraints {
   my $self=shift;

   return @{$self->{constraints}};
}

# get longevity 
sub longevity {
   my $self=shift;

   # get type in lowercase
   my $type=lc($self->type());

   # get config file instance
   my $cfg=$self->{pars}{cfg};

   # get potential longevity setting from the Authenticator-classes longevity variable
   my $long=$cfg->value("system.auth.$type.longevity");

   # sanity check the value from the config file, if any. Default to settings in constraints
   $long=(defined $long && $long =~ /^\d+$/ ? $long : ($self->constraints())[3]);

   # return the longevity
   return $long;
}

sub storable {
   my $self=shift;

   # get metadata short names
   my $MD=$self->{MD};

   # get the namespaces definition
   my $ns=$self->namespaces();
   # check if the authstr part of the namespaces hash says if it is storable or not?
   my $storable=(defined $MD->{authstr} && $ns->{$MD->{authstr}}{storable} ? 1 : 0);

   return $storable;
}

sub email {
   my $self=shift;
   my $authstr=shift || "";

   # check authstr
   my $check=($self->constraints())[2];
   my $qcheck=qq($check);
   if ((defined $authstr) && ($authstr =~ /^$qcheck$/)) {
      # autstr has the right format, give the string to generate to make it ready for saving
      my $user=$authstr;
      $user=~s/^$qcheck$/$1/;
      # return result
      return $user || "";
   } else {
      # wrong format
      $self->{error}="Input string is of wrong format. Format is supposed to be: ".($self->constraints())[0]." (".($self->constraints())[2].").";
      $self->{errorcode}=$ErrorAlias::ERR{authvalformat};
      return undef;
   }
}

# attempt to find user entity id
sub id {
   my $self = shift;
   my $str = shift;

   return 0;
}

sub anonymize {
   my $self=shift;
   my $id=shift; # id in database to anonymize

   # do whatever is required to anonymize user in database

   return 1; # or 0 upon some failure
}

sub error {
   my $self=shift;

   return $self->{error} || "";
}

sub errorcode {
   my $self=shift;

   return $self->{errorcode} || 0;
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Authenticator> - placeholder class for Authenticator modules in the Aurora REST-server.

=cut

=head1 SYNOPSIS

   my $db=AuroraDB::new(...);
   my $cfg=Settings::new(...);

   my $auth=Authenticator::new(db=>$db,cfg=>$cfg);

   my $authstr="this_is_a_authentication_string";

   my $userid=$auth->validate($authstr);

   if (!$userid) { print "Failed to authenticate: ".$auth->error()."\n"; }

   my $longevity=$auth->longevity();

   $auth->save($authstr);

   my $newauthstr=$auth->generate($authstr);

=cut

=head1 DESCRIPTION

This module is a placeholder class for authentication modules in the Aurora REST-server and is built around the notion of an authentication string whose
format is defined by the inheriting class. The return value from the validate()-method is to be the userid from the Aurora DB or 0 if it failed. Undef upon
some failure. 

=cut

=head1 CONSTRUCTOR

=head2 new()

Class constructor.

   Authenticator::new();

Required input is the parameters "db" and "cfg". These are to be the AuroraDB instance (db) and the Settings instance (cfg) that defines the 
configuration settings of Aurora.

Return instance upon success.

=cut

=head1 METHODS

=head2 define()

Defines the classes structures with information that are specific to the class in question. It is to be 
overridden by the inheriting class and are called by the new-constructur method. It is not to be called 
by the user of the class.

It takes no input.

The method needs to define four structures called type ($self->{type}), locations ($self->{MD}), namespaces ($self->{namespaces}) and 
constraints ($self->{constraints}).

The type is just the textual type of the Authenticator and is returned when calling the type()-method. Usually should 
be set to the Authenticator-class name, eg. "AuroraID".

The first thing to define is the location-structure which contains all the shortnames for the namespaces of the 
Authenticator-class:

   $MD => (
           "authstr" => "system.authenticator.placeholder.authstr",
           "expire"  => "system.authenticator.placeholder.expire",
         );
   # save it
   $self->{MD}=\%MD;

All code that later need to get the shortnames can refer to $self->{MD} to get them shortnames HASH. This is to easily allow remapping 
of the namespace without affecting the code. It also eliminates the need to remember and write correctly long namespace 
locations.

The namespaces structure is of type HASH and contains all the metadata namespaces and their settings that the 
authenticator-module in question uses. It also allows for the inheriting child-class to input his own settings to the 
namespace. Two option-values for each namespace-value is reserved/protected: "public" and "storable". These cannot be used 
for any other purpose and has the following purpose: "public" defines if the namespace value is public to everyone outside the 
authenticator-module or not? The "storable" settings defines if the value in question can be stored to the database or not.

The structure looks like this:

   NS => (
           $MD{"authstr"} => {
                               public => 0,
                               storable => 1,
                             },
           $MD{"expire"} => {
                              public => 1,
                              storable => 1,
                            },

         )

All keys entered into the structure are to refer to the $MD-structure. It is also important that the authstr-key is defined 
for all classes that are to be storable, that is where the authkey is to be stored in the database, because the 
storable()-method refers to the namespace-structures $MD{"authstr"}{storable} to find out if it is allowed to 
be stored or not? If no key for this is found, or the storable-setting is 0, the storable()-method will return
0 for storable which will impact what eg. the save()-method can do.

The constraints structure is also of type LIST and is to contain these values in the following order:

  - Textual format of the authstr (eg. EMAIL,PASSWORD).
  - Maxmimum length of the authstr in number of characters.
  - Regex with valid format for the authstr.
  - Default longevity setting that will override faulty or missing settings in the config-file.

The regex for the authstr for storable Authenticator-classes is to include enveloping paranthesis for the user ID and the authentication CODE.
User ID is expressed as a email-address (which is unique in the AURORA DB). The enveloping paranthesis 
is to make it possible to address the ID and CODE as $1 and $2 respectively.

It always return 1.

=cut

=head2 validate()

Validates the string against the data input to the class.

Input required is the authstr that one wants to validate against the Aurora database. The method is to be overridden by the inheriting class and 
perform validation based upon that class type. There are several ways of identifying a USER entity for a user in the database, but always by comparing 
some metadata value of the USER-entity against the authstr given to the method.

Returns AURORA userid upon successful validation of credentials or 0 upon failure.

Failure reason can be fetched by calling the error()-method.

=cut

=head2 deValidate()

Removes any validation credentials achieved by the class in question.

Input expected: authstr. Its the authstr that one uses to validate against the AURORA database. 
This method is to be overridden by the inheriting class and remove any validation credentials that 
class has achieved. If no validation credentials are achieved of any permanent nature, always return 0 (false).

Returns 1 upon successful removal on any credentials, 0 upon not having any credentials to remove 
or undef if some failure.

Check the error()-method for more information upon failure.

=cut

=head2 generate()

Generates an authstr based upon a raw string input. The method can be used to generate a valid authstr based upon some raw input from the user or the 
system. What the generate method does is up to the inheriting class and it is to be overridden.

Still it is expected that the input is the authstr according to the format defined in the constraints-structure. It will so rework the 
authstr to include the CODE part in the form that can be stored in the AURORA database.

It cases where the Authenticator-class does not generate a storable authenticator CODE-part (of the authstr) this method shall return 
a checked and cleaned version of the authstr.

Input to the method is the raw string to generate an authstr based upon according to the return of the constraints()-method. 

Return value is always a string or undef upon some failure. The exact error is to be read from the error-method.

=cut

=head2 namespacesData() 

Get the data for the namespaces keys.

Takes only one input: authstr. It uses the authstr to deteremine if it is a valid user or not and 
then to fetch that users data for the defined namespaces keys.

Upon success it returns the data in the database for the namespaces where such data 
exists as a HASH-reference. Upon failure returns undef. Please check the error()-method for more information on 
the failure in question.

The HASH-structure is as follows:

   data => (
             KEYNAMEa  => SCALAR # value of given key from namespaces-definition
             .
             .
             KEYNAMEz  => SCALAR # value of given key from namespaces-definition

           )

Please note that it only return data where it exists, and if no data is found in the database for the 
given key, nothing will be returned (not even the key). Further also note that this method returns all 
values of given keys regardless of the "public"-setting of the namespaces HASH (see the 
define()-method). It is up to the caller to "wash" the returned data to ensure that not too much is given away 
to a third party without looking at its public-setting.

=cut

=head2 save()

Saves the authstr to database.

Accepts two inputs in the following order: authstr and expire. Authstr sets the authstr to save according to 
the format in constraints. Expire sets the actual time when the authstr expires and are not usable anymore. 
Expire time is set in unixtime and it is optional. It will default to current time + return from the 
longevity()-method.

An expire-setting of 0 should mean never expire (but it is is up to the inheriting class how 
this is implemented in the validate()-method). So a specific class may not allow "eternal" validation strings. 
If no expire-parameters is set, it will generate one from constraints and settings in the configuration file. 
See the longevity()-method for more information.

The method uses the generate()-method to rework the authstr to a version that is ready to be stored. It uses the 
constraints()-settings to get the user ID- and CODE-part of of the string. The method is dependant upon that the 
Authenticator-class in question is storable. See the storable()-method for more information.

Returns 1 if successful, 0 if something failed. Please check the error()-method upon failure.

=cut

=head2 type()

Return the Authenticator class type as defined in the define()-method. No input is required and returns the textual type of the class.

=cut

=head2 longevity()

Returns the longevity setting of an authentication string.

It returns how long in seconds an authentication string is valid for. This setting is retrieved in the following steps:

  - The configuration file is read from the cfg-instance to the new()-method. If it finds a setting called 
system.auth.CLASSNAME.longevity, it is of integer type, it uses this as the longevity setting. CLASSNAME here is what 
the type()-method reports, but in lowercase.
  - If it cant find the longevity setting in the configuration file, it uses the default from the constraints()-
method.

It returns the longevity setting in seconds.

=cut

=head2 namespaces()

Returns the namespaces in the Aurora db for the authstr and the expire date as a HASH-reference.

Accepts to input.

See the define()-method for more information on the structure of the namespaces HASH.

=cut

=head2 locations()

Returns the locations in the Aurora db for the authstr and the expire date as a HASH-reference.

Accepts no input.

See the define()-method for more information on the structure of the location HASH.

=cut

=head2 constraints()

Returns the constraints of the raw string to be generated to an authstr by the generate()-method. It is defined by the define()-method. 

It requires no input and the return value is a LIST in the order defined in the define()-method. See the define()-method for more 
information.

=cut

=head2 storable()

Returns if the Store-class result from the generate()-method is meant to be stored in the Aurora DB.

No input accepted.

Returns 0 for not meant to be stored and 1 for meant to be stored. 

=cut

=head2 email()

Returns email (ID) of user in the authstr.
 
Takes the whole authstr as input.

Returns the email address in the authstr identifying the user or a blank string if it does not contain the user email (ID).

Upon some failure returns undef. Check the error()-method for more information upon failure.

=cut

=head2 id()

Attempts to find and return the user entity id of the user in the authstr.

Takes authstr as input.

Returns the user entity id upon success or 0 upon some failure. Please check the error()-method for 
more information upon failure.

This method is to be overridden by the inheriting class.

=cut

=head2 anonymize()

Anonymize user data in the database.

Input parameter is "id". It defines the database user id for the user to anonymize data for.

Returns 1 upon success, 0 upon some failure. Check the error()-method for more information upon failure.

This method is a placeholder and is required to be overridden by the inheriting class who knows best which of its 
authentication data that needs to be anonymized. Only information that may uniquely identify a person/individual is 
required to be removed, so hashed passwords can still remain (and might open a path to restore the account in case 
of such requests by the fact that the user remembers the password). Such things as email, name, username and so on 
needs to be anonymized.

=cut

=head2 error()

Returns last error from Authenticator-class.

=cut

=head2 errorcode()

Returns the error code of the last error (see the error()-method).

This error code is to be used by all inheriting sub-classes of Authenticator to set codes 
for the REST-server that uses the Authenticator-plugins. Error codes are set directly in the 
instance by using $self->{errorcode}=NN. See the ErrorAlias-module for more information on setting 
valid codes.

=cut
