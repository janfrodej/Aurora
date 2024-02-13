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
# Authenticator::AuroraID: Class for authenticating with a Auroras own DB
#
package Authenticator::AuroraID;
use parent 'Authenticator';

use Bytes::Random::Secure;
use strict;
use ErrorAlias;

sub define {
   my $self=shift;

   # Authenticator type
   $self->{type}="AuroraID";

   # metadata location specifications with short-names to be used elsewhere in the code
   my %MD = (
              "authstr" => "system.authenticator.auroraid.authstr",
              "expire"  => "system.authenticator.auroraid.expire",
            );
   $self->{MD}=\%MD;

   # namespaces structure
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
   push @c,"EMAIL,PASSWORD";      # authstr format
   push @c,288;                   # authstr length
   push @c,"([a-zA-Z]{1}[a-zA-Z0-9\.\!\#\$\%\%\&\'\*\+\-\/\=\?\^\_\`\{\|\}\~]*\@[a-zA-Z0-9\-\.]+)\,([\040-\176]+)"; # authstr acceptable chars
   push @c,(86400*365);           # def longevity
   $self->{constraints}=\@c;

   return 1;
}

sub validate {
   my $self=shift;
   my $string=shift || "";

   # get AuroraDB instance
   my $db = $self->{pars}{db};

   # get regex to check against
   my $check=($self->constraints())[2];
   my $qcheck=qq($check);

   # check string, it is to be a email address and a password
   if ($string =~ /^$qcheck$/) {
      my $email=$1 || "";
      my $pw=$2 || "";
      # cut email and pw - max 255 and 32 each - for a total of 288 including the comma
      $email=$SysSchema::CLEAN{email}->($email);
      $pw=$SysSchema::CLEAN{password}->($pw);

      # get namespaces for authstr and expire
      my $MD=$self->{MD};
      my $nmauthstr=$MD->{"authstr"};
      my $nmexpire=$MD->{"expire"};
      # set hash with username
      my %mdata;
      $mdata{$SysSchema::MD{"username"}}{"="}=$email;
      # fetch current salt, if user exists at all
      my @type=($db->getEntityTypeIdByName("USER"));
      my $ids=$db->getEntityByMetadataKeyAndType(\%mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
      if (defined $ids) {
         if (@{$ids} == 1) {
            # found entity - success
            my $id=$ids->[0] || 0;
            # get entity's authstr
            my $md=$db->getEntityMetadata($id,$nmauthstr);
            if (exists $md->{$nmauthstr}) {
               # we found it - get password
               my $mdpw=$md->{$nmauthstr};
               # retrieve the salt
               my $salt=$mdpw;
               $salt=~s/^(\$[0-9a-zA-Z]+\$[0-9a-zA-Z\.\/]+\$).*$/$1/;
               # we can now generate a pw and check against stored pw.
               my $cpw=crypt($pw,$salt);
               if ($cpw eq $mdpw) {
                  # passwords match - do some user metadata updating
                  my %mdata;
                  $mdata{$SysSchema::MD{"lastlogontime"}}=time();
                  # update without checking result
                  $db->setEntityMetadata($id,\%mdata,undef,undef,1);
                  # return validated id
                  return $id;
               } else {
                  # passwords do not match. Return 0
                  $self->{error}="Wrong username and/or password";
                  $self->{errorcode}=$ErrorAlias::ERR{authwrong};
                  return 0;
               }
            } else {
               # missing authinfo in the metadata
               $self->{error}="Missing authentication information for user $email. Unable to authenticate.";
               $self->{errorcode}=$ErrorAlias::ERR{authmissing};
               return 0;
            }
         } elsif (@{$ids} > 1) {
            # multiple hits - not acceptable
            $self->{error}="Multiple ids returned for authstr. Please contact an administrator";
            $self->{errorcode}=$ErrorAlias::ERR{authvalmultiple};
            return 0;
         } else {
            # passwords do not match. Return 0
            $self->{error}="Wrong username and/or password";
            $self->{errorcode}=$ErrorAlias::ERR{authwrong};
            return 0;
         }
      } else {
         # id does not exist or some other failure
         $self->{error}="Unable to search for user: ".$db->error();
         $self->{errorcode}=$ErrorAlias::ERR{authvalsearch};
         return 0;
      }
   } else {
      # wrong format
      $self->{error}="Input string is of wrong format. Format is supposed to be: ".($self->constraints())[0].". Unable to authenticate user.";
      $self->{errorcode}=$ErrorAlias::ERR{authvalformat};
      return 0;
   }

   # we never get to here...
}

sub generate {
   my $self=shift;
   my $string=shift;

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

   # get regex check
   my $check=($self->constraints())[2];
   my $qcheck=qq($check);

   # check string
   if ($string =~ /^$qcheck$/) {
      my $email=$1 || "";
      my $pw=$2 || "";

      # cut email and pw - max 255 and 32 each - for a total of 288 including the comma
      $email=$SysSchema::CLEAN{email}->($email);
      # cut pw - max 32 characters
      $pw=$SysSchema::CLEAN{password}->($pw);

      # generate a salt
      my $salt=generate_salt(16);

      # use password and salt to create an encrypted password
      my $cpw=crypt($pw,"\$6\$".$salt."\$");

      # return result
      return "$cpw";
   } else {
      $self->{error}="Input string is of wrong format. Format is supposed to be: ".($self->constraints())[0]." (".($self->constraints())[2]."). Cannot generate authentication from this.";
      $self->{errorcode}=$ErrorAlias::ERR{authvalformat};
      return undef;
   }
}

# get email based on authstr
# overrides super-class method
sub email {
   my $self=shift;
   my $authstr=shift||"";

   # get regex check
   my $check=($self->constraints())[2];
   my $qcheck=qq($check);

   # check string
   if ($authstr =~ /^$qcheck$/) {
      # get email from authstr, does not need to be valid
      # just based upon what was attempted in the authstr
      my $email=$1 || "";

      # return result or blank if no result (blank = N/A).
      return $email;
   } else {
      # email is unknown
      $self->{error}="Input string is of wrong format. Format is supposed to be: ".($self->constraints())[0]." (".($self->constraints())[2]."). Cannot retrieve email from this.";
      $self->{errorcode}=$ErrorAlias::ERR{authvalformat};
      return undef;
   }
}

# attempt to find user entity id
sub id {
   my $self=shift;
   my $string=shift || "";

   # get AuroraDB instance
   my $db = $self->{pars}{db};

   # get regex to check against
   my $check=($self->constraints())[2];
   my $qcheck=qq($check);

   # check string, it is to be a email address and a password
   if ($string =~ /^$qcheck$/) {
      my $email=$1 || "";
      my $pw=$2 || "";

      # cut email and pw - max 255 and 32 each - for a total of 288 including the comma
      $email=$SysSchema::CLEAN{email}->($email);
      $pw=$SysSchema::CLEAN{password}->($pw);

      # set hash with username
      my %mdata;
      $mdata{$SysSchema::MD{"username"}}{"="}=$email;
      # fetch current salt, if user exists at all
      my @type=($db->getEntityTypeIdByName("USER"));
      my $ids=$db->getEntityByMetadataKeyAndType(\%mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
      if (defined $ids) {
         if (@{$ids} == 1) {
            # found user entity - success
            my $id=$ids->[0] || 0;
            # return id
            return $id;
         } elsif (@{$ids} > 1) {
            # multiple hits - not acceptable
            $self->{error}="Multiple ids returned for authstr. Please contact an administrator";
            $self->{errorcode}=$ErrorAlias::ERR{authvalmultiple};
            return 0;
         } else {
            # user/email does not exist. Return 0
            $self->{error}="Wrong username";
            $self->{errorcode}=$ErrorAlias::ERR{authwrong};
            return 0;
         }
      } else {
         # id does not exist or some other failure
         $self->{error}="Unable to search for user: ".$db->error();
         $self->{errorcode}=$ErrorAlias::ERR{authvalsearch};
         return 0;
      }
   } else {
      # wrong format
      $self->{error}="Input string is of wrong format. Format is supposed to be: ".($self->constraints())[0].". Unable to authenticate user.";
      $self->{errorcode}=$ErrorAlias::ERR{authvalformat};
      return 0;
   }

   # we never get here
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Authenticator::AuroraID> - Class to handle authentication of AURORA REST-server internal user-accounts.

=head1 SYNOPSIS

It follows the same use as the Authenticator-class. See the Authenticator placeholder class for more information.

=head1 DESCRIPTION 

A class that inherits from the Authenticator placeholder class. Please see there for more information.

AuroraID uses the crypt-facility and SHA-512 encryption of passwords (id=6).

=head1 CONSTRUCTOR

See the Authenticator placeholder class for more information.

=head1 METHODS

=head2 define()

See description in the placeholder Authenticator-class.

=cut

=head2 validate()

Validates an internal AURORA REST-server accounts. It expects to get an authentication string (SCALAR) which is formatted in 
the following way:

   EMAIL,PASSWORD

Password in this case is expected to be un-encrypted/clear-text.

It calls the generate()-method on the authentication string and then uses the AURORA database to check if such an 
account exists and that the password matches.

It returns the AURORA database userid (entity id - int) of the user upon success or 0 upon user not found. 

Undef is returned upon failure. Check the error()-method for more information.

See description in the placeholder Authenticator-class for more information on the framework itself.

=cut

=head2 generate()

Generates a AuroraID authentication string (=password encrypted) by taking a raw password (unencrypted). 

The salt for the encryption is randomly generated each time and consisting of 16 characters as per the crypt-facility.

The function returns an authentication string upon success that consists of:

  ENCRYPTED_PASSWORD

where ENCRYPTED_PASSWORD consists of the salt and the encrypted password in the crypt-format.

Undef is returned upon failure. In such a case check the error()-method for more information.

See description in the placeholder Authenticator-class for more information on the framework itself.

=cut
