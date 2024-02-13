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
# Authenticator::OAuthAccessToken: Class for authenticating with a OAuthAccessToken
#
package Authenticator::OAuthAccessToken;
use parent 'Authenticator';

use strict;
use ErrorAlias;
use Content::JSON;
use Net::HTTPS;
use Unicode::Escape;
use UnicodeTools;
use GroupInfo;
use GroupInfo::NTNU;

sub define {
   my $self=shift;

   # Authenticator type
   $self->{type}="OAuthAccessToken";

   # metadata location specifications with short-names to be used elsewhere in the code
   my %MD = (
              "oauthuser" => "system.authenticator.oauthaccesstoken.user",
              "grupdate"  => "system.authenticator.oauthaccesstoken.groupupdate",
            );
   $self->{MD}=\%MD;

   # namespaces structure
   my %ns=(
            $MD{"oauthuser"} => {
                                  public => 1,
                                  storable => 1,
                                },
          );
   $self->{namespaces}=\%ns;

   # constraints structure
   my @c;
   push @c,"ACCESSTOKEN";               # authstr format
   push @c,4096;                        # authstr max length
   push @c,"[A-Za-z0-9\-\._~\+\/]+=*";  # authstr acceptable chars
   push @c,(86400*365);                 # def longevity
   $self->{constraints}=\@c;

   # define this authenticators authstr as not storable
   # in other words, the result of the generate()-method is not meant to be stored in
   # the Aurora database
   $self->{storable}=0;

   return 1;
}

