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
# AuroraDB - package for interaction with the Aurora DB.
#
# Copyright(C) 2019 Jan Frode Jæger & Bård Tesaker, NTNU, Trondheim.
#
package AuroraDB;

use strict;
use DBI;
use Time::HiRes qw(time);
use Schema;
use DBItransaction;
use SQLStruct;

my $VIEW_DEPTH=10;

sub new {
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars=@_;

   if (!$pars{data_source}) { my $host="localhost"; $pars{data_source}="DBI:mysql:database=AURORA;host=$host"; }
   if (!$pars{pw}) { $pars{pw}=""; } # must allow blank passwords, eg. SQLite
   if (!$pars{pwfile}) { $pars{pwfile}=""; } # read pw from file instead of as input, pw must be undef or blank.
   if (!$pars{user}) { $pars{user}=""; } # must allow blank users, eg. SQLite
   if (!$pars{depth}) { $pars{depth}=$VIEW_DEPTH; } # set depth to global default if not specified
   else { my $d=$pars{depth}; $d=~s/[^\d]//g; $d=$d||$VIEW_DEPTH; $pars{depth}=$d; } # clean and check depth param

   if (!$pars{entitytypescache}) { $pars{entitytypescache}=3600; } # update type structures every hour as default
   if (!$pars{templatescache}) { $pars{templatescache}=3600; } # update templates structures every hour as default
   if (!$pars{templateflagscache}) { $pars{templateflagscache}=3600; } # update flags structures every hour as default
   if (!$pars{entitiescache}) { $pars{entitiescache}=120; } # update entites every 2 min as default

   # save pars
   $self->{pars}=\%pars;

   return $self;
}

sub maxDepth {
   my $self = shift;

   return $self->{pars}{depth} || $VIEW_DEPTH;
}

sub getDBI {
   my $self = shift;

   my $method=(caller(0))[3];

   if ($self->connected()) {
      return $self->{dbi};
   } else {
      # no connection - connect.
      my $pw="";
      my $data_source=$self->{pars}{data_source};
      my $user=$self->{pars}{user};
      # select either direct pw or pwfile
      if ($self->{pars}{pw} ne "") {
         # set pw directly
         $pw=$self->{pars}{pw} || "";
      } else {
         # only read from pwfile if pwfile has a value
         if ($self->{pars}{pwfile} ne "") {
            # read database password from file
            if (!open (FH,"<","$self->{pars}{pwfile}")) {
               $self->{error}="$method: Unable to login to database. Cannot fetch database password from file \"".$self->{pars}{pwfile}."\" ($!)...";
               return undef;
            } else {
               eval { $pw = <FH>; };
               eval { close FH; };
               # clean password
               $pw =~ s/\r|\n//g;
            }
         }
      }

      # connect to database
      my %opt;
      $opt{RaiseError}=0; # is also default, but in case
      $opt{PrintError}=0; # please be silent
      my $dbi = DBI->connect($data_source, $user, $pw, \%opt) || undef; 
      $dbi->{mysql_enable_utf8}=1; # Use UTF8 by default, but not as option to connect!
      # check if it connected properly
      if ((!$dbi) || (!$dbi->{Active})) {
         my $err=DBI::errstr() || "";
         $self->{error}="$method: Unable to connect to database: $err. Location: $data_source User: $user";
         return undef;
      } else {
         # success 
         $self->{dbi}=$dbi; # store dbi instance
         return $dbi;
      }
   }
}

sub disconnect {
   my $self = shift;

   my $method=(caller(0))[3];
   
   # only disconnect when connected
   if ($self->connected()) {
      # attempt to disconnect
      my $dbi=$self->getDBI();
      my $rc=$dbi->disconnect();
      if (!$rc) {
         # some error disconnecting - create error message
         $self->{error}="$method: Unable to disconnect from database: ".DBI::errstr()||"";
          return 0;
      } else {
         return 1;
      }
   } else {
      # DB is already not connected - return undef
      $self->{error}="$method: Database is not connected. Unable to continue.";
      return undef;
   }
}

sub setDBIutf8 {
    my $self = shift;
    my $was = $self->getDBI->{"mysql_enable_utf8"};
    $self->getDBI->{"mysql_enable_utf8"} = shift ? 1 : 0 if @_;
    return $was;
}

sub connected {
   my $self = shift;

   my $method=(caller(0))[3];

   # check that we have a dbi instance
   my $dbi = $self->{dbi};
   if (defined $dbi) {      
       # check db handler Active flag
      if ($dbi->{Active}) {
         return 1;
      }
   }

   # all other scenarios fails
   return 0;
}

# input statement, return sql-instance
# if in transaction mode the sql return is only to indicate if prepare and execute
# was successful or not.
sub doSQL {
   my $self = shift;

   my $method=(caller(0))[3];

   if ($self->connected()) {
      # connected - get dbi instance
      my $dbi=$self->getDBI();
      # get statement
      my $statement=shift || "";
      my $sql = $dbi->prepare ($statement);
      if ($dbi->err()) {
         # problem with the prepare statement
         $self->{error}="$method: Unable to prepare SQL statement ($statement): ".$dbi->errstr();
         return undef;
      }
      # execute SQL
      $sql->execute();

      # check if failed or not.
      if ($dbi->err()) {
         # return failed
         $self->{error}="$method: Failed to execute SQL statement ($statement): ".$dbi->errstr();
         return undef;
      }

      # success - return sql instance
      return $sql;
   } else {
      $self->{error}="$method: Not connected yet. Unable to perform SQL statement";
      return undef;
   }
}

sub useDBItransaction {
    my $self = shift;
    return DBItransaction->new($self->getDBI, $self);
}

# Store modification times for (ENTITY,PERM,MEMBER) tables 
#
sub setMtime {
    my $self = shift;
    #
    my $table = shift;
    my $mtime = shift || time();
    $table = $Schema::CLEAN{table}->($table);
    $mtime = $Schema::CLEAN_GLOBAL{datetime}->($mtime);
    #
    my $sql = sprintf( "replace into MTIME values(%s,%f)",
                    $self->getDBI->quote($table),
                    $mtime,
        );
    $self->doSQL($sql) or return undef;
    return 1;
}
#
sub getMtime {
    my $self = shift;
    #
    my $sql = "select max(mtime) from MTIME";
    if (@_) {
        my @tables = map { $self->getDBI->quote($Schema::CLEAN{table}->($_)); } @_;
        $sql .= sprintf(" where table_name in (%s)", join(",", @tables));
    }
    my ($mtime) = $self->getDBI->selectrow_array($sql);
    return $mtime;
}

# All enum-methods of db tables (ENTITYTYPE,PERMTYPE,LOGLEVEL) only read values on first call, then cache.
# # fetch entitytypes from db - put as attributes
# $self->{ENTITYTYPE}=fetched values
# $self->{ENTITYTYPENAME}=selectall_hashref(sql select entitytype,entitytypename from ENTITYTYPE,"entitytype");

sub enumEntityTypes {
   # get entitytypes id's in a list.
   my $self=shift;

   my $method=(caller(0))[3];

   my $ctime=$self->{pars}{entitytypescache};
   my $tstamp=$self->{cache}{entitytypes}{timestamp} || 0;

   # only read types from database if cachetime has been
   # passed
   if (time() > ($tstamp+$ctime)) {
      if (my $dbi=$self->getDBI()) {
         # get entity types
         my $sql=$self->doSQL("SELECT entitytype,entitytypename FROM `ENTITYTYPE`");
         if (defined $sql) {
            # success - go through each row
            while (my @row=$sql->fetchrow_array()) {
               # uppercase the name
               my $key=uc($row[1]);
               # save value/key pair
               $self->{cache}{entitytypes}{value}{$row[0]}=$key;
               # save key/value pair
               $self->{cache}{entitytypename}{value}{$key}=$row[0];
            }
            # save timestamp
            $self->{cache}{entitytypes}{timestamp}=time() || 0;
            # return just the values
            return keys %{$self->{cache}{entitytypes}{value}};
         } else {
            # something failed - error already set
            return undef;
         }
      } else {
         # something failed - error already set
         return undef;
      }
   } else {
      # return from cache
      return keys %{$self->{cache}{entitytypes}{value}};
   }
}

sub getEntityTypeIdByName {
   my $self=shift;

   my $method=(caller(0))[3];

   # ensure that we have the entity types loaded
   $self->enumEntityTypes();

   # get types names to get id for
   my @n=@_;
   my @names;
   # clean values
   foreach (@n) { 
      my $name=$_ || "";
 
      # clean the value
      $name=$Schema::CLEAN{entitytypename}->($name);
      # add to list
      push @names,$name;
   }

   if (@names == 0) {
      # fetch from cache
      @names=sort {$a cmp $b} keys %{$self->{cache}{entitytypename}{value}};
   }

   my @values;
   foreach (@names) { 
      push @values,$self->{cache}{entitytypename}{value}{$_} || undef;
   }

   return @values;
}

sub getEntityTypeNameById {
   my $self = shift;

   my $method=(caller(0))[3];

   # output names instead of values 
   # ensure that we have the entity types loaded
   $self->enumEntityTypes();

   # get types to get name for
   my @v=@_;
   my @values;
   # clean values
   foreach (@v) {
      my $value=$_ || 0;

      # clean the value
      $value=$Schema::CLEAN{entitytype}->($value);
      # add the value to list
      push @values,$value;
   }

   if (@values == 0) {
      # fetch from cache
      @values=sort keys %{$self->{cache}{entitytypes}{value}};
   }

   my @names;
   foreach (@values) { 
      push @names,$self->{cache}{entitytypes}{value}{$_} || undef;
   }

   return @names;
}

# return all entities of given type - list of ids/entity
# multiple types allowed
sub enumEntitiesByType {
   my $self = shift;
   my $type = shift;

   my $method=(caller(0))[3];

   # check type of type (must be array or undef)
   if ((defined $type) && (ref($type) ne "ARRAY")) {
      $self->{error}="$method: type parameter must be an array. Unable to enum entities.";
      return undef;
   }

   my $types="";
   if ((defined $type) && (@{$type} > 0)) {
      foreach (@{$type}) {
         my $t=$_;

         # clean type
         $t=$Schema::CLEAN{entitytype}->($t);

         if (!($self->getEntityTypeNameById($t))[0]) {
            # invalid entity type
            $self->{error}="$method: Invalid entity type specified. Could not enumerate entities of this type";
            return undef;
         } else {
            # add type
            $types=($types eq "" ? " WHERE entitytype in ($t" : $types.",$t");
         }
      }
   }
   $types=($types eq "" ? "" : $types.")");

   # lets get the entities
   my $sql=$self->doSQL ("SELECT entity FROM `ENTITY`$types ORDER by entity ASC");
   if ($sql) {
      # success - lets read result
      my @entities;
      while (my @row=$sql->fetchrow_array()) {
         # add id to list
         push @entities,$row[0];
      }
      # finished, lets return the list, empty or not
      return \@entities;
   } else {
      # failed - error already set
      return undef;
   }
}

sub createEntity {
   # create an entity of given entitytype. Input is type and parent.
   my $self = shift;
   my $type = shift || ($self->getEntityTypeIdByName("DATASET"))[0]; # Dataset
   my $parent = shift || 1; # point to first entity in database if none given

   my $method=(caller(0))[3];

   # clean values
   $type=$Schema::CLEAN{entitytype}->($type);
   $parent=$Schema::CLEAN{entity}->($parent);

   my $maxdepth=$self->maxDepth();

   if (!($self->getEntityTypeNameById($type))[0]) {
      # invalid entity type
      $self->{error}="$method: Invalid entity type specified. Could not insert";
      return undef;
   }

   # check that parent exists
   if (!$self->existsEntity($parent)) {
      # invalid parent id
      $self->{error}="$method: Parent id $parent does not exist. Unable to create entity";
      return undef;
   }

   # get path to entity
   my @path=$self->getEntityPath($parent);
   if (!defined $path[0]) {
      $self->{error}="$method: Unable to create entity. Could not get path to parent $parent: ".self->error();
      return undef;
   }

   # check the number of path elements do not supersede view-depth
   if (@path >= $maxdepth) {
      # the parent is already at depth, cannot allow creation of entity
      $self->{error}="$method: Cannot create an entity at this depth. Maximum tree depth is set to $maxdepth.";
      return undef;
   }

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # do SQL insert
   my $sql=$self->doSQL("INSERT INTO `ENTITY` (entityparent,entitytype) VALUES($parent,$type)");

   if (defined $sql) { # Entity succesfully created
       # Get id of newly created entity
       my $entity = $self->getDBI()->last_insert_id(undef,undef,undef,undef) || 0;
       # Sequence the new entity;
       $self->sequenceEntity($entity) or return undef;
       # Manually inherit perms in perm cache. Best effort, no error handeling
       $self->doSQL("insert into PERM_EFFECTIVE_PERMS
                            select permsubject,$entity,perms
                            from PERM_EFFECTIVE_PERMS
                            where permobject=$parent
                            ");
       # And return the id.
       return $entity;
   } else {
      # something failed - error already set
      return undef;
   }
}

# delete an entity from database. Input is entity-id. Returns 1 on success, 0 on fail.
sub deleteEntity {
   my $self = shift;
   my $entity = shift || 0;

   my $method=(caller(0))[3];

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # clean entity
   $entity=$Schema::CLEAN{entity}->($entity);

   # check that entity Id exists
   if ($self->existsEntity($entity)) {
      # check if entity has any child
      my $sql=$self->doSQL("SELECT count(*) FROM `ENTITY` WHERE entityparent=$entity");
      if (defined $sql) {
         # check if we have any hits
         my @cols=$sql->fetchrow_array();
         my $children=$cols[0];
         if ($children > 0) {
            # there exists a child(ren), abort
            $self->{error}="$method: This entity $entity has $children child(ren). Cannot delete entity. Try moving child(ren) first.";
            return 0;
         }
         # no children, so we can go ahead with deletion - remember all memberships as well
         $sql=$self->doSQL("DELETE FROM `MEMBER` WHERE membersubject=$entity or memberobject=$entity") and $self->setMtime('MEMBER');
         if (!defined $sql) {            
            # failure - error already set
            return 0;
         }

         # remove all perms as well
         $sql=$self->doSQL("DELETE FROM `PERM` WHERE permsubject=$entity or permobject=$entity") and $self->setMtime('PERM');
         if (!defined $sql) {
            # failure - error already set
            return 0;
         }

         # delete template assignments
         $sql=$self->doSQL("DELETE FROM `TMPLASSIGN` WHERE tmplassignentity=$entity");
         if (!defined $sql) {
            # failure - error already set
            return 0; 
         }

         # delete log entries
         $sql=$self->doSQL("DELETE FROM `LOG` WHERE entity=$entity");
         if (!defined $sql) {
            # failure - error already set
            return 0; 
         }

         # delete all metadata
         $sql=$self->doSQL("DELETE FROM `METADATA` WHERE entity=$entity");
         if (!defined $sql) {
            # failure - error already set
            return 0; 
         }

         # delete the entity sequence         
         $sql=$self->doSQL("DELETE FROM `ENTITY_SEQUENCE` WHERE entity=$entity");
         if (!defined $sql) {
            # failure - error already set
            return 0;
         }

         # delete the entity itself         
         $sql=$self->doSQL("DELETE FROM `ENTITY` WHERE entity=$entity") and $self->setMtime('ENTITY');
         if (!defined $sql) {
            # failure - error already set
            return 0;
         }

         # success
         return 1;
      } else {
         # failure - error already set
         return 0;
      }
   } else {
      # failure
      $self->{error}="$method: Entity $entity does not exist. Unable to delete it."; 
      return 0;
   }
}

sub moveEntity {
   my $self = shift;
   my $entity = shift;
   my $to = shift;

   my $method=(caller(0))[3];

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   $entity=$Schema::CLEAN{entity}->($entity);
   $to=$Schema::CLEAN{entity}->($to);

   my $maxdepth=$self->maxDepth();

   # check that entity exists
   if ($self->existsEntity($entity)) {
      # check that to entity exists
      if ($self->existsEntity($to)) {
          # both exists, check depth of destination
          my $sql=$self->doSQL("select depth from DEPTH where entity=$to");
          if (!defined $sql) {
             $self->{error}="$method: Unable to get to entity $to depth: ".$self->error();
             return undef;
          }
          my $todepth=$sql->fetchrow_array() || 0;

          # check the depth do not supercede view-depth
          if ($todepth >= $maxdepth) {
             # the parent/destination is already at depth, cannot allow moving of entity
             $self->{error}="$method: Cannot move an entity to this depth. Maximum tree depth is set to $maxdepth.";
             return undef;
          }

          # get depth of entity to move
          $sql=$self->doSQL("select depth from DEPTH where entity=$entity");
          if (!defined $sql) {
             $self->{error}="$method: Unable to get entity $entity depth: ".$self->error();
             return undef;
          }
          my $entdepth=$sql->fetchrow_array() || 0;

          # get the maximum absolute depth of the children, including datasets
          $sql=$self->doSQL("select max(depth) from ANCESTORS a join DEPTH d on a.entity=d.entity where a.ancestor=$entity");
          if (!defined $sql) {
             $self->{error}="$method: Unable to get maximum depth of entity $entity children: ".$self->error();
             return undef;
          }
          my $chldepth=$sql->fetchrow_array() || 0;

          # calculate difference between entity and its child with max depth
          my $diff=$chldepth-$entdepth;

          # check if to-depth will be too deep, including the parent to move
          if (($todepth+$diff+1) > $maxdepth) {
             $self->{error}="$method: Unable to move entity. One or more children of entity $entity will be too deep in entity tree. Maximum tree depth is set to $maxdepth.";
             return undef;
          }

          # now check cyclic paths
          my @destpath = $self->getEntityPath($to) or return undef;
          if (grep /^$entity$/, @destpath) {
              $self->{error}="$method: Entity is in destination path. Cyclic paths is not allowed.";
              return 0;
          } 
          else { # We are clear, move on
              $sql=$self->doSQL("UPDATE `ENTITY` set entityparent=$to WHERE entity=$entity") and $self->setMtime('ENTITY');
              if (defined $sql) {
                  # success, resequence it
                  $self->sequenceEntity($entity) or return 0;
                  return 1;
              } else {
                  # failure - error already set
                  return 0;
              }
          }
      } else {
         # failure - error already set
         $self->{error}="$method: Parent $to does not exist. Unable to move entity $entity.";
         return 0;
      }
   } else {
      # failure - error already set
      $self->{error}="$method: Entity $entity does not exist. Unable to move it.";
      return 0;
   }
}

sub existsEntity {
   my $self = shift;
   my $entity = shift || 0; # set invalid default entity id

   my $method=(caller(0))[3];
   
   if (my $dbi=$self->getDBI()) {
      $entity=$Schema::CLEAN{entity}->($entity);
      # check if entity exists     
      my $sql=$self->doSQL("SELECT * FROM `ENTITY` WHERE entity=$entity");
      if (defined $sql) {
         # check that we have a hit
         if ($sql->fetchrow_array()) {
            # got a row - this is a success
            return $entity;
         } else {
            if ($dbi->err()) {
               $self->{error}="$method: Unable to fetch an array to a row in the database: ".$dbi->errstr();
               return undef;
            } else {
               # entity does not exist
               return 0;
            }
         }
      }
   } else {
      # error already set
      return undef;
   }
}

sub getEntityTree {
    # Generate hash with tree structure with given entity id as root.
    # return ref to hash: { <id> => { id => <id>, children => [ <id>, ...], parent => <id> }, ... }
    
    my $self = shift;
    my $entity = shift || 1; # start entity, if not specified defaults to 1 (root)
    my $include = shift || undef;  # include entity types for quicker recursion
    my $exclude = shift || undef;  # excude entity types for quicker recursion
    my $depth = shift; # specify max depth from start-entity

    my $method=(caller(0))[3];

    $entity=$Schema::CLEAN{entity}->($entity);

    my $maxdepth=$self->maxDepth();
    if (defined $depth) { $depth=$Schema::CLEAN{depth}->($depth,$maxdepth,1); }
    if ($entity < 1) {
        $self->{error}="$method($entity): missing/invalid parameter";
        return undef;
    }

    # get start-entity depth
    my $edepth;
    my $depthj="";
    my $depthstr="";
    if (defined $depth) {
       my $sql=$self->doSQL("SELECT depth from DEPTH where entity=$entity");

       if (!defined $sql) {
          # something went sideways - error already set
          return undef;
       }
       $edepth=($sql->fetchrow_array())[0] || undef;
    
       if (!defined $edepth) {
          $self->{error}="$method: Unable to get depth of entity $entity";
          return undef;
       }
       $depthj="LEFT JOIN DEPTH on ANCESTORS.entity=DEPTH.entity ";
       $depthstr=" AND (DEPTH.depth-$edepth <= $depth)";
    }

    my $moderators = "";
    if (defined($include) and ref($include) eq "ARRAY") {
	my @valid = grep { ($self->getEntityTypeNameById($_))[0]; } @$include; 
	$moderators .= " AND entitytype IN (".join(",", @valid).")" if @valid;
    }
    if (defined($exclude) and ref($exclude) eq "ARRAY") {
	my @valid = grep { ($self->getEntityTypeNameById($_))[0]; } @$exclude; 
	$moderators .= " AND entitytype NOT IN (".join(",", @valid).")" if @valid;
    }

    # get all entities in tree which have a common ancestor in specified entity root
    my $sql=$self->doSQL("SELECT * FROM `ANCESTORS` LEFT JOIN ENTITY on ANCESTORS.entity=ENTITY.entity ".
                      $depthj.
                      "where ".
                      "ancestor=$entity$moderators$depthstr ORDER BY ANCESTORS.entity");

    if (!defined $sql) {
       # something went sideways - error already set
       return undef;
    }

    # fill tree hash from query result
    my %tree;
    while (my @row=$sql->fetchrow_array()) {
       my $entity=$row[0];
       my $ancestor=$row[1];
       my $parent=$row[3];
       my $type=$row[4];
 
       # fill tree
       $tree{$entity}{id}=$entity;
       $tree{$entity}{parent}=$parent;
       $tree{$entity}{type}=$type;
       my @c;
       if (!exists $tree{$entity}{children}) { $tree{$entity}{children}=\@c; } # add empty children

       if ($entity == $parent) { next; } # do not add oneself as child (root)

       # add entity as parent's child
       push @{$tree{$parent}{children}},$entity;
    }
    # clean tree of dangling parents
    foreach (keys %tree) {
       my $entity=$_;

       # check if we have data for the parent or not
       if (!exists $tree{$entity}{id}) {
          # this is a non-valid parent - remove
          delete ($tree{$entity});
       }
    }
    return \%tree;
}

sub getEntityType {
   # get an entitys type. Input is entity-id. returns entitytype id
   my $self = shift;
   my $entity = shift;

   my $method=(caller(0))[3];

   # clean entity
   $entity=$Schema::CLEAN{entity}->($entity);

   if ($self->existsEntity($entity)) {
      # entity exists - get its type
      my $sql=$self->doSQL("SELECT entitytype FROM `ENTITY`where entity=$entity");
      if (defined $sql) {
         if (my @row=$sql->fetchrow_array()) {
            # return type
            return $row[0] || 0;
         } else {
            # unable to fetch row
            my $dbi=$self->getDBI();
            $self->{error}="$method: Unable to fetch entitys type: ".$dbi->errstr();
            return 0;
         }
      } else {
         # something failed - error already set
         return 0;
      }
   } else {
      # entity does not exist
      $self->{error}="$method: Entity $entity does not exist. Unable to fetch entitys type.";
      return 0;
   }
}

sub getEntityTypeName {
   my $self = shift;
   my $entity = shift;

   my $method=(caller(0))[3];

   # get an entitys typename. Input is entity-id. returns scalar of name.
   return ($self->getEntityTypeNameById($self->getEntityType($entity)))[0];
}

sub getEntityByMetadataKeyAndType {
   # get an entity id(s) based upon the value(s) of a metadata key hash and entity type id (if any)
   my $self = shift;
   my $metadata = shift || undef;
   my $offset = shift;
   my $count = shift;
   my $orderby = shift;
   my $order = shift;
   my $entities = shift;
   my $types = shift;
   my $tableopt = shift || 0;
   my $debug = shift || 0; # opt to get SQLStruct debug info (query being used)
   my $subject = shift; # subject that perms are valid for
   my $perm = shift; # perms to look for
   my $plop = shift || "ANY"; # logical operator between each perm bit
   my $sorttype = shift || 0; # type of sorting, either 0 = alphanumerical case-insensitive(default), 1=numerical,
                              # 2= alphanumerical case-sensitive

   # clean the sorttype
   $sorttype = $Schema::CLEAN{sorttype}->($sorttype);

   # clean tableopt (select between availability to search in parent md or not)
   $tableopt=$Schema::CLEAN{tableopt}->($tableopt);
   my $tablename=($tableopt ? "METADATA_COMBINED" : "METADATA");

   # clean offset values
   if (defined $offset) {
      $offset=$Schema::CLEAN{offset}->($offset);
      $offset=$offset-1;
      $count=$Schema::CLEAN{offsetcount}->($count);
   }

   my $method=(caller(0))[3];

   my $perms="";
   if (defined $subject) {
      $subject=$Schema::CLEAN{entity}->($subject);
      $plop=$Schema::CLEAN{permtype}->($plop);
      $perm=$perm||'';
      # get the numbered bits in the mask
      my @bits=$self->deconstructBitmask($perm);
      # get number of bits returned
      my $c=@bits;
      if ($plop eq "ANY") {
         $perms=" AND ENTITY.entity IN (select distinct permobject FROM PERM_EFFECTIVE where perm IN (".join(",",@bits).")".
                " AND permsubject=$subject)";
      } else {
         $perms=" AND ENTITY.entity IN (select distinct permobject from (select permobject,count(perm) as c".
                " from PERM_EFFECTIVE where perm in (".join(",",@bits).") and permsubject=$subject".
                " GROUP BY permsubject,permobject) t1 where c=$c)";
      }
   }

   # check that types is an array
   if ((defined $types) && (ref($types) ne "ARRAY")) {
      # failure
      $self->{error}="$method: types parameters must be an array or undef. Unable to proceed.";
      return undef;
   }

   # clean and verify entity types - if any
   my @entitytypes;
   foreach (@{$types}) {
      my $type=$_;

      $type=$Schema::CLEAN{entitytype}->($type);
      if (!$self->getEntityTypeNameById($type)) {
         # invalid entity type
         $self->{error}="$method: Invalid entity type specified. Could not get entity metadata";
         return undef;
      }
      # add cleaned types to list
      push @entitytypes,$type;
   }

   my $dbi=$self->getDBI();

   # go through entitytypes
   my $typs="";
   if (@entitytypes > 0) {
      $typs=join(",",@entitytypes);
      $typs=" AND ENTITY.entitytype IN ($typs)";
   }

   # check if we have entity list to use as base
   my $ents="";
   if (defined $entities) {
      if (ref($entities) eq "ARRAY") {
         if (@{$entities} > 0) {
            # we have a entities list
            $ents=join(",",@{$entities});
            $ents=" AND ENTITY.entity in ($ents) ";
         }
      } else {
         # wrong type
         $self->{error}="$method: Entities list must be an array. Unable to get entities.";
         return undef;
      }
   }

   my $where="";
   if (($typs ne "") || ($ents ne "")) {
      # one of types and/or moderators are not blank - add WHERE
      $where="WHERE 1"; # use 1 as TRUE-logic to let the rest use AND-statements
   }

   # create SQLStruct instance, no force-quoting, set identifier and identifier value names and clean functions
   my $struct=SQLStruct->new(dbi=>$dbi,forcequote=>0,iname=>"METADATAKEY.metadatakeyname",ivname=>"${tablename}.metadataval",
                             iclean=>$Schema::CLEAN{metadatakeyw},vclean=>$Schema::{metadatakeyval},
                             prepar=>"ENTITY.entity IN",
                             prelog=>"SELECT ENTITY.entity FROM ENTITY LEFT JOIN $tablename on ENTITY.entity = ${tablename}.entity ".
                                     "LEFT JOIN METADATAKEY on ${tablename}.metadatakey = METADATAKEY.metadatakey WHERE 1 AND");
   # go through possible metadata key moderators and create relevant SQL
   my $moderators=$struct->convert($metadata) || "";
   # add paranthesis.
   $moderators=($moderators eq "" ? "" : " AND ($moderators)");
 
   # clean orderby
   $orderby=$Schema::CLEAN{orderby}->($orderby);
   $orderby=$dbi->quote($orderby);

   # clean order
   $order=$Schema::CLEAN{order}->($order);

   # decide if sorting is alphanumerical og numerical and make order by statement accordingly
   my $orderbystr="";
   if ($sorttype == 1) { # numerical
      $orderbystr="${tablename}.metadataval+0";
   } elsif ($sorttype == 2) { # alphanumerical, case-sensitive
      $orderbystr="${tablename}.metadataval";
   } else { # alphanumerical, case-insensitive (=0 or default)
      $orderbystr="UPPER(${tablename}.metadataval)";
   }

   my $query="from `ENTITY` ".
             "LEFT JOIN `${tablename}` on ENTITY.entity = ${tablename}.entity ".
             "LEFT JOIN `METADATAKEY` on ${tablename}.metadatakey = METADATAKEY.metadatakey ".
             "WHERE METADATAKEY.metadatakeyname = $orderby$perms$typs$ents$moderators".
             " ORDER BY $orderbystr $order ";

   # execute query with limit or without limit clause
   my $limit=(defined $offset ? 1 : 0);
   my $sql;
   if ($limit) {
      $sql=$self->doSQL("SELECT SQL_CALC_FOUND_ROWS distinct ENTITY.entity,${tablename}.metadataval $query LIMIT $offset,$count");
   } else {
      $sql=$self->doSQL("SELECT SQL_CALC_FOUND_ROWS distinct ENTITY.entity,${tablename}.metadataval $query");
   }

   if (defined $sql) {
      # success - retrieve entity ids
      my @entities;
      while (my @row=$sql->fetchrow_array()) {
         # get id and push to list
         push @entities,$row[0];
      }
      my $total;
      if ($limit) {
         # calculate number of rows actually found, without using FOUND_ROWS as per modern recommendation
         $sql=$self->doSQL("SELECT FOUND_ROWS()");
         if (!defined $sql) {
            # something failed - error already set
            return undef;
         }
         # success - get count
         my @row=$sql->fetchrow_array();
         $total=$row[0] || 0;
         # save total
         $self->{limittotal}=$total;
      } 
      
      # return entity id(s) that match criteria, if any
      if (!$debug) {
         return \@entities;
      } else {
         if ($limit) { return \@entities,"SELECT distinct ENTITY.entity,${tablename}.metadataval $query LIMIT $offset,$count"; }
         else { return \@entities,"SELECT distinct ENTITY.entity,${tablename}.metadataval $query"; }
      }
   } else {
      # failure with sql, error already set
      return undef;
   }
}

sub getLimitTotal {
   my $self = shift;

   # returns the last total for a limit statement used in SQL
   return $self->{limittotal} || 0;
}

# gets entites that match a certain perm by type
sub getEntityByPermAndType {
   my $self=shift;
   my $subject=shift;
   my $perm=shift;
   my $permtype=shift;
   my $type=shift;
   my $entities=shift;

   my $method=(caller(0))[3];

   # clean subject
   $subject=$Schema::CLEAN{entity}->($subject);
   # clean permtype
   $permtype=$Schema::CLEAN{permtype}->($permtype);

   # check if we have entity list to use as base
   my $ents="";
   if (defined $entities) {
      if (ref($entities) eq "ARRAY") {
         if (@{$entities} > 0) {
            # we have a entities list
            $ents=join(",",@{$entities});
            $ents=" ENTITY.entity in ($ents) AND";
         }
      } else {
         # wrong type
         $self->{error}="$method: Entities list must be an array. Unable to get entities.";
         return undef;
      }
   }

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   if ((defined $type) && (ref($type) ne "ARRAY")) {
      $self->{error}="$method: Types-parameter is not an ARRAY. Unable to continue.";
      return undef;
   }

   my $types="";
   if ((defined $type) && (@{$type} > 0)) {
      foreach (@{$type}) {
         my $t=$_;

         # clean type
         $t=$Schema::CLEAN{entitytype}->($t);

         if (!($self->getEntityTypeNameById($t))[0]) {
            # invalid entity type
            $self->{error}="$method: Invalid entity type specified. Could not enumerate entities of this type";
            return undef;
         } else {
            # add type
            $types=($types eq "" ? " ENTITY.entitytype in ($t" : $types.",$t");
         }
      }
   }
   $types=($types eq "" ? "" : $types.") AND");

   # convert perms to bits
   my @bits=$self->deconstructBitmask($perm);
   # get number of bits in mask
   my $c=@bits;

   # get all objects that subject has permissions on
   my $sql;
   if (defined $perm) {
      if ($permtype eq "ANY") {
         $sql=$self->doSQL("SELECT permobject,perms FROM PERM_EFFECTIVE_PERMS LEFT JOIN ENTITY on PERM_EFFECTIVE_PERMS.permobject=ENTITY.entity".
                           " where$types$ents permsubject=$subject and permobject IN".
                           " (SELECT distinct permobject FROM PERM_EFFECTIVE where perm IN (".join(",",@bits).") AND permsubject=$subject)");
      } else {
         $sql=$self->doSQL("SELECT permobject,perms FROM PERM_EFFECTIVE_PERMS where$types$ents permsubject=$subject and permobject IN".
                           " (SELECT distinct permobject from (select permobject,permsubject,count(perm) as c".
                           " from PERM_EFFECTIVE where perm IN (".join(",",@bits).") and permsubject=$subject".
                           " GROUP BY permsubject,permobject) t1 where c=$c)");
      }
   } else {
      # permtype has no meaning
      $sql=$self->doSQL("SELECT permobject,perms FROM PERM_EFFECTIVE_PERMS LEFT JOIN ENTITY on PERM_EFFECTIVE_PERMS.permobject=ENTITY.entity".
                        " where$types$ents permsubject=$subject");

   }

   if (defined $sql) {
      # we need to parse through result
      my %pents;
      while (my @row=$sql->fetchrow_array()) {
         # go through each row of the result and parse
         my $obj=$row[0];
         my $perm=$row[1];
 
         $pents{$obj}=$perm;
      }
      # lets return result
      return \%pents;
   } else {
      # something failed - error already set
      return undef;
   }
}

sub getEntityPermByPermAndMetadataKeyAndType {
   my $self=shift;
   my $subject = shift;
   my $perm = shift;
   my $permtype = shift;
   my $metadata = shift || undef;
   my $offset = shift;
   my $count = shift;
   my $orderby = shift;
   my $order = shift;
   my $types = shift;
   my $tableopt = shift || 0;
   my $sorttype = shift || 0; # see the getEntityByMetadataKeyandType-method

   my $method=(caller(0))[3];

   # clean subject (the one we fetch perms for)
   $subject=$Schema::CLEAN{entity}->($subject);

   # clean tableopt (select between availability to search in parent md or not)
   $tableopt=$Schema::CLEAN{tableopt}->($tableopt);

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();
 
   # get entities that are within pents list and that matches metadata, offset and count of
   # given type
   my $entities=$self->getEntityByMetadataKeyAndType($metadata,$offset,$count,$orderby,$order,undef,$types,$tableopt,undef,$subject,$perm,$permtype,$sorttype);

   if (defined $entities) {
      # we have matches - get perm for all of them.
      # get entities of type that match perm and are in entities-list
      my $pents=$self->getEntityByPermAndType($subject,$perm,$permtype,$types,$entities);

      if (!(defined $pents)) {
         # something failed - error already set
         return undef;
      }

      my %entperms;
      my $pos=0;
      foreach (@{$entities}) {
         my $ent=$_;

         # fetch its perm from previous hash
         $pos++;
         $entperms{$pos}{entity}=$ent;
         $entperms{$pos}{perm}=$pents->{$ent} || '';
      }
      # return result
      return \%entperms;
   } else {
      # something failed - error already set
      return undef;
   }
}

# wrapper around getEntityByMetadataKeyAndType
sub getEntityPermByMetadataKeyAndType {
   my $self=shift;
   my $subject = shift;
   my $metadata = shift || undef;
   my $offset = shift;
   my $count = shift;
   my $orderby = shift;
   my $order = shift;
   my $types = shift;
   my $tableopt = shift || 0;
   my $sorttype = shift || 0; # see the getEntityByMetadataKeyAndType()

   my $method=(caller(0))[3];

   # clean subject (the one we fetch perms for)
   $subject=$Schema::CLEAN{entity}->($subject);

   # clean tableopt (select between availability to search in parent md or not)
   $tableopt=$Schema::CLEAN{tableopt}->($tableopt);

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # get entity(ies) that match search criteria
   my $entities=$self->getEntityByMetadataKeyAndType($metadata,$offset,$count,$orderby,$order,undef,$types,$tableopt,undef,undef,undef,undef,$sorttype);

   if (defined $entities) {
      # we have matches - get perm for all of them.
      my $perm=$self->getEntityByPermAndType($subject,undef,undef,undef,$entities);
      if (!defined $perm) {
         # something failed - error already set
         return undef;
      }
      my %perms;
      my $pos=0;
      foreach (@{$entities}) {
         my $entity=$_;

         # add perm to perms hash
         $pos++;
         $perms{$pos}{entity}=$entity;
         $perms{$pos}{perm}=$perm->{$entity}||'';
      }
      # return what we found
      return \%perms;
   } else {
      # something failed - error already set
      return undef;
   }
}

sub getEntityChildren {
   my $self = shift;
   my $entity = shift;
   my $type = shift;
   my $recursive = shift || 0;
   $entity = $Schema::CLEAN{entity}->($entity);

   my $method=(caller(0))[3];

   # check type of type (must be array or undef)
   if ((defined $type) && (ref($type) ne "ARRAY")) {
      $self->{error}="$method: type parameter must be an array. Unable to get entitys children.";
      return undef;
   }

   my $types="";
   if ((defined $type) && (@{$type} > 0)) {
      foreach (@{$type}) {
         my $t=$_;

         # clean type
         $t=$Schema::CLEAN{entitytype}->($t);

         if (!($self->getEntityTypeNameById($t))[0]) {
            # invalid entity type
            $self->{error}="$method: Invalid entity type ($t) specified. Could not get entity children of this type.";
            return undef;
         } else {
            # add type
            $types=($types eq "" ? " AND entitytype in ($t" : $types.",$t");
         }
      }
   }
   $types=($types eq "" ? "" : $types.")");

   if ($self->existsEntity($entity)) {
      # entity exists - get data
      my $sql;
      if ($recursive) {
         # get all children below parent
         $sql=$self->doSQL("SELECT ANCESTORS.entity FROM `ANCESTORS` LEFT JOIN `ENTITY` on ANCESTORS.entity=ENTITY.entity WHERE ancestor=$entity and ANCESTORS.entity <> $entity$types ORDER BY entity ASC");
      } else {
         $sql=$self->doSQL("SELECT entity FROM `ENTITY` where entityparent=$entity$types order by entity ASC");
      }
      if (defined $sql) {
         my @ents;
         while (my @row=$sql->fetchrow_array()) {
            # get entity
            push @ents,$row[0];
         } 
         # return ents
         return \@ents;
      } else {
         # something failed - error already set
         return undef;
      }
   } else {
      # entity does not exist
      $self->{error}="$method: Parent entity $entity does not exist. Unable to fetch entitys children.";
      return undef;
   }
}

sub getEntityParent {
   my $self = shift;
   my $entity = shift;
   $entity = $Schema::CLEAN{entity}->($entity);

   my $method=(caller(0))[3];

   my $ex=$self->existsEntity($entity);

   if ($ex) {
      # entity exists - get its type
      my $sql=$self->doSQL("SELECT entityparent FROM `ENTITY` where entity=$entity");
      if (defined $sql) {
         if (my @row=$sql->fetchrow_array()) {
            # return parent
            return $row[0];
         } else {
            # unable to fetch row
            my $dbi=$self->getDBI();
            $self->{error}="$method: Unable to fetch entitys parent: ".$dbi->errstr();
            return 0;
         }
      } else {
         # something failed - error already set
         return 0;
      }
   } else {
      # entity does not exist
      if ((defined $ex) && ($ex == 0)) {
         $self->{error}="$method: Entity $entity does not exist. Unable to fetch entitys parent.";
     } 
     return 0;
   }
}

sub getEntityPath {
    my $self = shift;
    my @ids = @_;
 
    for (my $i=0; $i < @ids; $i++) {
       $ids[$i]=$Schema::CLEAN{entity}->($ids[$i]);
    }

    my $method=(caller(0))[3];

    if (@ids < 1) {
        $self->{error}="$method: missing/invalid id parameter";
        return undef;
    }

    # join together IDs into a comma-separated string
    my $idsstr=join(",",@ids);	

    # start transaction if not already started
    my $transaction = $self->useDBItransaction();

    my $sql=$self->doSQL("SELECT ANCESTORS.entity,ancestor FROM `ANCESTORS` LEFT JOIN `ENTITY_SEQUENCE` on ANCESTORS.ancestor=ENTITY_SEQUENCE.entity WHERE ANCESTORS.entity IN ($idsstr) ORDER BY entity,sequence ASC") or return undef;

    # go through result
    my %path=();
    while (my @row=$sql->fetchrow_array()) { 
       my $entity=$row[0];
       my $ancestor=$row[1];

       if (!exists $path{$entity}) { $path{$entity}=(); }

       push @{$path{$entity}},$ancestor;
   }

   if (@ids > 1) {
      # caller asked for several ids path - return a hash
      return \%path;
   } else {
      # we are just dealing with one id - return just that as an array
      # this is backwards compatible
      return @{$path{$ids[0]}||[]};
   }
}

sub getEntityRoles {
    # Get a list of roles for an entity. Roles is the entity itself, its ancestors and any entity
    # tied directly or indirectly to any of them with the MEMBER table. 
    # The list is unsorted without duplicates.

    my $self = shift;
    my $id = shift;

    my $method=(caller(0))[3];
   
    $id = $Schema::CLEAN{entity}->($id);
  
    # Check the ID parameter
    if ($id < 1) {
        $self->{error}="$method: missing/invalid parameter";
        return undef;
    }

    # start transaction if not already started
    my $transaction = $self->useDBItransaction();

    my $sql = $self->doSQL("SELECT role FROM `ROLES`where entity=$id");
    if (defined $sql) {
       # success - get result
       my @roles=();
       while (my @row=$sql->fetchrow_array()) { push @roles,$row[0]; }
       return @roles;
    } else {
       # something failed - error already set
       return undef;
    }
}

# get all members of this entity
sub getEntityMembers {
   my $self = shift;
   my $id = shift; # object - entity to get members of

   $id=$Schema::CLEAN{entity}->($id);

   my $method=(caller(0))[3];

   # start transaction
   my $t=$self->useDBItransaction();

   if ($self->existsEntity($id)) {
      # entity exists - get its members
      my $sql=$self->doSQL("SELECT membersubject FROM `MEMBER` WHERE memberobject=$id");
      if (defined $sql) {
         # success - fetch all hits
         my @l;
         while (my @val=$sql->fetchrow_array()) {
            # add subject entity id to list
            push @l,$val[0];
         }
         # return result
         return \@l;
      } else {
         # something failed - error already set
         return undef;
      }
   } else {
      # entity does not exist
      $self->{error}="$method: Entity does not exist. Unable to get entity $id members.";
      return undef;
   }
}

# add entity member
sub addEntityMember {
   my $self = shift;
   my $object = shift;
   my @insubs = @_;

   my $method=(caller(0))[3];

   # clean
   $object=$Schema::CLEAN{entity}->($object);

   # start transaction
   my $t=$self->useDBItransaction();

   # go through each subject
   my @subjects;
   foreach (@insubs) {
      my $subject=$Schema::CLEAN{entity}->($_);

      # check if subject exists and that it is not trying to be a 
      # member of itself
      if ($subject == $object) {
         # trying to be member of itself, we do not like that
         $self->{error}="$method: Adding an entity ($subject) to itself as a member is not allowed.";
         return 0;
      } elsif ($self->existsEntity($subject)) {
         # subject entity exists, add to list
         push @subjects,$subject;
      } else {
         # does not exist - error already set
         return 0;
      }
   }

   # check that object exists
   if ($self->existsEntity($object)) {
      # check that we have at least one subject
      if (@subjects > 0) {
         # we have subjects, do several replaces
         foreach (@subjects) {
            my $subject=$_;
            # ready to set role, overwrite potential existing
            my $sql=$self->doSQL("REPLACE INTO `MEMBER` (membersubject,memberobject) VALUES($subject,$object)") and $self->setMtime('MEMBER');
            if (!defined $sql) {
               # something failed - error already set - do rollback
               $t->rollback();
               return 0;
            }
         }
         # got through all of them successfully
         return 1;
      }
      # even if we do not have subjects, we return success
      return 1;
   } else {
      # something failed - error already set
      return 0;
   }
}

# remove entity member
sub removeEntityMember {
   my $self = shift;
   my $object = shift; # entity to remove member from
   my @insubs = @_; # member(s) to remove, undef=all members

   my $method=(caller(0))[3];

   # clean
   $object=$Schema::CLEAN{entity}->($object);

   # start transaction
   my $t=$self->useDBItransaction();

   # go through each subject, clean and ensure it exists 
   my @subjects;
   foreach (@insubs) {
      my $subject=$Schema::CLEAN{entity}->($_);

      if ($self->existsEntity($subject)) {
         # subject entity exists, add to list
         push @subjects,$subject;
      } else {
         # does not exist - error already set
         return 0;
      }
   }
       
   # check that object exists
   if ($self->existsEntity($object)) {
      # object exists - construct subjectstr
      my $subjectstr=join(",",@subjects);
      $subjectstr=($subjectstr ne "" ? " AND membersubject IN ($subjectstr)" : ""); # remove specific or all
      # ready to do the SQL
      my $sql=$self->doSQL("DELETE FROM `MEMBER` WHERE memberobject=$object$subjectstr") and $self->setMtime('MEMBER');
      if (defined $sql) {
         # successfully sql execution
         return 1;
      } else {
         # something failed - error already set
         return 0;
      }
   } else {
      # something failed - error already set
      return 0;
   }
}

sub removeEntityPermsAndRoles {
   my $self = shift;
   my $id = shift;
   my $others = shift || 0;

   $id=$Schema::CLEAN{entity}->($id);

   # set others string if so enabled
   my $otherstrp="";
   my $otherstrm="";
   if ($others) { $otherstrp=" or permobject=$id"; $otherstrm=" or memberobject=$id"; }

   # start transaction if not already started
   my $trans = $self->useDBItransaction();

   # check that entity exists
   my $ex=$self->existsEntity($id);
   if (!$ex) { return $ex; } # either failed or do not exist

   # attempt to remove all of entity's permissions and memberships/roles
   # and all permissions on the entity itself (if any)
   # first remove from PERM   
   my $sql = $self->doSQL("DELETE FROM `PERM` WHERE permsubject=$id$otherstrp") or return undef;
   # then remove from MEMBER
   $sql = $self->doSQL("DELETE FROM `MEMBER` WHERE membersubject=$id$otherstrm") or return undef;
   
   # we succeeded - return 1
   return 1;
}

sub getEntityPerm {
    # gets an entitys perm on a given object/entity. Input is an subject/entity-id and object/entity-id
    # ask first about entity's ancestors, then retrieve list of subjects perms on object.
    # return value is one bitmask (scalar).

    my $self = shift;
    my $subject = shift;
    my $object = shift;

    $subject=$Schema::CLEAN{entity}->($subject);
    $object=$Schema::CLEAN{entity}->($object);

    use bytes;

    # Check the parameters
    my $method=(caller(0))[3];
    if ($subject < 1 or $object < 1) {
        $self->{error}="$method(object,subject): missing/invalid parameter";
        return undef;
    }

    # start transaction if not already started
    my $transaction = $self->useDBItransaction();

    # get all permissions that subject has on these child(ren)
    my $query="SELECT * FROM PERM_EFFECTIVE_PERMS where permobject=$object and permsubject=$subject";
    my $sql = $self->doSQL($query) or return undef;

    # generate result
    my $perm='';
    # we only expect 1 iteration here...
    while (my @row=$sql->fetchrow_array()) {
       $perm=$row[2];
    }

    return $perm;
}

sub getEntityPermsOnObject {
    # gets an entitys perm on a given object/entity. Input is an subject/entity-id and object/entity-id
    # ask first about entity's ancestors, then retrieve list of subjects perms on object.
    # return value is one bitmask (scalar).

    my $self = shift;
    my $object = shift;

    $object=$Schema::CLEAN{entity}->($object);

    use bytes;

    # start transaction if not already started
    my $transaction = $self->useDBItransaction();

    my @path = $self->getEntityPath($object); # Anchesters line top down, subject included.

    my $path_q = join(",", @path);
    my $sql = "select permsubject,permobject,permgrant,permdeny
	       from PERM
	       where permobject in ($path_q)";
    my $query = $self->doSQL($sql) or return undef;
    my $utf8before = $self->setDBIutf8(0);
    my $perms = $query->fetchall_hashref(['permsubject','permobject']);
    $self->setDBIutf8($utf8before);
    
    my %result = ();
    foreach my $subject (keys %$perms) {
	my $inherit = '';
	my $deny = '';
	my $grant = '';
	my $perm = '';
	foreach my $node (@path) {
	    $inherit = $perm;
	    my $this = $perms->{$subject}{$node};
	    $deny  = defined($this->{permdeny})  ? $this->{permdeny}  : '';
	    $grant = defined($this->{permgrant}) ? $this->{permgrant} : '';
	    my $invert = "\377" x length($perm);
	    $perm &= ($invert ^ $deny);
	    $perm |= $grant;
	}
	$result{$subject} = {
	    inherit => $inherit,
	    deny => $deny,
	    grant => $grant,
	    perm => $perm,
	}
    }

    return \%result;
}

sub getEntityChildrenPerm {
    # gets an entitys perm on a given entity's children.
    # Input is subject, object and optionally recursive.
    # Returns a hashref { $id => $bitmask, ... }
    # If recursive is true it include the object it self and all descendants.

    use bytes;

    my $self      = shift;
    my $subject   = shift;
    my $object    = shift;
    my $recursive = shift; # true or false, no restriction on how
    my $types = shift; # entity types to look for

    my $method=(caller(0))[3];
    
    $subject   = $Schema::CLEAN{entity}->($subject);
    $object    = $Schema::CLEAN{entity}->($object);

    if (!$self->existsEntity($object)) { return undef; }
    if (!$self->existsEntity($subject)) { return undef; }

    if ((defined $types) && (ref($types) ne "ARRAY")) { $self->{error}="$method: Types parameter is not an array."; return undef; }
    
    my @ntypes;
    my $typesstr="";
    if (defined $types) {
       # go through and clean types id
       foreach (@{$types}) {
          my $type=$_;
          push @ntypes,$Schema::CLEAN{entitytype}->($type);
       }
       $typesstr=join(",",@ntypes);
       if ($typesstr ne "") { $typesstr=" and entitytype in ($typesstr)"; }
    }

    # start transaction if not already started
    my $transaction = $self->useDBItransaction();

    # Select SQL for the children, either recursively (all descendants) or not...
    my $chlsql;
    if (!$recursive) {
       # non-recursive
       $chlsql = "SELECT entity FROM ENTITY WHERE entityparent = $object$typesstr";
    } else {
       # get all descendants of a parent object, including parent (recursive)
       $chlsql = "SELECT ANCESTORS.entity as entity FROM `ENTITY` LEFT JOIN `ANCESTORS` on ANCESTORS.entity=ENTITY.entity$typesstr WHERE ancestor = $object";
    }

    my %result;
    # get all permissions that subject has on these child(ren)
    my $sql="SELECT A.entity,P.perms FROM ($chlsql) A left join `PERM_EFFECTIVE_PERMS` P on P.permobject=A.entity and P.permsubject=$subject ORDER BY P.permobject";
    my $query = $self->doSQL($sql) or return undef;

    # generate result
    while (my @res=$query->fetchrow_array()) {
       my $obj=$res[0];
       my $perms=$res[1];

       $result{$obj}=$perms;           
    }
    return \%result;
}

sub getEntityPermCheck {
    # Check if you have all in a set of permissions.
    # Return 1 if all is granted, 0 if any is missing.
    my $self = shift;
    my $subject = shift;
    my $object = shift;
    my $want = shift; # bitmap with bits to check. Leave undef to check for any permission.

    my $method=(caller(0))[3];

    $subject=$Schema::CLEAN{entity}->($subject);
    $object=$Schema::CLEAN{entity}->($object);
    $want=$Schema::CLEAN{bitmask}->($want);

    # Check the parameters
    if ($subject < 1 or $object < 1 or !defined($want)) {
        $self->{error}="$method(object,subject,want): missing/invalid parameter";
        return undef;
    }
    
    my $got = $self->getEntityPerm($subject, $object);
    return undef unless defined $got;
    return 1 if ($want & $got) eq $want;
    return 0;
}

sub getEntityPermByObject {
    # get perms on a specific entity (no ancestors)
    # input entity-id of subject and object. 
    # Return value is ref to a list of grant and deny bitmasks, witch may be undef.
    # Returned bitmasks are undef if no grant/deny exists for this pair.

    my $self = shift;
    my $subject = shift;
    my $object = shift;

    my $method=(caller(0))[3];

    $subject=$Schema::CLEAN{entity}->($subject);
    $object=$Schema::CLEAN{entity}->($object);

    # Check the parameters
    if ($subject < 1 or $object < 1) {
        $self->{error}="$method(object,subject): missing/invalid parameter";
        return undef;
    }

    my $sql = "select permgrant,permdeny from PERM where permsubject=$subject and permobject=$object";
    my $query = $self->doSQL($sql) or return undef;

    my $utf8before = $self->setDBIutf8(0);
    my ($grant,$deny) = $query->fetchrow_array();
    $self->setDBIutf8($utf8before);
    return [$grant, $deny];
}

sub setEntityPermByObject {
    # Set perm on a specific entity (no ancestors)
    # Input entity-id of subject, object, grant bitmask, deny bitmask and set/clear/replace. 
    # Rreturn resultant bitmasks as ref to a list of grant and deny bitmasks. May be undef.
    # Return undef on failure.
    my $method=(caller(0))[3];
    
    my $self = shift;
    my $subject = shift;
    my $object = shift;
    my $grant = shift;
    my $deny = shift;
    my $operation = shift; # undef: replace bits, true: set bits, false: clear bits;

    $subject=$Schema::CLEAN{entity}->($subject);
    $object=$Schema::CLEAN{entity}->($object);
    $grant=$Schema::CLEAN{bitmask}->($grant);
    $deny=$Schema::CLEAN{bitmask}->($deny);
    $operation=$Schema::CLEAN{operation}->($operation);
   
    # Check the subject and object parameters
    if ($subject < 1 or $object < 1) {
        $self->{error}="$method(object,subject,...): missing/invalid parameter";
        return undef;
    }
    
    # start transaction if not already started
    my $transaction = $self->useDBItransaction();

    my @imasks = ($grant, $deny);
    my @omasks = ('','');
    if (defined $operation) {
	my $perms = $self->getEntityPermByObject($subject, $object);
	return undef unless defined $perms;
        if (@$perms) { @omasks = @$perms; }
        else         { @omasks = ('',''); }
    }
    foreach my $n (0,1) {
	# Operate on ref to the scalars
	my $i = \$imasks[$n]; 
	my $o = \$omasks[$n];
	#
	if (defined $$i) { 
	    if (defined $operation) { 
		$$o = "" unless defined $$o; # In case not previously set.
		if ($operation) { # Set the bits
		    $$o |= $$i;
		}
		else { # Clear the bits
		    my $invert = "\377" x length($$o);
		    $$o &= ($invert ^ $$i);
		}
	    }
	    else {
		$$o = $$i;
	    }
	}
    }

    my $sql;
    if (join('', @omasks) =~ /\A\x{0}*\z/) { # noop - remove entry if exists
	$sql = "delete from PERM where permsubject=$subject and permobject=$object"; 
    }
    else {
	my $grant_q = $self->getDBI->quote($omasks[0]); 
	my $deny_q  = $self->getDBI->quote($omasks[1]); 
	$sql = "replace into PERM(permsubject,permobject,permgrant,permdeny) values($subject,$object,$grant_q,$deny_q)";
    }
    my $update = $self->doSQL($sql) and $self->setMtime('PERM') or return undef;
    return \@omasks;
}

sub updateEffectivePerms {
    my $self = shift;
    #
    my $transaction = $self->useDBItransaction();
    my $dbi = $self->getDBI;
    my $method=(caller(0))[3];
    #
    my %effective = ();
    my $query;
    #
    # Calculate effective perms
    $query = $dbi->prepare("
                           select permsubject,permobject,permgrant,permdeny,perms 
                           from PERMISSIONS 
                           natural left join PERM_EFFECTIVE_PERMS
                           order by sequence
                           ") and
        $query->execute;
    if ($dbi->err) { $self->{error} = "$method: ".$dbi->errstr; return undef; }
    while (my @row = $query->fetchrow_array) {
        my ($subj, $obj, $grant, $deny, $old) = @row;
        my $perm = exists($effective{$subj}{$obj}) ? $effective{$subj}{$obj}[0] : '';
        $effective{$subj}{$obj} = [ $grant | ($perm ^ ($perm & $deny)), $old ];
    }
    #
    # Update table
    foreach my $subj (keys %effective) {
        foreach my $obj (keys %{$effective{$subj}}) {
            my ($new, $old) = @{$effective{$subj}{$obj}};
            my $new_q = $dbi->quote($new);
            if (defined $old) {
                if ($new eq "") {
                    $dbi->do("delete from PERM_EFFECTIVE_PERMS where permsubject=$subj and permobject=$obj");
                }
                elsif ($new ne $old) {
                    $dbi->do("update PERM_EFFECTIVE_PERMS set perms=$new_q where permsubject=$subj and permobject=$obj");
                }
            }
            else {
                if ($new ne "") {
                    $dbi->do("insert into PERM_EFFECTIVE_PERMS(permsubject,permobject,perms) values($subj,$obj,$new_q)");
                }
            }
            if ($dbi->err) { $self->{error} = "$method: ".$dbi->errstr; return undef; }
        }
    }
    #
    # Delete unknown entries
    $query = $dbi->prepare("select permsubject,permobject from PERM_EFFECTIVE_PERMS")
        and $query->execute;
    if ($dbi->err) { $self->{error} = "$method: ".$dbi->errstr; return undef; }
    while (my @row = $query->fetchrow_array) {
        my ($subj, $obj) = @row;
        next if exists $effective{$subj}{$obj};
        $dbi->do("delete from PERM_EFFECTIVE_PERMS where permsubject=$subj and permobject=$obj");
        if ($dbi->err) { $self->{error} = "$method: ".$dbi->errstr; return undef; }
    }
    #
    # Update LUT table with new entries
    $query = $dbi->prepare("
           select distinct e.perms
           from ( select perms     from PERM_EFFECTIVE_PERMS union
                  select permdeny  from PERM                 union
                  select permgrant from PERM
                  ) e
           natural left join PERM_EFFECTIVE_LUT l
           where l.perms is NULL
           ") and $query->execute;
    if ($dbi->err) { $self->{error} = "$method: ".$dbi->errstr; return undef; }
    while (my @row = $query->fetchrow_array) {
        my ($perms) = @row;
        my $perms_q = $dbi->quote($perms);
        my @bits = split(//,unpack("b*", $perms));
        my $bit = 0;
        while (@bits) {
            $dbi->do("insert into PERM_EFFECTIVE_LUT values($perms_q,$bit)") if shift(@bits);
            if ($dbi->err) { $self->{error} = "$method: ".$dbi->errstr; return undef; }
            $bit++;
        }
    }
    return 1;
}

sub updateEffectivePermsConditional {
    my $self = shift;
    #
    my $transaction = $self->useDBItransaction();
    my $mtime = $self->getMtime(qw(ENTITY PERM MEMBER));
    if (!defined($mtime) or $self->getMtime('PERM_EFFECTIVE_PERMS') != $mtime) {
        $self->updateEffectivePerms or return undef;
        $self->setMtime('PERM_EFFECTIVE_PERMS', $mtime);
    }
    return 1;
}

sub getEntityPermsForSubject { # return hash with object=>perm for a subject
    my $self = shift;
    my $subject = shift; # Subject to find perms for 
    my $want = shift;    # Optional mask with perms to report
    my $type = shift;    # Optional object type filter
    #
    $subject=$Schema::CLEAN{entity}->($subject);
    $want=$Schema::CLEAN{bitmask}->($want) if defined($want);
    $type=$Schema::CLEAN{entitytype}->($type) if defined($want);
    #
    my $dbi = $self->getDBI;
    my @roles = $self->getEntityRoles($subject);
    my $roles = join(',', @roles);
    my $query = $self->doSQL("select permobject,permgrant,permdeny from PERM where permsubject in ($roles)") or return undef;
    #
    # Direct permissions
    my %found = ();   # Objects found with 
    my %descend = (); # Subject marked for inheritance
    my $utf8before = $self->setDBIutf8(0);
    while (my @row = $query->fetchrow_array()) {
        my ($object, $grant, $deny) = @row;
        if (defined $want) {
            $grant &= $want;
            $deny &= $want;
        }
        $found{$object} = [$grant, $deny];
        $descend{$object} = 1 if $grant !~ /\A\x{0}*\z/; # Mark for inheritance if anything to inherit
    }
    $self->setDBIutf8($utf8before);
    #
    # Inherit permissions
    while (%descend) {
        #
        # Find all children of the markobjects marked for inheritance
        my $parents = join(',', keys %descend);
        my $query = $self->doSQL( "
                                  select entity,entityparent
                                  from ENTITY 
                                  where entityparent in ($parents)
                                  " ) or return undef;
        %descend = ();
        #
        # Descend into children
        while (my @row = $query->fetchrow_array()) {
            my ($object, $parent) = @row;
            my $perm = $found{$parent}[0];                  # Inherit permission from parent
            if (exists $found{$object}) {                   # If already found, merge inhereted rights
                my $grant = $found{$object}[0];
                my $deny = $found{$object}[1];
                if (defined $deny) {                        # Strip any denied bits
                    my $invert = "\377" x length($perm);
                    $perm &= ($invert ^ $deny);
                }
                if (defined $grant) {                       # Add any grantet
                    $perm |= $grant;
                }
                if ($found{$object}[0] ne $perm) {                  # If permision changed by inheritance...
                    $found{$object}[0] = $perm;                     #   - Update
                    $descend{$object} = 1 unless $perm =~ /\A\x{0}*\z/;  #   - Mark for inheritance
                }
            }
            else {                            # Not previous found.
                $found{$object} = [$perm,'']; #   - Create with inherited perms.
                $descend{$object} = 1;        #   - Mark for inheritance
            }
        }
    }
    #
    # Convert %found from object=>[g,d] to object=>g and strip blanks 
    foreach my $object (keys %found) {
        $found{$object} = $found{$object}[0];
        delete($found{$object}) if $found{$object} =~ /\A\x{0}*\z/;
    }
    #
    # Filter on type if specified.
    if ($type and %found) {
        my $objects = join(',', keys %found);
        my $query = $self->doSQL( "
                                  select entity 
                                  from ENTITY 
                                  where entity in ($objects) and entitytype!=$type 
                                  " ) or return undef;
        while (my @row = $query->fetchrow_array()) {
            delete($found{$row[0]});
        }       
    }
    return \%found;
}

sub getEntityPermsForObject {
    my $self = shift;
    my $object = shift;
    my $want = shift;
    my $type = shift;
    #
    $object=$Schema::CLEAN{entity}->($object);
    $want=$Schema::CLEAN{bitmask}->($want) if defined($want);
    $type=$Schema::CLEAN{entitytype}->($type) if defined($type);
    #
    my $dbi = $self->getDBI;

    # Get object path
    my @path = $self->getEntityPath($object) or return;
    return unless defined $path[0];

    # Get relevant records
    my $path = join(',', @path);
    my $query = $self->doSQL("select permsubject,permobject,permgrant,permdeny from PERM where permobject in ($path)") or return undef;
    #
    my %perms = ();
    my $utf8before = $self->setDBIutf8(0);
    while (my @row = $query->fetchrow_array()) {
        my ($subject, $object, $grant, $deny) = @row;
        if (defined $want) {
            $grant &= $want;
            $deny &= $want;
        }
        next if "$grant$deny"=~ /\A\x{0}*\z/;
        $perms{$subject}{$object} = [$grant, $deny];
    }
    $self->setDBIutf8($utf8before);
    
    # Evaluate path inheritance
    my $parent = 0;
    foreach my $object (@path) {
        foreach my $subject (keys %perms) {
            my $perm = ($parent and defined $perms{$subject}{$parent}[0])? $perms{$subject}{$parent}[0] : '';
            my $invert = "\377" x length($perm);
            my @roles = $self->getEntityRoles($subject) or return;
            foreach my $role (@roles) {
                next unless defined $perms{$role}{$object}[1];
                $perm &= ($invert ^ $perms{$role}{$object}[1]);
            }
            foreach my $role (@roles) {
                next unless defined $perms{$role}{$object}[0];
                $perm |= $perms{$role}{$object}[0];
            }
            $perms{$subject}{$object}[0] = $perm;
        }
        $parent = $object;
    }

    # Strip %perms for superfluous information
    foreach my $subject (keys %perms) {
        if ($perms{$subject}{$object}[0] =~ /\A\x{0}*\z/) {
            delete($perms{$subject});
            next;
        }
        $perms{$subject} = $perms{$subject}{$object}[0];
    }
    
    # Cascade memberships, including implisit through childhood;
    my %cascade = %perms;
    while (%cascade) {
        my $groups = join(',', keys %cascade);
        %cascade = ();
        my $sql = "(
                                  select membersubject,memberobject 
                                  from MEMBER 
                                  where memberobject in ($groups)
                                  ) union (
                                  select entity,entityparent 
                                  from ENTITY 
                                  where entityparent in ($groups)
        )";
        my $query = $self->doSQL($sql) or return undef;
        while (my @row = $query->fetchrow_array()) {
            my ($subject, $object) = @row;
            $perms{$subject} = '' unless exists $perms{$subject};
            my $old = $perms{$subject};
            $perms{$subject} |= $perms{$object};
            $cascade{$subject} = 1 if $perms{$subject} ne $old;
        }
    }

    # Filter on type if specified.
    if ($type and %perms) {
        my $subjects = join(',', keys %perms);
        my $query = $self->doSQL( "
                                  select entity 
                                  from ENTITY 
                                  where entity in ($subjects) and entitytype!=$type 
                                  " ) or return undef;
        while (my @row = $query->fetchrow_array()) {
            delete($perms{$row[0]});
        }       
    }
    
    return \%perms;
}

sub createBitmask {
    my $self = shift;
    my @bits = @_;

    my $method=(caller(0))[3];

    # check bits
    foreach (@bits) {
       my $bit=$_;

       next unless defined $bit; # skip undef bits

       if ($bit !~ /^\d+$/) {
          # wrong format in bits - return error
          $self->{error}="$method(bits): Bitmask cannot contain non-digit input. Unable to create bitmask.";
          return undef;
       }
    }

    # creates bitmask based upon the bit no specified in the input list. - iterate on vec-method in perl.
    my $mask="";
    foreach my $bit (@bits) {
	return undef unless defined $bit; # DONT set error code, it will mask the underlying error.
	vec($mask,$bit,1) = 1;
    }
    return $mask;
}

sub setBitmask {
    my $self = shift;
    my $bitmask = shift;
    my $set = shift;
    $bitmask = '' unless defined $bitmask;
    $set     = '' unless defined $set;
    return $bitmask | $set;
}
sub setBits { 
    my $self = shift;
    my $bitmask = shift;
    return $self->setBitmask($bitmask, $self->createBitmask(@_));
}
sub clearBitmask {
    my $self = shift;
    my $bitmask = shift;
    my $clear = shift;
    $bitmask = '' unless defined $bitmask;
    $clear   = '' unless defined $clear;
    my $invert = "\377" x length($bitmask);
    return $bitmask & ($invert ^ $clear);
}
sub clearBits { 
    my $self = shift;
    my $bitmask = shift;
    return $self->clearBitmask($bitmask, $self->createBitmask(@_));
}


# deconstructs the bitmask into
# bit positions of the bits that have been set
sub deconstructBitmask {
   my $self=shift;

   my $perm=shift;

   if (!defined $perm) { return []; }

   my @bits=split(//,unpack("b*",$perm));
   
   my @set;
   my $pos=-1;
   foreach (@bits) {
      my $bit=$_;
      $pos++;

      if ($bit == 1) {
         # store this bit position as set to 1
         push @set,$pos;
      }
   }

   # return the array of set positions
   return @set;
}

sub enumPermTypes {
    my $self = shift;
    my $method=(caller(0))[3];

    unless (exists $self->{permtype}) {
	my $query = $self->doSQL("select PERMTYPE,PERMNAME from PERMTYPE") or return undef;
	$self->{permtype} = {};
	while (my @row = $query->fetchrow_array()) {
	    $self->{permtype}{name}{$row[0]} = $row[1];
	    $self->{permtype}{value}{$row[1]} = $row[0];
	}
    }
    return keys(%{$self->{permtype}{value}});
}

sub getPermTypeValueByName {
    my $self = shift;

    my $method=(caller(0))[3];

    $self->enumPermTypes() or return undef;
    my @list = ();
    foreach (@_) {
        my $in=$_;
	return undef unless defined $in; # DONT set error code, it will mask the underlying error.
        $in=$Schema::CLEAN{permname}->($in);
	my $out = $self->{permtype}{value}{$in};
	unless (defined $out) {
	    $self->{error} = "$method($in): permission $in is not defined!";
	    return undef;
	}
	push(@list, $out);
    }
    return @list;
}

sub getPermTypeNameByValue {
    my $self = shift;
    my $method=(caller(0))[3];

    $self->enumPermTypes() or return undef;
    my @list = ();
    foreach (@_) {
        my $in=$_;
	return undef unless defined $in; # DONT set error code, it will mask the underlying error.
        $in=$Schema::CLEAN{permvalue}->($in);
	my $out = $self->{permtype}{name}{$in};
	unless (defined $out) {
	    $self->{error} = "$method($in): permission $in is not defined!";
	    return undef;
	}
	push(@list, $out);
    }
    return @list;
}

sub createPermBitmask { 
    # Shortcut for $self->createBitmask($self->getPermTypeValueByName(list))
    # Accepts mix of names and numbers
    my $self = shift;
    my @bits = @_;
    my $method=(caller(0))[3];

    $self->enumPermTypes() or return undef;
    
    my $mask="";
    foreach my $bit (@bits) {
	return undef unless defined $bit; # DONT set error code, it will mask the underlying error.
	unless ($bit =~ /^\d+$/) {
	    unless (exists $self->{permtype}{value}{$bit}) {
		$self->{error} = "$method($bit): permission $bit is not defined!";
		return undef;
	    }
	    $bit = $self->{permtype}{value}{$bit};
	}
	vec($mask,$bit,1) = 1;
    }
    return $mask;
}

# get all metadata for an entity 
# input entity-id. 
# return is hash, undef upon error
sub getEntityMetadata {
   my $self = shift;
   my $entity = shift || 0; # set a default, invalid entity id
   my %opts;
   # check for options hash before list
   if (@_ && ref($_[0])) { %opts=%{shift()}; }
   my @metadata = @_;
   my $tableopt = $opts{parent};

   # clean tableopt (select between availability to search in parent md or not)
   $tableopt=$Schema::CLEAN{tableopt}->($tableopt);
   my $tablename=($tableopt ? "METADATA_COMBINED" : "METADATA");

   my $method=(caller(0))[3];

   # check entity id
   if ($self->existsEntity($entity)) {   
      $entity=$Schema::CLEAN{entity}->($entity);
      my $dbi=$self->getDBI();
      # go through possible metadata key moderators
      my $moderators="";
      foreach (@metadata) {
         my $name=$_ || "";
         # clean and quote
         $name=$Schema::CLEAN{metadatakey}->($name,1);
         # replace wildcard with SQL percentage
         $name=~s/[\*]/\%/g;
         $name=$dbi->quote($name);
         # set suitable comparator if wildcard or not
         my $cmp=($name =~ /.*\%.*/ ? "LIKE" : "=");         
         $moderators=($moderators eq "" ? "METADATAKEY.metadatakeyname $cmp $name" : $moderators." or METADATAKEY.metadatakeyname $cmp $name");
      }
      # if moderators are empty, keep it so, if not add "and" and paranthesis.
      $moderators=($moderators eq "" ? $moderators : " and ($moderators)");
  
      # entity exists - lets get metadata
      my $sql=$self->doSQL("SELECT ${tablename}.metadatakey,metadatakeyname,metadataidx,metadataval FROM `${tablename}` ".
                           "LEFT JOIN `METADATAKEY` on ${tablename}.metadatakey = METADATAKEY.metadatakey ".
                           "WHERE ${tablename}.entity = $entity$moderators ".
                           "ORDER BY ${tablename}.metadatakey,${tablename}.metadataidx ASC"
                           );
      if (defined $sql) {
         # success, go through metadata 
         my %metadata;
         # most efficient with fetchrow_array and SQL specifies field order
         # 0=metadatakey, 1=metadatakeyname,2=metadataidx,3=metadataval
         while (my @row=$sql->fetchrow_array()) {
            # check if keyname exists or not
            if (!defined $row[1]) { next; }
            # check if array or not
            if (exists $metadata{$row[1]}) {
               # this is an array value, check if previous value is an array or not
               my @list;
               if (ref(\$metadata{$row[1]}) eq "SCALAR") {
                  push @list,$metadata{$row[1]};
               } else {
                  @list=@{$metadata{$row[1]}};
               }
               # add latest value to list
               push @list,$row[3];
               # set keyname to list
               $metadata{$row[1]}=\@list;
            } else {
               # this is not an array value - just add the scalar
               $metadata{$row[1]}=$row[3];
            }
         }
         # return hash, empty or not
         return \%metadata;
      } else {
         # error already set by doSQL
         return undef;
      }
   } else {
      # entity does not exist
      $self->{error}="$method: Entity does not exist ($entity). Unable to get any metadata";
      return undef;
   }
}

sub getEntityMetadataList {
   my $self=shift;
   my $mdkey=shift || "";
   my $entities=shift;
   my $tableopt = shift || 0;

   # clean tableopt (select between availability to search in parent md or not)
   $tableopt=$Schema::CLEAN{tableopt}->($tableopt);
   my $tablename=($tableopt ? "METADATA_COMBINED" : "METADATA");

   my $method=(caller(0))[3];

   if ((defined $entities) && (ref($entities) ne "ARRAY")) {
      $self->{error}="$method: Optional entities parameter is not an ARRAY-reference. Unable to proceed.";
      return undef;
   } 

   # clean values
   $mdkey=$Schema::CLEAN{metadatakey}->($mdkey);
   my $dbi=$self->getDBI();
   if (!defined $dbi) {
      # something failed - error already set
      return undef;
   }
   my $qmdkey=$dbi->quote($mdkey);
   if (defined $entities) {
      for (my $i=0; $i < @{$entities}; $i++) {
         $entities->[$i]=$Schema::CLEAN{entity}->($entities->[$i]);
      }
   }

   # make in-str
   my $instr="";
   foreach (@{$entities}) {
      $instr=($instr eq "" ? $_ : "$instr,$_");
   }
   $instr=($instr eq "" ? "" : " AND ENTITY.entity in ($instr)");

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();
   
   my $sql=$self->doSQL("SELECT ENTITY.entity,metadataidx,metadataval FROM ENTITY ".
                        "LEFT JOIN ${tablename} on ENTITY.entity = ${tablename}.entity ".
                        "LEFT JOIN METADATAKEY on ${tablename}.metadatakey = METADATAKEY.metadatakey ".
                        "WHERE METADATAKEY.metadatakeyname = $qmdkey$instr ".
                        "ORDER BY ENTITY.entity,metadataidx ASC");

   if (defined $sql) {
      # fetch results and add to hash
      my %result;
      while (my @row=$sql->fetchrow_array()) {
         my $id=$row[0];
         my $value=$row[2];
         if (exists $result{$id}) {
            # already exists - add to existing value
            my @v;
            if (ref($result{$id}) eq "ARRAY") {
               # get existing array
               @v=@{$result{$id}};
            } else {
               # this is a scalar
               # add existing value
               push @v,$result{$id};
            }
            # add new value
            push @v,$value;
            # assign LIST
            $result{$id}=\@v;
         } else {
            $result{$id}=$value;
         }
      }

      # return result
      return \%result;
   } else {
      # error already set
      return undef;
   }
}

sub getEntityMetadataMultipleList {
   my $self=shift;
   my $mdkeys=shift;
   my $entities=shift;
   my $tableopt = shift || 0;

   # clean tableopt (select between availability to search in parent md or not)
   $tableopt=$Schema::CLEAN{tableopt}->($tableopt);
   my $tablename=($tableopt ? "METADATA_COMBINED" : "METADATA");

   my $method=(caller(0))[3];

   if ((defined $mdkeys) && (ref($mdkeys) ne "ARRAY")) {
      $self->{error}="$method: Optional metadata keys parameter is not an ARRAY-reference. Unable to proceed.";
      return undef;
   }

   if ((defined $entities) && (ref($entities) ne "ARRAY")) {
      $self->{error}="$method: Optional entities parameter is not an ARRAY-reference. Unable to proceed.";
      return undef;
   } 

   my $dbi=$self->getDBI();
   if (!defined $dbi) {
      # something failed - error already set
      return undef;
   }

   # clean metadata keys, if defined
   my $mdkeystr="";
   if (defined $mdkeys) {
      my @l;
      foreach (@{$mdkeys}) {
         my $key=$Schema::CLEAN{metadatakey}->($_);       

         # quote its value
         $key=$dbi->quote($key);

         # add to list 
         push @l,$key;

         $mdkeystr=($mdkeystr eq "" ? "(METADATAKEY.metadatakeyname = $key" : $mdkeystr." or METADATAKEY.metadatakeyname = $key");
      }
      if (@l > 0) { 
         $mdkeys=\@l;
         $mdkeystr.=")";
      }     
   }
   if ($mdkeystr eq "") { $mdkeystr="1"; }

   # clean entities, if any
   if (defined $entities) {
      for (my $i=0; $i < @{$entities}; $i++) {
         $entities->[$i]=$Schema::CLEAN{entity}->($entities->[$i]);
      }
   }

   # make in-str
   my $instr="";
   foreach (@{$entities}) {
      $instr=($instr eq "" ? $_ : "$instr,$_");
   }
   $instr=($instr eq "" ? "" : " AND ENTITY.entity in ($instr)");

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   my $sql=$self->doSQL("SELECT ENTITY.entity,metadatakeyname,metadataidx,metadataval FROM ENTITY ".
                        "LEFT JOIN ${tablename} on ENTITY.entity = ${tablename}.entity ".
                        "LEFT JOIN METADATAKEY on ${tablename}.metadatakey = METADATAKEY.metadatakey ".
                        "WHERE $mdkeystr$instr ".
                        "ORDER BY ENTITY.entity,metadataidx ASC");

   if (defined $sql) {
      # fetch results and add to hash
      my %result;
      while (my @row=$sql->fetchrow_array()) {
         my $id=$row[0];
         my $name=$row[1];
         my $value=$row[3];
         # check if name exists or not
         if (!defined $name) { next; }
         if (exists $result{$id}{$name}) {
            # already exists - add to existing value
            my $v;
            if (ref($result{$id}{$name}) eq "ARRAY") {
               # get existing array
               $v=$result{$id}{$name};
            } else {
               # this is a scalar
               # add existing value
               my @l; 
               $v=\@l;
               push @{$v},$result{$id}{$name};
            }
            # add new value
            push @{$v},$value;
            # assign LIST
            $result{$id}{$name}=$v;
         } else {
            $result{$id}{$name}=$value;
         }
      }

      # return result
      return \%result;
   } else {
      # error already set
      return undef;
   }
}

sub setEntityMetadata {
  # set an entity's metadata. old overwritten/updated, new inserted. 
  # input entity-id and hash. chech compliance with metadata template.
  # return either 1 on success or 0 on fail.
   my $self=shift;
   my $entity=shift || 0; # set a default invalid entity id
   my $metadata=shift || undef; # metadata to add
   my $type=shift; # template type to check against, if none is given the entitys type itself is used
   my $path=shift; # template path to use for aggregating template, if none given the path of the entity itself it selected
   my $override=shift||0; # override template settings to allow critical updates to go through. Use with care
                          # the values in metadata will still be cleaned to comply with DB requirements

   my $method=(caller(0))[3];

   # check if we have metadata at all
   if ((!defined $metadata) || (ref($metadata) ne "HASH")) {
      # invalid metadata, unable to set
      $self->{error}="$method: Metadata not defined or invalid. Unable to set metadata";
      return 0;
   }

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # check entity id 
   if ($self->existsEntity($entity)) {
      $entity=$Schema::CLEAN{entity}->($entity);
      my $dbi=$self->getDBI();

      # get existing metadata - if any
      my $sql=$self->doSQL("SELECT METADATA.metadatakey,metadatakeyname,metadataidx,metadataval FROM `METADATA` ".
                           "LEFT JOIN `METADATAKEY` on METADATA.metadatakey = METADATAKEY.metadatakey ".
                           "WHERE METADATA.entity = $entity ".
                           "ORDER BY METADATA.metadatakey,METADATA.metadataidx ASC"
                           );

      # check for success
      if (defined $sql) {
         # go through metadata and create a hash
         my %existing;
         while (my @row=$sql->fetchrow_array()) {
            # check if array or not
            if (exists $existing{$row[1]}) {
               # this is an array value, check if previous value is an array or not
               my @list;
               if (ref(\$existing{$row[1]}{value}) eq "SCALAR") {
                  push @list,$existing{$row[1]}{value};
               } else {
                  @list=@{$existing{$row[1]}{value}};
               }
               # add latest value to list
               push @list,$row[3];
               # save value of key
               $existing{$row[1]}{value}=\@list;
               # save key id
               $existing{$row[1]}{key}=$row[0];
               # set size
               $existing{$row[1]}{size}=@list;
            } else {
               # this is not an array value - just add the scalar
               $existing{$row[1]}{value}=$row[3];
               # save key id
               $existing{$row[1]}{key}=$row[0];
               # set size
               $existing{$row[1]}{size}=1;
            }                      
         }

         # only do the following checks if override evaluates to false
         if (!$override) {
            # get entity template aggregate so we can check if a key is to be persistent
            if ((!defined $path) || (ref($path) ne "ARRAY")) {
               # none specified - use the path of the entity
               $path=$self->getEntityTemplatePath ($entity);
               if (!defined $path) {
                  # error already set
                  return 0;
               }
            }
            my $templ=$self->getEntityTemplate($type,@{$path});

            if (!defined $templ) {
               # something failed - error already set
               return 0;
            }

            # define persistent-flag
            my $persist=($self->createBitmask($self->getTemplateFlagBitByName("PERSISTENT")))[0];

            # add existing metadata where none exist in new metadata to ensure correct functioning
            my @persistent;
            my %mdcheck=%{$metadata};
            foreach (keys %existing) {
               my $key=$_;
               my $flags=$templ->{$key}{flags};

               # check flags for wide characters
               if ((defined $flags) && ($Schema::CHECK{utf8wide}->($flags))) {
                  $self->{error}="$method: Flags for key $key contains characters above 0xFF. Unable to perform bitwise operations. Unable to continue.";
                  return 0;
               }

               # remove key if the PERSISTENT-flag has been set and 
               # it is attempting to set new value on key
               if ((defined $flags) && (($flags & $persist) eq $persist)) { 
                  # if a new value exists in metadata to check, delete it
                  delete ($metadata->{$key});
                  if (exists $mdcheck{$key}) { 
                     # delete new value, we already have a persistent old one
                     delete ($mdcheck{$key});
                  }
                  # save the name of all persistent keys for use later.
                  push @persistent,$key;
                  next;
               }

               # add value to metadata to check, if no new value there
               if (!exists $mdcheck{$key}) {
                  $mdcheck{$key}=$existing{$key}{value};
               }
            }
            # DO SOME TEMPLATE CHECKING
            my $check=$self->checkEntityTemplateCompliance($entity,\%mdcheck,$type,$path);

            if (!defined $check) {
               # error already set
               return 0;
            }

            # remove any returned keys that were persistent earlier
            # to avoid issues with MANDATORY and default settings
            foreach (@persistent) {
               my $key=$_;

               if (exists $check->{metadata}{$key}) {
                  # remove the whole key, we do not care about the result
                  delete ($check->{metadata}{$key});
               }
            }        

            # break off if not compliant, even if that is because of a new 
            # setting in a persistent key.
            if (!$check->{compliance}) {
               $self->{error}="$method: Input metadata is not compliant with entity template in the key(s): @{$check->{noncompliance}}. Cannot set entity metadata.";
               return 0;
            }

            # add missing metadata from template
            foreach (keys %{$check->{metadata}}) {
               my $key=$_;
 
               # only add key to metadata if it is not in input metadata or in
               # existing metadata (we do not want to trigger update on values that are already in place
               if ((!(exists $metadata->{$key})) && (!exists $existing{$key})) {
                  # add missing keys from template to metadata
                  $metadata->{$key}=$check->{metadata}{$key}{value};
               }
            }
         }

         # go through and clean metadata hash
         foreach (keys %{$metadata}) {
            my $key=$_;

            if (ref(\$metadata->{$key}) eq "SCALAR") { # also undef value
               # GENERAL METADATA CLEAN
               my $value=$Schema::CLEAN{metadataval}->($metadata->{$key});
               # put cleaned value in place
               $metadata->{$key}=$value;
            } elsif (ref($metadata->{$key}) eq "ARRAY") {
               my @l=@{$metadata->{$key}};
               my @n;
               foreach (@l) {
                  my $item=$_;
                  # GENERAL METADATA CLEAN
                  $item=$Schema::CLEAN{metadataval}->($item);
                  push @n,$item;
               }
               # update metadata
               $metadata->{$key}=\@n;
            } else {
               # invalid type, remove from hash
               delete ($metadata->{$key});
            }
         }

         # build update hash
         my %updates;
         foreach (keys %existing) {
            my $key=$_;

            # check to see if key exists in metadata that is to be set (ie it is an update)
            if (exists $metadata->{$key}) {
               $updates{$key}=$metadata->{$key};
               # remove key from input metadata, so that in the end we have only inserts here
               delete ($metadata->{$key});
            }
         }

         # do update where possible, then insert and then clean up by deleting surplus
         foreach (keys %updates) {
            my $key=$_;

            # do some general stuff
            my $keyid=$existing{$key}{key} || 0;
            # create list with one or several items
            my $type;
            my @list;            
            if (ref(\$updates{$key}) eq "SCALAR") { 
               push @list,$updates{$key};
               $type="SCALAR";
            } elsif (ref($updates{$key}) eq "ARRAY") {
               @list=@{$updates{$key}};
               $type="ARRAY";
            }

            # we know that keys exists already up to a certain size, so we
            # proceed with the list
            my $size=$existing{$key}{size} || 1;
            my $i=0;            
            foreach (@list) {
               my $value=$_;
               # check previous value, if any
               # increment index 
               $i++;
               # if identical or not
               my $identical=0;
               if ($i <= $size) {
                  if (($type eq "SCALAR") && ($value eq $existing{$key}{value})) {
                     $identical=1;
                  } elsif (($type eq "ARRAY") && (ref($existing{$key}{value}) eq "ARRAY") && ($value eq $existing{$key}{value}[$i-1])) {
                     $identical=1;
                  }
               } 
               # quote value to be used or accept undef value
               $value=$dbi->quote($value);
               # only update if value is not the same as before
               if (($i <= $size) && (!$identical)) {
                  # we know a row exists for this index, just overwrite value (more efficient)
                  my $sql=$self->doSQL("UPDATE `METADATA` set metadataval=$value WHERE entity=$entity and metadatakey=$keyid and metadataidx=$i");
               } elsif ($i > $size) {
                  # no row exists, so do an insert, less efficient
                  my $sql=$self->doSQL("INSERT INTO `METADATA` (entity,metadatakey,metadataidx,metadataval) VALUES ($entity,$keyid,$i,$value)");
               }
            }

            # delete surplus rows, if any
            if ($i < $size) {
               # we have surplus rows from before - remove
               my $sql=$self->doSQL("DELETE FROM `METADATA` WHERE entity=$entity and metadatakey=$keyid and metadataidx > $i");
            }
         }

         # last, but not least, do just inserts of remaining, new values
         foreach (keys %{$metadata}) {
            my $key=$_;

            # first create new key id (or get it if it exists)
            my $keyid=$self->createMetadataKey ($key);

            # create list with one or several items
            my @list;
            if (ref(\$metadata->{$key}) eq "SCALAR") { 
               push @list,$metadata->{$key};
            } elsif (ref($metadata->{$key}) eq "ARRAY") {
               @list=@{$metadata->{$key}};
            }

            if (defined $keyid) {
               # go through list and add
               my $i=0;
               foreach (@list) {
                  my $value=$_;

                  # quote value
                  $value=$dbi->quote($value);
                  # increment index
                  $i++;
                  my $sql=$self->doSQL("INSERT INTO `METADATA` (entity,metadatakey,metadataidx,metadataval) VALUES($entity,$keyid,$i,$value)");
               }
            }
         }

         return 1;
      } else {
         # error already set
         return 0;
      }
   } else {
      # entity does not exist
      $self->{error}="$method: Entity does not exist ($entity). Unable to set any metadata.";

      # error already set
      return 0;
   }
}

sub deleteEntityMetadata {
   # deletes all metadata from entity or Metadata specified by list ref (accepts wildcard *). Metadata keynames
   # in list that do not exist are just ignored (they are or'ed).
   # input is entity-id. Returns 1 on success, 0 on no rows to delete. Undef upon other failures.
   my $self = shift;
   my $entity = shift || 0; # default to an invalid entity id
   my $metadata = shift || undef;

   my $method=(caller(0))[3];

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   if (my $dbi=$self->getDBI()) {
      # clean entity
      $entity=$Schema::CLEAN{entity}->($entity);
      # go through possible metadata key moderators
      my $moderators="";
      foreach (@{$metadata}) {
         my $name=$_ || "";
         # clean and quote
         $name=$Schema::CLEAN{metadatakey}->($name,1);
         # replace wildcard with SQL percentage
         $name=~s/[\*]/\%/g;
         $name=$dbi->quote($name);
         # set suitable comparator if wildcard or not
         my $cmp=($name =~ /.*\%.*/ ? "LIKE" : "=");
         $moderators=($moderators eq "" ? "METADATAKEY.metadatakeyname $cmp $name" : $moderators." or METADATAKEY.metadatakeyname $cmp $name");
      }
      # if moderators are empty, keep it so, if not add "and" and paranthesis.
      $moderators=($moderators eq "" ? $moderators : " and ($moderators)");
      # do sql
      my $sql=$self->doSQL("DELETE METADATA.* FROM `METADATA` ".
                           "LEFT JOIN METADATAKEY on METADATA.metadatakey = METADATAKEY.metadatakey ".
                           "WHERE METADATA.entity = $entity$moderators"
                          );
      if (defined $sql) {
         # sql a success - check rows deleted to determine actual success
         if ($sql->rows() > 0) {
            # sql a success and rows affected
            return 1;
         } else {
            # sql a success, but no rows affected (already deleted or invalid entity most likely)
            return 1;
         }
      } else {
         # failed to delete - error already set by sql
         return undef;
      }
   } else {
      # error already set by getDBI
      return undef;
   }
}

sub getMetadataKey {
   # gets the metadata key by giving the metadatakeyname
   # returns the metadatakey id on success, 0 if key does not exist, undef upon failure.
   my $self = shift;
   my $name = shift || "";

   my $method=(caller(0))[3];

   if (my $dbi=$self->getDBI()) {
      # clean name
      $name=$Schema::CLEAN{metadatakey}->($name,0);

      # quote the value
      $name=$dbi->quote($name);
      my $sql=$self->doSQL("SELECT metadatakey FROM METADATAKEY ".
                           "WHERE metadatakeyname = $name");
      if ($sql) {
         # success
         my @row;
         # array is most efficient and we only have one field in query
         if (@row=$sql->fetchrow_array()) {
            # got row, now get the id.
            return $row[0];
         } else {
            # metadatakey does not exist
            $self->{error}="$method: Metadatakey does not exist";
            return 0;
         }
      } else {
         # error message already set by doSQL.
         return undef;
      }
   } else {
      # error already set
      return undef;
   }
}

sub createMetadataKey {
   my $self = shift;
   my $name = shift || "";
   # creates a metadatakey id by specifying a name/scalar.
   # if it exists, the existing id is returned, if not the newly created id is returned.
   # on failure, undef.
   # does an insert, then a select to check and find the new value. IF not exist - fail.
   # it is not allowed with blank key names and they have to be /a-zA-Z0-9\./ name must have at least one period (.)

   # start transaction if not already started
   my $method=(caller(0))[3];

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # check if it exists already
   if (my $mkey=$self->getMetadataKey($name)) {
      # return key
      return $mkey;
   } else {
      # does not exist
      my $dbi=$self->getDBI();
      # clean name
      $name=$Schema::CLEAN{metadatakey}->($name,0);
      $name=$dbi->quote($name);
      # create it
      my $sql=$self->doSQL("INSERT INTO `METADATAKEY` (metadatakeyname) VALUES ($name)");
      if (defined $sql) {
         # sql successful, read lastinsert_id
         my $id=$dbi->last_insert_id(undef,undef,undef,undef) || 0;

         # return the last insert id
         return $id;
      } else {
         # sql failed, error already set
         return undef;
      }
   }
}

sub deleteMetadataKey {
    # Delete unused metadata keys.
    # take keynames (accept wildcard *) as parameters to restrict the scope.
    # Returns 1 on success, 0 on no rows to delete. Undef upon other failures.
   my $self = shift;

   my $method=(caller(0))[3];

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   if (my $dbi=$self->getDBI()) {
      # go through possible metadata key moderators
      my $moderators="";
      foreach (@_) {
         my $name=$_ || "";
         # clean and quote
         $name=$Schema::CLEAN{metadatakey}->($name,1);
         # replace wildcard with SQL percentage
         $name=~s/[\*]/\%/g;
         $name=$dbi->quote($name);
         # set suitable comparator if wildcard or not
         my $cmp=($name =~ /.*\%.*/ ? "LIKE" : "=");
         $moderators=($moderators eq "" ? "METADATAKEY.metadatakeyname $cmp $name" : $moderators." or METADATAKEY.metadatakeyname $cmp $name");
      }
      # if moderators are empty, keep it so, if not add "and" and paranthesis.
      $moderators=($moderators eq "" ? $moderators : " and ($moderators)");
      # do sql
      my $sqlcode = qq[
	  delete from METADATAKEY 
	  where metadatakey in (
	      select metadatakey
	      from (select * from METADATAKEY) as MDK 
	      left join METADATA using (metadatakey) 
	      where entity is NULL $moderators
	      )
	  ];
      
      my $sql=$self->doSQL($sqlcode);
      if (defined $sql) {
         # sql a success - check rows deleted to determine actual success
         if ($sql->rows() > 0) {
            # sql a success and rows affected
            return 1;
         } else {
            # sql a success, but no rows affected (already deleted or invalid entity most likely)
            return 1; # Should be 0?
         }
      } else {
         # failed to delete - error already set by sql
         return undef;
      }
   } else {
      # error already set by getDBI
      return undef;
   }
}


sub enumTemplateFlags {
   my $self=shift;

   my $ctime=$self->{pars}{templateflagscache};
   my $tstamp=$self->{cache}{templateflags}{timestamp} || 0;

   my $method=(caller(0))[3];

   if (time() > ($tstamp+$ctime)) {
      # update cache
      my $sql=$self->doSQL("SELECT tmplflag,tmplflagname FROM `TMPLFLAG` ORDER BY tmplflag ASC");
      if (defined $sql) {
         # success - get result
         while (my @row=$sql->fetchrow_array()) {
            # uppercase the name
            my $key=uc($row[1]);
            # save value/key pair
            $self->{cache}{templateflags}{value}{$row[0]}=$key;
            # save key/value pair
            $self->{cache}{templateflagsname}{value}{$key}=$row[0];
         }
         # save timestamp
         $self->{cache}{templateflags}{timestamp}=time() || 0;
         # return just the values
         return sort {$a <=> $b} keys %{$self->{cache}{templateflags}{value}};
      } else {
         # somthing failed
         return undef;
      }
   } else {
      # serve answer from cache
      return sort {$a <=> $b} keys %{$self->{cache}{templateflags}{value}};
   }
}

sub getTemplateFlagBitByName {
   my $self=shift;

   my $method=(caller(0))[3];

   # ensure that we have the flag types loaded
   $self->enumTemplateFlags();

   # get flag names to get id for
   my @n=@_;
   my @names;
   # clean values
   foreach (@n) { 
      my $name=$_ || "";
 
      # clean the value
      $name=$Schema::CLEAN{templateflagname}->($name);
      # add to list
      push @names,$name;
   }

   if (@names == 0) {
      # fetch from cache
      @names=sort {$a cmp $b} keys %{$self->{cache}{templateflagsname}{value}};
   }

   my @values;
   foreach (@names) { 
      my $name;
      my $value=$self->{cache}{templateflagsname}{value}{$_} || undef;
      # do not push values that are not defined
      if (defined $self->{cache}{templateflagsname}{value}{$_}) {
         push @values,$value;
      } 
   }

   return @values;
}

sub getTemplateFlagNameByBit {
   my $self = shift;

   my $method=(caller(0))[3];

   # output names instead of values 
   # ensure that we have the flag types loaded
   $self->enumTemplateFlags();

   # get flags to get name for
   my @v=@_;
   my @values;
   # clean values
   foreach (@v) {
      my $value=$_ || 0;

      # clean the value
      $value=$Schema::CLEAN{templateflag}->($value);
      # add the value to list
      push @values,$value;
   }

   if (@values == 0) {
      # fetch from cache
      @values=sort keys %{$self->{cache}{templateflags}{value}};
   }

   my @names;
   foreach (@values) { 
      my $value=$_;

      $value=$self->{cache}{templateflags}{value}{$_} || undef;
      # only add name if value is defined
      if (defined $value) {
         push @names,$value;
      }
   }

   return @names;
}

# create a template. Input name of template and optionally a hash with
# the constraints values. Partly wrapper for createEntity
sub createTemplate {
   my $self = shift;
   my $parent = shift || 0;
   my $set = shift || undef; # hash ref

   my $method=(caller(0))[3];

   # check template constraints hash
   if ((defined $set) && (ref($set) ne "HASH")) {
      # wrong type, error
      $self->{error}="$method: This is not a hash ref. Unable to create template.";
      return 0;
   }

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # the creation is wrapper around createEntity
   my $tid=$self->createEntity($self->getEntityTypeIdByName("TEMPLATE"),$parent);

   if (defined $tid) {
      # entity created
      # set template constraints, if possible
      if ($self->setTemplate($tid,$set)) {
         # success
         # return template id 
         return $tid;
      } else {
         # failed to set template constraints - error already set
         return 0;
      }
   } else {
      # someting failed - error already set
      return 0;
   }
}

# partly wrapper to Entity-methods
sub deleteTemplate {
   my $self=shift;
   my $tmpl=shift || 0;

   my $method=(caller(0))[3];

   # clean tmpl value
   $tmpl=$Schema::CLEAN{entity}->($tmpl);

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # check if template exists
   if (!$self->existsEntity($tmpl)) {
      $self->{error}="$method: Template $tmpl does not exist. Unable to delete it.";
      return 0;
   }

   # check that id is a template
   if ($self->getEntityTypeName($tmpl) ne "TEMPLATE") {
      $self->{error}="$method: Template $tmpl is not of entity type TEMPLATE. Unable to delete template.";
      return 0;
   }

   # delete template constraints
   if (!$self->doSQL("DELETE FROM `TMPLCON` WHERE tmpl=$tmpl")) {
      return 0;
   }

   # delete template defaults
   if (!$self->doSQL("DELETE FROM `TMPLDEF` WHERE tmpl=$tmpl")) {
      return 0;
   }

   # delete all assignments to this template
   if (!$self->doSQL("DELETE FROM `TMPLASSIGN` WHERE tmpl=$tmpl")) {
      return 0;
   }

   # delete the template itself, logs etc - including checking children
   my $success=0;
   if (!$self->deleteEntity($tmpl)) {
      return 0;
   } 

   # success 
   return 1;
}

sub setTemplate {
   # sets template constraints.
   # input is tmplid and a hash ref for the keys
   # defaults:
   # templatedefval = undef
   # templateregex = //
   # templateflags = 0
   # templatemin = 0
   # templatemax = 1
   my $self = shift;
   my $tmpl= shift || 0;
   my $set = shift || undef;
   my $reset = shift || 0;

   my $method=(caller(0))[3];

   # clean tmpl variable
   $tmpl=$Schema::CLEAN{entity}->($tmpl);

   # clean reset variable
   $reset=$Schema::CLEAN{boolean}->($reset);

   # check if template exists
   if (!$self->existsEntity($tmpl)) {
      $self->{error}="$method: Template $tmpl does not exist. Unable to define or set its constraints.";
      return 0;
   }

   # check that id is a template
   if ($self->getEntityTypeName($tmpl) ne "TEMPLATE") {
      $self->{error}="$method: Template $tmpl is not of entity type TEMPLATE. Unable to define or set its constraints.";
      return 0;
   }

   # check template hash
   if ((defined $set) && (ref($set) ne "HASH")) {
      # wrong type, error
      $self->{error}="$method: This is not a hash ref. Unable to set template constraints.";
      return 0;
   }

   # start transaction if not already started
   my $tr = $self->useDBItransaction();

   if ($reset) {
      # asked for a reset of all template constraints and defaults - start with constraints
      my $sql=$self->doSQL("DELETE FROM `TMPLCON` WHERE tmpl=$tmpl");
      if (!defined $sql) {
         # something failed - error already set
         return 0;
      }
      # reset defaults
      $sql=$self->doSQL("DELETE FROM `TMPLDEF` WHERE tmpl=$tmpl");
      if (!defined $sql) {
         # something failed - error already set
         return 0;
      }
   }

   # clean hash
   my %nset; # new, cleaned hash
   foreach (keys %{$set}) {
      my $key=$_;
     
      if (!defined $set->{$key}) { next; } # key exists, but is not defined, so skip it.

      my $nkey=$Schema::CLEAN{metadatakey}->($key,0);
      if ($nkey ne $key) {
         # this is an invalid key entry - fail!
         $self->{error}="$method: Invalid key $key input. Unable to set template constraints.";
         return 0;
      } else {
         # clean all key->values of this key
         my @ckeys=("default","regex","flags","min","max","comment");
         my %ckeys;
         $ckeys{default}="tmplcondefval";
         $ckeys{regex}="tmplconregex";
         $ckeys{flags}="tmplconflags";
         $ckeys{min}="tmplconmin";
         $ckeys{max}="tmplconmax";
         $ckeys{comment}="tmplconcom";
         foreach (keys %{$set->{$nkey}}) {
            my $skey=$_;

            # clean the key name
            my $nskey=$Schema::CLEAN{metadatakey}->($skey,0);
            # check the new keys name
            if (exists $ckeys{$nskey}) {
               # check its value if it is other than undef. Only check it if it is other than undef
               my $value=$set->{$nkey}{$skey};
               if (defined $value) { $value=$Schema::CLEAN{$ckeys{$nskey}}->($value); }
               # add to hash
               $nset{$nkey}{$nskey}=$value;
               # this key was found, remove from ckeys
               delete ($ckeys{$nskey});
            }
         }
         # ensure validity of values and flags
         # min and max are already bounded within cleaned values (0 - 2**X)
         my $min=$nset{$nkey}{min};
         my $max=$nset{$nkey}{max};
         # we do not allow min to be larger than max, except 0 (no limit).
         if ((defined $min) && (defined $max) && ($max != 0) && ($min > $max)) {
            $max=$min;
         } 
         my $flags=$nset{$nkey}{flags};

         # check flags for wide characters above 0xFF
         if ((defined $flags) && ($Schema::CHECK{utf8wide}->($flags))) {
            # wide characters - we cannot allow the setting of this template
            $self->{error}="$method: Flags for key $nkey in template contains characters above 0xFF. This is not permitted. Unable to continue.";
            # since this is not an SQL-failure as such, manually rollback any current changes
            $tr->rollback();
            return 0;
         }

         # define masks for single bits
         my $nonoverride=($self->createBitmask($self->getTemplateFlagBitByName("NONOVERRIDE")))[0];
         my $singular=($self->createBitmask($self->getTemplateFlagBitByName("SINGULAR")))[0];
         my $multiple=($self->createBitmask($self->getTemplateFlagBitByName("MULTIPLE")))[0];
         my $persist=($self->createBitmask($self->getTemplateFlagBitByName("PERSISTENT")))[0];
         if ((defined $flags) && (($flags & $singular) eq $singular) && (($flags & $multiple) eq $multiple)) {
            # singular and multiple bits are not allowed simultaneously. Singular has precedence
            $flags=$self->clearBitmask ($flags,$multiple);
            # we only allow 1 value, so both min and max needs to be 1
            $min=1;
            $max=1;
         }
         if ((defined $flags) && (($flags & $multiple) eq $multiple)) {
            # we have a multiple flag still, we only allow 1 or more in min, 0 or 2 or more in max.
            if ((!defined $min) || ($min < 1)) { $min=1; } # minimum 1
            if ((!defined $max) || ($max == 1)) { $max=0; } # no maximum limit
         }
         
         # set corrected min and max
         $nset{$nkey}{min}=$min;
         $nset{$nkey}{max}=$max;

         # set new mask 
         $nset{$nkey}{flags}=$flags;
      }
   }

   # go through each key and insert values
   my $dbi=$self->getDBI();
   foreach (keys %nset) {
      my $key=$_;

      # create and/or get key
      my $keyid=$self->createMetadataKey($key);
   
      if (defined $keyid) {
         # we have a keyid, quote the two strings
         my $defval=$nset{$key}{default};
         my $regex=(defined $nset{$key}{regex} ? $dbi->quote($nset{$key}{regex}) : "NULL");
         my $flags=(defined $nset{$key}{flags} ? $dbi->quote($nset{$key}{flags}) : "NULL");
         my $min=(defined $nset{$key}{min} ? $nset{$key}{min} : "NULL");
         my $max=(defined $nset{$key}{max} ? $nset{$key}{max} : "NULL");
         my $com=(defined $nset{$key}{comment} ? $dbi->quote($nset{$key}{comment}) : "NULL");

         # put constraints into the database, use replace for possible conflicts. Replace is good enough for templates.
         my $sql=$self->doSQL("REPLACE INTO `TMPLCON` (tmpl,tmplconkey,tmplconregex,tmplconflags,tmplconmin,tmplconmax,tmplconcom) ".
                              "VALUES ($tmpl,$keyid,$regex,$flags,$min,$max,$com)");
         if (defined $sql) {
            # success - add defaults, treat one or several as an array
            my @list;
            if ((defined $defval) && (ref($defval) eq "ARRAY")) {
               # this is an array
               push @list,@{$defval};
            } elsif (defined $defval) {
               # we assume this is just a SCALAR
               push @list,$defval;
            } else {
               # add value undefined
               push @list,undef;
            }
            # first remove old defaults, if any
            $sql=$self->doSQL("DELETE FROM `TMPLDEF` WHERE tmpl=$tmpl and tmplconkey=$keyid");
            if (defined $sql) {
               # add new defaults
               my $no=0;
               foreach (@list) {
                  my $def=$_;

                  $no++;
                  # quote the value
                  my $qdef;
                  if (defined $def) { $qdef=$dbi->quote($def); }
                  else { $qdef="NULL"; } # undef translates to no definition of key/part of key values
                  # add default to table
                  $sql=$self->doSQL("INSERT INTO `TMPLDEF` (tmpl,tmplconkey,tmpldefno,tmpldef) ".
                                    "VALUES ($tmpl,$keyid,$no,$qdef)");
                  if (!defined $sql) {
                     # something failed - abort the whole process
                     $self->{error}="$method: Unable to add template key default(s) for $key: ".$self->error();
                     return 0;
                  }
               }
            } else {
               # something failed
               $self->{error}="$method: Unable to delete template key $key: ".$self->error();
               return 0;
            }
 
            # go to next key to add to template
            next;
         } else {
            # something failed, stop transaction if we started it
            return 0;
         }
      }
   }

   # success if we reach here
   return 1;
}

# get a specific id'ed template and its constraints
sub getTemplate {
   my $self = shift;
   my $tmpl= shift || 0;

   my $method=(caller(0))[3];

   # clean tmpl variable
   $tmpl=$Schema::CLEAN{entity}->($tmpl);

   # check if exists
   if (!$self->existsEntity($tmpl)) {
      # does not exist - error already set
      return undef;
   }

   # check if right type
   if ($self->getEntityType($tmpl) != ($self->getEntityTypeIdByName("TEMPLATE"))[0]) {
      $self->{error}="Entity $tmpl is not a template.";
      return undef;
   }

   # define some bitmasks for later use
   my $nonoverride=($self->createBitmask($self->getTemplateFlagBitByName("NONOVERRIDE")))[0];
   my $singular=($self->createBitmask($self->getTemplateFlagBitByName("SINGULAR")))[0];
   my $multiple=($self->createBitmask($self->getTemplateFlagBitByName("MULTIPLE")))[0];
   my $persist=($self->createBitmask($self->getTemplateFlagBitByName("PERSISTENT")))[0];

   # ready to fetch template and constraints
   my $sql=$self->doSQL("SELECT METADATAKEY.metadatakeyname as name,tmplconregex,".
                        "tmplconflags,tmplconmin,tmplconmax,tmplconcom,tmpldefno as no,tmpldef FROM `TMPLCON` ".
                        "LEFT JOIN METADATAKEY on TMPLCON.tmplconkey = METADATAKEY.metadatakey ".
                        "LEFT JOIN TMPLDEF on TMPLCON.tmplconkey = TMPLDEF.tmplconkey ".
                        "WHERE TMPLCON.tmpl=$tmpl and TMPLDEF.tmpl=$tmpl ORDER BY METADATAKEY.metadatakeyname,tmpldefno");

   if (defined $sql) {
      # success - fetch values from all rows
      my %templ;
      while (my @values=$sql->fetchrow_array()) {
         my $name=$values[0];
         my $regex=$values[1];
         my $flags=$values[2];
         my $min=$values[3];
         my $max=$values[4];
         my $com=$values[5];
         my $no=$values[6];
         my $tmpldef=$values[7];

         # check for illegal characters in flags
         if ((defined $flags) && ($Schema::CHECK{utf8wide}->($flags))) {
            # flags contains characters above 0xFF
            $self->{error}="$method: Flags for key $name in template $tmpl contains characters above 0xFF. This is not permitted. Unable to continue";
            return undef;
         }
         
         # ensure flag validity - even out of database
         if ((defined $flags) && (($flags & $singular) eq $singular) && (($flags & $multiple) eq $multiple)) {
            # singular and multiple bits are not allowed simultaneously. Singular has precedence
            $flags=$self->clearBitmask ($flags,$multiple);
         }
         
         $templ{$name}{regex}=$regex;     
         $templ{$name}{flags}=$flags;     
         $templ{$name}{min}=$min;     
         $templ{$name}{max}=$max; 
         $templ{$name}{comment}=$com;

         if (defined $templ{$name}{default}) {
            if (ref($templ{$name}{default}) eq "ARRAY") {
               my $v=$templ{$name}{default};
               push @{$v},$tmpldef;
            } else {
               # we assume a SCALAR
               my $v=$templ{$name}{default};
               my @a;
               push @a,$v;
               push @a,$tmpldef;
               $templ{$name}{default}=\@a;
            }
         } else {
            # we assume SCALAR and set undef
            $templ{$name}{default}=$tmpldef;
         }
      }
      # return result
      return \%templ;
   } else {
      # failed - error already set
      return undef;
   }
}

sub getEntityTemplate {
   # get an entitys metadata template.
   # input entity(s), entitytype, return hash or undef upon fail.
   my $self=shift;
   my $type=shift || ($self->getEntityTypeIdByName("DATASET"))[0];
   my @entities=@_; # the parent tree of entities (for inheritence) or just the entity itself (for the template on that specific entity)

   my $method=(caller(0))[3];

   # clean type
   $type=$Schema::CLEAN{entitytype}->($type);
   # check type
   if (!($self->getEntityTypeNameById($type))[0]) {
      # invalid entity type
      $self->{error}="$method: Invalid entity type specified. Unable to get template for this entity(ies).";
      return undef;
   }

   # clean entities
   my @cents;
   foreach (@entities) {
      my $ent=$_;

      $ent=$Schema::CLEAN{entity}->($ent);
      push @cents,$ent;
   }

   # fetch templates for entire tree in one go
   my %template;
   my $ents=join(",",@cents) || "";
   my $order="";
   # define order at which to return the entity tree (top down in the order of the array)
   foreach (@cents) {
      $order=($order eq "" ? "tmplassignentity=$_ DESC" : $order.",tmplassignentity=$_ DESC");
   }
   $order=($order eq "" ? "" : "$order,");
   my $sql=$self->doSQL("SELECT TMPLASSIGN.tmplassignentity,METADATAKEY.metadatakeyname as name,tmplconregex,tmplconflags,tmplconmin,tmplconmax,".
                        "tmplconcom,TMPLASSIGN.tmplassignno,TMPLASSIGN.tmpl,TMPLDEF.tmplconkey,TMPLDEF.tmpldefno,TMPLDEF.tmpldef FROM `TMPLCON` ".
                        "LEFT JOIN METADATAKEY on TMPLCON.tmplconkey = METADATAKEY.metadatakey ".
                        "LEFT JOIN TMPLASSIGN ON TMPLCON.tmpl = TMPLASSIGN.tmpl ".
                        "LEFT JOIN TMPLDEF on TMPLASSIGN.tmpl = TMPLDEF.tmpl ".
                        "WHERE TMPLASSIGN.tmplassignentity IN ($ents) and TMPLASSIGN.tmplassigntype=$type and ".
                        "TMPLDEF.tmplconkey = TMPLCON.tmplconkey ".
                        "ORDER BY TMPLASSIGN.tmplassignentity,TMPLASSIGN.tmplassignno,${order}name,TMPLDEF.tmplconkey,TMPLDEF.tmpldefno ASC");

   if (defined $sql) {
      # success - fetch values from all rows
      my $non=$self->createBitmask(($self->getTemplateFlagBitByName("NONOVERRIDE"))[0]);
      my $omit=$self->createBitmask(($self->getTemplateFlagBitByName("OMIT"))[0]);
      my $singular=($self->createBitmask($self->getTemplateFlagBitByName("SINGULAR")))[0];
      my $multiple=($self->createBitmask($self->getTemplateFlagBitByName("MULTIPLE")))[0];
      my $persist=$self->createBitmask(($self->getTemplateFlagBitByName("PERSISTENT"))[0]);

      my $oldent=0;
      my $oldassno=0;
      my $oldkey=0;
      my $nontmpl=0;
      while (my @values=$sql->fetchrow_array()) {
         # add values to hash, overwriting previous settings (if allowed), if any (inheritance)
         # check if nonoverride flag is already set
         my $entity=$values[0];
         my $name=$values[1];
         my $regex=$values[2];
         my $flags=$values[3];
         my $min=$values[4];
         my $max=$values[5];
         my $com=$values[6];
         my $assignno=$values[7];
         my $tmplid=$values[8];
         my $conkey=$values[9];
         my $defno=$values[10];
         my $defval=$values[11];
 
         # ensure we have correctly formatted flags before passing it to bitwise (above 0xFF or not)
         if ((defined $flags) && ($Schema::CHECK{utf8wide}->($flags))) {
            # we have wide-characters above 0xFF - notify and abort
            $self->{error}="$method: Flags for key $conkey in template $tmplid contains wide characters above 0xFF. Cannot perform bitwise operations on this. Unable to continue.";
            return undef;
         }

         # ensure flag validity - even out of database
         if ((defined $flags) && (($flags & $singular) eq $singular) && (($flags & $multiple) eq $multiple)) {
            # singular and multiple bits are not allowed simultaneously. Singular has precedence
            $flags=$self->clearBitmask ($flags,$multiple);
         }

         # check if this is the first nonoverride instance
         if (($nontmpl == 0) && (defined $flags) && (($flags & $non) eq $non)) { $nontmpl=$tmplid; }

         # if nonoverride has been set on this key, no override allowed further down
         if ((defined $template{$name}{flags}) &&
             ($nontmpl != $tmplid) && (($template{$name}{flags} & $non) eq $non)) {
               # keep existing values
               next; 
         }

         # there is no non-override in function, check if key is to be omitted
         if ((defined $flags) && (($flags & $omit) eq $omit)) {
            # this key->value is to be omitted. Remove key from template
            if (defined $template{$name}) { delete ($template{$name}); }
            next;
         }

         # only add/overwrite values if they are other than undef
         if (defined $regex) { $template{$name}{regex}=$regex; }
         if (defined $flags) { $template{$name}{flags}=$flags; }
         if (defined $min) { $template{$name}{min}=$min; }
         if (defined $max) { $template{$name}{max}=$max; }
         if (defined $com) { $template{$name}{comment}=$com; }

         # store which template last effected change to values and on which entity in the tree
         $template{$name}{template}=$tmplid;
         $template{$name}{assignedto}=$entity;

         # check that if we are to reset default-content (avoid accumulting defaults across assignments)
         if (($oldent != $entity) || ($oldassno != $assignno) || ($oldkey != $conkey)) {
            # reset default values, since we it is populated with old content and we have a 
            # new template that is not undef
            $template{$name}{default}=undef;
            # save the change of tmplid
            $oldent=$entity;
            $oldassno=$assignno;
            $oldkey=$conkey;
         }
         # add/accumulate default(s)
         if ((defined $template{$name}{default}) && (ref($template{$name}{default}) eq "ARRAY")) {
            my $v=$template{$name}{default};
            push @{$v},$defval;
         } elsif (defined $template{$name}{default}) {
            my $v=$template{$name}{default};
            my @a;
            push @a,$v;
            push @a,$defval;
            $template{$name}{default}=\@a; 
         } else {
            $template{$name}{default}=$defval;
         }
      }
   } else {
      # failed - error already set
      return undef;
   }

   # ensure defaults where there is undef
   foreach (keys %template) {   
      my $key=$_;

      if (!defined $template{$key}{regex}) { $template{$key}{regex}=$Schema::CLEAN{tmplconregex}->(); }
      if (!defined $template{$key}{flags}) { $template{$key}{flags}=$Schema::CLEAN{tmplconflags}->(); }
      if (!defined $template{$key}{min}) { $template{$key}{min}=$Schema::CLEAN{tmplconmin}->(); }
      if (!defined $template{$key}{max}) { $template{$key}{max}=$Schema::CLEAN{tmplconmax}->(); }
      if (!defined $template{$key}{comment}) { $template{$key}{comment}=$Schema::CLEAN{tmplconcom}->(); }
   }
   
   # if here, we have some kind of template
   return \%template;
}

# get template assignments on an entity
sub getEntityTemplateAssignments {
   my $self=shift;
   my $entity=shift;
   my $type=shift;

   my $method=(caller(0))[3];

   # clean the entity
   $entity=$Schema::CLEAN{entity}->($entity);

   if (!$self->existsEntity($entity)) {
      # invalid entity id
      $self->{error}="$method: Invalid entity $entity specified. Unable to get template assignment(s) on this entity.";
      return undef;
   }

   # check type
   if (defined $type) {
      $type=$Schema::CLEAN{entitytype}->($type);
      if (!($self->getEntityTypeNameById($type))[0]) {
         # invalid entity type
         $self->{error}="$method: Invalid entity type $type specified. Unable to get template assignment(s) of this type.";
         return undef;
      }
   }

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();
 
   my $moderator="";
   if (defined $type) {
      $moderator="and tmplassigntype=$type ";
   }

   my $sql=$self->doSQL ("SELECT tmplassignentity,tmplassigntype,tmplassignno,tmpl FROM `TMPLASSIGN` WHERE tmplassignentity=$entity ".
                         "${moderator}ORDER BY tmplassigntype,tmplassignno ASC");

   if (defined $sql) {
      # success - get result
      my %val;
      while (my @values=$sql->fetchrow_array()) {
         # get values
         my $type=$values[1];
         my $no=$values[2];
         my $tmpl=$values[3];
         
         $val{$type}{$no}=$tmpl;
      }
      # rebuild hash to include templates in an array
      my %res;
      foreach (keys %val) {
         my $type=$_;

         my @arr;
         foreach (sort {$a <=> $b} keys %{$val{$type}}) {
            my $no=$_;
            push @arr,$val{$type}{$no};
         }
         # assign resulting array to type
         $res{$type}=\@arr;
      }
      # return result, if any
      return \%res;
   } else {
      # something failed - error already set.
      return undef;
   }
}

# assign a template to an entity
# assign it as a template for a specific entity type (it does not care about the type of the entity it is assigned to)
# old/earlier assignments will be overwritten
# if tmpl is undef the template assignent for the entity of the given type will be removed/unassigned.
# 1 upon success, 0 upon some failure
sub assignEntityTemplate {
   my $self=shift;
   my $entity=shift || 0;
   my $type=shift || ($self->getEntityTypeIdByName("DATASET"))[0]; # Dataset;
   my @tmpl=@_; # can have multiple assignments to one type

   my $method=(caller(0))[3];

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # check template if defined
   if (defined $tmpl[0]) {
      my @ntmpl;
      foreach (@tmpl) {
         my $t=$_;
         $t=$Schema::CLEAN{entity}->($t);
         my $ct=$self->existsEntity($t);
         if (!$ct) {
            if (defined $ct) {
               # does not exist
               $self->{error}="$method: Entity template $t does not exist. Unable to assign it to an entity.";
            } 
            return 0;
         } else {
            # check if template or not
            my $typ=$self->getEntityTypeName($t);
            if ($typ ne "TEMPLATE") {  
               $self->{error}="$method: Template ID $t is not a template entity. Unable to proceed.";
               return 0;
            }
            # add cleaned templ id to new template list
            push @ntmpl,$t;
         }
      }
      # update template list
      @tmpl=@ntmpl;
   } 

   # check entity
   $entity=$Schema::CLEAN{entity}->($entity);
   my $ce=$self->existsEntity($entity);
   if (!$ce) {
      if (defined $ce) {
         # does not exist
         $self->{error}="$method: Entity $entity does not exist. Unable to assign a template to it.";
      } 
      return 0;
   } 

   # check type
   $type=$Schema::CLEAN{entitytype}->($type);
   if (!($self->getEntityTypeNameById($type))[0]) {
      # invalid entity type
      $self->{error}="$method: Invalid entity type $type specified. Unable to assign a template of this type.";
      return 0;
   }

   # ready to assign or remove assignments
   my $sql;
   if (defined $tmpl[0]) {
      # start with deleting all template assignments
      $sql=$self->doSQL("DELETE FROM `TMPLASSIGN` WHERE tmplassignentity=$entity and tmplassigntype=$type");
      if (defined $sql) {
         my $no=0;
         foreach (@tmpl) {
            my $t=$_;
            $no++;
            $sql=$self->doSQL("INSERT INTO `TMPLASSIGN` (tmplassignentity,tmplassigntype,tmplassignno,tmpl) VALUES ($entity,$type,$no,$t)");
         }
      }
   } else {
      # this is just an unassignment
      $sql=$self->doSQL("DELETE FROM `TMPLASSIGN` WHERE tmplassignentity=$entity and tmplassigntype=$type");
   }
   # check for success
   if (defined $sql) {
      # success
      return 1;
   } else {
      # some failure - error already set
      return 0;
   }
}

# wrapper
sub unassignEntityTemplate {
   my $self=shift;
   my $entity=shift;
   my $type=shift;

   my $method=(caller(0))[3];
 
   # set tmpl to undef to unassign given type from entity.
   return $self->assignEntityTemplate($entity,$type,undef);
}

sub getTemplateAssignments {
   my $self=shift;
   my $tmpl=shift || 0; # tmpl to get assignments of
   my $type=shift; # optional entity type
   my $dupl=shift; # remove duplicates or not?

   my $method=(caller(0))[3];

   # clean the tmpl id
   $tmpl=$Schema::CLEAN{entity}->($tmpl);

   # clean dupl if defined, if not defined default to remove duplicates
   if (defined $dupl) { $dupl=substr($dupl,0,1); } else { $dupl=1; }

   if ((!$self->existsEntity($tmpl)) || ($self->getEntityTypeName ($tmpl) ne "TEMPLATE")) {
      # invalid entity id
      $self->{error}="$method: Invalid template id $tmpl specified. Unable to get assignment(s) of this entity id.";
      return undef;
   }

   # check type
   if (defined $type) {
      $type=$Schema::CLEAN{entitytype}->($type);
      if (!($self->getEntityTypeNameById($type))[0]) {
         # invalid entity type
         $self->{error}="$method: Invalid entity type $type specified. Unable to get assignment(s) of this type.";
         return undef;
      }
   }

   # start transaction 
   my $transaction = $self->useDBItransaction();
 
   my $moderator="";
   if (defined $type) {
      $moderator="and tmplassigntype=$type ";
   }

   my $sql=$self->doSQL ("SELECT tmplassigntype,tmplassignentity FROM `TMPLASSIGN` WHERE tmpl=$tmpl ".
                         "${moderator}ORDER BY tmplassigntype,tmplassignentity ASC");

   if (defined $sql) {
      # success - get result
      my %val;
      while (my @values=$sql->fetchrow_array()) {
         # get values
         my $type=$values[0];
         my $entity=$values[1];

         my @list=(exists $val{types}{$type} ? @{$val{types}{$type}} : ());

         push @list,$entity;

         $val{types}{$type}=\@list;
      }
      # accumulate all and remove duplicates at the same time
      my @acc;
      foreach (keys %{$val{types}}) {
         my $type=$_;
         # get list of entities on type
         my @list=@{$val{types}{$type}};
         if ($dupl) {
            # remove duplicates in type-list
            my %seen;
            my @nondup=grep { ! $seen{$_}++ } @list;
            push @acc,@nondup;
            # reassign type-list to a non duplicate one
            $val{types}{$type}=\@nondup;
         } else { 
            # accumulate type list with potential duplicates
            push @acc,@list; 
         }
      }

      # remove duplicates in all
      my %seen;
      my @all=grep { ! $seen{$_}++ } @acc;
      $val{all}=\@all;
      # return the complete results
      return \%val;
   } else {
      # something went awry - error already set
      return undef;
   }
}

sub getTemplateAssignmentsTree {
   my $self=shift;
   my $entities=shift; # entity to get inheritance of or specific path to use (ARRAY-ref of 1 or more elements)
   my $type=shift || ($self->getEntityTypeIdByName("DATASET"))[0]; # Dataset;
   my $include=shift; # just show some template ids in response, can be undef (show all results)
   my $prune=shift; # remove entities with no template assignments, can be undef (no pruning)

   my $method=(caller(0))[3];

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # clean 
   $type=$Schema::CLEAN{entitytype}->($type);

   my %includes;
   if (defined $include) { 
      # first check type
      if (ref($include) ne "ARRAY") {
         $self->{error}="$method: Invalid include-parameter. It must be undefined or an ARRAY.";
         return undef;
      }
      # to through array and check and clean
      my @inc;
      foreach (@{$include}) {
         my $t=$_;

         $t=$Schema::CLEAN{entity}->($t); 
         if ($self->getEntityTypeName($t) ne "TEMPLATE") {
            $self->{error}="$method: Invalid entity $t specified in include-parameter. This is not a TEMPLATE entity.";
            return undef;
         }
         # add template to new include list
         push @inc,$t;
         # add this id to hash for easy exists check
         $includes{$t}=1;
      }
      # set include to cleaned list
      $include=\@inc;
   }

   if (defined $prune) { $prune=substr($prune,0,1); }

   if ((!defined $entities) || (ref($entities) ne "ARRAY") || (@{$entities} == 0)) {
      $self->{error}="$method: Invalid entity(ies) input specified. It must be one or more entity ids.";
      return undef;
   }

   # get path to follow when building inheritance overview
   my @path;
   if (@{$entities} == 1) { @path=$self->getEntityPath($entities->[0]); }
   else { @path=@{$entities}; }

   # go through each entry in path and build result
   my %res;
   my %cache;
   my $pos=1;
   foreach (@path) {
      my $entity=$_;

      # get all template assignments on this entity
      my $assign=$self->getEntityTemplateAssignments($entity,$type);

      if (!defined $assign) {
         # something failed - error already set
         return undef;
      }

      # get template defs for all assigned templates, except if tmpl set
      my $apos=0;
      foreach (@{$assign->{$type}}) {
         my $t=$_; # get template id
         $apos++;

         # if include is defined, ensure that template is of given id, or else skip
         if ((defined $include) && (!exists $includes{$t})) { next; }

         # get template, if not cached already
         if (!exists $cache{$t}) { my $tmpl=$self->getTemplate($t); if (!defined $tmpl) { return undef; } $cache{$t}=$tmpl; }

         # update result hash
         $res{$pos}{entity}=$entity;
         foreach (keys %{$cache{$t}}) {
            my $key=$_;
            $res{$pos}{assigns}{$apos}{$t}{$key}=$cache{$t}{$key};
         }
      }

      if ($prune) { next; }
      elsif (!exists $res{$pos}) { 
         # adding entry to entities with no assignments if no pruning requrested
         $res{$pos}{entity}=$entity; 
         $res{$pos}{assigns}=undef;
      }
      $pos++;
   }
   # return the result
   return \%res;
}

# get template id(s) of 
# template for entity(ies).
# return list of template id(s) upon success, undef upon failure. Returned list will
# be in the same order as the list input with entity(ies) id.
# Entity(ies) without template assigned of given type will have their entry set to zero 
# in the list returned.
sub getEntityTemplateId {
   my $self=shift;
   my $type=shift; # can be undef, then get all types
   my @entities=@_;

   my $method=(caller(0))[3];

   if (defined $type) {
      # clean type
      $type=$Schema::CLEAN{entitytype}->($type);
      # check type
      if (!($self->getEntityTypeNameById($type))[0]) {
         # invalid entity type
         $self->{error}="$method: Invalid entity type specified. Unable to get template ids for this entity(ies).";
         return undef;
      }
   }

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # create type moderator, either get specific type or get all types
   my $moderator=(defined $type ? " and TMPLASSIGN.tmplassigntype=$type" : "");

   # go through the entity(ies) and get the ids of the templates that may be assigned to them. 
   # no template gives a zero 
   my @ids;
   foreach (@entities) {
      my $entity=$_;

      # clean entity
      $entity=$Schema::CLEAN{entity}->($entity);

      if ($self->existsEntity($entity)) {
         # fetch entity's template
         my $sql=$self->doSQL("SELECT tmpl,tmplassignno FROM `TMPLASSIGN` ".
                              "WHERE TMPLASSIGN.tmplassignentity=$entity$moderator ORDER BY tmplassignno ASC");

         if (defined $sql) {
            # success - fetch values from all rows
            while (my @row=$sql->fetchrow_array()) {
               # add template id of type for this entity, if exists
               push @ids,$row[0];
            }
         } else {
            # something failed - error already set. clean up transaction if started by this method
            return undef;
         } 
      } else {
         # entity does not exist - abort
         $self->{error}="$method: Entity $entity does not exist. Unable to find any template of given type for this entity.";
         return undef;
      }
   }

   # if we made it this far, return our list
   return \@ids;
}

# right now just a wrapper for getEntityPath, but can be tweaked.
sub getEntityTemplatePath {
   my $self=shift;
   my $entity=shift;
   my $type=shift;

   my $method=(caller(0))[3];

   # clean entity
   $entity=$Schema::CLEAN{entity}->($entity);

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # clean type
   if (defined $type) {
      $type=$Schema::CLEAN{entitytype}->($type);

      if (!($self->getEntityTypeNameById($type))[0]) {
         # invalid entity type
         $self->{error}="$method: Invalid entity type specified.";
         return undef;
      }
   } else {
      $type=$self->getEntityType ($entity);
   }

   # check if valid entity
   if ($self->existsEntity($entity)) {
      # get path
      my @path=$self->getEntityPath ($entity);

      return \@path;
   } else {
      $self->{error}="$method: Entity does not exist. Unable to get the entity template path.";
      return undef;
   }
}

sub checkEntityTemplateCompliance {
   # check an entity-ids compliance with its types template.
   # input entity-id, hash-ref to be checked and optionally type to set which type of template for the entity
   # to check compliance with. If no type is specified the type of the entity itself is selected.
   # returns hash with undef on non-compliant key's value. keys not specified that are required are also
   # put into hash and set to undef.
   # return hash upon success, undef upon failure.
   my $self=shift;
   my $entity=shift || 0;
   my $check=shift; # hash ref to check values from
   my $type=shift; # template type to use. If none given the type of the entity is used
   my $path=shift; # template path to use. If none given the path of the entity itself is used

   my $method=(caller(0))[3];

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   # clean entity
   $entity=$Schema::CLEAN{entity}->($entity);
   # ensure entity exists before proceeding
   if ($self->existsEntity($entity)) {
      # entity exists - let get type, so we can fetch relevant template

      # check that entity type exists if it is defined
      if ((defined $type) && (!($self->getEntityTypeNameById($type))[0])) {
         # invalid entity type
         $self->{error}="$method: Entity type does not exist. Unable to check compliance.";
         return undef;
      } elsif (!defined $type) {
         # we use the entity's type itself
         $type=$self->getEntityType($entity);
      }
      if (defined $type) {
         # get the entity's template tree if none is specified
         if (!defined $path) {
            # none specified - use the path of the entity
            $path=$self->getEntityTemplatePath ($entity);
         }
         if (defined $path) { 
            # get resulting template based on tree and type
            my $templ=$self->getEntityTemplate ($type,@{$path});
            if (defined $templ) {
               # lets go through supplied hash and check against template
               my $compliance=1;
               my @ncompliant;
               my %checked;
               foreach (keys %{$check}) {
                  my $key=$_;

                  # general cleaning of input
                  my $nkey=$Schema::CLEAN{metadatakey}->($key,0);

                  # get value(s) into an array
                  my @values;
                  if (ref($check->{$key}) eq "ARRAY") {
                     # this is an array, add values to array
                     push @values,@{$check->{$key}};
                  } elsif (ref(\$check->{$key}) eq "SCALAR") {
                     # this is a scalar - add to array
                     push @values,$check->{$key}; 
                  } else {
                     # invalid input
                     $checked{$key}{value}=$check->{$key};
                     $checked{$key}{compliance}=0;
                     $checked{$key}{reason}="Invalid input type. It must be either a SCALAR or an ARRAY";
                     $checked{$key}{default}=(exists $templ->{$key} ? $templ->{$key}{default} : $Schema::CLEAN{tmplcondefval}->() );
                     $checked{$key}{regex}=(exists $templ->{$key} ? $templ->{$key}{regex} : $Schema::CLEAN{tmplconregex}->() );
                     $checked{$key}{flags}=(exists $templ->{$key} ? $templ->{$key}{flags} : $Schema::CLEAN{tmplconflags}->() );
                     $checked{$key}{min}=(exists $templ->{$key} ? $templ->{$key}{min} : 0 );
                     $checked{$key}{max}=(exists $templ->{$key} ? $templ->{$key}{max} : 0 );
                     $checked{$key}{comment}=(exists $templ->{$key} ? $templ->{$key}{comment} : $Schema::CLEAN{tmplconcom}->() );
 
                     # mark overall compliance as false
                     $compliance=0;

                     # add to non-compliant keys
                     push @ncompliant,$key;
                     next;
                  }

                  # does it pass general cleaning?
                  if ($key eq $nkey) {
                     # the key is ok - lets check the value(s) for compliance
                     my $ok=1;
                     my $reason="";

                     # check if key is mandatory, because we do not allow erasing/leaving out 
                     # mandatory keys by giving an undef value
                     my $man=$self->createBitmask($self->getTemplateFlagBitByName("MANDATORY"));
                     if ((exists $templ->{$nkey}) && (defined $templ->{$nkey}{flags}) && (($templ->{$nkey}{flags} & $man) eq $man) && (@values == 0)) { 
                        # this is mandatory and we have undef specified for the key. This is not allowed
                        $ok=0;
                        $reason="MANDATORY-flag enabled and the value is specified as undef. This is not allowed for this key.";
                     }

                     # check if template says this is a singular or multiple value
                     my $singular=$self->createBitmask($self->getTemplateFlagBitByName("SINGULAR"));
                     my $multiple=$self->createBitmask($self->getTemplateFlagBitByName("MULTIPLE"));
                     my $persist=$self->createBitmask($self->getTemplateFlagBitByName("PERSISTENT"));
                     # first check singular flag, which have precedence, careful not to create keys in template
                     if ((exists $templ->{$key}) && (defined $templ->{$key}{flags}) && (($templ->{$key}{flags} & $singular) eq $singular)) {
                        # singular-flag set - ensure that value conforms one of the defaults.
                        # value must be a SCALAR - in this case means only one entry
                        if (@values > 1) { 
                           $ok=0;
                           $reason="SINGULAR-flag enabled, but the value is not a SCALAR.";
                        } elsif (@values == 0) {
                           # not defined, one needs to be set
                           $ok=0;
                           $reason="SINGULAR-flag enabled, but no value specified.";
                        } else {
                           my @defs;
                           if (ref($templ->{$key}{default}) eq "ARRAY") { @defs=@{$templ->{$key}{default}}; }
                           else { push @defs,$templ->{$key}{default}; }

                           my $conform=0;
                           foreach (@defs) {
                              my $def=$_;
                              if ($values[0] eq $def) { $conform=1; last; }
                           }
                           if (!$conform) {
                              $ok=0;
                              $reason="SINGULAR-flag enabled, but value does not conform to any of the value(s) in the template.";
                           }
                        }
                     } elsif ((exists $templ->{$key}) && (defined $templ->{$key}{flags}) && (($templ->{$key}{flags} & $multiple) eq $multiple)) {
                        # multiple flag set (no singular) - ensure that values conforms to one or more values in defaults
                        if (@values == 0) {
                           # not defined, at least one needs to be set
                           $ok=0;
                           $reason="MULTIPLE-flag enabled, but no value(s) specified.";
                        } else {
                           my @defs;
                           if (ref($templ->{$key}{default}) eq "ARRAY") { @defs=@{$templ->{$key}{default}}; }
                           else { push @defs,$templ->{$key}{default}; }

                           my $conform=1;
                           my @nonconforms;
                           foreach (@values) {
                              my $value=$_;
 
                              my $found=0;
                              foreach (@defs) {
                                 my $def=$_;
                                 if ($value eq $def) { $found=1; last; }
                              }
                              if (!$found) { $conform=0; push @nonconforms,$value; }
                           }
                           if (!$conform) {
                              $ok=0;
                              $reason="MULTIPLE-flag enabled, but value(s) @nonconforms does not conform to any of the value(s) in the template.";
                           }
                        }
                     }

                     my $size=@values;
                     foreach (@values) {
                        my $value=$_;
                        my $nvalue=$Schema::CLEAN{metadataval}->($value);

                        if (!$ok) { last; }

                        # create pattern check, accept all if no template regex exists
                        my $pattern=(exists $templ->{$nkey} ? qq($templ->{$nkey}{regex}) : $Schema::CLEAN{tmplconregex}->() );
                        # set minimum values, if no template, set to infinite
                        my $min=(exists $templ->{$nkey} ? $templ->{$nkey}{min} : 0);
                        # set maximum values, if no template, set to infinite
                        my $max=(exists $templ->{$nkey} ? $templ->{$nkey}{max} : 0);

                        # do an evaled patternmatch in case of bad regex
                        my $pmatch=0;
                        my $err="";
                        {
                           my $qpattern=qq($pattern);
                           local $@;
                           eval { if ((defined $value) && ($value =~ /^$qpattern$/s)) { $pmatch=1; } };
                           $@ =~ /nefarious/;
                           $err=$@;
                        }
                        if ($err ne "") { $ok=0; $reason="The regex for the key is bad: $err. Please have it corrected."; last; }
                        # check that value is the same and conforms to regex
                        if (((!defined $value) && ($pattern=".*")) || ((defined $value) && ($nvalue eq $value) && ($pmatch))) {
                          # check min and max bounds
                           if ((($min > 0) && ($size < $min)) ||
                               (($max > 0) && ($size > $max))) {
                              $ok=0;
                              $reason="The number of elements in key ($size) is outside bounds of min ($min) and/or max ($max) constraints";
                              last;
                           } 

                           # come here? it is ok
                           next;
                        } else {
                           # failed, just end loop
                           $ok=0;
                           if ($nvalue ne $value) {
                              $reason="Invalid characters in value";
                           } else {
                              $reason="Failed regex pattern match";
                           }
                           last;
                        }
                     }

                     # add correct reply to given key
                     if ($ok) {
                        $checked{$nkey}{value}=$check->{$nkey};
                        $checked{$nkey}{compliance}=1;
                        $checked{$key}{default}=(exists $templ->{$key} ? $templ->{$key}{default} : $Schema::CLEAN{tmplcondefval}->() );
                        $checked{$key}{regex}=(exists $templ->{$key} ? $templ->{$key}{regex} : $Schema::CLEAN{tmplconregex}->() );
                        $checked{$key}{flags}=(exists $templ->{$key} ? $templ->{$key}{flags} : $Schema::CLEAN{tmplconflags}->() );
                        $checked{$key}{min}=(exists $templ->{$key} ? $templ->{$key}{min} : 0 );
                        $checked{$key}{max}=(exists $templ->{$key} ? $templ->{$key}{max} : 0 );
                        $checked{$key}{comment}=(exists $templ->{$key} ? $templ->{$key}{comment} : $Schema::CLEAN{tmplconcom}->() );
                     } else {
                        $checked{$nkey}{value}=$check->{$nkey};
                        $checked{$nkey}{compliance}=0;
                        $checked{$nkey}{reason}=$reason;
                        $checked{$key}{default}=(exists $templ->{$key} ? $templ->{$key}{default} : $Schema::CLEAN{tmplcondefval}->() );
                        $checked{$key}{regex}=(exists $templ->{$key} ? $templ->{$key}{regex} : $Schema::CLEAN{tmplconregex}->() );
                        $checked{$key}{flags}=(exists $templ->{$key} ? $templ->{$key}{flags} : $Schema::CLEAN{tmplconflags}->() );
                        $checked{$key}{min}=(exists $templ->{$key} ? $templ->{$key}{min} : 0 );
                        $checked{$key}{max}=(exists $templ->{$key} ? $templ->{$key}{max} : 0 );
                        $checked{$key}{comment}=(exists $templ->{$key} ? $templ->{$key}{comment} : $Schema::CLEAN{tmplconcom}->() );
                        # mark overall compliance as false
                        $compliance=0;
                        # add to non-compliant keys
                        push @ncompliant,$key;
                     }
                  } else {
                     # invalid key value - mark as undef
                     $checked{$key}{value}=$check->{$key};
                     $checked{$key}{compliance}=0;
                     $checked{$key}{reason}="Invalid key name: $key";
                     $checked{$key}{default}=$Schema::CLEAN{tmplcondefval}->();
                     $checked{$key}{regex}=$Schema::CLEAN{tmplconregex}->();
                     $checked{$key}{flags}=$Schema::CLEAN{tmplconflags}->();
                     $checked{$key}{min}=0;
                     $checked{$key}{max}=0;
                     $checked{$key}{comment}=$Schema::CLEAN{tmplconcom}->();

                     # mark overall compliance as false
                     $compliance=0;
                     # add to non-compliant keys
                     push @ncompliant,$key;
                  }
               }

               # we made it this far, now input missing mandatory keys
               foreach (keys %{$templ}) {
                  my $key=$_;
                  # flag bit mandatory
                  my $man=$self->createBitmask($self->getTemplateFlagBitByName("MANDATORY"));
                  if ((!exists $checked{$key}) && (defined $templ->{$key}{flags}) && (($templ->{$key}{flags} & $man) eq $man)) {
                     # key does not exist and it is mandatory
                     if (defined $templ->{$key}{default}) {
                        # default exists in template, use this...if possible
                        my $default=(ref($templ->{$key}{default}) eq "ARRAY" ? $templ->{$key}{default}->[0] : $templ->{$key}{default});
                        my @values;
                        my $singular=$self->createBitmask($self->getTemplateFlagBitByName("SINGULAR"));
                        my $multiple=$self->createBitmask($self->getTemplateFlagBitByName("MULTIPLE"));
                        # check if singular or multiple flag has been enabled, then select only one value                      
                        if ((defined $templ->{$key}{flags}) && ((($templ->{$key}{flags} & $singular) eq $singular) || (($templ->{$key}{flags} & $multiple) eq $multiple)))  {
                           push @values,$default;
                        } else {
                           # input the number of values defined by min.
                           my $min=(exists $templ->{$key}{min} ? $templ->{$key}{min} : 0);
                           # if min is bigger than one - add as LIST
                           for (my $i=1; $i <= $min; $i++) { push @values,$default; }
                        }

                        # check defaults going into database, in case the template invalidates itself
                        my $ok=1;
                        my $reason="";
                        my $pattern=(exists $templ->{$key} ? qq($templ->{$key}{regex}) : $Schema::CLEAN{tmplconregex}->() );
                        foreach (@values) {
                           my $value=$_;
                           # do an evaled patternmatch in case of bad regex
                           my $pmatch=0;
                           my $err="";
                           {
                              my $qpattern=qq($pattern);
                              local $@;
                              eval { if ((defined $value) && ($value =~ /^$qpattern$/)) { $pmatch=1; } };
                              $@ =~ /nefarious/;
                              $err=$@;
                           }
                           if ($err ne "") { $ok=0; $reason="The regex for the key is bad: $err. Please have it corrected."; last; } 
                           if (!$pmatch) { $ok=0; $reason="The default value for this key conflicts with its regex. Please have it corrected."; last; }
                        }
                      
                        if (@values > 1) {
                           # add an array
                           $checked{$key}{value}=\@values;
                        } else {
                           # just add one value
                           $checked{$key}{value}=$default;
                        }
 
                        if (!$ok) {
                           $checked{$key}{compliance}=0;
                           $checked{$key}{reason}=$reason;
                           # mark overall compliance as false
                           $compliance=0;
                           # add to non-compliant keys
                           push @ncompliant,$key;
                        } else {                            
                           $checked{$key}{compliance}=1;
                        }
                        $checked{$key}{default}=$templ->{$key}{default};
                        $checked{$key}{regex}=$templ->{$key}{regex};
                        $checked{$key}{flags}=$templ->{$key}{flags};
                        $checked{$key}{min}=$templ->{$key}{min};
                        $checked{$key}{max}=$templ->{$key}{max};
                        $checked{$key}{comment}=$templ->{$key}{comment};
                     } else {
                        # no default, mark key as undef
                        $checked{$key}{compliance}=0;
                        $checked{$key}{reason}="Value is MANDATORY and none has been set and no default exists";
                        $checked{$key}{default}=$templ->{$key}{default};
                        $checked{$key}{regex}=$templ->{$key}{regex};
                        $checked{$key}{flags}=$templ->{$key}{flags};
                        $checked{$key}{min}=$templ->{$key}{min};
                        $checked{$key}{max}=$templ->{$key}{max};
                        $checked{$key}{comment}=$templ->{$key}{comment};
                        # mark overall compliance as false
                        $compliance=0;
                        # add to non-compliant keys
                        push @ncompliant,$key;
                     }
                  }
               }
               my %result;
               # set overall compliance
               $result{compliance}=$compliance;
               # set keys that are non-compliant
               $result{noncompliance}=\@ncompliant;
               # save specific template compliance
               $result{metadata}=\%checked;
               # now lets deliver our result
               return \%result;
            } else {
               # something went wrong
               return undef;
            }
         } else {
            # something went wrong
            return undef;
         }
      } else {
         # something went wrong..
         return undef;
      }
   } else {
      # entity does not exist
      $self->{error}="$method: Entity $entity does not exist. Unable to check compliance.";
      return undef;
   }
}

sub enumLoglevels {
   # outputs just the id's, return ids or undef upon failure
   my $self = shift;

   my $method=(caller(0))[3];
  
   my $sql=$self->doSQL("SELECT loglevel FROM `LOGLEVEL` ORDER BY loglevel ASC");
   if (defined $sql) {
      # SQL successful
      my @ids=();
      # fetchrow_array is most effective
      while (my @row=$sql->fetchrow_array()) {         
         # add id to list
         push @ids,$row[0];
      }
      # return list
      return \@ids;
   } else {
      # error already set by doSQL
      return undef;
   }
}

# return loglevel, 0 if not exist and undef upon failure.
sub getLoglevelByName {
   my $self = shift;
   my $name = shift || "";

   my $method=(caller(0))[3];

   # get database instance or fail
   if (my $dbi=$self->getDBI()) {
      # clean name
      $name=$Schema::CLEAN{"loglevelname"}->($name);
      # quote name
      $name=$dbi->quote($name);
      # check if it exists
      my $sql=$self->doSQL("SELECT loglevel FROM `LOGLEVEL` WHERE loglevelname=$name");
      if (defined $sql) {
         # sql successful - check result
         if (my @id=$sql->fetchrow_array()) {
            # managed to get id - return it
            return $id[0];
         } else {
            # id does not exist
            return 0;
         }

      }
   } else {
      # failed, error already set
      return undef;
   }
}

# returns loglevel upon success, ""/blank on not exists and undef upon failure
sub getLoglevelNameByValue {
   my $self = shift;
   my $value = shift || 0;

   my $method=(caller(0))[3];

   # clean value
   $value=$Schema::CLEAN{"loglevel"}->($value);
   # check for name
   my $sql=$self->doSQL("SELECT loglevelname FROM `LOGLEVEL` WHERE loglevel=$value");
   if (defined $sql) {
      # get row and check it
      if (my @row=$sql->fetchrow_array()) {
         # loglevel is found - return name
         return $row[0];
      } else {
         # no hits - blank
         return "";
      }
   } else {
      # error already set
      return undef;
   }
}

sub getLogEntries {
   # either all entries or entry by entity-id
   my $self = shift;
   my $entity = shift || 0;

   my $method=(caller(0))[3];

   # clean entity
   $entity=$Schema::CLEAN{entity}->($entity);
   # define moderator
   my $moderator=($entity > 0 ? " WHERE entity=$entity" : "");
   # do sql
   my $sql=$self->doSQL("SELECT logidx,logtime,loglevel,logtag,logmess FROM `LOG`$moderator ORDER BY logtime,logidx ASC");
   if (defined $sql) {
      # sql succeeded
      my %log=();
      # use fetchrow_array 
      my $i=0;
      while (my @row=$sql->fetchrow_array()) {
         $i++;
         $log{$i}{time}=$row[1];
         $log{$i}{loglevel}=$row[2];
         $log{$i}{message}=$row[4];
         $log{$i}{idx}=$row[0];
         $log{$i}{tag}=$row[3];
      }
      # return the hash, empty or not
      return \%log;
   } else {
      # error already set
      return undef;
   }
}

sub setLogEntry {
   # insert a log entry
   my $self = shift;

   my $logtime=shift || time();
   my $entity=shift || 0;
   my $loglevel=shift || $self->getLoglevelByName("INFO"); 
   my $logtag=shift || "NONE";
   my $logmess=shift || "";

   my $method=(caller(0))[3];

   # start transaction if not already started
   my $transaction = $self->useDBItransaction();

   if (my $dbi=$self->getDBI()) {
      # clean
      $logtime=$Schema::CLEAN{"logtime"}->($logtime);
      $logtime=$logtime || time();
      $entity=$Schema::CLEAN{entity}->($entity);
      $loglevel=$Schema::CLEAN{"loglevel"}->($loglevel);
      $loglevel=$loglevel || 1;
      $logtag=$Schema::CLEAN{"logtag"}->($logtag);
      $logtag=$dbi->quote($logtag);
      $logmess=$Schema::CLEAN{"logmess"}->($logmess);
      $logmess=$dbi->quote($logmess);
      # check loglevel
      if (!$self->getLoglevelNameByValue($loglevel)) {
         $self->{error}="$method: Invalid loglevel specified. Unable to set log entry.";
         return 0;
      }
      # check entity
      if (!$self->existsEntity($entity)) {
         # entity does not exist
         $self->{error}="$method: Entity $entity does not exist. Unable to set log entry.";
         return 0;
      }

      # insert into db
      my $sql=$self->doSQL("INSERT INTO `LOG` (logtime,entity,loglevel,logtag,logmess) VALUES ($logtime,$entity,$loglevel,$logtag,$logmess)");
      if (defined $sql) {
         # success
         return 1;
      } else {
         # something failed, error already set
         return 0;
      }
   } else {
      # error already set
      return 0;
   }   
}

sub sequenceEntity {
    # Uodate the ENTITY_SEQUENCE table
    my $self = shift;
    my $entity = $Schema::CLEAN{entity}->(shift);

    my $method=(caller(0))[3];
    $self->{error}="$method: no entity to sequence" and return undef unless $entity;

    my $transaction = $self->useDBItransaction();

    $self->doSQL("delete from ENTITY_SEQUENCE where entity=$entity");
    $self->doSQL("insert into ENTITY_SEQUENCE(entity) values($entity)") or return 0; # error already set
    my $children = $self->getEntityChildren($entity) or return 0; # error already set
    my $total = 1;
    foreach my $child (@$children) {
        next if $child == $entity; # Avoid root loop
        my $descendants = $self->sequenceEntity($child) or return 0;
        $total += $descendants;
    }
    return $total;
}

sub error {
   my $self = shift;

   my $method=(caller(0))[3];

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<AuroraDB> - Interface methods to the AURORA database.

=head1 SYNOPSIS

   my $dbfile="./aurora.db";
   my $db=AuroraDB->new(data_source=>"DBI:SQLite:dbname=$dbfile",user=>"",pw=>"");

   # create a entity of type GROUP
   my $id=$db->createEntity($db->getEntityTypeIdByName("GROUP"));

   # set some metadata
   my %md;
   $md{".DublinCore.Creator"}="Albert Einstein";
   $md{".DublinCore.Created"}="20190101";
   if (!$db->setEntityMetadata($id,\%md)) {
      print "Failed to set entity $id's metadata: ".$db->error()."\n";
   }

   # get the metadata
   my $m;
   $m=$db->getEntityMetadata($id);
   use Data::Dumper;
   print "METADATA: ".Dumper($m);

=head1 DESCRIPTION

This module interfaces with the AURORA database. AURORA stands for Archive and Upload Research Objects for Retrieval and Alteration and
was created at the Norwegian University of Science and Technology (NTNU) in Trondheim, Norway to facilite retrieval of data 
from science labs, storage of the datasets and the ability to flexibly add metadata on each dataset.

The AURORA database module was written to be general enough to be used with most SQL engines, while still trying to optimize 
functions where necessary.

The AURORA database module was written by Bård Tesaker and Jan Frode Jæger

=head1 CONSTRUCTOR

=head2 new()

Instantiates the AuroraDB-class: new(data_source=>P,pw=>Q,pwfile=>R,user=>S,cachetime=>T)

Required parameters are:

=over

=item 

B<data_source> Perl DBI data_source parameter for the database chosen. See DBI's documentation.

=cut

=item 

B<pw> Password to login to database with. 

=cut

=item 

B<pwfile> Filename to read password from. PW must be undef or blank.

=cut

=item 

B<user> Username to login to database with.

=cut

=item

B<depth> Sets the maximum depth allowed on the entity tree. Optional. SCALAR. Default if not 
given is set to the global constant VIEW_DEPTH. This value should be set with care since it 
reflects what is possible to recurse with the various mandatory database views, such as 
ANCESTORS. The value should therefore reflect actual conditions in the AURORA database itself. 
Either this or expect a visit to the twilight zone, where entities both exists and do not exist 
at the same time. Or, is that just quantum reality even though we deny that entities are sub-atomic 
particles.

=cut

=item

B<entitytypescache> How often to update the cache of entity types. Default is every 3600 seconds.

=cut

=item

B<templatescache> How often to update template structures. Default is every 3600 seconds.

=cut

=item

B<templateflagscache> How often to update the template flag types. Default is every 3600 seconds.

=cut

=item 

B<entitiescache> How often to update existing entity(ies). Default is every 120 seconds.

=cut

=back

The method returns the reference to the instantiated class.

=cut

=head1 METHODS

=head2 addEntityMember()

Adds a member to an entity.

Accepts these inputs in the following order:

=over

=item

B<object> The entity to add a member to. Required.

=cut

=item

B<subjects> The entity(ies) to add as a member(s). Required. It can be one or more entity IDs as a LIST.

=cut

=back

The method returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

=cut

=head2 assignEntityTemplate()

Assigns template(s) to an entity.

Input is in the following order:

=over

=item

B<entity> The entity id to assign the template(s) to.

=cut

=item

B<type> The entity type that the template(s) are to be valid for. If not defined or 0 it will default to DATASET.

=cut

=item

B<template> The template id(s) to assign to the given entity. The value expected here is a LIST of one or more ids. The order of the list defines the order in which the templates take effect. If template is set to undef it will remove any template assignment of the given type on the entity.

=cut

=back

Previous assignment on the given entity and type are overwritten with the new assignment. 

Return value is 1 upon success or 0 upon failure. Check the error()-method for more information on the error.

=cut

=head2 checkEntityTemplateCompliance()

Checks a set of metadata key->value pairs compliance with an entity's aggregated template.

Input for this method are in the following order:

=over

=item

B<entity> The entity id to check the compliance for.

=cut

=item

B<metadata> The metadata HASH-reference with key->value pairs to check against the entity's aggregated template.

=cut

=item

B<type> The template type to use when checking the compliance. If type is undef, it will default to the entity id's type (see entity-option).

=cut

=item

B<path> The path to use to aggregate a template. If none given it uses the path of the entity itself.

=cut

=back

The return value is a HASH-reference. Undef is returned upon failure. Check the error()-method for more information upon failure.

The format of the return HASH is as follows:

   ( compliance => VALUE,
     noncompliance => LIST,
     metadata => { KEYx => { value => SCALAR,
                             compliance => BOOLEAN,
                             default => SCALAR,
                             regex => SCALAR,
                             flags => BITMASK,
                             min => SCALAR,
                             max => SCALAR,
                             comment => SCALAR,
                           },
                   KEYy => { ... },
                 },
   )

The top compliance value gives the overall compliance of all the metadata in a boolean (1=success,0=failure). The noncompliance value is a LIST of keys that
failed compliance (if any). The metadata sub-hash gives all the keys that the input metadata had and if they are compliant or not, their template and so on.
It will also contain any missing keys and their value taken from the aggregated template of the entity when those keys are missing and the MANDATORY-flag has been set.

See also the getTemplate and setTemplate methods for documentation upon the format of the templates.

=cut

=head2 clearBitmask()

Clear bits in a bitmask.

Input is the bitmask to modify and bitmask with bits to clear. 
Default parameters is ''. 

Return value is the resulting bitmask as a SCALAR. The input bitmask is unaltered.

=cut

=head2 clearBits()

Clear bits in a bitmask.

Input is the bitmask to modify and a list of bit numbers to clear. 
Default bitmask is ''. 

Return value is the resulting bitmask as a SCALAR. The input bitmask is unaltered.

=cut

=head2 connected()

This method attempts to check if the we are connected to the database or not by quering the DBI-instance: connected()

Returns 1 upon being connected and 0 upon not being connected.

=cut

=head2 createBitmask()

Creates a bitmask based upon the bit number specified in the input list - iterates on the vec-method in Perl.

Input is the bit numbers to set as a LIST. 

Return value is the bitmask as a SCALAR.

=cut

=head2 createEntity()

Creates an entity of a given type in the database: createEntity([type],[parent])

Input are in the following order:

=over

=item

B<type> Entity type id to create. Optional and it defaults to "DATASET". 

=cut

=item

B<parent> Parent entity id for the newly created entity. Optional and will default to 1 if none specified.

=cut

=back

Return value is the created entity's id or undef upon failure. Please call the error-method for more information on the failure.

=cut

=head2 createMetadataKey()

Creates a metadata key in the database.

Input is the name of the metadata key to create (assign a metadata key id). 

Return value is the metadata key id created or if it already exists its existing key id. Undef is returned upon failure. Please call the error-method to get more information about the error.

=cut

=head2 createPermBitmask()

Creates a permission bitmask based upon a mix of names and bit position values.

Input is a LIST fo permission name(s) and/or bit position value(s).

Returns a bitmask of those name(s) and/or value(s). Undef is returned upon failure. Please check the error()-method in such cases.

=cut

=head2 createTemplate()

Creates a template in the database and sets the given constraints.

Input for the method are these options in the following order:

=over

=item

B<parent> The entity id of the parent which the template is to be created under.

=cut

=item

B<constraints> The template constraints that are to be set for the template. This is a reference to a HASH. See the setTemplate()-method for more information.

=cut

=back

The method creates the template and sets the template constraints on the template.

Return value is the new template id upon success or 0 upon failure. Check the error-message by calling the error()-method.

=cut

=head2 deconstructBitmask()

Deconstruct a given bitmask into the bit numbers that have been set.

Input is the bitmask to deconstruct.

Return value is a LIST of bit numbers that have been set.

=cut

=head2 deleteEntity()

Deletes an entity of the given entity id from the database: deleteEntity(id)

Input is entity id to delete or it will default to the invalid entity id of zero.

It will delete all references to this entity in the database, including permission memberships, template assignments, log entries and metadata.
A deletion will only succeed if the entity does not have any children entity(ies). Children must first be moved or deleted. 

Return value is 1 upon success, 0 upon failure. Call the error-method to get more information on the failure.

=cut

=head2 deleteEntityMetadata()

Deletes metadata from an entity moderated by a set of metadata keys.

Input is in the following order:

=over

=item

B<entity> Id of the entity to delete metadata from.

=cut

=item

B<keys> The metadata keys to remove as a LIST-reference. If no metadata keys are specified it will remove all of the entitys metadata. The metadata keys accept wildcards (*) in them.

=cut

=back

Return value is 1 upon success, 0 when there are no rows to delete and undef upon failure. Please call the error-method to inquire about the details of the error in question.

=cut

=head2 deleteTemplate()

Deletes a template and its constraints and assignments to it.

Input is the template id.

Return value is 1 upon success, 0 upon failure. Check the error()-method for more information upon a failure.

=cut

=head2 doSQL()

This method prepares and executes a SQL statement and then checks the result: doSQL(SQL-Statement)

Input is the SQL statement to execute as a SCALAR. Return values are the DBI-class's statement handle upon success, undef upon failure. Please check the error-method to find out more about the issue.

This method is called from most methods in the AuroraDB-class and handles every relevant side of executing SQL-statements and handling errors. It also connects to the database if not already connected.

=cut

=head2 enumEntitiesByType()

Returns all entities of a certain type.

Input is entity type(s) as a LIST-reference. The entity type(s) are optional and if none is specified all entities will be returned.

Return value is a reference to a LIST entity id(s), if any.

It will return a reference to a LIST of entity id(s) upon success (it migth be an empty list), undef upon failure. Upon failure, call the error-method for more information on the failure.

=cut

=head2 enumEntityTypes()

Enumerates the entity type ids of the AURORA database: enumEntityTypes(). Returns a LIST of entity type IDs.

No input is required. It returns the list upon success, undef upon failure. Please check the error-method for more information on the failure.

=cut

=head2 enumLoglevels()

Enumerates the loglevels in the database.

Input is none. It returns the loglevel ids on success as a LIST-reference, undef upon failure. Call the error()-method to check information on the error.

=cut

=head2 enumPermTypes()

Enumerates the permission type names that exists in the AURORA database.

It accepts no input.

Return value is a LIST of permission type names.

=cut

=head2 enumTemplateFlags()

Enumerates the template flags that exists in the database. 

Returns a sorted LIST of template flag values.

=cut

=head2 error()

Gets the last error message from the AuroraDB library and its methods. Its functionality is used and referred to by all methods.

No input required and the return value is the last error message that has happened or ""/blank if no error message found.

=cut

=head2 existsEntity()

Checks to see if an entity exists or not? existsEntity(id).

Input is entity id to check or it will default to the invalid entity id of zero.

Return value is the entity id upon success, id zero if not existing, undef upon failure. Please call the error-method for more information.

=cut

=head2 getDBI()

This method attempt to return the DBI-object that AuroraDB creates: getDBI(). If it is not already created it attempts to connect to the database and then return the instance.

The method requires no input.

Return value is the instance of the DBI-class. Returns undef upon error. Check the error-method to get more information on the issue.

It is called from the most relevant method, such as doSQL.

=cut

=head2 disconnect()

Attempts to disconnect from database if already connected.

This method requires no input.

Returns 1 upon success, 0 upon some failure and undef if database is not connected already. Please check the error()-method for 
more information upon failures.

=cut

=head2 getEntityByMetadataKeyAndType()

Retrieves the entity(ies) id that matches the criteria given. There must exist one or more metadata on the entity(ies) searched for in order for this method to succeed. 

The method takes the following parameters in the following order:

=over

=item 

B<metadata> This options gives the metadata key->value pairs to search for state in a SQLStruct format (see SQLStruct-module for more information). This option can be set to undef (get all metadata). When given it has to be a HASH-reference.

=cut

=item

B<offset> This option gives the offset in a search result set to get. It optimizes search windows (where you want to only display a certain number of matches at a time) by using a SQL I<LIMIT>-clause. Lowest value is 1. Can be undef (no LIMIT-clause used - all matches returned).

=cut

=item

B<count> This option gives the number of entity(ies)/rows to fetch in the search result. SCALAR. Optional. Defaults to 2^64-1 if not specified. It is part of the optimization using a SQL I<LIMIT>-clause (see the offset option). 

=cut

=item

B<orderby> This option specifies which metadata key to order the search matches after. It also optimizes searches by using the SQL I<ORDER BY> clause. This option is mandatory as it is required for the method to work. The metadata key to order by B<must> exist in all entity(ies) that are to be returned in the result. The orderby-option in conjunction with the offset- and count-options will give a ordered, SQL optimized search of entities based on metadata. The validity/existence of the orderby option is not checked. If set to undef it will default to "system.dataset.time.created", which is B<only> valid for datasets (this default referring to a higher level is the only one coded into the AuroraDB-library).

=cut

=item

B<order> Sets the ordering part of the orderby-option. It refers to the SQL ordering keywords of ASC and DESC. Will default to "ASC" if invalid order-option specified or undef.

=cut

=item

B<entities> Sets the entities to constrain the search result with. Type expected is a reference to a LIST of entity ids. It is optional and will constrain the search result, independant of metadata structure, to the entities in the given LIST.

=cut

=item

B<types> Sets the entity types to return in the search result.  Type expected is a reference to a LIST of type(s). It is optional and will constrain the search result only to entity(ies) of the given type(s). It can be undef and then no entity type constraints will be imposed.

=cut

=item

B<tableopt> Select between including parent metadata or not. SCALAR. Optional. Defaults to 0. Value can be either 0 (false) or 1 (true).

=cut

=item

B<debug> Sets if the method returns the actual SQL query being used or not. SCALAR. Optional. If not set it 
will default to false and no sql query will be returned. The settings is boolean, where something that evaluates 
to false or true, become that setting. When this option is set the method will return the debug string as the 
second reference after the result array:

  $(myresult,$debug)=$db->getEntityMetadataByKeyAndType(.....,1)

=cut

=item

B<subject> Entity ID that the perm-parameter is to be valid for. SCALAR. Optional. Defaults to undef. If subject is specified the method will attempt 
to get entities that also match whatever value is in the perm-parameter.

=cut

=item

B<perm> Permission mask that entities must match to be included. SCALAR. Optional.

=cut

=item

B<lop> Logical operator for the permission mask in the perm-parameter. SCALAR. Optional. Defaults to "ANY". Valid values are "ANY" (logical OR) or "ALL" (logical AND).

=cut

=item

B<sorttype> Sets if the orderby-option is to be sorted alphanumerical or numerical. 0 means alphanumerical case-insensitive (default), 
1 means numerical and 2 means alphanumerical case-sensitive. Please note that the sorting is case-insensitive.

=cut

=back

The return value is a reference to a LIST of entity id(s) upon success in the order stated by the orderby- and order-options, or undef upon failure. Call the error-method to know more about the failure.

When using the offset- and count-options to create search windows it will also set the total number of entity(ies) found independant of the search window. This count can be retrieved by calling the getLimitTotal()-method after a successful call to this method with the offset-options.

=cut

=head2 getEntityByPermAndType()

Gets entity(ies) based upon a permission mask and entity type(s).

The method takes these options in the following order:

=over

=item

B<subject> This option specifies for which entity the permission mask is to be valid for? Typically it will be eg. a USER-entity id. This option is mandatory.

=cut

=item

B<perm> This option specifies the permission mask to use in the search. See createBitmask()-method for more information. Option can be undef for no bits set.

=cut

=item

B<permtype> This options specifies the search moderator type to use for the permission mask. It sets if the subject in question needs to have ALL the bits in the mask (logical AND) or ANY of the bits (logical OR). Valid setting is therefore either ALL or ANY. Will default to ALL if set to undef or an invalid value.

=cut

=item

B<types> This option specifies the entity types to moderate for in the search. The option is optional and if not set will search for the permission mask in all entity(ies). Type expected for option is a reference to a LIST.

=cut

=item

B<entities> Only include entities in this list if they match the other criteria. LIST-reference. Optional. Defaults to undef.

=cut

=back

Return value from method is a reference to a HASH in the format: entity => PERM. The PERM gives the complete perm for the given entity for the stated subject.

=cut

=head2 getEntityChildren()

Gets an entity's children.

Input is in the following order: entity id, entity type(s), recursive. The entity id is the entity parent to get the children of. The entity type(s) 
are the type(s) to get in the result (LIST-reference). It is optional and if not set will return entities of all types. The "recursive" sets 
if one is to fetch all children recursively for given parent and not only its immediate children.

It returns the parents children entity ids upon success as a LIST-reference, undef upon some failure. Please check the error()-method for more information upon failure.

=cut

=head2 getEntityChildrenPerm()

Gets an entitys perm on a given entity's children: getEntityChildrenPerm

This method takes these options in the following order:

=over

=item

B<subject> The ID of the entity that the permission mask is valid for.

=cut

=item

B<object> The entity to get the childrens permissions of.

=cut

=item

B<recursive> (optional) Specifies if one wants to recurse further down in the entity structure or not? It is optional and default to false. Set it to true for recursion.

=cut

=item

B<types> (optional) Sets the entity type IDs to include in the result. ARRAY-reference.

=cut

=back

The method returns a reference to a HASH-structure in the following format:

   ( ID => PERM,
     ID => PERM,
   )

where ID is the entity ID of ones of the object's children (see object-option). PERM is the permission mask on that child, relative to the subject (see subject-option).

Upon failure the method returns undef. Please check the error()-method for more information upon a failure.

=cut

=head2 getEntityMembers()

Get all members of given entity.

Accepts one input and that is the entity id of the entity to list the members of.

Returns a LIST-reference of entity ids that are members of the given entity:

   (entity id,entity id, entity id)

The LIST can be empty. The LIST-reference is undef upon failure. Please check the error()-method for more information.

=cut

=head2 getEntityMetadata()

Gets an entity's metadata moderated by a set of metadata keys.

Required input is in the following order:

=over

=item

B<entity> The id of the entity to get metadata of.

=cut

=item

B<options> A HASH-reference of options to the method. HASH-reference. Optional. Can be used to specified options to the method. As of 
today only "parent" is supported (boolean). If parent is 1 (true) the metadata is fetched from METADATA_COMBINED instead of 
METADATA in the database. If parent is 0 or anything else metadata is fetched from METADATA.

=cut

=item

B<keys> A LIST of metadata keys to be returned (instead of all). If no metadata LIST is specified it will default to undef (return all key->values of the entity). The metadata keys can contain wildcards (*).

=cut

=back

Return value is the metadata HASH-referemce with key->values (it can be empty logically enough). Upon failure undef is returned. Please call the error-method to find out more about the error.

=cut

=head2 getEntityMetadataList()

Returns a HASH-reference of entities metadata value for a given metadata-key.

Input is in the following order: metadata-keyname, entities. The metadata-keyname is the key-name for the key to get values for. The entities parameter is the entities to return that metadata-value for (LIST-ref). The entities-parameter is optional. If not given it will match against all entities in the database. 
And the last parameter accepted is "parent" that decides if the metadata is fetched from METADATA_COMBINED or just from METADATA. 
If parent is 1 (true) the metadata is fetched from METADATA_COMBINED instead of 
METADATA in the database. If parent is 0 or anything else metadata is fetched from METADATA.

Returns a HASH-reference upon success, undef upon failure. Please check the error()-method for more information upon failure.

The structure of the HASH returned is as follows:

   (
      entid => VALUE (SCALAR or LIST)
      entid => VALUE (SCALAR or LIST)
      .
      .
      entid => VALUE (SCALAR or LIST)
   )  

The VALUE will either be a SCALAR or a LIST, depending upon if the metadata key in question has multiple values or not (ARRAY or not).

=cut

=head2 getEntityMetadataMultipleList()

Returns a HASH-reference of entities metadata value for a given metadata-keys (or all keys).

Input is in the following order: metadata-keyname(s), entities, parent. The metadata-keyname is the key-name(s) for the key(s) to get values for as a 
LIST-reference. It can be undefined or empty upon which all metadata keys will be fetched. The entities parameter is the entities to return 
that metadata-value for (LIST-ref). The entities-parameter is optional. If not given it will match against all entities in the database. 
And the last parameter accepted is "parent" that decides if the metadata is fetched from METADATA_COMBINED or just from METADATA. 
If parent is 1 (true) the metadata is fetched from METADATA_COMBINED instead of 
METADATA in the database. If parent is 0 or anything else metadata is fetched from METADATA.

Returns a HASH-reference upon success, undef upon failure. Please check the error()-method for more information upon failure.

The structure of the HASH returned is as follows:

   (
      entid => {
                 KEYNAMEa => VALUE (SCALAR or LIST)
                 .
                 .
                 KEYNAMEz => VALUE (SCALAR OR LIST)
               }
      entid => {
                 KEYNAMEa => VALUE (SCALAR or LIST)
                 .
                 .
                 KEYNAMEz => VALUE (SCALAR or LIST)
   )  

The VALUE will either be a SCALAR or a LIST, depending upon if the metadata key in question has multiple values or not (ARRAY or not). The 
metadata keys are given its full textual name which then points to the VALUE. Not all entities need to have all KEYNAME values present and 
depends upon what is available in the database for that given entity ID.

=cut

=head2 getEntityParent()

Gets an entity's parent.

Input is the entity id to get the parent of.

It returns the parent entity id upon success, 0 upon some failure. Please check the error()-method for more information upon failure.

=cut

=head2 getEntityPath()

Gets entity(ies)'s parent and their parents (ancestors): getEntityPath(id1,id2,id3..idN).

Input is the entity id(s) that one wants to get the parent and ancestors of.

Return value is dependant upon the number of IDs asked for. In all cases the return value for a given entity is a LIST of 
ancestral entities in descending order (including the entity itself). 

If the caller asked for just one ID, the return structure is a LIST as follows (backwards-compatible):

   (ANCESTOR1,ANCESTOR2,ANCESTOR3..ID)

If the caller asked for more than just one ID, the return structure is a HASH-reference as follows:

   (
      ID1 => [ANCESTOR1,ANCESTOR2..ID1],
      ID2 => [ANCESTOR1,ANCESTOR2,ANCESTOR3..ID2],
      .
      .
      IDn => [ANCESTOR1..IDn],
   )

If some error occured the return value is undef. Check error()-method to get more information on a potential error.

=cut

=head2 getEntityPerm()

Gets an entitys permissions on a given object/entity: getEntityPerm(subject,object).

Input is in the following order:

=over

=item

B<subject> The id of the entity which you want to know which permission it has on the object.

=cut

=item

B<object> The id of the entity to get permission on.

=cut

=back

Returns a bitmask that is an aggregate of permissions from the entity tree. 
The DENY mask is added before the GRANT. Returns undef upon failure. 
Please call the error-method for more details upon errors.

=cut

=head2 getEntityPermByObject()

Gets the permissions on a specific entity (no ancestors): 

Input are in the follwing order:

=over

=item

B<subject> The entity id of the subject that the permissions are valid for. 

=cut

=item

B<object> the id of the entity that the permissions are fetched from.

=cut

=back

The return value is a LIST of grant and deny permission masks, in that order.

Returns undef upon failure. Call the error-method to find more details on the error in question.

=cut

=head2 getEntityPermByMetadataKeyAndType()

Retrieves the entities that match the criteria of metadata and type and the permission on them for a given entity (subject). This method is a wrapper around the getEntityPerm()- and getEntityByMetadataKeyAndType()-methods.

The method takes these options in the following order:

=over

=item

B<subject> The entity id of the entity that the PERM mask is valid for. See the getEntityPerm()-method.

=cut

=item

B<metadata> Metadata to moderate the search on. See explanation in the getEntityByMetadataKeyAndType()-method.

=cut

=item

B<offset> Offset of a search window to use. See explanation in the getEntityByMetadataKeyAndType()-method.

=cut

=item

B<count> Number of search entries to retrieve in a search window. See explanation in the getEntityByMetadataKeyAndType()-method.

=cut

=item

B<orderby> Which metadata key to order the search result by. See explanation in the getEntityByMetadataKeyAndType()-method.

=cut

=item

B<order> In what order to return the result in. See explanation in the getEntityByMetadataKeyAndType()-method.

=cut

=item

B<types> Entity types to moderate the search on. See explanation in the getEntityByMetadataKeyAndType()-method.

=cut

=item

B<tableopt> Select between including parent metadata or not. SCALAR. Optional. Defaults to 0. Value can be either 0 (false) or 1 (true).

=cut

=item

B<sorttype> See the sorttype option of the getEntityByMetadataKeyAndType()-method.

=back

Return value is a reference to a HASH of permissions for entity(ies). Upon failure undef is returned. Check the error()-method for more information on error.

The format of the returned HASH is:

   ( POS => { entity => ID,
              perm => PERM,
            }
   )

where POS is the numbered position in the search result, ID the entity ID and PERM the permission mask on that entity ID.

=cut

=head2 getEntityPermByPermAndMetadataKeyAndType

Retrieves entity(ies) by a permission mask and moderated for by a metadata key->value structure and entity type(s). It is a wrapper around getEntityByPermAndType()- and getEntityByMetadataKeyAndType()-methods.

The method takes these options in the following order:

=over

=item

B<subject> Entity id that the permission mask is valid for. See explanation in the getEntityByPermAndType()-method.

=cut

=item

B<perm> Permission mask. See explanation in the getEntityByPermAndType()-method.

=cut

=item

B<permtype> Logical match type to use for the permission mask. See explanation in the getEntityByPermAndType()-method.

=cut

=item

B<metadata> Metadata to moderate the search on. See explanation in the getEntityByMetadataKeyAndType()-method.

=cut

=item

B<offset> Offset of a search window to use. See explanation in the getEntityByMetadataKeyAndType()-method.

=cut

=item

B<count> Number of search entries to retrieve in a search window. See explanation in the getEntityByMetadataKeyAndType()-method.

=cut

=item

B<orderby> Which metadata key to order the search result by. See explanation in the getEntityByMetadataKeyAndType()-method.

=cut

=item

B<order> In what order to return the result in. See explanation in the getEntityByMetadataKeyAndType()-method.

=cut

=item

B<types> Entity types to moderate the search on. See explanation in the getEntityByPermAndType()-method.

=cut

=item

B<tableopt> Select between including parent metadata or not. SCALAR. Optional. Defaults to 0. Value can be either 0 (false) or 1 (true).

=cut

=item

B<sorttype> Sets how the search is performed. See the "sorttype" option in the getEntityByMetadatakeyAndType()-method.

=cut

=back

Returns a reference to a HASH-structure upon success, undef upon failure. Check the error()-method for more information on a potential error.

The format of the returned HASH-structure is:

   ( POS => 
      { entity => ID,
        perm => PERM,
      },
   )

Where POS is the numbered position in the returned and ordered result (always starting from 1, even with search windows). ID is the entity ID in position POS and PERM is the permission mask in the same position.

=cut

=head2 getEntityPermCheck()

This method checks if an entity has all the permission of the given bitmask on a specific object.

The method have these options in the following order:

=over

=item

B<subject> Entity id of the entity which the mask is valid for.

=cut

=item

B<object> Entity id of the entity which you want to check if the subject entity have the required permissions on.

=cut

=item

B<mask> The bitmask to check if the subject entity has on the object entity.

=cut

=back

The method returns 1 if the subject entity has the required permissions, 0 if not. Undef is returned upon failure. Please check the error()-method in such a case.

=cut

=head2 getEntityPermsForObject()

Gets the permissions on a object: 

Input are in the following order:

=over

=item

B<object> The entity id of the object. 

=cut

=item

B<perm mask> An optional mask of permission bits we are looking for.

=cut

=item

B<object type> An optional subject type to filter for.

=cut

=back

The return value is a HASH of object => permission of objects thet match the criteras.

Returns undef upon failure. Call the error-method to find more details on the error in question.

=cut

=head2 getEntityPermsForSubject()

Gets the permissions held by a subject: 

Input are in the follwing order:

=over

=item

B<subject> The entity id of the subject. 

=cut

=item

B<perm mask> An optional mask of permission bits we are looking for.

=cut

=item

B<object type> An optional object type to filter for.

=cut

=back

The return value is a HASH of object => permission of objects thet match the criteras.

Returns undef upon failure. Call the error-method to find more details on the error in question.

=cut

=head2 getEntityPermsOnObject()

Gets the permissions on an object: 

Input are in the follwing order:

=over

=item

B<object> the id of the entity that the permissions are fetched from.

=cut

=back

The return value is a HASHREF of subjects with permissions on an object. Take into account the objects inheritance, but not implisit or explisit subject membership.
Hash key is subject id, value is a hash with mask for inherit, deny, grant and perm ( grant | inherit & (~inherit ^ deny)) 

Returns undef upon failure. Call the error-method to find more details on the error in question.

=cut

=head2 getEntityRoles()

Get a list of roles for an entity: getEntityRoles(id).

Roles are the entity itself,its ancestors and any entity tied directly or indirectly to any of them through the databases MEMBER-table.

Returns an unsorted list without duplicates. Undef upon error. Check the error()-method to get more information upon failure.

=cut

=head2 getEntityTemplate()

Get an aggregated template for an entity.

Input is in the following order:

=over

=item 

B<type> The entity type to get a template for. SCALAR. Optional. If not specified will attempt to default to DATASET-type.

=cut

=item

B<entities> The entity(ies) to get template for. ARRAYM of SCALAR. Required. The options expects a LIST of one or more entity(ies). 
If just one entity is specified it will attempt to return the template that is valid on just that entity itself (if any). If multiple 
entities are specified it assumes that it is a tree list to aggregate template constraints from going from element 0 to element N 
(inheritance).

=cut

=back

The return value is a HASH-reference to a set of template constraints. If any of the constraints on a given metadatakey has not been set, it will revert to defaults. The defaults are as follows:

=over

=item

B<default> undef (no default(s) set/default(s) do not exist)

=cut

=item

B<regex> .*

=cut

=item

B<flags> undef (no bit set)

=cut

=item

B<min> 0

=cut

=item

B<max> 1

=cut

=item

B<comment> Blank string.

=cut

=back

Inheritance on templates works by going from the first entity specified in the entities-parameter LIST-ref to this 
method and down to the last entity in that list (often the entity you need to know the aggregated template of). 

Only whole key-constraints will supplant another one while recursing the tree defined in the entities-parameter. This means that 
parts of the key, like say max or min, will not replace just max and min. All the constraints for the key in 
question will be replaced upon finding a replacement key constraint definition, even undef.

Similarly, the default-constraint will not accumulate defaults as in traverses down the entity tree, but replace any defaults earlier 
in the tree with the new defaults defined for that key in the template being processed.

Let us assume we have the entities GROUP, USER, DATASET in addition to the special TEMPLATE-entity type.

All entities in AuroraDB can have any number of templates assigned to them (up to the limits of the database), but all assignments are type-
specific. This means that the templates assigned on an entity belong in an entity type group. Eg. one can assign 
any number of templates having effect for DATASET-entities on a GROUP-entity. The templates themselves are type-
neutral and only gain templating effect once they are assigned on an entity (see the assignEntityTemplate()-method) and a entity type for that entity.

All entities can have template assignments for entity types that are not the same as itself, since this is about 
aggregated templates and inheritance. When calling the getEntityTemplate()-method is called it will require the 
entity type to be specified in order to figure out the aggregated template.

At the end of the aggregation process, any missing or undefined constraints for a specific key will be defaulted to standard values (see above).

Upon success this method will return a HASH-reference to a aggregated entity template, undef will be returned 
upon any error. Please call the error()-method for more information upon failure.

See the setTemplate()-method for more information on the format of the returned, aggregated template. Please note, however, that the 
getEntityTemplate()-method will add two fields to the template of each "key" that are called "template" and "assignedto". The "template" 
fields tell which template affected the last change on the definition and "assignedto" says on which entity that this template was 
assigned. This information enables the user to know if the aggregated template result for a given "key" is defined on the entity that 
one asked for the aggregated template of, or if it was inherited from above (the assignedto id is not the same as the entity asked for). 
It also says which template effected that result.

=cut

=head2 getEntityTemplateAssignments

Gets template assignment(s) on an entity

Input is in the following order:

=over

=item

B<entity> The entity id to get the assignments of. SCALAR. Required.

=cut

=item

B<type> The entity type to get assignments of. SCALAR. Optional. If not specified the method will 
return all assignments of all types on the entity in question.

=cut

=back

This method gets template assignment(s) on an entity and optionally just of a given type. All templates are 
assigned to entities based upon what type the template is to have effect for. By giving a set type, only the 
assignment(s) for that type on the entity in question are returned. If no type is specified this method will 
return all template assignments set on the entity.

Upon success returns a HASH-reference of the assignments, undef upon failure. Please check the error()-method for more 
information upon failure.

The return structure upon success is as follows:

  (
     TYPEa => [TEMPLATEID1,TEMPLATEID2 .. TEMPLATEIDn]
     .
     .
     TYPEz => [TEMPLATEID4,TEMPLATEID5 .. TEMPLATEIDn]
  )

where TYPEa and so on are the entity type id of the type assignment. TEMPLATEID1 and so on is the entity id of the template 
that are assigned on the given type. This is an ARRAY-reference of template entity ids and the array returns the assignments in the 
order that they are set, starting from element 0 and up.

If no assignments have been set on the entity in question (or of the chosen type), the HASH-structure will be empty.

=cut

=head2 getEntityTemplateId()

Retrieve template assignments on a given entity(ies). This is actual template id's and not an aggregated template.

Input is entity type to fetch template for and entity id they belong to accordingly. Entity id is expected to be a LIST of one or more elements. We recommend not using more than one elements, since it will be impossible to know which template id belongs to which entity?

Return value is a LIST reference upon success, undef upon failure. Check the error()-method for more information upon failure.

The LIST returned contains template id's that belongs to the given entity. The list is ordered according to when the templates take effect.

=cut

=head2 getEntityTemplatePath()

Retrieves the path for an entity's templates. As of writing a wrapper around getEntityPath.

See getEntityPath()-method for more information.

=cut

=head2 getEntityTree()

Gets the entity tree from given entity id.

Input is in the following order:

=over

=item

B<entity> Entity id to start from. 1 can be used to signify the top, ROOT entity. Defaults to 1 if none specified.

=cut

=item

B<include> LIST-reference of entity types to consider. Default to undef which will include all of the tree.

=cut

=item

B<exclude> LIST-reference of entity types to exclude from result. Default to no exluded.

=cut

=item

B<depth> The maximum depth from the depth of the start entity to return in the result. SCALAR. Optional. If not 
specified it will return all entity children of start entity independant of depth. Depth 0 is the same as all entites on 
the same level as the start entity, 1 is all on the level below it and so on.

=cut

=back

Returns a HASH-reference of the entities in the tree and their children with attributes. 

The return HASH-structure is as follows:

  (
    IDa => {
            id => IDa,
            type => INT,
            children => [ IDb...IDn ],
          }
    IDb => {
            id => IDb,
            parent => IDa,
            type => INT,
            children => [],
          }
  )

IDx is the INT entity id. The subhash specified the ID of that entity again in the key id. It also gives the entity's type and
parent, except for the root entity 1 (IDa in example above), which has no parent (or technically itself). It also contains a LIST of children with IDs of
its immediate children (that has it has its parent). The returned HASH is therefore flat and all entities in the tree can be addressed 
at its root level.

Returns undef upon failure. Check error()-method for more information on the failure.

=cut

=head2 getEntityType()

Retrives the entity type of an entity id: getEntityType(entityid)

Input is entity id or it will default to the invalid id of zero.

Return value is the entity type of id referenced upon success, or 0 upon failure. Please call the error-method for more details.

=cut

=head2 getEntityTypeIdByName()

Retrieves the entity type id based upon the textual name input to the method: getEntiyTypeIdByName([name1,name2..nameN]);

No input is required and then all entity type ids are returned. If one or more names are specified (comma separated), it will return the entity type ids as a LIST for the names it recognizes or undef for unknown ones.

Return value is a LIST.

=cut

=head2 getEntityTypeName()

Retrives the textual name of the entity type: getEntityTypeName (entityid)

Input is the entity id or it will default to the invalid id of zero.

Return value is the entity ids type name upon success, undef upon failure. 

Please call the error-method for more details of the error.

=cut

=head2 getEntityTypeNameById()

Retrieves the entity type name by specifying the entity type id(s): getEntityTypeNameById([id1,i2..idN]).

No input is required and it will then return all entity type textual names. If one or more type id(s) are specified (comma separated), it will return the entity type name(s) for the entity type id(s) specified.

Return value is a LIST.

=cut

=head2 getLogEntries()

Gets the log entries of entity or if none given all log entries in the database.

Input is the entity id to get the logs for. If none given it will fetch log entries for all entites.

Return value is a HASH pointer of the resulting log entries. The format of the HASH is:

   ( NO => { time => TIME,
             loglevel => LEVEL,
             message => SCALAR,
             idx => SCALAR,
             tag => SCALAR
           }
   )

the NO is the auto increment value of the database. time is given in hires time, loglevel is the level value from possible loglevels (see enumLoglevels()-method), message is the message of the log entry and idx is the log entries auto increment index in the database.

It will return undef upon failure. Please check the error()-method for more information in the case of an error.

=cut

=head2 getLoglevelByName()

Gets the loglevel id by giving its name. 

Input is the loglevel name. Defaults to "" and will result in a "0" return value (does not exist).

Returns the id upon success, 0 if it does not exist, undef upon failure. Please check the error()-method for information on a potential error.

=cut

=head2 getLoglevelNameByValue()

Gets the loglevel name by giving its value.
Input is the loglevel value. If none given it defaults to 0 which will result in a "" return value (does not exist).

Return value is the loglevel name upon success, "" or blank if it does not exist, undef upon failure. Check the error-method for more information on an error.

=head2 getMetadataKey()

Get the metadata key id by specifying the metadata key name.

Input is the metadata key name.

Return value is the metadata key id upon success, 0 if it does not exist, undef upon failure. Please call the error-method to find out more about the error.

=cut

=head2 getMtime()

This methods read modification time for tables and return the newest one.

Optional parameter: table names - tables to get mtime for, default all tables with set mtime.

Return value: the newest mtime found. 

Time format is floating unis time.

=cut

=head2 getPermTypeNameByValue()

Returns the permission type name(s) for the given permission type value(s).

Input is a LIST of permission type value(s).

Return value is a LIST of permission type name(s) for those value(s).

=cut

=head2 getPermTypeValueByName()

Returns the permission type value(s) for the given permission type name(s).

Input is a LIST of permission type name(s).

Return value is a LIST of permission type value(s) for those name(s).

=cut

=head2 getTemplate()

Get a template and its constraints.

Input is the template id to get the constraints for.

Return value is HASH-reference with the constraints upon success (see setTemplate for more information on structure), or undef upon failure. Check the error()-method for more information upon failure. 
Undef-values in the keys are to be understood as there are no more values for that "value".

=cut

=head2 getTemplateAssignments()

Retrieves all entities that the given template has been assigned to as well as type.

Input parameters are in the following order: template id (SCALAR, required), type (SCALAR, optional), duplicates (SCALAR, optional) 

Template ID is the template that one wishes to get all assignments of. Type is the type id that one 
wishes to get assignments of (other type assignments of given template id are omitted). Duplicates sets 
if any duplicates of entities on the same entity type assignment will be removed or not? It is possible to 
assign the same template several times on the same entity and entitytype and this parameter controls if this 
will be visible in the returned result or not? It is evaluated as a boolean and if true will remove 
duplicates and if false will not remove duplicates. If parameter is undef it will default to true and 
duplicates will be removed.

Returns a HASH-reference upon success, undef upon failure. Please check the error()-method for 
more information upon failure.

The HASH structure is as follows:

   ( 
      all => [entity1,entity2,entity3 .. entityN]
      types => { 
                 typeA => [entity1 .. entityN]
                 typeB => [entity2, entity3 .. entityN]
                 .
                 .
                 typeZ
               }
   )

Please note that the "all" key contains all the entities that have the given template 
assigned to them, without duplicates (no matter what the duplicates-parameter says). The 
"types" key contains the entity assignments ordered into entity types, so that one can 
easily check eg. what "DATASET" assignments have been put in place with the given template.

=cut

=head2 getTemplateAssignmentsTree()

Gets a tree of template assignments and their metadata key definitions.

This method accepts the following parameters in this order:

=over

=item

B<entities> Entity og entities ID(s) to get template assignments of. ARRAY-reference. Required. It can be one or more elements. If just one 
element is specified it will get the entity tree path down to that entity and generate a tree of assignments based on that. If more than one 
element is specified it will use that as the entity tree and generate assignments based on that.

=cut

=item

B<type> Entity type ID to get template assignments to. SCALAR. Optional. Will default to "DATASET". This decides which entity type to get 
template for, since all template assignments are assigned as a type and have effect on a given entity type in the tree.

=cut

=item

B<include> Moderates which template IDs to include in the result. ARRAY-reference. Optional. If not specified will include all template 
assignments found. If specified it will only include those template IDs that are specified in the ARRAY-reference. This makes it possible 
to analyze how just some template IDs have effect down the entity tree.

=cut

=item

B<prune> Decides if an empty entity in the generated tree should be included or not if it has no template assignments. SCALAR. Optional. If 
not specified will not prune away entities with no template assignments. The value is interpreted as a boolean and must be either true or 
false.

=cut

=back

This method returns a tree of template assignments on the entity(ies) specified according to the use of the "entities"-parameter. It will also 
return the metadata key-definitions of all the template assignments.

Upon success this method returns a HASH-reference, undef upon failure. Please check the error()-method for more information upon failure.

The HASH-structure returned upon success looks like this:

   (
      1 => entity => SCALAR,
           assigns => {
                         1 => { 
                                 TMPLIDa => {
                                               KEYNAMEa => {
                                                              default => ...
                                                              regex => ...
                                                              flags => ...
                                                              min => ...
                                                              max => ...
                                                              comment => ...                                  
                                                           }
                                              .
                                              .
                                              KEYNAMEz
 
                                            }
                                 .
                                 .
                                 TMPLIDz                                                                                  
                              }
                         .
                         .
                         N
                      }
      .
      .
      N
   )

The assignmenst are ordered from 1 to N in order to know which order to iterate on it. Inside each initial order number is two fields: 
"entity" and "assigns". "entity" defines which entity these assignments are valid for, if any? "assigns" gives the template assignments 
for that entity given any constraints set in the method-parameters (see above). The "assigns" sub-structure is also numbered from 
1 to N and gives the order in which the template(s) are valid. After the number comes the template ID (TMPLIDa .. TMPLIDz) from the 
database. Each ordered assignment will only have one template ID here and is only there to inform what the template ID is for that 
assignment. After the template ID comes the textual metadata key-name (KEYNAMEa .. KEYNAMEz) and after that comes the actual definition of 
the key name (see the setTemplate()-method for more information).

If one uses the include-parameter the numbering in the assigns sub-structure will reflect which template that are included and are not a 
numbering reflecting the actual assignment order on that entity if the output then have been moderated.

This method optimizes the use of the getTemplate()-method to get the definition of the template by caching the response and eliminates the 
need to call it many times for the same template id. The method will be further optimized if one uses the include-parameter to narrow down 
which template ids that are to be included in the response.

=cut

=head2 getTemplateFlagBitByName()

Returns the template flag bit number(s) for the given name(s)

Input is a LIST of flag bit name(s) to get flag value for.

Return value is a LIST of flag bit position values of those names or undef for non-existing ones.

=cut

=head2 getTemplateFlagNameByBit()

Returns the template flag bit name(s) for the given flag bit position value(s).

Input is a LIST of flag bit position value(s) to get name(s) for.

Return value is a LIST of flag bit name(s) for those flag bit value(s) or undef for non-existing ones.

=cut

=head2 maxDepth()

Returns the maximum depth allowed on the entity tree.

No input is accepted.

Returns the maximum depth allowed on the tree as set through the constructor new() or the default 
from the global constant $VIEW_DEPTH. The value set through the constructor new() takes precedence 
if valid.

=cut

=head2 moveEntity()

This methods moves an entity provided the new parent or to-entity exists.

Input are in the following order:

=over

=item

B<entity> The entity to move.

=cut

=item

B<parent> The parent to move the entity to.

=back

Returns 1 upon success, 0 upon failure. Call the error-method to get more information on the failure.

=cut

=head2 removeEntityMember()

Removes member(s) from an entity.

The method accepts these parameters in the following order:

=over

=item

B<object> The id of the entity to remove member(s) from. Required.

=cut

=item

B<subjects> The id of the entity(ies) to remove as member(s). Optional. If not set (not undef) all members of the object-entity will be 
removed. It can be one or more entity ids as a LIST.

=cut

=back

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

=cut

=head2 removeEntityPermsAndRoles()

Remove all of an entity's permissions and roles in the AURORA database. Optionally all permissions other 
entity(ies) has/have on that entity.

This method accepts the following parameters in this order: id,others. ID is the entity ID of the entity 
to remove all permissions and roles of, SCALAR, Required. Others is the flag to tell the method to also remove 
all permissions and memberships that other entity(ies) might have on the given entity, BOOLEAN, optional. If 
not given will default to 0/false and do not remove permissions and roles others have on the given entity.

Returns 1 upon success, 0 upon not being able to remove it, undef upon some failure. Please check the 
error()-method for more information upon failure.

=cut

=head2 sequenceEntity()

(Re)sequence an entity and any descendants. Done on createEntity and moveEntity to ensure parents is sequenced before child. 

Input is entity. Returns count of sequenced entitys on success, 0 on failure.

=cut

=head2 setBitmask()

Sets bits in a bitmask.

Input is the bitmask to modify and bitmask with bits to set. 
Default parameters is ''. 

Return value is the resulting bitmask as a SCALAR. The input bitmask is unaltered.

=cut

=head2 setBits()

Sets bits in a bitmask.

Input is the bitmask to modify and a list of bit numbers to set. 
Default bitmask is ''. 

Return value is the resulting bitmask as a SCALAR. The input bitmask is unaltered.

=cut

=head2 setEntityMetadata()

Sets an entitys metadata. Old metadata keys are overwritten with new value or new keys are added. The values allowed to be set are moderated by the templates for this entity.

The method accepts these options in the following order:

=over

=item

B<entity> The entity id of the entity to set the metadata on.

=cut

=item

B<metadata> The metadata HASH-reference of key->values to set on the entity. Can be undef.

=cut

=item

B<type> Template type to check the metadata entered against. If set to undef it will default to the entity id's type itself (see entity option).

=cut

=item

B<path> Entity-path to use for the aggregated template that the metadata is checked against as a LIST-reference. If set to undef it will use the path of the entity id itself (see entity option).

=cut

=item

B<override> Override template checking for metadata being set. Optional, default to false. If statement here evaluates to true it will ignore any template definitions 
that are valid for the metadata being set. This setting is to allow for critical system-updates and should be used with care. Should normally be false.

=cut

=back

The method checks the metadata compliance against relevant aggregated template and if it fails returns the metadata keys it failed on in the error message (call the error()-method to read it). 
Please note that if the entity in question already have metadata on it, the existing metadata will be collected and used for the keys that are not in the input to the 
method. The input keys and values together with the keys that are not in the input will be checked against the aggregated template for compliance. This ensures that 
one can update just one key in the metadata without getting template compliance issues, since existing metadata will fill missing key-values. 

This way of handling setting metadata on an entity means that the update follow the rule of the three musketeers: all for one and one for all. An update of a key or 
an addition of key value(s) will need to check all of the metadata for template compliance.

Please also be aware, that if you want to delete a metadata key while updating other keys, you can set that key to 
an empty LIST reference. Eg:

   $hash->{KEYNAME}=\@list

The reason for this is that the method handles all value setting as lists (as does the database) and tries to 
optimize for using UPDATE/REPLACE-statements in SQL, so after setting values for a key, it removes any extra LIST 
values that are not needed anymore. If you set zero LIST values, it removes all LIST values afterwards since 
they are not needed anymore. Ergo thereby in effect performing a deletion of a key.

It return 1 upon success, 0 upon failure. Please call the error()-method to get more information on the error.

This function is simplified to work with basic and standardized SQL like UPDATE, INSERT and DELETE (no REPLACE or INSERT...on DUPLICATE UPDATE) for compability reasons. It is also optimized to favour UPDATE of values where possible (were there are existing metadatakeys), even for arrays. When no existing key or index of that key (in case of arrays) exists, it will insert new values. If the new array contains less values than the previous it will delete away surplus rows in the database. In addition it will skip running an UPDATE on values that are the same as before for a given key. This optimizes the function to work on most database engines, while also optimizing its speed and functionality. The working of the function is based upon some assumptions:

=over

=item 

Most databases handles "REPLACE" or "INSERT on some conflict UPDATE" (and its variants) as a delete followed by an insert. This is sub-optimal if one can in many cases just execute a UPDATE statement.

=cut

=item 

Most metadata hashes given to the method contains key->value pairs that are already stored in the database. Ergo no need to either update or insert, but to skip.

=cut

=item

We would rather want to update a row with a new value, than delete and then insert it of speed reasons. 

=cut

=item

It is faster to first read all metadata key-value pairs of an entity from the database (SELECT) and then do mostly skip or UPDATE, than use the "REPLACE" or "INSERT on some conflict UPDATE" strategy.

=cut

=item 

"REPLACE" and "INSERT on some conflict UPDATE" do not handle surplus values of a key (arrays). In order to know of the surplus one has to either fetch data by using SELECT or run a compulsive DELETE after each ended key->value writing to the database (all elements of array written). This is is circumvented by reading all key->value pairs before beginning in the method (the DELETE will be skipped if not needed).

=back

These are the main considerations for the workings of the method.

=cut

=head2 setEntityPermByObject()

Set the permissions on a specific entity.

This methods takes these options in the following order:

=over

=item

B<subject> Entity id of the entity which the permission masks are to be set for. Required.

=cut

=item

B<object> Entity id of the entity witch the permission masks are set on. Required.

=cut

=item

B<grant> The grant mask to set. Accepts undef (no bits set).

=cut

=item

B<deny> The deny mask to set. Accepts undef (no bits set).

=cut

=item

B<operation> Defines how to apply the bitmasks. undef means replace bits, true (eg. 1) means set bits and false (eg. 0) means clear bits.

=cut

=back

The method returns a reference to a LIST of the grant and deny permission masks after completion of the operation (in that order). 

Undef is returned upon failure. Please check the exact error message by calling the error()-method.

=cut

=head2 setLogEntry()

Sets a log entry.

Input is in the following order:

=over

=item

B<time> Time of log entry. If undef will default to current time.

=cut

=item

B<entity> Entity id which the log entry concerns. Required.

=cut

=item

B<loglevel> loglevel of the log entry. See the enumLogLevels()-method.

=cut

=item

B<tag> Tag the message entry in the log. Optional. SCALAR. Will default to "NONE". Valid characters are A-Z, a-z, 0-9, "-" and "_". Maximum size is 16 characters.

=cut

=item

B<message> Textual message for the log entry. Defaults to a blank string.

=cut

=back

Return value is 1 upon success, 0 upon failure. Check the error-method for more information upon error.

=cut

=head2 setMtime()

This methods updates set modification time for a table.

Required parameter: table name - table to update mtime for. 

Optional parameter: mtime - time to set, defaults to now. 

Time format is floating unix time.

Return value: undef on failure, 1 otherwise.

=cut

=head2 setTemplate()

Sets the constraints of a template.

Input parameters are in the following order:

=over

=item

B<id> Entity ID of the template to set/change. SCALAR. Required.

=cut

=item

B<constraints> Constraint definition(s) to set on template. HASH-reference. Optional. If not set, will just not set any constraints 
on the template in question.

=cut

=item

B<reset> Whether to reset/delete all existing template contraints, before applying new ones (or do nothing). BOOLEAN. Optional. 
If not specified the method will just apply the new constraints given, ignoring keys that have been already set. Since booleans does not 
exist as a type in Perl, it is enough that the expression in "reset" evaluates to true, but is technically just a SCALAR.

=cut

=back

The template constraints HASH has the following format:

   ( KEY => { 
              default => VALUE,
              regex => VALUE,
              flags => VALUE,
              min => VALUE,
              max => VALUE,
              comment => VALUE,
            }
   )

You can set any number of these KEY-constraints that you want on a given template. With KEY here is meant the textual name of the metadata key on an entity. 

Please note that the values undef and not exists are interchangable concepts when it comes to templates. Undef is the same as the key does not exist and/or is not defined. So when setting a template, a value not specified will appear as an undef-value when loading that same template again (see the getTemplate-method). The 
exception to this behaviour is when getting the aggregated template of an entity by calling the getEntityTemplate()-method. Here it will default values at the end that has not been defaulted by the metadata definition. There are 
in other words no valid value in AuroraDB for undef. Undef just means that it is not existing or defined.

This method will also strip away flags bit-combinations that are not allowed, such as SINGULAR at the same time as MULTIPLE. Singular is preferred (conservative approach).

The meaning of the KEY-constraints are as follow:

=over

=item

B<default> Default value(s) for the template key in question. Defaults to undef. It sets which values to be set by the template if user does not fill in anything. This constraint can contain one or more values. If it contains more than one value it is to be a pointer to a LIST. Several values can also be combined 
with the SINGULAR and MULTIPLE flag to indicate that the value entered is to be chosen from one or more values in this default (see the flags constraint). Then the default-constraint will act database-like (but not storing an ID or identifier like a database would).

=cut

=item 

B<regex> The regex for checking the template key value in question (when used). Defaults to undef. You are not to include the slashes of the regex, just the regex-expression itself.

=cut

=item 

B<flags> The flags of the template key in question (bitmask). Defaults to undef (no flag bit set). Supported flags are: MANDATORY, 
NONOVERRIDE, SINGULAR, MULTIPLE, PERSISTENT and OMIT. The meaning of these flags are as follows:

=over

=item

B<MANDATORY> The key is mandatory to be answered. If default is defined, this will be chosen in the event of a missing value.

=cut

=item

B<NONOVERRIDE> The key definition is not allowed to be overridden. Template further down are not allowed to change the constraints and defaults 
of this key. 

=cut

=item

B<SINGULAR> States that the key is to have a value from one of the value(s) in the constraint "default". The key will then act like in a database and the value entered will be checked against the default(s).

=cut

=item

B<MULTIPLE> States that the key is to have a value from one or more of the value(s) in the constraint "default". If enabled together with 
the SINGULAR-flag, the SINGULAR-flag will take precedence and the MULTIPLE-flag will be stripped away.

=cut

=item

B<PERSISTENT> States that key value is not to change once it has been set by any updates later on.

=cut

=item

B<OMIT> Omits a key from the template. This can be used to remove key-constraints further down the entity-tree.

=cut

=back

=cut

=item 

B<min> The minimum number of values to enter for this template key. Defaults to undef (not defined/default does not exist). 

=cut

=item 

B<max> The maximum number of values to enter for this template key. Defaults to undef (not defined/default does not exist). Multiple values on a template key equates to an array.

=cut

=item

B<comment> Textual comment upon the constraint that explain what is expected in a normal and understandable language. Defaults to undef (not defined/default does not exist).

=cut

=back

Return value is 1 upon success, 0 upon failure. Check the error()-method for more information on a potential error.

=cut

=head2 unassignEntityTemplate()

Removes template assignment of given type on entity. A wrapper around assignEntityTemplate.

Input is entity id and entity type. See assignEntityTemplate()-method for more information.

Return value is 1 on success, 0 on failure. Check the error()-method for more information.

=cut

=head2 updateEffectivePerms()

Updates the PERM_EFFECTIVE_* tables to keep PERM_EFFECTIVE up to date.

No input parameters

Return 1 on success, undef on failure. 

=cut

=head2 updateEffectivePermsConditional()

Calls updateEffectivePerms() if mtime of the source tables differ from mtime of PERM_EFFECTIVE_PERMS.

Updates mtime for PERM_EFFECTIVE_PERMS to the mtime of the sources and return true on success.

Return undef on failure.

=cut

=head2 useDBItransaction()

This methods returns a DBItransaction instance that keep track of who started a transaction, committing transaction and handling rollback and so no with minimal code in the methods: useDBItransaction()

The methods requires no input. Returns a DBItransaction-instance.

See the DBItransaction module for more information.

=cut
