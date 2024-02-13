#!/usr/bin/perl -w
# Copyright (C) 2019-2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
# Copyright (C) 2019-2024 Bård Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway
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
# RestTools: module with utility functions for the AURORA REST-server
#
package RestTools;
use strict;
use POSIX;
use Exporter 'import';

our @EXPORT = qw(_get_params _with_error _with_success arrayToFlags arrayToPerm flagsToArray getEntityTask getInvalidFlagArrayElements getInvalidPermArrayElements hasPerm mergeMetadata permToArray listFolders recurseListing);

sub listFolders {
   my $path=shift||"/dev/null";
   # get if we are to recurse down the folders or not, default is true/1.
   my $recursive=shift;
   $recursive=(defined $recursive ? ($recursive ? 1 : 0) : 1);
   # are we to md5 sum the files or not? default is true/1
   my $md5sum=shift;
   $md5sum=(defined $md5sum ? ($md5sum ? 1 : 0) : 1);
   # are we to tag data as utf8?
   my $tag=shift;
   $tag=(defined $tag ? ($tag ? 1 : 0) : 1);

   sub listFolder {
      my $folder=shift; # folder to list
      my $struct=shift; # structure to put it in
      my $recursive=shift; # recurse into sub-folders?
      my $md5sum=shift; # md5-sum files?
      my $tag=shift; # tag folder and file names?

      if (opendir (DH,$folder)) {
         my @items=grep { $_ !~ /^[\.]{1,2}$/ } readdir (DH);
         closedir (DH);
         # go through each item and stat a little bit
         foreach (@items) {
            my $item=$_;
            # make a copy for possible decoding purposes
            my $titem=$item;
            # utf8 decode or not?
            if ($tag) { utf8::decode($titem); }

            my @stat=stat("$folder/$item");

            if (S_ISDIR($stat[2])) {
               # folder - add
               $struct->{$titem}{"."}{name}=$titem;
               $struct->{$titem}{"."}{type}="D";
               $struct->{$titem}{"."}{size}=$stat[7];
               $struct->{$titem}{"."}{atime}=$stat[8];
               $struct->{$titem}{"."}{mtime}=$stat[9];
               # recurse into folder itself if so chosen
               if ($recursive) { listFolder ("$folder/$item",$struct->{$titem},$recursive,$md5sum,$tag); }
               next;
            } elsif (S_ISREG($stat[2])) {
               # file - check if we are to md5sum it
               my $md5;
               if ($md5sum) {
                  if (open (my $fh, '<',"$folder/$item")) {
                     binmode ($fh);
                     # eval the process so that if it croaks it
                     # doesnt kill the caller as well

                     my $err;
                     local $@;
                     eval { $md5=Digest::MD5->new->addfile($fh)->hexdigest(); };
                     $@ =~ /nefarious/;
                     $err = $@;
                     if ($err ne "") {
                        # some error while md5 summing
                        $md5="N/A: $err";
                     }
                     eval { close ($fh); };
                  } else {
                     # failed to open file - save error
                     $md5="N/A: $!";
                  }
               }

               # add
               $struct->{$titem}{"."}{name}=$titem;
               $struct->{$titem}{"."}{type}="F";
               $struct->{$titem}{"."}{size}=$stat[7];
               $struct->{$titem}{"."}{mtime}=$stat[9];
               $struct->{$titem}{"."}{ctime}=$stat[10];
               $struct->{$titem}{"."}{md5}=$md5;
               next;
            }
         }
         return;
      } else {
         return;
      }
   }

   # get structure
   my %struct;
   listFolder ($path,\%struct,$recursive,$md5sum,$tag);

   return \%struct;
}