sub validate {
   my $self=shift;
   my $string=shift || "";

   # get AuroraDB instance
   my $db = $self->{pars}{db};

   # generate authstr and clean it at the same time
   my $gstring=$self->generate($string);

   if (defined $gstring) {
      # get MD short-names
      my $MD=$self->{MD};
      # attempt to contact endpoint to match key-field against USER-entity email
      # get settings instance
      my $cfg=$self->{pars}{cfg};
      # get host
      my $audience=$cfg->value("system.auth.oauthaccesstoken.audience") || "";
      # get host
      my $host=$cfg->value("system.auth.oauthaccesstoken.host") || "dummy.dummy.com";
      # get endpoint link
      my $endpoint=$cfg->value("system.auth.oauthaccesstoken.endpoint") || "/";
      # get name of email-field to check in endpoint - mandatory
      my @emailfield=@{($cfg->value("system.auth.oauthaccesstoken.emailfield"))[0]};
      if (@emailfield == 0) { push @emailfield,"email"; }
      # get name of name-field to check in endpoint - can be empty/not defined since it is not mandatory
      my @namefield=@{($cfg->value("system.auth.oauthaccesstoken.namefield"))[0]};
      # get username
      my @userfield=@{($cfg->value("system.auth.oauthaccesstoken.userfield"))[0]};

      # create https client instance
      my $api=Net::HTTPS->new(Host=>$host) || die $@;
      if (defined $api) {
         # successfully connected - now make get request
         my %header=(
            Authorization => "Bearer $gstring",
            charset => "UTF-8",
         );
         my $content;
         $api->write_request(GET=>$endpoint,%header);
         # get response
         my (%code,$mess,%h) = $api->read_response_headers();

         my $codes;
         foreach (keys %code) {
            # only store codes of feedback from server, not other header info
            if ($_ =~ /^\d+$/) {
               $codes.=$_." ".$code{$_}."   ";
            }
         }
   
         # read body content of return
         my $body; 
         while (1) {
            my $buf;
            my $n = $api->read_entity_body($buf, 1024);
            if (!defined $n) {
               $self->{error}="Error reading from external resource $endpoint failed ($!)!";
               $self->{errorcode}=$ErrorAlias::ERR{authvalextother};
               return 0;
            }
            last unless $n;
            $body.=$buf;
         }
         # convert any escaped unicode characters in the reply ...
         $body=Unicode::Escape::unescape($body); # ... to UTF-8 octetts, and then ...
	 utf8::decode($body);                    # ... to perl utf8 scalar
         # decode response
         my $convert=Content::JSON->new();
         if (!defined $convert->decode($body)) {
            # something failed
            $self->{error}="Internal data processing failure: failed decoding endpoint JSON response: ".$convert->error();
            $self->{errorcode}=$ErrorAlias::ERR{authvaldataproc};
            return 0;
         }

         my %response=%{$convert->get()};

         # get the audience from response
         my $audvalue=$response{audience} || "";
         # clean audience value
         $audvalue=$SysSchema::CLEAN{oauthaudience}->($audvalue);
         # ensure audience is consistent with setting - or else reject
         if (($audience eq "") || ($audvalue ne $audience)) {
            $self->{error}="Audience of endpoint is not consistent with expectations. Unable to validate";           
            $self->{errorcode}=$ErrorAlias::ERR{authvalaudience};
            return 0;
         }
         # get email from response
         my $emailvalue=recursiveGet(0,\%response,@emailfield);
         # get name from response, if setting defined
         my $namevalue;
         if (@namefield > 0) { $namevalue=recursiveGet(0,\%response,@namefield); }
         # get username from response, if defined
         my $uservalue=recursiveGet(0,\%response,@userfield);
         $uservalue=(ref($uservalue) eq "ARRAY" ? $uservalue->[0] : $uservalue);
         # remove everything before colon
         $uservalue=~s/^[^\:]+\:+(.*)$/$1/;
         $uservalue=$SysSchema::CLEAN{email}->($uservalue);

         # check if field exists
         if (defined $emailvalue) {
            # get field value
            my $email=$emailvalue;
            my $name=$namevalue;
            # clean the value from the API
            $email=$SysSchema::CLEAN{email}->($email);
            # ensure that noone is attempting to validate with localhost
            # addresses of security reasons and to shield the Zombie-accounts that are reserved
            if ($email =~ /^[^\@]+\@localhost$/i) {
               $self->{error}="Email address $email is restricted/local and you are not allowed to validate with it through this authenticator.";
               $self->{errorcode}=$ErrorAlias::ERR{authvalrestricted};
               return 0;
            }
            if (defined $name) { $name=$SysSchema::CLEAN{name}->($name); }
            # let operate in a transactional mode to make it atomic
            my $trans=$db->useDBItransaction();
            # set the metadata for the search, email is the unique identifier
            my @mdata; # use LIST so the values are or'ed together.
            push @mdata,"AND"; # must specify what to do with array, even if just one
            push @mdata,{$SysSchema::MD{"username"} => { "=" => $email }};
#            push @mdata,{$SysSchema::MD{"system.authenticator.oauthaccesstoken.user"} => { "=" => $uservalue }};
            # try to fetch entity
            my @type=($db->getEntityTypeIdByName("USER"));
            my $ids=$db->getEntityByMetadataKeyAndType(\@mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
            # we will also try to fetch entities that match the uservalue (username@domain), just in case the user exists already
            # and he/she may have changed their email address due to name changes
            @mdata=();
            push @mdata,"AND";
            push @mdata,{$MD->{oauthuser} => { "=" => $uservalue }};
            my $uids=$db->getEntityByMetadataKeyAndType(\@mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
            # we select the answer from uids if ids is empty - a fallback in case uservalue matches
            $ids=(defined $ids && @{$ids} > 0 ? $ids : $uids);
            if (defined $ids) {
               if (@{$ids} == 1) { # we must have one match, or we have inconsistencies
                  # found entity - success - do some checks and update some metadata
                  my $id=$ids->[0] || 0;   
                  # user metadata to set
                  my %user;
                  # get users metadata
                  my $umd=$db->getEntityMetadata($id);
                  if (!defined $umd) { 
                     $self->{error}="Unable to get metadata of user: ".$db->error();
                     $self->{errorcode}=$ErrorAlias::ERR{authvalgetmd};
                     return 0;
                  }
                  # but before we update, check if this is a new email-address or not?
                  if ($ids != $uids) {
                     # we matched on email username, ensure we have the same username, or else we have a conflict
                     # get oauth user
                     my $oauth=$umd->{$MD->{oauthuser}}||"";
                     if ($oauth ne $uservalue) {
                        $self->{error}="User appears to have changed his oauth username (or more likely his email address). It is a conflict with this account with a possible other account. Please contact an administrator.";
                        $self->{errorcode}=$ErrorAlias::ERR{authvalconflict};
                        return 0;
                     }
                  } else {
                     # we matched on username - update email address
                     if (defined $email) { $user{$SysSchema::MD{"username"}}=$email; }
                  }
                  # update the users last logon time
                  $user{$SysSchema::MD{"lastlogontime"}}=time();
                  if (defined $name) {
                     # fullname defined - check if it is consistent with what is stored.
                     $user{$SysSchema::MD{fullname}}=$namevalue;
                  }
                  my $grinterval=$cfg->value("system.auth.groupinfo.interval")||600; # default to every 10 minute
                  my $grupdate=((($umd->{$MD->{grupdate}}||0) + $grinterval) < time() ? 1 : 0);
                  # set new update stamp
                  $user{$MD->{grupdate}}=time();
                  # also set entity name to email and fullname (for viewing purposes)
                  my $displayname=(defined $name ? "$email ($name)" : $email);
                  $user{$SysSchema::MD{name}}=$displayname;
                  # attempt to update metadata - ignore failure
                  if (keys %user > 0) { $db->setEntityMetadata($id,\%user,undef,undef,1); }
                  
                  # only update group memberships if interval has passed
                  if ($grupdate) {
                     # also retrieve users group memberships, first get groupinfo-classes to use
                     my @classes=@{$cfg->value("system.auth.groupinfo.classes")};
                     foreach (@classes) {
                        my $class=$_;
                        my $gitype="GroupInfo::$class";
                        my $gi;
                        my $err="";
                        local $@;
                        eval { $gi=$gitype->new() || undef; };
                        $@ =~ /nefarious/;
                        $err = $@;

                        # only do something if this success, or else ignore and go to next
                        if (defined $gi) {
                           # we had success instantiating - lets retrieve groups
                           my $groups=$gi->getGroups($email) || [];
                           if (@{$groups} > 0) {
                              # we have some groups, let go through them and attempt to add user as a member
                              foreach (@{$groups}) {
                                 my $group=$_;
                                 # get group id
                                 my $gid=$gi->getGroupID($group);
                                 if (defined $id) {
                                    # attempt to locate group in AURORA
                                    my @md;
                                    push @md,"AND";
                                    push @md,{$gi->namespace() => { "=" => $gid }}; # check if groupinfo-class's namespace for id matches group id 
                                    my @type=($db->getEntityTypeIdByName("GROUP")); # we are looking for group entities
                                    my $aids=$db->getEntityByMetadataKeyAndType(\@md,undef,undef,$SysSchema::MD{"name"},undef,undef,\@type);
                                    if (defined $aids) {
                                       # we found match, check that it is the only one - multiple matches suggest conflicts
                                       # conflicts are ignored - they should be resolved elsewhere
                                       if (@{$aids} == 1) { 
                                          # lets just attempt to add user to group - the method uses replace-statements.                                        
                                          my $aid=$aids->[0] || 0;
                                          # we ignore errors in here - those must be resolved elsewhere
                                          $db->addEntityMember($aid,$id);
                                       }
                                    }
                                 }                              
                              }
                           }
                        }
                     }
                  }

                  # Return entity id
                  return $id;
               } elsif (@{$ids} > 1) {
                  # too many hits, inconsistencies in database
                  $self->{error}="Multiple ids returned for authstr. Please contact an administrator";
                  $self->{errorcode}=$ErrorAlias::ERR{authvalmultiple};
                  return 0; 
               } else {
                  # no match. Return 0 or create user?
                  my $create=$cfg->value("system.auth.oauthaccesstoken.createuser") || 0;
                  my $sorted=$cfg->value("system.auth.oauthaccesstoken.createsorted") || 0;
                  my $parent=$cfg->value("system.auth.oauthaccesstoken.userparent") || 1;
                  my $group=$cfg->value("system.auth.oauthaccesstoken.usergroup") || 0;
                  # clean
                  $create=($create =~ /^[01]{1}$/ ? $create : 0); 
                  $sorted=($sorted =~ /^[01]{1}$/ ? $sorted : 0); 
                  $parent=((($parent =~ /^\d+$/) && ($parent > 0)) ? $parent : 1);
                  $group=((($group =~ /^\d+$/) && ($group > 0)) ? $group : 0);
                  if ($create) {
                     # do some metadata updates
                     my %md;
                     $md{$SysSchema::MD{"lastlogontime"}}=time();
                     # only add name to metadata if it is defined
                     $md{$SysSchema::MD{username}}=$email;

                     if ((!defined $name) || ($name eq "")) {
                        # to create the user, the name needs to be defined
                        $self->{error}="Unable to create user. No user fullname was returned from the resource servers endpoint.";
                        $self->{errorcode}=$ErrorAlias::ERR{authvalextmissing};
                        return 0;
                     } else { 
                        # name exists, set it in the metadata
                        $md{$SysSchema::MD{fullname}}=$name;
                     }
                     if (defined $uservalue) {
                        # uservalue was located - store the value
                        $md{$MD->{oauthuser}}=$uservalue;
                     }
                     # also set entity name to email and fullname (for viewing purposes)
                     $md{$SysSchema::MD{name}}="$email ($name)";

                     # user is set to be created since we trust this api endpoint
                     # check if user creation is to be sorted or not
                     if ($sorted) {
                        # user creation is to be sorted and balanced on the tree under the given
                        # parent. Sorting is based on the first letter in the users first name.
                        my $letter=uc(map2azmath(map2az(substr($name,0,1))));
                        my $chldr=$db->getEntityChildren($parent,[$db->getEntityTypeIdByName("GROUP")],0);
                        if (!defined $chldr) {
                           $self->{error}="Unable to query database: ".$db->error();
                           $self->{errorcode}=$ErrorAlias::ERR{authvalquery};
                           return 0;
                        }
                        my $children=$db->getEntityMetadataList($SysSchema::MD{name},$chldr);
                        if (!defined $children) {
                           $self->{error}="Unable to query database: ".$db->error();
                           $self->{errorcode}=$ErrorAlias::ERR{authvalquery};
                           return 0;
                        }
                        my $found=0;
                        foreach (keys %{$children}) {
                           my $c=$_;

                           if ($children->{$c} eq $letter) { $found=$c; last; }
                        } 
                        # if 
                        if ($found) { $parent=$found; }
                        else {
                           # sub-group does not exist already - create it
                           my $grp=$db->createEntity($db->getEntityTypeIdByName("GROUP"),$parent);
                           if (!defined $grp) {
                              $self->{error}="Unable to insert data into database: ".$db->error();
                              $self->{errorcode}=$ErrorAlias::ERR{authvaldbins};
                              $trans->rollback(); 
                              return 0;
                           }
                           my %md;
                           $md{$SysSchema::MD{name}}=$letter;
                           if (!$db->setEntityMetadata($grp,\%md,undef,undef,1)) {
                              $self->{error}="Unable to insert data into database: ".$db->error();
                              $self->{errorcode}=$ErrorAlias::ERR{authvaldbins};
                              $trans->rollback();
                              return 0;
                           } else { $parent=$grp; }
                        }                       
                     }
                     my $id=$db->createEntity($db->getEntityTypeIdByName("USER"),$parent);
                     if (defined $id) {
                        # success - lets input the email metadata
                        if ($db->setEntityMetadata($id,\%md,undef,undef,1)) {
                           # the new user needs all relevant task-permissions on himself
                           my @taskperms=grep { $_ =~ /^TASK\_.*$/ } $db->enumPermTypes();
                           my $perms=$db->createBitmask($db->getPermTypeValueByName(@taskperms));
                           # set perms and check result
                           my $pres=$db->setEntityPermByObject($id,$id,$perms,undef,1);
                           if (!defined $pres) {
                              # something failed - stop the login
                              $self->{error}="Unable to insert data into database: ".$db->error(); 
                              $self->{errorcode}=$ErrorAlias::ERR{authvaldbins};
                              $trans->rollback(); # rollback all changes
                              return 0;
                           }
                           # Also enroll user as a group member if so specified
                           if ($group) {
                              # group is > 0 - attempt to enroll as member, we ignore result and allow user to login anyway
                              if ($db->getEntityTypeName($group) eq "GROUP") {
                                 # the entity specified is a group, attempt member enrollment
                                 my $res=$db->addEntityMember($group,$id);
                              }
                           }

                           # also retrieve users group memberships, first get groupinfo-classes to use
                           my @classes=@{$cfg->value("system.auth.groupinfo.classes")};
                           foreach (@classes) {
                              my $class=$_;
                              my $gitype="GroupInfo::$class";
                              my $gi;
                              my $err="";
                              local $@;
                              eval { $gi=$gitype->new() || undef; };
                              $@ =~ /nefarious/;
                              $err = $@;

                              # only do something if this success, or else ignore and go to next
                              if (defined $gi) {
                                 # we had success instantiating - lets retrieve groups
                                 my $groups=$gi->getGroups($email) || [];
                                 if (@{$groups} > 0) {
                                    # we have some groups, let go through them and attempt to add user as a member
                                    foreach (@{$groups}) {
                                       my $group=$_;
                                       # get group id
                                       my $gid=$gi->getGroupID($group);
                                       if (defined $id) {
                                          # attempt to locate group in AURORA
                                          my @md;
                                          push @md,"AND";
                                          push @md,{$gi->namespace() => { "=" => $gid }}; # check if groupinfo-class's namespace for id matches group id 
                                          my @type=($db->getEntityTypeIdByName("GROUP")); # we are looking for group entities
                                          my $aids=$db->getEntityByMetadataKeyAndType(\@md,undef,undef,$SysSchema::MD{"name"},undef,undef,\@type);
                                          if (defined $aids) {
                                             # we found match, check that it is the only one - multiple matches suggest conflicts
                                             # conflicts are ignored - they should be resolved elsewhere
                                             if (@{$aids} == 1) { 
                                                # lets just attempt to add user to group - the method uses replace-statements.                                        
                                                my $aid=$aids->[0] || 0;
                                                # we ignore errors in here - those must be resolved elsewhere
                                                $db->addEntityMember($aid,$id);
                                             }
                                          }
                                       }                              
                                    }
                                 }
                              }
                           }

                           # return id
                           return $id;
                        } else {
                           # something failed 
                           $self->{error}="Unable to insert data into database: ".$db->error();
                           $self->{errorcode}=$ErrorAlias::ERR{authvaldbins};
                           $trans->rollback(); # rollback all changes
                           return 0;
                        }
                     } else {
                        # something failed
                        $self->{error}="Unable to create user: ".$db->error();
                        $self->{errorcode}=$ErrorAlias::ERR{authvalcruser};
                        $trans->rollback(); # rollback all changes
                        return 0;
                     }
                  } else {   
                     $self->{error}="Unable to find any matching user in the system";
                     $self->{errorcode}=$ErrorAlias::ERR{authvalinvalid};
                     return 0;
                  }
               }
            } else {
               # some other failure
               $self->{error}=$db->error();
               return 0;
            }
         } else {
            $self->{error}="Endpoint data for field @emailfield is missing in response from endpoint server $endpoint";
            $self->{errorcode}=$ErrorAlias::ERR{authvalextmisseml};
            return 0;
         }
      } else {
         # could not connect to api
         $self->{error}="Unable to connect to endpoint $endpoint";
         $self->{errorcode}=$ErrorAlias::ERR{authvalextconnect};
         return 0;
      }
   } else {
      # something went wrong generating authstr - error already set
      return 0;
   }

   # we never get to here...
}

sub generate {
   my $self=shift;
   my $string=shift;

   my $check=($self->constraints())[2];
   my $qcheck=qq($check);

   # check string, that it is of correct OAuth access token format
   if ($string =~ /^$check$/) {
      my $token=$string || "";

      # cut token to max length - no length specified in RFC, but keep it under 4K
      $token=substr($token,0,4096);

      # return result
      return $token;
   } else {
      $self->{error}="Input string is of wrong format. Format is supposed to be: ".($self->constraints())[0]."(".($self->constraints())[2]."). Cannot generate authstr from this.";
      $self->{errorcode}=$ErrorAlias::ERR{authvalformat};

      return undef;
   }   
}

# get email based upon
# Oauth token
sub email {
   my $self=shift;
   my $authstr=shift;

   my $cauth=$self->generate($authstr);

   if (defined $cauth) {
      # get MD short-names
      my $MD=$self->{MD};
      # attempt to contact endpoint to match key-field against USER-entity email
      # get settings instance
      my $cfg=$self->{pars}{cfg};
      # get host
      my $audience=$cfg->value("system.auth.oauthaccesstoken.audience") || "";
      # get host
      my $host=$cfg->value("system.auth.oauthaccesstoken.host") || "dummy.dummy.com";
      # get endpoint link
      my $endpoint=$cfg->value("system.auth.oauthaccesstoken.endpoint") || "/";
      # get name of email-field to check in endpoint - mandatory
      my @emailfield=@{($cfg->value("system.auth.oauthaccesstoken.emailfield"))[0]};
      if (@emailfield == 0) { push @emailfield,"email"; }
      # get name of name-field to check in endpoint - can be empty/not defined since it is not mandatory
      my @namefield=@{($cfg->value("system.auth.oauthaccesstoken.namefield"))[0]};
      # get username
      my @userfield=@{($cfg->value("system.auth.oauthaccesstoken.userfield"))[0]};

      # create https client instance
      my $api=Net::HTTPS->new(Host=>$host) || die $@;
      if (defined $api) {
         # successfully connected - now make get request
         my %header=(
            Authorization => "Bearer $cauth",
            charset => "UTF-8",
         );
         my $content;
         $api->write_request(GET=>$endpoint,%header);
         # get response
         my (%code,$mess,%h) = $api->read_response_headers();

         my $codes;
         foreach (keys %code) {
            # only store codes of feedback from server, not other header info
            if ($_ =~ /^\d+$/) {
               $codes.=$_." ".$code{$_}."   ";
            }
         }
   
         # read body content of return
         my $body; 
         while (1) {
            my $buf;
            my $n = $api->read_entity_body($buf, 1024);
            if (!defined $n) {
               $self->{error}="Error reading from external resource $endpoint failed ($!)!";
               $self->{errorcode}=$ErrorAlias::ERR{authvalextother};
               return undef;
            }
            last unless $n;
            $body.=$buf;
         }
         # convert any escaped unicode characters in the reply ...
         $body=Unicode::Escape::unescape($body); # ... to UTF-8 octetts, and then ...
	 utf8::decode($body);                    # ... to perl utf8 scalar
         # decode response
         my $convert=Content::JSON->new();
         if (!defined $convert->decode($body)) {
            # something failed
            $self->{error}="Internal data processing failure: failed decoding endpoint JSON response: ".$convert->error();
            $self->{errorcode}=$ErrorAlias::ERR{authvaldataproc};
            return undef;
         }

         my %response=%{$convert->get()};

         # get the audience from response
         my $audvalue=$response{audience} || "";
         # clean audience value
         $audvalue=$SysSchema::CLEAN{oauthaudience}->($audvalue);
         # ensure audience is consistent with setting - or else reject
         if (($audience eq "") || ($audvalue ne $audience)) {
            $self->{error}="Audience of endpoint is not consistent with expectations. Unable to validate";           
            $self->{errorcode}=$ErrorAlias::ERR{authvalaudience};
            return undef;
         }
         # get email from response
         my $emailvalue=recursiveGet(0,\%response,@emailfield);

         return $emailvalue;
      } else {
         # could not connect to api
         $self->{error}="Unable to connect to endpoint $endpoint";
         $self->{errorcode}=$ErrorAlias::ERR{authvalextconnect};
         return undef;
      }
   } else {
      # email not known, failed to generate authstr
      return undef;
   }
}

sub id {
   my $self=shift;
   my $string=shift || "";

   # get AuroraDB instance
   my $db = $self->{pars}{db};

   # generate authstr and clean it at the same time
   my $gstring=$self->generate($string);

   if (defined $gstring) {
      # get MD short-names
      my $MD=$self->{MD};
      # attempt to contact endpoint to match key-field against USER-entity email
      # get settings instance
      my $cfg=$self->{pars}{cfg};
      # get host
      my $audience=$cfg->value("system.auth.oauthaccesstoken.audience") || "";
      # get host
      my $host=$cfg->value("system.auth.oauthaccesstoken.host") || "dummy.dummy.com";
      # get endpoint link
      my $endpoint=$cfg->value("system.auth.oauthaccesstoken.endpoint") || "/";
      # get name of email-field to check in endpoint - mandatory
      my @emailfield=@{($cfg->value("system.auth.oauthaccesstoken.emailfield"))[0]};
      if (@emailfield == 0) { push @emailfield,"email"; }
      # get name of name-field to check in endpoint - can be empty/not defined since it is not mandatory
      my @namefield=@{($cfg->value("system.auth.oauthaccesstoken.namefield"))[0]};
      # get username
      my @userfield=@{($cfg->value("system.auth.oauthaccesstoken.userfield"))[0]};

      # create https client instance
      my $api=Net::HTTPS->new(Host=>$host) || die $@;
      if (defined $api) {
         # successfully connected - now make get request
         my %header=(
            Authorization => "Bearer $gstring",
            charset => "UTF-8",
         );
         my $content;
         $api->write_request(GET=>$endpoint,%header);
         # get response
         my (%code,$mess,%h) = $api->read_response_headers();

         my $codes;
         foreach (keys %code) {
            # only store codes of feedback from server, not other header info
            if ($_ =~ /^\d+$/) {
               $codes.=$_." ".$code{$_}."   ";
            }
         }
   
         # read body content of return
         my $body; 
         while (1) {
            my $buf;
            my $n = $api->read_entity_body($buf, 1024);
            if (!defined $n) {
               $self->{error}="Error reading from external resource $endpoint failed ($!)!";
               $self->{errorcode}=$ErrorAlias::ERR{authvalextother};
               return 0;
            }
            last unless $n;
            $body.=$buf;
         }
         # convert any escaped unicode characters in the reply ...
         $body=Unicode::Escape::unescape($body); # ... to UTF-8 octetts, and then ...
	 utf8::decode($body);                    # ... to perl utf8 scalar
         # decode response
         my $convert=Content::JSON->new();
         if (!defined $convert->decode($body)) {
            # something failed
            $self->{error}="Internal data processing failure: failed decoding endpoint JSON response: ".$convert->error();
            $self->{errorcode}=$ErrorAlias::ERR{authvaldataproc};
            return 0;
         }

         my %response=%{$convert->get()};

         # get the audience from response
         my $audvalue=$response{audience} || "";
         # clean audience value
         $audvalue=$SysSchema::CLEAN{oauthaudience}->($audvalue);
         # ensure audience is consistent with setting - or else reject
         if (($audience eq "") || ($audvalue ne $audience)) {
            $self->{error}="Audience of endpoint is not consistent with expectations. Unable to validate";           
            $self->{errorcode}=$ErrorAlias::ERR{authvalaudience};
            return 0;
         }
         # get email from response
         my $emailvalue=recursiveGet(0,\%response,@emailfield);
         # get name from response, if setting defined
         my $namevalue;
         if (@namefield > 0) { $namevalue=recursiveGet(0,\%response,@namefield); }
         # get username from response, if defined
         my $uservalue=recursiveGet(0,\%response,@userfield);
         $uservalue=(ref($uservalue) eq "ARRAY" ? $uservalue->[0] : $uservalue);
         # remove everything before colon
         $uservalue=~s/^[^\:]+\:+(.*)$/$1/;
         $uservalue=$SysSchema::CLEAN{email}->($uservalue);

         # check if field exists
         if (defined $emailvalue) {
            # get field value
            my $email=$emailvalue;
            my $name=$namevalue;
            # clean the value from the API
            $email=$SysSchema::CLEAN{email}->($email);
            # ensure that noone is attempting to validate with localhost
            # addresses of security reasons and to shield the Zombie-accounts that are reserved
            if ($email =~ /^[^\@]+\@localhost$/i) {
               $self->{error}="Email address $email is restricted/local and you are not allowed to validate with it through this authenticator.";
               $self->{errorcode}=$ErrorAlias::ERR{authvalrestricted};
               return 0;
            }
            if (defined $name) { $name=$SysSchema::CLEAN{name}->($name); }
            # let operate in a transactional mode to make it atomic
            my $trans=$db->useDBItransaction();
            # set the metadata for the search, email is the unique identifier
            my @mdata; # use LIST so the values are or'ed together.
            push @mdata,"AND"; # must specify what to do with array, even if just one
            push @mdata,{$SysSchema::MD{"username"} => { "=" => $email }};
            # try to fetch entity
            my @type=($db->getEntityTypeIdByName("USER"));
            my $ids=$db->getEntityByMetadataKeyAndType(\@mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
            # we will also try to fetch entities that match the uservalue (username@domain), just in case the user exists already
            # and he/she may have changed their email address due to name changes
            @mdata=();
            push @mdata,"AND";
            push @mdata,{$MD->{oauthuser} => { "=" => $uservalue }};
            my $uids=$db->getEntityByMetadataKeyAndType(\@mdata,undef,undef,$SysSchema::MD{"username"},undef,undef,\@type);
            # we select the answer from uids if ids is empty - a fallback in case uservalue matches
            $ids=(defined $ids && @{$ids} > 0 ? $ids : $uids);
            if (defined $ids) {
               if (@{$ids} == 1) { # we must have one match, or we have inconsistencies
                  # found entity - success 
                  my $id=$ids->[0] || 0;   

                  # Return entity id
                  return $id;
               } elsif (@{$ids} > 1) {
                  # too many hits, inconsistencies in database
                  $self->{error}="Multiple ids returned for authstr. Please contact an administrator";
                  $self->{errorcode}=$ErrorAlias::ERR{authvalmultiple};
                  return 0; 
               } else {
                  # no match. 
                  $self->{error}="Unable to find any matching user in the system";
                  $self->{errorcode}=$ErrorAlias::ERR{authvalinvalid};
                  return 0;
               }
            } else {
               # some other failure
               $self->{error}=$db->error();
               return 0;
            }
         } else {
            $self->{error}="Endpoint data for field @emailfield is missing in response from endpoint server $endpoint";
            $self->{errorcode}=$ErrorAlias::ERR{authvalextmisseml};
            return 0;
         }
      } else {
         # could not connect to api
         $self->{error}="Unable to connect to endpoint $endpoint";
         $self->{errorcode}=$ErrorAlias::ERR{authvalextconnect};
         return 0;
      }
   } else {
      # something went wrong generating authstr - error already set
      return 0;
   }
}

# internal method not to be called
# outside class
sub recursiveGet {
   my $no=shift || 0;
   my $h=shift || undef;
   my @arr=@_;
 
   if (exists $arr[$no+1]) {
      if (exists $h->{$arr[$no]}{$arr[$no+1]}) {
         return recursiveGet($no+1,$h->{$arr[$no]}{$arr[$no+1]},@arr);
      } else { return undef; }
   } else {
      return $h || undef;
   }
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Authenticator::OAuthAccessToken> - Class to handle authentication of AURORA REST-server by trusting a OAuth-servers access token.

=head1 SYNOPSIS

It follows the same use as the Authenticator-class. See the Authenticator placeholder class for more information.

=head1 DESCRIPTION

A class that inherits from the Authenticator placeholder class. Please see there for more information.

=head1 CONSTRUCTOR

See the Authenticator placeholder class for more information.

=head1 METHODS

=head2 define()

See description in the placeholder Authenticator-class.

=cut

=head2 validate()

Validates to the AURORA REST-server by using an OAuth access token. The access token is passed to the generate()-method for
checking of the formatting.

There are certain settings from the settings-file that the Settings-instance delivers and the method expects or takes the following options:

=over

=item

B<system.auth.oauthaccesstoken.audience> OAuth audience ID that are defined by the resource server. See RFC6749 for details on the OAuth flow. Required.

=cut

=item

B<system.auth.oauthaccesstoken.host> Host name of the OAuth resource server (see RFC6749). Required.

=cut

=item

B<system.auth.oauthaccesstoken.endpoint> Endpoint URL on the resource server where the user information can be fetched by using the access token. Required.

=cut

=item

B<system.auth.oauthaccesstoken.emailfield> Name of the key in the returned endpoint HASH that identifies the users email address. It is of type LIST and can therefore facilitate addressing sub-keys of a HASH. Required, but will default to ["email"].

=cut

=item

B<system.auth.oauthaccesstoken.namefield> Name of the key in the returned endpoint HASH that identifies the users full name. It is of type LIST and can therefore facilitate addressing sub-keys of a HASH. Required.

=cut

=item

B<system.auth.oauthaccesstoken.userfield> Name of the key in the returned endpoint HASH that identifies the users username. It is of type LIST and can therefore facilitate addressing sub-keys of a HASH. Required.

=cut

=item

B<system.auth.oauthaccesstoken.createuser> If the user is not found the AURORA database the module can create the account. This settings tells the module if it is ok to create the account in such an instance. Optional, will default to 0. Set to 1 to create account.

=cut

=item

B<system.auth.oauthaccesstoken.createsorted> Sets if the possible creation of a user account sorts the results in sub-keys based on the first letter in the accounts name. Optional. Valid values are 0 (disabled), 1 (enabled). When not set it defaults to 0.

=cut

=item

B<system.auth.oauthaccesstoken.userparent> If the user is to be created in instances where it does not exist in the AURORA database, this setting tell the module which entity id in the AURORA database is the parent of such an user-account. It is optional and will default to 1 (the root entity).

=cut

=item

B<system.auth.oauthaccesstoken.usergroup> If the user is to be created in instances where it does not exist in the AURORA database, this setting tell the module which group id the user should be added as a member of. It is optional and will default to not adding the user to any group if it is undefined, 0 or lower.

=cut

=back

It calls the generate()-method on the authentication string (access token) and upon successful checking and cleaning, 
will use the access token to connect to the resource server to get the users email- and name details. These details will be
checked in the AURORA database to see if there are any matches? Upon successful match, the entity id of the user will be returned (userid). 

If the user cannot be found in the AURORA database, it checks if it is allowed to create the user (see options above)? 
If it is allowed to create the user, it will to so in the AURORA database and set the email and then return the entity id of
the newly created user as the userid.

It returns the AURORA database userid (entity id - int) of the user upon success or 0 upon user not found.

Undef is returned upon failure. Check the error()-method for more information.

See description in the placeholder Authenticator-class for more information on the framework itself.

=cut

=head2 generate()

Takes the authentication string (in this case OAuth access token) and checks the validity of the characters and cuts the length
at a maximum of 4096 characters.

Returns the cleaned and accepted access token upon success.

Undef is returned upon failure. In such a case check the error()-method for more information.

See description in the placeholder Authenticator-class for more information on the framework itself.

=cut

