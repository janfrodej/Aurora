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
# Authenticator::Crumbs: Class for authenticating with a crumb/UUID. 
#
package Authenticator::Crumbs;
use parent 'Authenticator';

use strict;
use UUID qw(uuid);
use ErrorAlias;

sub define {
   my $self=shift;

   # Authenticator type
   $self->{type}="Crumbs";

   # metadata location specifications with short-names to be used elsewhere in the code
   # crumbs uses none, since its basically a loopback to a real Authenticator-class
   my %MD = ();
   $self->{MD}=\%MD;

   # namespaces structure
   # none to define for crumbs
   my %ns=();
   $self->{namespaces}=\%ns;

   # constraints structure
   my @c;
   push @c,"UUID";      # authstr format
   push @c,36;          # authstr length
   push @c,"([a-fA-F0-9\-]{36})"; # authstr acceptable chars
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

   # check string
   if ($string =~ /^$qcheck$/) {
      my $uuid=$1;

      my $cfg=$self->{pars}{cfg};

      if (!$db->connected()) {
         $self->{error}="Unable to contact database while validating: ".$db->error();
         return 0;
      }

      # get timeout value
      my $now=time();
      my $timeout=$cfg->value("system.auth.crumbs.timeout")||14400; # default to 4 hours.
      my $lifespan=$cfg->value("system.auth.crumbs.lifespan")||43200; # absolute timespan of a crumb, half a day as default
      # get shared salt
      my $salt=$cfg->value("system.auth.crumbs.salt")||"dummy";
      # crypt uuid
      my $cuuid=crypt($uuid,$salt)||"dummy";
      # set criteria
      my @mdata;
      push @mdata,"OR";
      # generate a number of logical checks
      for (my $i=1; $i <= 10; $i++) {
         my %h;
         $h{$SysSchema::MD{crumbsuuid}.".$i.uuid"}{"="}=$cuuid;
         push @mdata,\%h;
      }
      # get user type
      my @type=($db->getEntityTypeIdByName("USER"));
      # check if we can find matches
      my $ids=$db->getEntityByMetadataKeyAndType(\@mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
      if (defined $ids) {
         if (@{$ids} == 1) {
            # found entity, now we need to check if it is timed out or not
            my $id=$ids->[0] || 0;
            # get entity metadata
            my $md=$db->getEntityMetadata($id);
            if (!defined $md) {
               $self->{error}="Unable to get metadata of user: ".$db->error();
               $self->{errorcode}=$ErrorAlias::ERR{authvalgetmd};
               return 0;
            }
            # locate count position that uuid is in
            my $pos=0;
            for (my $i=1; $i <= 10; $i++) {
               if (!exists $md->{$SysSchema::MD{crumbsuuid}.".$i.uuid"}) { last; }
               if ($md->{$SysSchema::MD{crumbsuuid}.".$i.uuid"} eq $cuuid) { $pos=$i; last; }
            }
            if ($pos == 0) {
               # unable to locate uuid
               $self->{error}="Unable to find any matching user in the system";
               $self->{errorcode}=$ErrorAlias::ERR{authvalinvalid};
               return 0;
            }
            my $tstamp=$md->{$SysSchema::MD{crumbsuuid}.".$pos.timeout"}||0;
            my $created=$md->{$SysSchema::MD{crumbsuuid}.".$pos.created"}||0;
            if ($tstamp >= ($now-$timeout)) {
               if ($now > ($created+$lifespan)) {
                  # timed out on lifespan
                  $self->{error}="Authstr has timed out on its lifespan and is no longer valid.";
                  $self->{errorcode}=$ErrorAlias::ERR{authvallifespan};
                  return 0;
               } else {
                  # still valid - update time
                  my %nmd;
                  $nmd{$SysSchema::MD{crumbsuuid}.".$pos.timeout"}=$now;
                  if (!$db->setEntityMetadata($id,\%nmd,undef,undef,1)) {
                     # unable to update timestamp
                     $self->{error}="Unable to insert data into database: ".$db->error();
                     $self->{errorcode}=$ErrorAlias::ERR{authvaldbins};
                     return 0;
                  }
                  # success - return id
                  return $id;
               }
            } else {
               # uuid has timed out
               $self->{error}="Authstr has timed out and is no longer valid";
               $self->{errorcode}=$ErrorAlias::ERR{authvaltimeout};
               return 0;
            }
         } elsif (@{$ids} > 1) {
            # multiple hits - not acceptable. This is theroetically possible, but should not happen in reality
            $self->{error}="Multiple ids returned for authstr. Please contact an administrator.";
               $self->{errorcode}=$ErrorAlias::ERR{authvalmultiple};
            return 0;
         } else {
            # no matches found in database. Return 0
            $self->{error}="UUID $uuid could not be found. Unable to validate.";
            $self->{errorcode}=$ErrorAlias::ERR{authvalinvalid};
            return 0;
         }
      } else {
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

sub deValidate {
   my $self=shift;
   my $string=shift||"";

   # get regex to check against
   my $check=($self->constraints())[2];
   my $qcheck=qq($check);

   # check string
   if ($string =~ /^$qcheck$/) {
      my $uuid=$1;

      my $cfg=$self->{pars}{cfg};
      my $db=$self->{pars}{db};

      # get timeout value
      my $now=time();
      my $timeout=$cfg->value("system.auth.crumbs.timeout")||14400; # default to 4 hours.
      my $lifespan=$cfg->value("system.auth.crumbs.lifespan")||43200; # absolute timespan of a crumb, half a day as default
      # get shared salt
      my $salt=$cfg->value("system.auth.crumbs.salt")||"dummy";
      # crypt uuid
      my $cuuid=crypt($uuid,$salt)||"dummy";
      # set criteria
      my @mdata;
      push @mdata,"OR";
      # generate a number of logical checks
      for (my $i=1; $i <= 10; $i++) {
         my %h;
         $h{$SysSchema::MD{crumbsuuid}.".$i.uuid"}{"="}=$cuuid;
         push @mdata,\%h;
      }
      # get user type
      my @type=($db->getEntityTypeIdByName("USER"));
      # check if we can find matches
      my $ids=$db->getEntityByMetadataKeyAndType(\@mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
      if (defined $ids) {
         if (@{$ids} == 1) {
            # found entity, now we need to check if it is timed out or not
            my $id=$ids->[0] || 0;
            # get entity metadata
            my $md=$db->getEntityMetadata($id);
            if (!defined $md) {
               $self->{error}="Unable to get metadata of user: ".$db->error();
               $self->{errorcode}=$ErrorAlias::ERR{authvalgetmd};
               return undef;
            }
            # locate count position that uuid is in
            my $pos=0;
            for (my $i=1; $i <= 10; $i++) {
               if (!exists $md->{$SysSchema::MD{crumbsuuid}.".$i.uuid"}) { last; }
               if ($md->{$SysSchema::MD{crumbsuuid}.".$i.uuid"} eq $cuuid) { $pos=$i; last; }
            }
            if ($pos == 0) {
               # unable to locate uuid
               $self->{error}="Nothing more to de-authenticate.";
               $self->{errorcode}=1;
               return 0;
            }
            my $tstamp=$md->{$SysSchema::MD{crumbsuuid}.".$pos.timeout"}||0;
            my $created=$md->{$SysSchema::MD{crumbsuuid}.".$pos.created"}||0;
            if ($tstamp >= ($now-$timeout)) {
               if ($now > ($created+$lifespan)) {
                  # already timed out, so no more to de-auhtenticate
                  $self->{error}="Nothing more to de-authenticate.";
                  $self->{errorcode}=1;
                  return 0;
               } else {
                  # still valid - reset time by setting timeout to 0
                  my %nmd;
                  $nmd{$SysSchema::MD{crumbsuuid}.".$pos.timeout"}=0;
                  if (!$db->setEntityMetadata($id,\%nmd,undef,undef,1)) {
                     # unable to update timestamp
                     $self->{error}="Unable to insert data into database: ".$db->error();
                     $self->{errorcode}=$ErrorAlias::ERR{authvaldbins};
                     return undef;
                  }
                  # success
                  $self->{error}="";
                  $self->{errorcode}=0;
                  return 1;
               }
            } else {
               # uuid has timed out
               $self->{error}="Authstr has timed out and is no longer valid";
               $self->{errorcode}=$ErrorAlias::ERR{authvaltimeout};
               return undef;
            }
         } elsif (@{$ids} > 1) {
            # multiple hits - not acceptable. This is theoretically possible, but should not happen in reality
            $self->{error}="Multiple ids returned for authstr. Please contact an administrator.";
            $self->{errorcode}=$ErrorAlias::ERR{authvalmultiple};
            return undef;
         } else {
            # no matches found in database. Return 0
            $self->{error}="UUID $uuid could not be found. Unable to de-validate.";
            $self->{errorcode}=$ErrorAlias::ERR{authvalinvalid};
            return 0;
         }
      } else {
         $self->{error}="Unable to search for user: ".$db->error();
         $self->{errorcode}=$ErrorAlias::ERR{authvalsearch};
         return undef;
      }
   } else {
      # wrong format
      $self->{error}="Input string is of wrong format. Format is supposed to be: ".($self->constraints())[0].". Unable to de-authenticate user.";
      $self->{errorcode}=$ErrorAlias::ERR{authvalformat};
      return undef;      
   }
}

sub generate {
   my $self=shift;
   my $string=shift;

   my $check=($self->constraints())[2];
   my $qcheck=qq($check);

   # check string, that it is of correct format
   if ($string =~ /^$check$/) {
      my $uuid=$string || "";

      # cut uuid to max length
      $uuid=substr($uuid,0,36);

      # return result
      return $uuid;
   } else {
      $self->{error}="UUID string is of wrong format. Format is supposed to be: ".($self->constraints())[0]."(".($self->constraints())[2].").";
      $self->{errorcode}=$ErrorAlias::ERR{authvalformat};
      return undef;
   }
}

sub email {
   my $self=shift;
   my $authstr=shift||"";

   # get AuroraDB instance
   my $db = $self->{pars}{db};

   my $uuid = $self->generate($authstr);

   if (defined $uuid) {
      # we have a valid cauth-string, lets attempt to get email/identity of user
      my $cfg=$self->{pars}{cfg};

      if (!$db->connected()) {
         $self->{error}="Unable to contact database while validating: ".$db->error();
         return undef;
      }

      # get timeout value
      my $now=time();
      my $timeout=$cfg->value("system.auth.crumbs.timeout")||14400; # default to 4 hours.
      my $lifespan=$cfg->value("system.auth.crumbs.lifespan")||43200; # absolute timespan of a crumb, half a day as default
      # get shared salt
      my $salt=$cfg->value("system.auth.crumbs.salt")||"dummy";
      # crypt uuid
      my $cuuid=crypt($uuid,$salt)||"dummy";
      # set criteria
      my @mdata;
      push @mdata,"OR";
      # generate a number of logical checks
      for (my $i=1; $i <= 10; $i++) {
         my %h;
         $h{$SysSchema::MD{crumbsuuid}.".$i.uuid"}{"="}=$cuuid;
         push @mdata,\%h;
      }
      # get user type
      my @type=($db->getEntityTypeIdByName("USER"));
      # check if we can find matches
      my $ids=$db->getEntityByMetadataKeyAndType(\@mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
      if (defined $ids) {
         if (@{$ids} == 1) {
            # found entity, now we need to check if it is timed out or not
            my $id=$ids->[0] || 0;
            # get entity metadata
            my $md=$db->getEntityMetadata($id);
            if (!defined $md) {
               $self->{error}="Unable to get metadata of user: ".$db->error();
               $self->{errorcode}=$ErrorAlias::ERR{authvalgetmd};
               return undef;
            }
            # locate count position that uuid is in
            my $pos=0;
            for (my $i=1; $i <= 10; $i++) {
               if (!exists $md->{$SysSchema::MD{crumbsuuid}.".$i.uuid"}) { last; }
               if ($md->{$SysSchema::MD{crumbsuuid}.".$i.uuid"} eq $cuuid) { $pos=$i; last; }
            }
            if ($pos == 0) {
               # unable to locate uuid
               $self->{error}="Unable to find any matching user in the system";
               $self->{errorcode}=$ErrorAlias::ERR{authvalinvalid};
               return "";
            }
            # success - return email of user entity 
            my $result=(defined $md->{$SysSchema::MD{email}} ? $md->{$SysSchema::MD{email}} : $id);
            return $result;
         } elsif (@{$ids} > 1) {
            # multiple hits - not acceptable. This is theroetically possible, but should not happen in reality
            $self->{error}="Multiple ids returned for authstr. Please contact an administrator.";
            $self->{errorcode}=$ErrorAlias::ERR{authvalmultiple};
            return undef;
         } else {
            # no matches found in database.
            return "";
         }
      } else {
         $self->{error}="Unable to search for user: ".$db->error();
         $self->{errorcode}=$ErrorAlias::ERR{authvalsearch};
         return undef;
      }      
   } else {
      # failure of some kind
      return undef;
   }
}

sub id {
   my $self=shift;
   my $string=shift || "";

   # get AuroraDB instance
   my $db = $self->{pars}{db};

   # get regex to check against
   my $check=($self->constraints())[2];
   my $qcheck=qq($check);

   # check string
   if ($string =~ /^$qcheck$/) {
      my $uuid=$1;

      my $cfg=$self->{pars}{cfg};

      if (!$db->connected()) {
         $self->{error}="Unable to contact database while validating: ".$db->error();
         return 0;
      }

      # get shared salt
      my $salt=$cfg->value("system.auth.crumbs.salt")||"dummy";
      # crypt uuid
      my $cuuid=crypt($uuid,$salt)||"dummy";
      # set criteria
      my @mdata;
      push @mdata,"OR";
      # generate a number of logical checks
      for (my $i=1; $i <= 10; $i++) {
         my %h;
         $h{$SysSchema::MD{crumbsuuid}.".$i.uuid"}{"="}=$cuuid;
         push @mdata,\%h;
      }
      # get user type
      my @type=($db->getEntityTypeIdByName("USER"));
      # check if we can find matches
      my $ids=$db->getEntityByMetadataKeyAndType(\@mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
      if (defined $ids) {
         if (@{$ids} == 1) {
            # found entity
            my $id=$ids->[0] || 0;
            # success - return id
            return $id;
         } elsif (@{$ids} > 1) {
            # multiple hits - not acceptable. This is theoretically possible, but should not happen in reality
            $self->{error}="Multiple ids returned for authstr. Please contact an administrator.";
            $self->{errorcode}=$ErrorAlias::ERR{authvalmultiple};
            return 0;
         } else {
            # no matches found in database. Return 0
            $self->{error}="UUID $uuid could not be found. Unable to validate.";
            $self->{errorcode}=$ErrorAlias::ERR{authvalinvalid};
            return 0;
         }
      } else {
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
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Authenticator::Crumb> - Class for authenticating with a UUID in AURORA.

=head1 SYNOPSIS

It follows the same use as the Authenticator-class. See the Authenticator placeholder class for more information.

=head1 DESCRIPTION 

Class for authenticating with a UUID in AURORA. AURORA supports requesting an UUID upon validation which 
then can subsequently be used instead of the original credentials, such as AuroraID. 

When validation is performed the AURORA REST-server can generate an UUID to be used instead of the original 
credentials. All Authenticator-classes can be used with this scheme, with the exception of the UUID-class itself - Crumbs.

One asks for such a UUID to be generated by including the parameter "authuuid" and setting to a value that evaluates to true. The 
REST-server will then upon success return the newly generated UUID in the parameter "authuuid".

This scheme makes it possible for browser-side apps, such as using javascript, to hide the initial credentials used to authenticate 
by asking for a UUID replacement and then throwing the original credentials.

=head1 CONSTRUCTOR

See the Authenticator placeholder class for more information.

=head1 METHODS

=head2 define()

See description in the placeholder Authenticator-class.

=cut

=head2 validate()

Attempt to find user based upon a valid UUID. The authstr of the class is formatted as follows:

   UUID

It returns the AURORA database userid (entity id - int) of the user upon success or 0 upon user not found or some failure. 
Check the error()-method for more information.

See description in the placeholder Authenticator-class for more information on the framework itself.

=cut

=head2 generate()

Generates a UUID authentication string cleaning it.

Undef is returned upon failure. In such a case check the error()-method for more information.

See description in the placeholder Authenticator-class for more information on the framework itself.

=cut