sub recurseListing {
   my $listing=shift; # returned result from listDatasets
   my $nlisting=shift; # new list
   my $path=shift || ""; # preceeding path

   # go through each listing on this hash-level sorted
   foreach (sort {$a cmp $b} keys %{$listing}) {
      my $item=$_;

      if ($item eq ".") { next; } # we are not interested in the folder listing itself

      if ($listing->{$item}{"."}{type} eq "F") {
         # this is a file
         my $size=$listing->{$item}{"."}{size};
         my $time=strftime("%Y/%m/%d-%H:%M:%S",gmtime($listing->{$item}{"."}{mtime}));
         my $md5=$listing->{$item}{"."}{md5};
         # add to list with same format as with rsync Store-class.
         # difference is that this is local checksumming and not of the remote original
         push @{$nlisting},"($size)()($time)($md5) $path/$item";
      } elsif ($listing->{$item}{"."}{type} eq "D") {
         # this is a folder - store info into a list
         push @{$nlisting},"$path/$item";
         # recurse into folder
         recurseListing($listing->{$item},$nlisting,"$path/$item");
      }
   }
}

sub mergeMetadata {
   my $db=shift;
   my $entitytype=shift || "DATASET";
   my $notemplate=shift || 0; # include template metadata by default
   my $noentity=shift || 0; # include entity metadata by default
   my @entities=@_; # entities in precedence order, next has precedence over previous

   # go through each entity and aggregate metadata
   my %md;
   foreach (@entities) {
      my $entity=$_;

      # first get template
      my ($templ,$mdata);
      if (!$notemplate) { $templ=$db->getEntityTemplate($db->getEntityTypeIdByName($entitytype),$entity); }
      if (!$noentity) { $mdata=$db->getEntityMetadata($entity); }
      if ((defined $mdata) || (defined $templ)) {
         # add latest metadata to hash, overwriting potential old values (precedence of last entity)
         # first template
         foreach (keys %{$templ}) {
            my $key=$_;
            $md{$key}=$templ->{$key}{default};
         }
         # then metadata
         foreach (keys %{$mdata}) {
            my $key=$_;
            $md{$key}=$mdata->{$key};
         }
      }
   }

   # return result
   return \%md;
}

