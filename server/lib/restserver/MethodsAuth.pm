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
# MethodsAuth: Authentication methods for the AURORA REST-server
#
package MethodsAuth;
use strict;
use RestTools;

sub registermethods {
   my $srv = shift;

   $srv->addMethod("/changeAuth",\&changeAuth,"Change given auth types credentials.");
   $srv->addMethod("/doAuth",\&doAuth,"Attempts to authenticate user.");
   $srv->addMethod("/doDeAuth",\&doDeAuth,"Remove any authentication tokens.");
   $srv->addMethod("/enumAuthTypes",\&enumAuthTypes,"Enumerates the authentication types that are available.");
   $srv->addMethod("/getAuthData",\&getAuthData,"Get public authenticator data for logged in user.");
}

sub changeAuth {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # get auth type
   my $type=$SysSchema::CLEAN{authtype}->($query->{type});
   my $authstr=substr($query->{auth}||"",0,4096); # general cut, cleaning by the auth-class itself

   # go through each type in the config file and check if it matches type
   my @authmethods=@{($cfg->value("system.auth.methods"))[0]};
   my $id=0;
   my $found=0;
   my $auth;
   my $err="";
   my $change=1;
   foreach (@authmethods) {
      my $m=$_;

      # match is case-sensitive in order to invoke actual Authenticator sub-class
      if ($type eq $m) {
         # match found - try to instantiate class
         $found=1;
         my $atype="Authenticator::$type";         
         my $err="";
         local $@;
         eval { $auth=$atype->new(db=>$db,cfg=>$cfg) || undef; };
         $@ =~ /nefarious/;
         $err = $@;            

         if (defined $auth) {         
            # get some information
            $change=$auth->storable();
            my $email="dummy";
            # only get user if auth is storable
            if ($change) {
               # get user
               $email=$SysSchema::CLEAN{email}->($auth->email($authstr));
               $email=$email || "";
            } else {
               $content->value("errstr","Unable to change authentication credentials. The authentication type $type does not support being changed.");
               $content->value("err",1);

               return 0;
            }
            # attempt to locate the users ID
            my @mdata; # use LIST so the values are or'ed together.
            push @mdata,"AND"; # must specify what to do with array, even if just one
            push @mdata,{$SysSchema::MD{"username"} => { "=" => $email }};
            # fetch current salt, if user exists at all
            my @type=($db->getEntityTypeIdByName("USER"));
            my $ids=$db->getEntityByMetadataKeyAndType(\@mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
            if (defined $ids) {
               if (@{$ids} > 0) {
                  # id found, get it
                  $id=$ids->[0];
               }
            } else {
               # ids not defined - something failed
               $err="Cannot change authentication credentials for $type. Unable to get user id: ".$db->error();
            }
            # we are finished with the foreach-loop in any case
            last;
         } else {
            # something failed
            $err="Cannot change authentication for $type. Unable to instantiate it: ".$err;
            last;
         }
      }
   }

   if ($err ne "") {
      # we failed something
      $content->value("errstr",$err);
      $content->value("err",1);

      return 0;
   } elsif (!$found) {
      # did not find auth type
      $content->value("errstr","Cannot change authentication for $type. The authentication type does not exists or is not enabled.");
      $content->value("err",1);

      return 0;
   } elsif ($id == 0) {
      # user not found
      $content->value("errstr","Cannot change authentication for $type. Unable to find user in the system.");
      $content->value("err",1);

      return 0;
   }

   # if user is himself he implicitly has permissions, then skip permission check
   if ($id != $userid) {
      # the id attempting to change its credentials is not the user
      # authenticated on the rest-server. We need to check that he has permission to go ahead.
      # user must have ALL of the perms on ANY of the levels
      my $allowed=hasPerm($db,$userid,$id,["USER_CHANGE"],"ALL","ANY",1,1,undef,1);
      if (!$allowed) {
         # user does not have the required permission or something failed
         if (!defined $allowed) {
            $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
            $content->value("err",1);
            return 0;
         } else {
            $content->value("errstr","User does not have the USER_CHANGE permission on the USER $id. Unable to fulfill the request.");
            $content->value("err",1);
            return 0;
         }
      }
   }

   # if here, we have necessary permissions - go ahead and change and save at the same time.
   if (!$auth->save($authstr)) {
      # Unable to change and save authstr
      $content->value("errstr","Unable to change and save new authentication: ".$auth->error());
      $content->value("err",1);

      return 0;      
   }

   # if we got this far, success!
   $content->value("errstr","");
   $content->value("err",0);

   return 1;
}

sub doAuth {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # if we got this far, we are authenticated, set return values
   $content->value("errstr","");
   $content->value("err",0);
   # return userid of authenticated user
   $content->value("id",$userid);

   return 1;
}

sub doDeAuth {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # we need to know what type to de-authenticate, so authtype needs to be set
   # as well as authstr (coming all the way here, they should be ok.)
   my $type=$query->{authtype} || "";
   $type=$SysSchema::CLEAN{authtype}->($type);
   my $str=$query->{authstr} || "";

   # go through each allowed auth methods and see if we have a match
   my @authmethods=@{($cfg->value("system.auth.methods"))[0]};
   my $ok=0;
   my $username="N/A";
   my $found=0;
   my $auth;
   foreach (@authmethods) {
      my $m=$_;

      # match is case-sensitive in order to invoke actual Authenticator sub-class
      if ($type eq $m) {
         # match found - try to instantiate class
         my $atype="Authenticator::$type";
         my $err="";
         local $@;
         eval { $auth=$atype->new(db=>$db,cfg=>$cfg,query=>$query) || undef; };
         $@ =~ /nefarious/;
         $err = $@;

         if (defined $auth) {
            # class was instantiated successfully
            $found=1;
            # attempt to get email/username of user
            $username=$auth->email($str);
            $username=(defined $username ? $username : "N/A");
            # attempt to de-authenticate
            $ok=$auth->deValidate($str);
            # we are finished with the foreach-loop in any case
            last;
         } else {
            # something failed
            $err=(defined $err ? ": $err" : "");
            $content->value("errstr","Unable to instantiate Authenticator-class $atype$err");
            $content->value("err",$ErrorAlias::ERR{restinstfailed});
            return 0;
         }
      }
   }

   # check for failures or success,
   # ignore ok=0 which means no more tokens to reset.
   if (!defined $ok) {
      # failure to devalidate
      $content->value("errstr","Unable to de-authenticate user: ".$auth->error());
      $content->value("err",1);
      return 0;
   } elsif ($ok) {
      # log that we successfully logged out...
      # log to USERLOG success in authenticating, no checking for success
      $db->doSQL("INSERT INTO USERLOG (timedate,entity,tag,message) VALUES (".time().",$userid,\"DEAUTH SUCCESS\",\"De-Authentication success from ".$query->{"SYSTEM_REMOTE_ADDR"}.":".$query->{"SYSTEM_REMOTE_PORT"}." using $type for user $userid ($username)\")");
   } 

   # successfully de-authenticated
   $content->value("errstr","");
   $content->value("err",0);

   return 1;
}

sub enumAuthTypes {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # check in config file which authenticator are defined as 
   # allowed
   my @authtypes=@{($cfg->value("system.auth.methods"))[0]};

   # go through list and check that they can be invoked and 
   # harvest data
   my %types;
   foreach (@authtypes) {
      my $type=$_;

      # attempt to invoke the class-type to ensure it is working
      # and get some data on it
      my $atype="Authenticator::$type";
      my $auth;
      my $err="";
      local $@;
      eval { $auth=$atype->new(db=>$db,cfg=>$cfg) || undef; };
      $@ =~ /nefarious/;
      $err = $@;         

      if (defined $auth) {
         # it worked - lets ask it about its storable state
         # which defines if user is allowed to change its credentials
         my $storable=$auth->storable();
         $types{$type}{change}=$storable;
         my @con=$auth->constraints();
         $types{$type}{format}=$con[0];
         $types{$type}{maxlength}=$con[1];
         $types{$type}{regex}=$con[2];
         $types{$type}{longevity}=$auth->longevity();
      } else {
         # it was defined in the config file, but is not working
         # skip it...
         next;
      }
   }

   # if we got this far - return auth types
   $content->value("errstr","");
   $content->value("err",0);
   # return userid of authenticated user
   $content->value("authtypes",\%types);

   return 1;
}

# get an authenticator-modules data
# that is specific to its class
sub getAuthData {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # gotten so far, we know authtype and authstr are valid
   my $type=$query->{authtype} || "";
   my $str=$query->{authstr} || "";

   # clean auth type
   $type=$SysSchema::CLEAN{authtype}->($type);
   # go through each allowed auth methods and see if we have a match
   my @authmethods=@{($cfg->value("system.auth.methods"))[0]};
   my $found=0;
   my $auth;
   foreach (@authmethods) {
      my $m=$_;

      # match is case-sensitive in order to invoke actual Authenticator sub-class
      if ($type eq $m) {
         # match found - try to instantiate class
         my $atype="Authenticator::$type";
         my $err="";
         local $@;
         eval { $auth=$atype->new(db=>$db,cfg=>$cfg) || undef; };
         $@ =~ /nefarious/;
         $err = $@;

         if (defined $auth) {
            # we found the correct class
            $found=1;
            # we are finished with the foreach-loop in any case
            last;
         } else {
            # something failed
            $err=(defined $err ? ": $err" : "");
            $content->value("errstr","Unable to get authenticator data of $atype$err");
            $content->value("err",1);

            return 0;
         }
      }
   }
   # check if found, although it must have been found
   if (!$found) {
      $content->value("errstr","Unable to find authenticator for type: $type. Cannot fulfill request.");
      $content->value("err",1);

      return 0;
   }

   # a-ok! - get data, if any
   my $data=$auth->namespaceData($str);

   if (defined $data) {
      # we have data, go through it and only get what is public
      my $ns=$auth->namespaces();
      my %wdata;
      foreach (keys %{$data}) {
         my $key=$_;

         # select only public data
         if ((exists $ns->{$key}) && ($ns->{$key}{public})) { $wdata{$key}=$data->{$key}; }
      }

      # also get the general user metadata
      my $md=$db->getEntityMetadata($userid);

      if (!defined $md) {
         # something went wrong
         $content->value("errstr","Unable to get metadata for user $userid: ".$db->error());
         $content->value("err",1);

         return 0;
      }

      # return whatever is public
      $content->value("errstr","");
      $content->value("err",0);
      # the auth module specific data
      $content->value("data",\%wdata);
      # the general user info
      $content->value("id",$userid);
      $content->value("email",$md->{$SysSchema::MD{email}});
      $content->value("fullname",$md->{$SysSchema::MD{fullname}});
      $content->value("displayname",$md->{$SysSchema::MD{name}});
   } else {
      # something failed
      $content->value("errstr","Unable to get authenticator data for type $type: ".$auth->error());
      $content->value("err",1);

      return 0;
   }   
}

1;

__END__

=encoding UTF-8

=head1 AUTHENTICATION METHODS

=head2 changeAuth()

Changes the authentication data for a authentication type.

Parameters of this method are (beyond the standard auth-strings):

=over

=item

B<type> Authentication scheme that you want to change the authentication for as textual string. Eg. "AuroraID".

=cut

=item

B<auth> The new authentication string to change to. The content and format of this string is up to the authentication type 
one is trying to change. It does, however, consist of an email address first identifying the user, followed by a comma as separator and then the new authentication.

=cut

=back

The method returns 1 upon success or 0 upon failure (see documentation of restsrvc.pl for more information on the format of 
return values in the REST-server)

=cut

=head2 doAuth()

Performs an authentication test.

No input is needed as they are supplied as part of the authentication-strings to the REST-server.

Always return 1 (as it is impossible to run the method without valid authentication).

=cut

=head2 doDeAuth()

Removes any authentication tokens that may exist.

Requires the following input: authtype and authstr.

Returns 1 upon success, 0 upon failure.

=cut

=head2 enumAuthTypes()

Enumerates the authentications types that are defined as acceptable in the REST-servers settings file and are possible to 
instantiate. In other words it return the authentication schemes that are valid for the REST-server running.

No input is needed.

The return data structure contains the authtypes substructure like thus:

authtypes => (
               "type" => ( 
                           change => INT    # 0 or 1 for possible to change (1) or not(0).
                           format => STRING # acceptable format of the authentication string
                           maxlength => INT # maximum length of the authentication string
                           regex => STRING  # regex that checks the authentication string
                           longevity => INT # the lifespan of a set of authentication details in AURORA.
                         )
               "typeN" => (
                          )
             )

Please check the documentation of the Authenticator.pm-module for more information upon the meaning of the values in the 
returned structure. Type above means the textual authentication type, such as "AuroraID".

=cut

=head2 getAuthData()

Get public authenticator data for logged in user.

No input is accepted.

The method will attempt to retrieve any public authenticator data that er stored for logged in user.

The result upon success is returned as a HASH named data:

   data => (
              AUTHDATAKEYa => STRING # value of given authetnicator data key
              .
              .
              AUTHDATAKEYz => STRING # value....
           )

The AUTHDATAKEY reflect the metadata namespace in the database where the value is stored. The metadata 
itself is stored on a USER-entity. It will also return the shared and general authentication data like 
so:

   id => INTEGER # entity ID of logged on user
   email => STRING # the email/unique username of the user
   fullname => STRING # the full name of the user
   displayname => STRING # the users display name

Please note that when it comes to the return data-HASH, which keys will appear depends upon which authenticator type the 
user used to log in with. Please see the documentation for the given Authenticator-class in question to know which 
namespaces key it stores and tags as public.

=cut