# checks if subject has given perms on object (with moderators)
# pop-parameter decides what logical operator is applied between each permission in perms-parameter.
# oop-parameter decides what logical operator is applied between the various object levels (inherit, grant, deny and effective)
# effective, inherit, deny and grant can all be set to 0 (must not have permission), 1 (must have permission), undef (we dont care)
# Return 0 for false, 1 for true, undef for any failure (please check $db->error().
# Please also note that if one inputs logically bizarre conditions like undef in all four levels, while asking for
# oop-parameter "ALL", the result evaluates to true (it is true that we do not care for any of the four levels).
# if no perms specified, the method return 1 (true), because there is nothing to evaluate.
sub hasPerm {
   my $db=shift;
   my $subject=shift; # entity that has potential perms
   my $object=shift; # entity that perms are checked on
   my $perms=shift; # perms to check for - ARRAY of SCALAR/STRING
   my $pop=shift; # perm operation (ANY/ALL)
   my $oop=shift; # object operation (ANY/ALL)
   my $effective=shift; # must have perms effective 0/1/undef
   my $inherit=shift; # must have perms on inheritance? 0/1/undef
   my $deny=shift; # must have perms on non-inherit deny 0/1/undef
   my $grant=shift; # must have perms on non-inherit grant 0/1/undef

   # cleaning
   $subject=$Schema::CLEAN{entity}->($subject);
   $object=$Schema::CLEAN{entity}->($object);
   $pop=$Schema::CLEAN{permtype}->($pop);
   $oop=$Schema::CLEAN{permtype}->($oop);
   $effective=$SysSchema::CLEAN{permmatch}->($effective);
   $inherit=$SysSchema::CLEAN{permmatch}->($inherit); 
   $deny=$SysSchema::CLEAN{permmatch}->($deny);
   $grant=$SysSchema::CLEAN{permmatch}->($grant); 

   if ((!defined $perms) || (ref($perms) ne "ARRAY")) { return undef; }

   # if no perms defined, we return true (nothing to evaluate)
   if (@{$perms} == 0) { return 1; }

   # now, make mask of permissions that we want to match
   my $want=arrayToPerm($db,$perms);

   # lets get some permissions on the object and the parent of the object.
   # only get permission for the levels, if we ask for it (optimalization)
   my $effmask;
   if (defined $effective) { $effmask=$db->getEntityPerm($subject,$object); if (!defined $effmask) { return undef; } }
   my ($grmask,$dnmask);
   # only run getEntityPermByObject if necessary
   if ((defined $grant) || (defined $deny)) {
      my $mask=$db->getEntityPermByObject($subject,$object);
      if (!defined $mask) { return undef; }
      ($grmask,$dnmask)=@{$mask};
   }
   $grmask=$grmask || "";
   $dnmask=$dnmask || "";
   my $inhmask;
   if (defined $inherit) { $inhmask=$db->getEntityPerm($subject,$db->getEntityParent($object)); if (!defined $inhmask) { return undef; } }

   # initialize has-vars (if we match input-criteria).
   my ($haseff,$hasinh,$hasdn,$hasgr)=(0,0,0,0); 
   # see if we have some matches
   if (defined $effective) {
      # lets check if we have given perms effective
      if ($pop eq "ALL") { if (($effmask & $want) eq $want) { $haseff=($effective && 1); } elsif ($effective == 0) { $haseff=1; } }
      if ($pop eq "ANY") { if (($effmask & $want) !~ /\A\000*\z/) { $haseff=($effective && 1); } elsif ($effective == 0) { $haseff=1; } } 
   } else { $haseff=1; } # undef always matches, but are ignored if level is not asked for
   if (defined $inherit) {
      # lets check if we have given perms inherited
      if ($pop eq "ALL") { if (($inhmask & $want) eq $want) { $hasinh=($inherit && 1); } elsif ($inherit == 0) { $hasinh=1; } }
      if ($pop eq "ANY") { if (($inhmask & $want) !~ /\A\000*\z/) { $hasinh=($inherit && 1); } elsif ($inherit == 0) { $hasinh=1; } }
   } else { $hasinh=1; } # undef
   if (defined $deny) {
      # lets check if we have given perms deny
      if ($pop eq "ALL") { if (($dnmask & $want) eq $want) { $hasdn=($deny && 1); } elsif ($deny == 0) { $hasdn=1; } }
      if ($pop eq "ANY") { if (($dnmask & $want) !~ /\A\000*\z/) { $hasdn=($deny && 1); } elsif ($deny == 0) { $hasdn=1; } }
   } else { $hasdn=1; } # undef
   if (defined $grant) {
     # lets check if we have given perms grant
      if ($pop eq "ALL") { if (($grmask & $want) eq $want) { $hasgr=($grant && 1); } elsif ($grant == 0) { $hasgr=1; } }
      if ($pop eq "ANY") { if (($grmask & $want) !~ /\A\000*\z/) { $hasgr=($grant && 1); } elsif ($grant == 0) { $hasgr=1; } }
   } else { $hasgr=1; } # undef

   # return result of logical operation
   if ($oop eq "ANY") { 
      my $ret=0;
      $ret=($haseff || $ret) if defined $effective;
      $ret=($hasinh || $ret) if defined $inherit;
      $ret=($hasdn || $ret) if defined $deny;
      $ret=($hasgr || $ret) if defined $grant;

      return $ret;
   } else { 
      my $ret=1; # this will only evaluate till true if all defined levels are true. If no levels
                 # have been asked for - we are also true (so beware)
      $ret=($haseff && $ret) if defined $effective;
      $ret=($hasinh && $ret) if defined $inherit;
      $ret=($hasdn && $ret) if defined $deny;
      $ret=($hasgr && $ret) if defined $grant;

      return $ret;
   }
}

sub getInvalidPermArrayElements {
   my $db=shift;
   my $array=shift;

   my @invperms;
   foreach (@{$array}) {
      my $name=$_;

      if (!$db->getPermTypeValueByName($name)) {
         # invalid perm name
         push @invperms,$name;
      }
   }

   # return invalid perm elements
   return \@invperms;
}

sub permToArray {
   my $db = shift;
   my $mask = shift;
  
   my @perms=$db->getPermTypeNameByValue($db->deconstructBitmask($mask));

   if (!defined $perms[0]) { @perms=(); }

   return \@perms;
}

sub arrayToPerm {
   my $db = shift;
   my $array = shift;

   # go through each string element in array
   my $perm=$db->createBitmask($db->getPermTypeValueByName (@{$array}));

   if (!defined $perm) { $perm=''; }

   return $perm;
}

sub getInvalidFlagArrayElements {
   my $db=shift;
   my $array=shift;

   my @invflags;
   foreach (@{$array}) {
      my $name=$_;

      if (!$db->getTemplateFlagBitByName($name)) {
         # invalid flag name
         push @invflags,$name;
      }
   }

   # return invalid flag elements
   return \@invflags;
}

sub flagsToArray {
   my $db=shift;
   my $flags=shift;

   my @array=$db->getTemplateFlagNameByBit($db->deconstructBitmask($flags));

   return \@array;
}

sub arrayToFlags {
   my $db = shift;
   my $array = shift;

   my $flags;
   if ((defined $array) && (ref($array) eq "ARRAY") && (@{$array} > 0)) {
      $flags=$db->createBitmask($db->getTemplateFlagBitByName(@{$array}));
   }

   return $flags;
}

# Rest interface shortcuts
#
sub _get_params { # Extract and clean parameters from query hash
    # usage:
    #   my ($param1, $param2, ...) = _get_params( $query,
    #      param1 => [$Schema::CLEAN{entity}],
    #      param2 => [<cleaner>, <optional parameters, ...>],
    #         :
    #      );
    my $query = shift;  # Hash of supplied param values 
    my @params = ();    # List of return values
    while (@_) {                      # While params left...
        my $param = shift;            #   get the wantet param name
        my $schema = shift;           #     and schema list
        my $value = $$query{$param};  #   Map value from query
        if (defined $value) {                                 # If value is defined
            my ($cleaner, @constraints) = @$schema;           #   dissect the schema list
            push (@params, $cleaner->($value, @constraints)); #   add the cleaned value to the result list
        }                                                     #
        else {                                                # else
            push (@params, $value);                           #   add the undefined value
        }
    }
    return @params;
}

sub _with_error { # Prepare content hash for a bailout
    my $content = shift;
    my $reason = shift;
    $content->value("errstr", $reason);
    $content->value("err",1);
    return 0;
}

sub _with_success { # Prepare content hash for a sucsessfull return
    my $content = shift;
    $content->value("errstr","");
    $content->value("err",0);
    return 1;
}

# get an entitys (computer, group or user) task
# by going up the entity tree
sub getEntityTask {
   my $db=shift;
   my $id=shift; # start entity

   # check that id is valid
   if ((!$db->existsEntity($id)) || (($db->getEntityType($id) != ($db->getEntityTypeIdByName("COMPUTER"))[0]) &&
                                     ($db->getEntityType($id) != ($db->getEntityTypeIdByName("GROUP"))[0]) &&
                                     ($db->getEntityType($id) != ($db->getEntityTypeIdByName("USER"))[0]))) {
      return 0;
   }

   # entity is valid, lets get its ancestors
   my @path=$db->getEntityPath($id);

   if (defined $path[0]) {
      # we have a path, lets go through it and find a tasks, start at the bottom and go up
      my $task=0; # set invalid task in case we find none
      foreach (reverse @path) {
         my $ent=$_;

         # check if entity has any tasks
         my $children=$db->getEntityChildren($ent,[$db->getEntityTypeIdByName("TASK")]);
         if (defined $children) {
            # if we have one or more hits?
            if (@{$children} > 1) {
               # get the name of all children
               my $names=$db->getEntityMetadataList($SysSchema::MD{name},$children);
               # go through tasks alphabetically
               foreach (sort {$a->{$_} cmp $b->{$_}} @{$names}) {
                  # select first hit
                  $task=$_;
                  last;
              }
              # ensure that we have a hit in case of
              # missing task name
              if ($task) { last; }
            } elsif (@{$children} == 1) {
               # we only have one hit, use that one
               $task=$children->[0];
               last;
            }
            # if here, no tasks, so continue
            next;
         } else {
            # something failed
            return 0;
         }
      }
 
      # return the task found, if any.
      return $task;
   } else {
      # something failed
      return 0;
   }
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<RestTools> Module with shared, general utility/tool methods for the AURORA REST-server

=cut

=head1 SYNOPSIS

   use RestTools;

   # merge metadata with same keys from several entity sources
   my $md=mergeMetadata($db,"DATASET",0,0,@my_entities);

   # check if a subject has given permissions on an entity object (all permissions, on any level).
   # we ask for levels: effective, inherit and grant.
   my $ok=hasPerm($db,$subject,$object,["DATASET_CREATE","DATASET_DELETE"],"ALL","ANY",1,1,undef,1);

   # get invalid textual permissions in list
   my $invalid=getInvalidPermArrayElements($db,["DATASET_BLIPP","DATASET_CREATE"]);

   # deconstruct a bitmask into its textual permission names and deliver as an array
   my $perms=permToArray($db,$mask)

   # create a bitmask based on a list-reference of permission names
   my $mask=arrayToPerm($db,$perms);

   # get invalid textual flag names returned as a list-reference
   my $invalid=getInvalidFlagArrayElements($db,["OMIT","BLIPPBLAPP","MANDATORI"]);

   # convert flag bitmask into its textual flag names and deliver as an array
   my $flags=flagsToArray($db,$flagmask);

   # convert textual flag names into a flag bitmask
   my $flagmask=arrayToFlags($db,["OMIT","MANDATORY"]);

   # extract and clean parameters from query hash
   my ($id, $token, $expire) = _get_params( $query, 
        id     => [$Schema::CLEAN{entity}],          
        token  => [$SysSchema::CLEAN{token}], 
        expire => [$Schema::CLEAN_GLOBAL{trueint}],
        );

   # return an error message 
   my $result=_with_error($content, "User does not have the $required permission on the dataset $id. Unable to fulfill request.")

   # return a success message
   my $return=_with_success($content);

   # get closest task of an entity
   my $task=getEntityTask($db,$entity);

=cut

=head1 DESCRIPTION

Collection of general utility/tool functions used by the REST-server. All functions are exported and can be used 
directly in the namespace of the code that uses it.

=cut

=head1 METHODS

=head2 _get_params()

Extract and clean parameters from query hash

Input parameters:

=over

=item

B<query> HASH-reference to values that are to be cleaned. This refers to the query-HASH that are delivered automatically to all 
REST-server methods in AURORA.

=cut

=item

B<params> A list of parameters and their cleaning function. One can deliver 1-N number of these parameters in the list as a list 
of key->value assignments (HASH) where the value is a LIST-reference, eg: my_param_name => [$Schema::CLEAN{entity}]. Any value in the 
LIST-reference after the cleaning function is optional parameters to the cleaning function.

=cut

=back

Returns a LIST of cleaned parameters in return in the same order as they were delivered to the function.

It is useful to assign the LIST to single parameters right away, like so:

my ($my_param1,$my_param2) = _get_param($query,my_param1=>[Schema::CLEAN{entity}],my_param2=>[Schema::CLEAN{entitytype}]);

=cut

=head2 _with_error()

Returns a correctly formatted error message for the AURORA REST-server.

Accepts input in the following order: content,reason. Content is a HASH-reference to the hash that will contain the 
error-message and its values. Reason is the textual reason given for the error that just happened.

Always returns 0

=cut

=head2 _with_success()

Returns a correctly formatted success message for the AURORA REST-server.

Accepts input in the following order: content. Content is the HASH-reference to the hash that will contain the 
success-message and its values.

Always returns 1

=cut

=head2 arrayToFlags()

Converts a textual array of flag names into its bitmask

Accepts the following input in this order:  db, array. Db is the reference to the AuroraDB-instance used by the 
REST-server. Array is a LIST-reference to the textual flag names that are to be converted into a bitmask (as if all 
the flag names are set in the bitmask).

Returns a bitmask.

=cut

=head2 arrayToPerm()

Convert a textual array of permission names into its bitmask.

Accepts the following input in this order: db, array. Db is the reference to the AuroraDB-instance used by the REST-server. 
Array is the LIST-reference to the textual permission names that are to be converted into a bitmask (as if all the 
permission names are set in the bitmask).

Returns a bitmask.

=cut

=head2 flagsToArray()

Convert flag bitmask into its textual flag names

Accepts the following input in this order: db, bitmask. Db is the reference to the AuroraDB-instance used by the REST-server. 
Bitmask is the bitmask of flags that are to be converted to its textual counterpart.

Returns a LIST-reference of the textual flags names that have been set in the bitmask.

=cut

=head2 getEntityTask()

Get closest task on an entity in the entity tree.

This method accepts this input in the following order: db, id. Db is the reference to the AuroraDB-instance used 
by the REST-server. Id is the entity ID from the AURORA database that one wants to get the task of (if any defined). 

This method will search from the entity ID specified in id and up the tree to find the closest matching task. If several 
tasks are defined in the same place in the entity tree, it will select the one that comes first alphabetically on 
display name of the task entity.

Returns the task ID or 0 if not anyone found or something failed.

=cut

=head2 getInvalidFlagArrayElements()

Returns the textual flag names in the array that are not valid names for flags.

Accepts the following input in this order: db, array. Db is the reference to the AuroraDB-instance used by the REST-server. Array 
is the LIST-reference to the list of textual flag names to check for possible invalid items.

Returns a LIST-reference to the flag names that were invalid (if any). If none were invalid, the returned array is empty.

=cut

=head2 getInvalidPermArrayElements()

Returns the textual permission names in the array that are not valid names for permissions.

Accepts the following input in this order: db, array. Db is the reference to the AuroraDB-instance used by the REST-server. Array 
is the LIST-reference to the list of textual permission names to check for possible invalid items.

Returns a LIST-reference to the permission names that were invalid (if any). If none were invalid, the returned array is empty.

=cut

=head2 hasPerm()

Checks if a subject has the specified permission(s) on an object.

Accepts the following input in this order: db, subject, object, perms, pop, oop, effective, inherit, deny, grant.

The meaning of these inputs are as follows:

=over

=item

B<db> Reference to the AuroraDB-instance used by the REST-server.

=cut

=item

B<subject> The subject entity id from the AURORA database for which we want to check if has the permission(s).

=cut

=item

B<object> The object entity id from the AURORA database for which we want to check the permission(s) on.

=cut

=item

B<perms> The textual permission(s) that we want to check for. LIST-reference. The LIST must contain one or more textual permission 
names that one wants to check if the subject has permission(s) on the object. Be aware that if no permissions are specified the method 
will return 1 (true) since it has nothing to evaluate. Also note that if you specify a refernce here that is not a LIST or an undefined 
value, the method will return undef (false).

=cut

=item

B<pop> Logical operator for the permissions. If several permissions are specified in the "perms" option, this option decides if one 
needs to match ALL (logical AND) or ANY (logical OR) of them. Defaults to "ALL". Valid values are "ALL" or "ANY".

=cut

=item

B<oop> Logical operator for the entity tree permission levels (effective, inherit, grant and deny). This option decides if 
one need to match ALL (logical AND) or ANY (logical OR) of the given permission(s) on the levels that one have enabled 
to be targeted (see the effective-, inherit-, deny- and grant-options below). Defaults to "ALL". Valid values are "ALL" or "ANY". 
Please note that if one specifies logically absurd conditions, such as this OOP-option set to ALL, while not targeting/enabling 
any of the four levels (effective, inherit, deny or grant), this method will return 1 (true): it is in other words true that we 
do not care for the result on all of the levels. So beware of logical monsters.

=cut

=item

B<effective> This option decides if one wants to enable/target the effective permission level when checking if the subject 
has the given permission(s) on the object (effective on the object that is). Defaults to undef (false). Valid values are undef, 0 
and 1. Both undef and 0 basically says to not check this level, however, the difference is that if one specifies undef, the method 
will not attempt to retrieve the effective permissions of the subject on the object, thus saving time and resources. If 0 is 
specified the effective permissions will be retrieved. 1 means that we want to enable/target the effective permission level.

=cut

=item

B<inherit> This option decides if one wants to enable/target the inherited permission level when checking if the subject 
has the given permission(s) on the object (inherited from above on the object that is). Defaults to undef (false). Valid values are undef, 0
and 1. Both undef and 0 basically says to not check this level, however, the difference is that if one specifies undef, the method 
will not attempt to retrieve the inherited permissions of the subject on the object, thus saving time and resources. If 0 is 
specified the inherited permissions will be retrieved. 1 means that we want to enable/target the inherited permission level.

=cut

=item

B<deny> This option decides if one wants to enable/target the deny permission level when checking if the subject 
has the given permission(s) on the object (denied on the object itself that is). Defaults to undef (false). Valid values are undef, 0
and 1. Both undef and 0 basically says to not check this level, however, the difference is that if one specifies undef, the method 
will not attempt to retrieve the permissions of the subject on the object itself, thus saving time and resources. If 0 is 
specified the permission(s) on the object will be retrieved. 1 means that we want to enable/target the deny-level. Please note 
that if one has disabled the deny-level, but enabled the grant-level, the permission(s) on object will still be retrieved. The 
reason for this is that both the deny- and grant-level resides on the object itself, so one has to retrieve it if one of deny- or 
grant is enabled.

=cut

=item

B<grant> This option decides if one wants to enable/target the grant permission level when checking if the subject 
has the given permission(s) on the object (granted on the object itself that is). Defaults to undef (false). Valid values are undef, 0
and 1. Both undef and 0 basically says to not check this level, however, the difference is that if one specifies undef, the method 
will not attempt to retrieve the permissions of the subject on the object itself, thus saving time and resources. If 0 is 
specified the permission(s) on the object will be retrieved. 1 means that we want to enable/target the grant-level. Please note 
that if one has disabled the grant-level, but enabled the deny-level, the permission(s) on object will still be retrieved. The   
reason for this is that both the deny- and grant-level resides on the object itself, so one has to retrieve it if one of deny- or 
grant is enabled. 

=cut

=back

Will return an expression that either evaluates to true or false. In the case of false it will be either undef or 0. In the case of 
true it will be a value >= 1. If the expression returned is false, the subject does not fulfill the given permission(s) on the 
object. If true is returned, the subject has the given permission(s) on the object (and on the levels enabled with the stated 
logical operators).

=cut

=head2 listFolders()

List a folder and its subfolders if so specified and return the result in a hash.

Accepts input in the following order: path, recursive, md5sum, tag.

The meaning of these input options are as follows:

=over

=item

B<path> Path to the root of the folder(s) to list. It should be given as an absolute path. If none is specified it will default 
to /dev/null.

=cut

=item

B<recursive> Sets if the listing is to be done recursive down into possible sub-folders. The default setting is true/1. You can 
use any expression you want to on this, but it needs to evaluate to true or false.

=cut

=item

B<md5sum> Sets if files that are discovered will be md5-summed or not? Default setting is true/1. You can use any expression 
you want to on this, but it needs to evaluate to true or false.

=cut

=item

B<tag> Sets if the folder- and file names are to be tagged as UTF8 or not? Default 
is true/1. This parameter must evaluate to either true or false. Usually one wants 
to tag I/O content going in/out so that characters are handled correctly.

=back

This method will return a HASH-reference upon success. Undef upon some failure.

The structure of the HASH-reference is as follows:

   %result = (
      "FolderA" => { 
         "." => { 
            name => "FolderA",
            type => "D",
            size => SCALAR,
            atime => SCALAR,
            mtime => SCALAR,
                },
         "FolderB" => { ... }
         "FileX" => { ... }
      "FileA" => {
         "." => {
            name => "FileA",
            type => "F",
            size => SCALAR,
            atime => SCALAR,
            mtime => SCALAR,
            ctime => SCALAR,
            md5 => SCALAR,
                },
      .
      .
      "FileZ" > { ... }
   )

Information on the folder entry itself is stored in the dot-folder ".". This is true for both files and folders and is 
done for consistency between files and folders. Any entry within a folder is stored inside that folders sub-hash with a 
entry equal to its name. The "recursive" parameters governs if method recurses into sub-folders or not. Also, the md5-sum 
of a file might not be present if the md5sum parameters is set to false/undef/0. Errors performing md5-sum will also be saved in 
the md5-attribute on the sub-hash. It might also be undef, such as when no md5-summing has been requested.

Error-messages on the md5 attribute will have the form: "N/A: Some Error Message", such as when failing to open or 
sum the file in question.

=cut

=head2 mergeMetadata()

Merge metadata with same keys from several entity sources

Accepts this input in the following order: db, entitytype, notemplate, noentity, entities. 

The meaning of these input options are as follows:

=over

=item

B<db> Reference to the AuroraDB-instance used by the REST-server.

=cut

=item

B<entitytype> The textual entitytype to fetch templates for the entities specified in the entities-option. Defaults to DATASET. This 
option will be ignored if the notemplate-option is true.

=cut

=item

B<notemplate> Disables the fetching of template data for the entities specified in the entities-option. Defaults to 0 (false). 
Valid values are 0 (false) and 1 (true - do not fetch template metadata). If false the method will fetch template metadata for 
the entities in the entities-option and merge that with metadata from the entity itself (if not the noentity-option is enabled).

=cut

=item

B<noentity> Disables the fetching of metadata for the entities specified in the entities-option. Defaults to 0 (false). Valid 
values are 0 (false) and 1 (true - do not fetch entity metadata). If false the method will fetch entity metadata for 
the entities in the entities-option and merge that with metadata from the template (if not the notemplate-option is enabled).

=cut

=item

B<entities> The entities that we want to merge metadata for. LIST of entity IDs from the AURORA database.

=cut

=back

This method will merge metadata from the enabled sources (template and/or entity itself) and from all the entities in the 
entities-option into one HASH with key->value entries. In other words it merges metadata from both templates and entities into 
one hash as if the result is for one entity. The merging will take precedence in the order of the entities-option for keys with 
the same name, where first entity specified is antecedent to the next and so on and the last entity in the list takes 
precedence over all the previous.

Returns a HASH-reference with all the merged data in a key=>value structure.

=cut

=head2 permToArray()

Convert permission bitmask into its textual permission names

Accepts the following input in this order: db, bitmask. Db is the reference to the AuroraDB-instance used by the REST-server. 
Bitmask is the bitmask of permission that are to be converted to its textual counterpart.

Returns a LIST-reference of the textual permission names that have been set in the bitmask.

=cut

=head2 recurseListing()

Recurse a listing from the listFolders()-method and produce a iterable array with textual entries.

Accepts these parameters in the following order: listing, newlist, level, path.

The meaning of these parameters are as follows:

=over

=item

B<listing> HASH-reference to the listing produced by the listFolders()-method.

=cut

=item

B<newlist> Reference to the array list being produced by this method. All results of the recursion is added to this list.

=cut

=item

B<level> The level we are at for a specific run of this method. Should be started with the number 0.

=cut

=item

B<path> The preceeding path at any given moment of calling the recurseListing()-method. Is is used to know which folder/part of 
the listFolders structure one is in at any given moment. Should start with just a blank string ("") and the rest is handled 
internally by the recursing method.

=cut

=back

Returns an array list reference in the newlist-option as explained above. 

=cut
