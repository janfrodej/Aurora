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
# Store: class to represent a store type
#
package Store;

use strict;
use StoreProcess;
use StoreProcess::Shell;
use Parameter::Group;
use sectools;

# STORE MODES
our $STORE_MODE_NOP = 0;
our $STORE_MODE_GET = 1;
our $STORE_MODE_PUT = 2;
our $STORE_MODE_DEL = 3;
our $STORE_MODE_LOCAL_LIST = 4;
our $STORE_MODE_REMOTE_LIST = 5;
our $STORE_MODE_LOCAL_SIZE = 6;
our $STORE_MODE_REMOTE_SIZE = 7;

# AUTH TYPES
our $AUTH_PW      = 1;
our $AUTH_PWFILE  = 2;
our $AUTH_KEY     = 3;
our $AUTH_KEYFILE = 4;

# constructor
sub new {
   # instantiate
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # set defaults if not specified 
   # unqiue name of the store
   if (!exists $pars{storename}) { $pars{storename}=sectools::randstr(64); }
   # timeout for get and put commands in seconds, 0=never
   if (!exists $pars{timeout}) { $pars{timeout}=0; }
   # wait for get and put commands in seconds, 0=forever
   if (!exists $pars{wait}) { $pars{wait}=0; } 
   if (!exists $pars{sandbox}) { $pars{sandbox}="/nonexistant"; }
   # set the metadata of the dataset, if any (ensure it is a HASH)
   if ((!exists $pars{metadata}) || (ref($pars{metadata}) ne "HASH")) { my %h; $pars{metadata}=\%h; } 
   # set the authentication mode of the Store. Identity/Key-based is preferred. The username and password themselves are passed as parameters to the open()-method.
   $self->{authmode}=(exists $pars{authmode} ? ( (($pars{authmode} >= 1) && ($pars{authmode} <= 4)) ? $pars{authmode} : $AUTH_KEY ) : $AUTH_KEY);
   
   # save parameters
   $self->{pars}=\%pars;
 
   $self->{error}="";

   # set modes
   $self->{mode}=$STORE_MODE_NOP;
   $self->{success}=0;

   # store has not been defined/opened yet
   $self->{open}=0;

   # params instances
   $self->{getparams}=Parameter::Group->new();
   $self->{putparams}=Parameter::Group->new();
   $self->{delparams}=Parameter::Group->new();
   $self->{extra}=Parameter::Group->new();

   # add logs for list- and size methods
   # they all share an empty log to begin with
   my $sproc=StoreProcess->new(command=>$self->{getparams});
   $self->{listlocallog}=$sproc->getlog();
   $self->{listremotelog}=$sproc->getlog();
   $self->{sizelocallog}=$sproc->getlog();
   $self->{sizeremotelog}=$sproc->getlog();

   # define store
   $self->open_define();

   return $self;
}

# probe remote source/dest about its
# capabilities.
sub probe {
   my $self=shift;

   return 1;
}

# get or set storename
sub name {
   my $self = shift;
   
   if (@_) {
      # set store name
      my $name = shift;

      $self->{pars}{storename}=$name;
      return 1;
   }

   # get storename
   return $self->{pars}{storename};
}

# opens the store for business
# setting parameters and creating
# instances of StoreProcesses.
# parameters to open are interpreted as
# parameters to the StoreProcesses.
# Return 1 if opened successfully
# return 0 if fails or already open
sub open {
   my $self = shift;
   my %pars = @_;

   if (!$self->isOpen()) {
      # get instances
      my $get = $self->{getparams};
      my $put = $self->{putparams};
      my $del = $self->{delparams};
      my $extra = $self->{extra};

      # check put/get and that we have each parameter and that it adheres
      # to the regex rule
      my $missing=0;
      my $failed=0;
      my @parmissing;
      my @parfailed;
      foreach (@{[$put,$get,$del,$extra]}) {
         my $par=$_;

         foreach (@{$par->enumRequiredObjects()}) {
            my $reqname = $_;

            if ($par->get($reqname)->private()) { next; } # not allowed to change private parameters

            if (exists $pars{$reqname}) {
               # get regex check
               my $check = $par->get($reqname)->regex();
               $check=qq($check);

               if ((exists $pars{$reqname}) && (defined $pars{$reqname}) && ($pars{$reqname} =~ /^$check$/)) {   
                  # ok
                  next;
               } else {
                  # regex check failed
                  $failed=1;
                  my $exist=0;
                  foreach (@parfailed) {
                     if ($_ eq $reqname) { $exist=1; }
                  }
                  if (!$exist) { push @parfailed,$reqname; }
               }
            } else {
               # parameter doesnt exists
               $missing=1;
               my $exist=0;
               foreach (@parmissing) {
                  if ($_ eq $reqname) { $exist=1; }
               }
               if (!$exist) { push @parmissing,$reqname; }
            }
         }
      }

      # check for missing and/or failed parameters
      if (($missing) || ($failed)) {
         # parameters are missing or failed
         my $mstr=($missing ? "missing parameters that are required: @parmissing" : "");
         my $fstr=($failed ? "failed parameters that are required: @parfailed" : "");
         my $and=($missing && $failed ? " and " : ""); 
         $self->{error}="Unable to open store. You have $fstr$and$mstr.";
         return 0;
      }

      # all required parameters approved - update get and put param instances
      foreach (keys %pars) {
         my $name = $_;

         # go through both put and get params
         foreach (@{[$put,$get,$del,$extra]}) {
            my $par=$_;

            if ((!$par->exists($name)) || ($par->get($name)->private())) { next; } # not allowed to change private parameter
            # set parameter
            # get regex check
            my $check = $par->get($name)->regex() || "";
            $check=qq($check);

            if ((exists $pars{$name}) && (defined $pars{$name}) && ($pars{$name} =~ /^$check$/)) {
               # passed check
               my $val=$pars{$name};
               # check if param is to be sandboxed
               if ($par->get($name)->sandbox()) {
                  # this param is to be sandboxed, strip it down and add start path
                  $val=~s/\.\.//g; # no dot dots 
                  $val=~s/[\/\<\>\*\?\[\]\`\$\|\;\&\(\)\#\\]//g; # remove all characers we do not allow (shell metacharacters++)
                  # add sandbox prefix from class
                  $val=$self->{pars}{sandbox}."/".$val;
               }

               # set/change value
               $par->get($name)->value($val);
            } else {
               # check failed - use failed var from earlier
               $failed=1;
               my $exist=0;
               foreach (@parfailed) {
                  if ($_ eq $name) { $exist=1; }
               }
               # add failed parameters to var from earlier if not exists already
               if (!$exist) { push @parfailed,$name; }
            }
         } 
      }

      # check for failed parameters
      if ($failed) {
         $self->{error}="Unable to open store. You have failed non-required parameters: @parfailed.";
         return 0;
      }

      # all parameters present and accounted for. create instances
      if ($self->open_create()) {
         # set store to open
         $self->{open}=1;
         # success
         return 1;
      } else {
         # failed. open_create handles errors
         return 0;
      }
   } else {
      # already open
      $self->{error}="Store is already open.";
      return 0;
   }
}

# defines the stores put and get parameters needed for
# the store and returns 1 if successful, 0 if not
# To be overridden by inheriting child.
# Parameters "local" and "remote" are always
# used to denote locations in the storeprocess
# operations no matter the type. The "local" 
# parameter is manipulated and set to the 
# tmp-storage area when used by the
# storehandler
sub open_define { 
   my $self = shift;

   # only proceed if not open
   if (!$self->isOpen()) {
      my $get = $self->{getparams};
      my $put = $self->{putparams};
      my $del = $self->{delparams};
      my $extra = $self->{extra};

      # get auth mode - it defines how the command looks and what needs to be done...
      my $mode=$self->{authmode};

      $get->addVariable("remote","/dev/null","[^\\000]*",1,0);
      $get->addVariable("local","/dev/null","[^\\000]*",1,0);

      $put->addVariable("remote","/dev/null","[^\\000]*",1,0);
      $put->addVariable("local","/dev/null","[^\\000]*",1,0);

      $del->addVariable("remote","/dev/null","[^\\000]*",1,0);
      $del->addVariable("local","/dev/null","[^\\000]*",1,0);

      return 1;
   } else {
      # failure - already open
      $self->{error}="Store already open. Unable to define it.";
      return 0;
   }
}

# creates put and get instances and
# sets parameters of StoreProcesses
# to be overriden by inheriting child
# return 1 if successful, 0 if not
# not to be called directly.
sub open_create {
   my $self = shift;

   # only proceed if not open
   if (!$self->isOpen()) {
      # define get and put processes 
      $self->{get}=StoreProcess->new(command=>$self->{getparams});
      $self->{put}=StoreProcess->new(command=>$self->{putparams});
      $self->{del}=StoreProcess->new(command=>$self->{delparams});

      return 1;
   } else {
      # failure - already open
      $self->{error}="Store already open. Unable to create processes.";

      return 0;
   }
}

# closes the store, cleans up - to be overridden.
sub close {
   my $self=shift;

   if ($self->isOpen()) { 
      $self->{open}=0;
      return 1;
   } else {
      $self->{error}="No store is yet open - unable to close store.";
      return 0;
   }
}

sub paramValueGet {
   my $self = shift;
   my $name = shift;

   my $get=$self->{getparams};

   # get/set
   my $object=$get->get($name);
   return $object->value(@_) if defined $object || undef;
}

sub paramValuePut {
   my $self = shift;
   my $name = shift;

   my $put=$self->{putparams};

   # get/set
   my $object=$put->get($name);
   return $object->value(@_) if defined $object || undef;
}

sub paramValueDel {
   my $self = shift;
   my $name = shift;

   my $del=$self->{delparams};

   # get/set
   my $object=$del->get($name);
   return $object->value(@_) if defined $object || undef;
}

# set the given parameter in put, get and del
# storeprocesses
sub setParam {
   my $self = shift;
   my $name = shift || "DUMMY";
   my $value = shift;

   # one of three must succeed for us to be happy
   my $get=$self->paramValueGet($name,$value);
   my $put=$self->paramValuePut($name,$value);
   my $del=$self->paramValueDel($name,$value);

   return ($get || $put || $del ? 1 : 0);
}

# get a hash of required
# parameters for the store and their current value. 
# Must be called after open
sub paramsRequired {
   my $self = shift;

   # go through parameters
   my %req;
   my $get=$self->{getparams};
   my $put=$self->{putparams};
   my $del=$self->{delparams};
   my $extra=$self->{extra};
   foreach (@{[$get,$put,$del,$extra]}) {
      my $par=$_;

      foreach (@{$par->enumRequiredObjects()}) {
         my $name = $_;

         # get parameter data
         my $data=$par->get($name)->toHash();

         foreach (keys %{$data}) {
            my $key=$_;

            $req{$name}{$key}=$data->{$key};
         }
      }
   }

   # return required params for store
   return %req;
}

# puts data into storage
sub put {
   my $self = shift;

   if ($self->isOpen()) {
      # ensure that nothing else is running right now.
      if (!$self->isRunning()) {
         $self->{mode}=$STORE_MODE_PUT;
         $self->{success}=0;
         my $put=$self->{put};
         $put->execute();
         return 1;
      } else {
         $self->{error}="A store operation is in progress. Unable to invoke a PUT.";
         return 0;
      }
   } else {
      $self->{error}="Store is not open yet.";
      return 0;
   }
}

# gets data from storage
sub get {
   my $self = shift;

   if ($self->isOpen()) {
      # ensure that nothing else is running right now.
      if (!$self->isRunning()) {
         $self->{mode}=$STORE_MODE_GET;
         $self->{success}=0;
         my $get=$self->{get};
         $get->execute();
         return 1;
      } else {
         $self->{error}="A store operation is in progress. Unable to invoke a GET.";
         return 0;
      }
   } else {
      $self->{error}="Store is not open yet.";
      return 0;
   }
}

# delete data from remote storage
sub del {
   my $self = shift;

   if ($self->isOpen()) {
      # ensure that nothing else is running right now.
      if (!$self->isRunning()) {
         $self->{mode}=$STORE_MODE_DEL;
         $self->{success}=0;
         my $del=$self->{del};
         $del->execute();
         return 1;
      } else {
         $self->{error}="A store operation is in progress. Unable to invoke a DEL.";
         return 0;
      }
   } else {
      $self->{error}="Store is not open yet.";
      return 0;
   }
}

# Gives the size on the remote location.
# this method is to be overridden.
sub remoteSize {
   my $self = shift;

   $self->{mode}=$STORE_MODE_REMOTE_SIZE;
   # save log
   # $self->{sizeremotelog}=$log;

   return 0;
}

# gives the size on the local location. Local location is always a filesystem,
# so this method can be used by other sub-classes. It can also be overridden.
# is should return size upon success (in bytes) or undef upon error.
sub localSize {
   my $self = shift;

   # must be opened to proceed
   if ($self->isOpen()) {
      # get local location
      $self->{mode}=$STORE_MODE_LOCAL_SIZE;
      my $get=$self->{getparams};
      my $extra=$self->{extra};
      my $local=$get->get("local")->value() || $extra->get("local")->value(); # sometimes the local parameter is in extra

      # define command to check size
      my $cmd=Parameter::Group->new();
      # we use rsync to calculate the local size - reliable and tested
      $cmd->addVariable("cmd","/usr/bin/rsync");
      $cmd->addVariable("option","-vrtn");
      $cmd->addVariable("local",$local);
      # make a random name for the destination folder
      my $randstr=sectools::randstr(32);
      $cmd->addVariable("destination","/tmp/$randstr");

      # run calculation - set a sensible timeout, less than global timeout - a little bit
      my $timeout=($self->{pars}{timeout} < 300 ? $self->{pars}{timeout}-30 : 300);
      my $calc=StoreProcess::Shell->new(pars=>$cmd, timeout=>$timeout, wait=>$self->{pars}{wait});
      $calc->execute();
      # wait for result or timeout
      while (($calc->isrunning()) || (!$calc->isemptied())) {
      }
      # get log
      my $log=$calc->getlog();
      $log->resetNext();
      # save log
      $self->{sizelocallog}=$log;
      # ensure we were successful
      if ($calc->success()) {
         # get just the size from the message
         my $size = $log->getLastAsString(1,"%m ");
         chomp ($size);
         # remove commas and dots - we do not want them in the size
         $size =~ s/[\,\.]//g;
         # get just the size
         $size =~ s/\D+(\d+)\D+.*/$1/;
         return $size;
      } else {
         # unable to acquire size, get reason by perusing log
         # get last few messages
         my $msg=$log->getLastAsString(11);
         $msg=(defined $msg ? $msg : "Unknown reason");
         $self->{error}="Unable to get size of local data: $msg";
         return undef;
      }
   } else {
      $self->{error}="Store not opened yet. Unable to get local size.";
      return undef;
   }
}

# list remote folder - this method is to be overridden by inheriting class
sub listRemote {
   my $self=shift;
   my $path=shift || "";

   if ($self->isOpen()) {
      my %result;

      $self->{mode}=$STORE_MODE_REMOTE_LIST;
      # save log
      # $self->{listremotelog}=$log;

      return \%result;
   } else {
      $self->{error}="Store not opened yet. Unable to list remote folder.";
      return undef;
   }
}

# list local folder - this implements a file listing on a local filesystem
# in most cases it does not need to be overridden. Returns a HASH structure-reference with files and folders.
sub listLocal {
   my $self=shift;
   my $path=shift || "";

   if ($self->isOpen()) {
      $self->{mode}=$STORE_MODE_LOCAL_LIST;
      # remove dotdot - no moving around and up out of "root".
      $path=~s/\.\.//g;

      # define command to check size
      my $cmd=Parameter::Group->new();
      $cmd->addVariable("cmd","/bin/ls");
      $cmd->addVariable("option1","-lan");
      $cmd->addVariable("option2","--time-style=+%Y%m%d %H%M%S");
      $cmd->addVariable("local",$path);

      # run calculation - set a sensible timeout, less than global timeout - a little bit
      my $timeout=($self->{pars}{timeout} < 300 ? $self->{pars}{timeout}-30 : 300);
      my $calc=StoreProcess::Shell->new(pars=>$cmd, timeout=>$timeout, wait=>$self->{pars}{wait});
      $calc->execute();
      # wait for result or timeout
      while (($calc->isrunning()) || (!$calc->isemptied())) {
      }
      # get log
      my $log=$calc->getlog();
      $log->resetNext();
      # save log
      $self->{listlocallog}=$log;
      # ensure we were successful
      if ($calc->success()) {
         my %result;
         my ($mess,$time);
         while (my $l=$log->getNext()) {
            ($mess,$time)=@{$l};

            # retrieve information in question
            if ($mess =~ /^([-dl]){1}[^\s\t]+[\s\t]+\d+[\s\t]+\d+[\s\t]+\d+[\s\t]+(\d+)[\s\t]+(\d{8})[\s\t]+(\d{6})[\s\t]{1}(.+)[\r\n]*$/) {
               # save to structure
               my $type=$1;
               $type=(uc($type) eq "D" ? "D" : (uc($type) eq "L" ? "L" : "F")); # either directory or file type 
               my $size=$2;
               my $dt=$3.$4;
               $dt=$Schema::CLEAN{datetimestr}->($dt);
               my $name=$5;
               if ($name =~ /^[\.]{1,2}$/) { next; } # we are not interested in . and ..
               # if a link, check if we also have the target
               my $target="";
               if ($type eq "L") { $name=~s/^(.*)[\s\t]+\-\>[\s\t]+(.*)[\r\n]*$/$1/; $target=$2; }
               my @l;
               push @l,substr($dt,12,2); # second
               push @l,substr($dt,10,2); # minute
               push @l,substr($dt,8,2); # hour
               push @l,substr($dt,6,2); # day
               push @l,int(substr($dt,4,2))-1; # month
               push @l,substr($dt,0,4); # year
               my $datetime=sprintf ("%d",timelocal(@l));
               $result{$type}{$name}{type}=$type;
               $result{$type}{$name}{size}=$size;
               $result{$type}{$name}{datetime}=$datetime;
               $result{$type}{$name}{name}=$name;
               # add target value if this is a link
               if ($type eq "L") { $result{$type}{$name}{target}=$target; }
            }
         }     
         # return HASH-structure
         return \%result;
      } else {
         # unable to acquire size
         $self->{error}="Unable to list local folder: ".$calc->error();
         return undef;
      }       
   } else {
      $self->{error}="Store not opened yet. Unable to list local folder.";
      return undef;
   }
}

# Verifies the operation on the Store. this method is to be overridden, 
# so what that means is up to the inheriting child. But it needs to 
# quality ensure the put or get operation that has been performed. 
# Return 1 for success, 0 for failure. This dummy function always return 1.
# The same should be true for all Store-classes that are either unable to
# verify or were it is not implemented.
sub verify {
   my $self = shift;

   return 1;
}

sub getLog {
   my $self = shift;

   if ($self->mode() == $STORE_MODE_GET) {
      my $get=$self->{get};
      my $log=$get->getlog();
      return $log;
   } elsif ($self->mode() == $STORE_MODE_PUT) {
      my $put=$self->{put};
      my $log=$put->getlog();
      return $log;
   } elsif ($self->mode() == $STORE_MODE_DEL) {
      my $del=$self->{del};
      my $log=$del->getlog();
      return $log;
   } elsif ($self->mode() == $STORE_MODE_LOCAL_LIST) {
      return $self->{listlocallog};
   } elsif ($self->mode() == $STORE_MODE_REMOTE_LIST) {
      return $self->{listremotelog};
   } elsif ($self->mode() == $STORE_MODE_LOCAL_SIZE) {
      return $self->{sizelocallog};
   } elsif ($self->mode() == $STORE_MODE_REMOTE_SIZE) {
      return $self->{sizeremotelog};
   } else {
      $self->{error}="No store operation has been run yet.";
      return 0;
   }
}

# get the getparams instance
sub getParams {
   my $self=shift;

   return $self->{getparams};
}

sub putParams {
   my $self=shift;

   return $self->{putparams};
}

sub delParams {
   my $self=shift;

   return $self->{delparams};
}

# get exitcode
sub exitcode {
   my $self = shift;

   if ($self->mode() == $STORE_MODE_GET) {
      my $get=$self->{get};
      return $get->exitcode();
   } elsif ($self->mode() == $STORE_MODE_PUT) {
      my $put=$self->{put};
      return $put->exitcode();
   } elsif ($self->mode() == $STORE_MODE_DEL) {
      my $del=$self->{del};
      return $del->exitcode();
   } else {
      $self->{error}="No store operation has been run yet.";
      return undef;
   }
}

# set/get metadata
sub metadata {
   my $self = shift;

   if (@_) {
      # set value
      my $md = shift;
      # ensure that metadata is a HASH reference, or else fail
      if ((!defined $md) || (ref($md) ne "HASH")) { $self->{error}="Not a HASH-reference. Unable to set metadata."; return undef; }

      # set the new metadata
      $self->{pars}{metadata}=$md;
      return $md;
   } else {
      # return value
      return $self->{pars}{metadata};
   }
}

# set/get timeout
sub timeout {
   my $self = shift;

   if (@_) {
      # set value
      my $timeout = shift || 0;

      my $get=$self->{get};
      my $put=$self->{put};
      my $del=$self->{del};
   
      $get->timeout($timeout);
      $put->timeout($timeout);
      $del->timeout($timeout);

      $self->{pars}{timeout}=$timeout;
      return 1;
   } else {
      # read - return timeout value
      return $self->{pars}{timeout};
   }
}

# set/get wait
sub wait {
   my $self = shift;

   if (@_) {
      # set value
      my $wait = shift || 0;

      my $get=$self->{get};
      my $put=$self->{put};
      my $del=$self->{del};
   
      $get->wait($wait);
      $put->wait($wait);
      $del->wait($wait);

      $self->{pars}{wait}=$wait;
      return 1;
   } else {
      # return value
      return $self->{pars}{wait};
   }
}

# check if get is running
sub isRunning {
   my $self = shift;

   if ($self->mode() == $STORE_MODE_GET) {
      my $get=$self->{get};
      return $get->isrunning();
   } elsif ($self->mode() == $STORE_MODE_PUT) {
      my $put=$self->{put};
      return $put->isrunning();
   } elsif ($self->mode() == $STORE_MODE_DEL) {
      my $del=$self->{del};
      return $del->isrunning();
   } else {
      $self->{error}="No store operation has been run yet.";
      return 0;
   }
}

# check to see if store has been
# opened
sub isOpen {
   my $self = shift;

   return $self->{open};

}

# get put/get alive timestamp
sub alive {
   my $self = shift;

   if ($self->mode() == $STORE_MODE_GET) {
      my $get=$self->{get};
      return $get->alive();
   } elsif ($self->mode() == $STORE_MODE_PUT) {
      my $put=$self->{put};
      return $put->alive();
   } elsif ($self->mode() == $STORE_MODE_DEL) {
      my $del=$self->{del};
      return $del->alive();
   } else {
      $self->{error}="No store operation has been run yet.";
      return undef;
   }
}

# return mode that store is in
sub mode {
   my $self = shift;

   return $self->{mode} || $STORE_MODE_NOP;
}

# get success of last GET or PUT operation
sub success {
   my $self = shift;

   if ($self->isOpen()) {  
      # check what has been running last - GET, PUT or DEL
      my $method;
      if ($self->mode() == $STORE_MODE_GET) {
         $method=$self->{get};      
      } elsif ($self->mode() == $STORE_MODE_PUT) {
         $method=$self->{put};
      } elsif ($self->mode() == $STORE_MODE_DEL) {
         $method=$self->{del};
      } else {
         $self->{error}="No store operation has been run yet.";
         return 0;
      }

      # isrunning triggers reading of the latest progress
      # including a possible setting of the success flag
      if ((!$method->isrunning()) && ($method->success())) {
         return 1;
      } else {
         # not successful
         return 0;
      }
   } else {
      $self->{error}="No store is open yet.";
      return 0;
   }
}

sub ceaseOperations {
   my $self = shift;

   if ($self->isOpen()) {
      # check what has been running last - GET, PUT or DEL
      my $method;
      if ($self->mode() == $STORE_MODE_GET) {
         $method=$self->{get};
      } elsif ($self->mode() == $STORE_MODE_PUT) {
         $method=$self->{put};
      } elsif ($self->mode() == $STORE_MODE_DEL) {
         $method=$self->{del};
      } else {
         $self->{error}="No store operation has been run yet.";
         return 0;
      }

      if ($method->isrunning()) {
         return $method->cease();
      } else {
         $self->{error}="The store is not running. Unable to cease operations.";
         return 0;
      }
   } else {
      $self->{error}="No store is open yet.";
      return 0;
   }
}

# get last error message
sub error {
   my $self = shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Store> - Placeholder class that represents a way of storing data and getting and putting that data, verifying it and so on.

=cut

=head1 SYNOPSIS

   use Store;

   # instantiate the store
   my $s=Store->new(authmode=>Store::AUTH_PW);

   # get storename
   $s->name();

   # set storename
   $s->name("WHATEVER");

   # open store to start using it
   $s->open();

   # get param value for a get parameter
   my $val=$s->paramValueGet("PARAMNAME");

   # set param value for a get parameter
   $s->paramValueGet("PARAMNAME","VALUE");

   # get param value for a put parameter
   my $val=$s->paramValuePut("PARAMNAME");

   # get param value for a del parameter
   my $val=$s->paramValueDel("PARAMNAME");
   
   # set param value for a put parameter
   $s->paramValuePut("PARAMNAME","VALUE");
   
   # set a param in put-, get- and del parameters
   $s->setParam ("PARAMNAME","VALUE);

   # get required put-, get and extra-parameters and
   # their current value
   my %r=$s->paramsRequired();

   # put data into store
   $s->put();

   # get data from store
   $s->get();

   # delete data from remote store
   $s->del();

   # get size of remote location
   my $size=$s->remoteSize();

   # get size of local location
   my $size=$s->localSize();

   # list local folder/data area
   my $list=$s->listLocal("/whatever/path");

   # list remote folder/data area
   my $list=$s->listRemote("/whatever/path");

   # verify the operation on the Store
   $s->verify();

   # get log of either get- or put-operation
   my $log=$s->getLog();

   # get put or get exitcode
   my $ecode=$s->exitcode();

   # get timout value
   my $timeout=$s->timeout();

   # set timeout value
   $s->timeout(10000);

   # get wait value
   my $wait=$s->wait();

   # set wait value
   $s->wait(6000);

   # check if put, get or del is running
   my $running=$s->isRunning();

   # check if store is open
   my $open=$s->isOpen();

   # get success of last get-, put- or del operation
   my $succ=$s->success();

   # cease get or put operation on a store 
   $s->ceaseOperations();

   # get last error message
   my $error=$s->error();

   # close the store - clean up. Should be called, even upon error when stopping to use the store.
   $s->close();

=cut

=head1 DESCRIPTION

Placeholder class to represent a way of storing data and how to get-, put- and delete data on it, verifying the data, the size, logging and log output of get-, put- and delete operations.

This placeholder class is to be inherited by classes that represent actual ways of storing data.

=cut

=head1 CONSTRUCTOR

=head2 new()

Constructor. Instantiate a Store-class.

Input accepts the following parameters:

=over

=item

B<authmode> Sets the authentication mode of the Store. It can either be AUTH_PW (password is specifed as input 
parameters password), AUTH_PWFILE (password is read from file set in parameter passwordfile), AUTH_KEY (uses privatekey 
specified as input parameter privatekey) or AUTH_KEYFILE (uses privatekey read from file name and location 
specified as input parameter privatekeyfile). All these parameters (password, passwordfile, privatekey and privatekeyfile) 
are parameters to the open()-method and are reserved for this (not to be used for other purposes). They might not have meaning 
for all classes, such as eg. FTP, which do not use a privatekey-scheme for authentication.

=cut

=item

B<metadata> Sets the metadata of the dataset that is being put/get/deleted. HASH-reference. Optional. If not set or set to 
non-HASH reference, will default to an empty HASH. It is up to the inheriting Store-class to use this metadata or not.

=cut

=item

B<storename> Sets the unique store name. If none is specified it defaults to a 64 character random string.

=cut

=item

B<timeout> Sets the timeout of a get- or put operation in seconds. Defaults to 0 which means no timeout. This setting sets the time the get- or 
put-operation waits even if there is no activity generated by the underlying operation.

=cut

=item

B<wait> Sets the wait time on a get- or put operation in seconds. Defaults to 0 which means to wait forever. This settings sets the time the get- or 
put operation waits on a completetion of the underlying operation independant upon if it generates activity or not. It is only recommended to use 
this option if you have special needs for the operation to end if not completed within a certain time. To end operation if nothing happens, please use 
the timeout setting instead.

=cut

=back

The methods returns an instantiated class.

=cut

=head1 METHODS

=head2 probe()

Probe remote location of its capabiliites.

Input parameteres: none. All is taken from already setup paramteres.

Returns 1 if successful in probing. 0 if it failed. Please check the error()-method for more information upon 
failure.

If successful the probe()-method will update the parameter set of the class based upon what it learned.

We recommend all users call this method prior to other methods.

=head2 name()

Sets or gets the name of the Store.

If not input is set, it returns the name of the store. If one add a SCALAR input, that input is set as the name of the store.

Returns 1 when setting the store name or it returns the name the store already has.

=cut

=head2 open()

Opens a store to execute operations on it.

Needed input depends on the Store-class in question and this method is to be overridden by the inheriting class.

Please call the paramsRequired()-method to find which parameters are needed for a specific Store-class.

The method checks that all required parameters are present and that they meet their regex pattern as defined in the Parameter-class (see Parameter-class 
for more information).

When all criterias have been met for the required parameters, it will attempt to set the value passed on to open as 
parameters into the Store-class in question, both required and non-required. It will also check the regex-compliance of 
non-required parameters. In addition, if the parameter in question has been tagget as a sandbox-parameter, this method 
will strip away all "..", all slashes and all relevant shell metacharacters to force the parameter to relate only to a 
filename. The filename will be prepended with the location path of the sandbox-folder from the sandbox-option to the class. This 
makes it possible to refer to local files, while retaining security for files outside of the sandboxed folder.

The method returns 1 upon successful opening of the store or 0 upon failure. Please check the error()-method upon failure.

=cut

=head2 open_define()

Defines a store's get-, put-, del- and extra-parameters that are needed for the store-class in question. The extra-parameters are 
not part of any command that is run and their defined order does not matter. They are only used to modify the behaviour of 
the get- og put-parameters. But, all parameters names between the get-,put-, del-command and the extra-parameters are unique. 
That means that no parameters should be used in two places (get-,put-,del- and/or extra) without having the same meaning.

It is important that all non-private parameters (see the flags in the Parameter-class) are properly escaped or 
checked for security issues. If a parameter is marked as "private" the Store-class will use quotemeta to escape 
meta characters. This will in most cases suffice, but there are some command line utilities that are not 
always happy to get parameters quotes (such as remote- and local paramters). Examples of utilities that are 
not always happy in some scenarios are sftp and ftp. It is generally considered safe to not quote the local 
parameter since that in the AURORA-system is supplied by the system and not by the user. However, all non-private 
parameters should be escaped to be sure there are no issues if possible.

Only non-private parameters can be overwritten by supplying parameters to the open()-method. Others cannot be 
overwritten by the user of Store-classes. 

This method is to be overridden by the inheriting class and are not to be called by user himself.

Several parameters are reserved and has special meaning to the Store-class(es):

=over

=item

B<local> Defines the local data location (for get- and put-operations).

=cut

=item

B<remote> Defines the remote data location (for get- and put-operations).

=cut

=item

B<privatekey> Defines the privatekey to be used for classes that uses key-authentication (authmode must be set to AUTH_KEY).

=cut

=item

B<privatekeyfile> Defines the location of the privatekey file and is to be used for classes that uses key-authentication 
(authmode must be set to AUTH_KEYFILE).

=cut

=item

B<pw> Defines the password to be used for classes that uses password-authentication (authmode must be set to AUTH_PW).

=cut

=item

B<pwfile> Defines the location and name of the password file to be used for classes that uses password-authentication 
(authmode must be set to AUTH_PWFILE).

=cut

=back

Returns 1 if successful, 0 if not.

=cut

=head2 open_create()

Creates the put-, get- and del-instances of the StoreProcess-class or subclasses. Placeholder to be overridden by inheriting class.

Returns 1 if successful, 0 if not.

This method is not to be called directly by user.

=cut

=head2 close()

Closes the store and cleans up. 

This method closes the store and sets the result of isOpen()-method to 0. It cleans up whatever needs to be cleaned up. This 
method is to be overridden by the inheriting class if one needs to do some kind of cleanup.

The method is to be called by the user of the class when he is finished using the instance in question to ensure cleanup of 
temporary resources. It should even be called in event of a failure to perform methods when the user is fininshed with the instance.

Returns 1 upon success, 0 upon failure. Pleace check the error()-method for more information upon failure.

=cut

=head2 paramValueGet()

Get or set a GET parameter value.

Input is the name of the parameters to get. Additionally one can add a value as the next parameter if one wishes to set the value of
the parameter name given as the first parameter.

Returns the value of the parameter upon get, or upon a set returns the result of setting that parameter on the Parameter-class (see Parameter-class 
for more information).

=cut

=head2 paramValuePut()

Get or set a PUT parameter value.

Input is the name of the parameters to get. Additionally one can add a value as the next parameter if one wishes to set the value of
the parameter name given as the first parameter.

Returns the value of the parameter upon get, or upon a set returns the result of setting that parameter on the Parameter-class (see Parameter-class 
for more information).

=cut

=head2 paramValueDel()

Get or set a DEL parameter value.

Input is the name of the parameters to get. Additionally one can add a value as the next parameter if one wishes to set the value of
the parameter name given as the first parameter.

Returns the value of the parameter upon get, or upon a set returns the result of setting that parameter on the Parameter-class (see Parameter-class 
for more information).

=cut

=head2 setParam()

Sets a given parameter in all of the GET-, PUT- and DEL-parameters of the Store-class.

Input is the name and the value of the parameter to set.

Returns 1 upon successful set in one or more of the GET-, PUT- or DEL-parameters or 0 upon failure.

=cut

=head2 paramsRequired()

Returns the required parameters of the Store-class.

This method get the required parameters of GET-, PUT- and DEL-methods and the extra-parameters of the Store-class.

No input is accepted and it returns a HASH upon success or 0 upon failure.
Check the error()-method for more information upon failure.

The return HASH of the required parameters has the following format:

   (
      paramA => { name => SCALAR (this is a repeat of paramA),
                  value => SCALAR,
                  check => REGEX
                  required => BOOLEAN,
                  escape => BOOLEAN,
                }
      paramB => { name => SCALAR (this is a repeat of paramB),
                  etc...       

   )

For more information on the data returned in the HASH see the Parameter-class documentation.

=cut

=head2 put()

Starts the method of putting data into store.

The store must first have been opened for this to start successfully. The store cannot already be in a get-, put- or del-mode.

No input is accepted.

It returns 1 upon successful start of the put-operation, 0 upon failure. Please check the error()-method for more
information upon failure.

=cut

=head2 get()

Starts the method of getting data from the store.

The store must first have been opened for this to start successfully. The store cannot already be in a get-, put- or del-mode.

It returns 1 upon successful start of the get-operation, 0 upon failure. Please check the error()-method for more
information upon failure.

=cut

=head2 del()

Starts the method of deleting data from the remote store.

This method is meant to be overridden by inheriting class.

The store must first have been opened for this to start successfully. The store cannot already be in a get-, put- or del-mode.

It returns 1 upon successful start of the del-operation, 0 upon failure. Please check the error()-method for more
information upon failure.

It only deletes remotely.

=cut

=head2 remoteSize()

Get the size of the data in the remote location.

This method is to be overridden by the inheriting class. 

This method is not to be called by user, but by internal methods.

Returns the size in bytes or undef upon error. Please check the error()-method for more information in the event
of an error.

=cut

=head2 localSize()

Get the size of the data in the local location.

This method is always calculating on a local filesystem. It is therefore written a general localSize-method that uses
the rsync utility. However, this method can be overridden by the inheriting class. 

It is recommended that the localSize()-method be careful with how to calculate its own local size, since the local location 
might have data from several locations/stores. This is not required, however, and the default localSize()-method does not 
implement this.

Returns the local size in bytes or undef upon error. Please check the error()-method for more information in the event 
of an error.

=cut

=head2 listRemote()

Lists the folder/store contents on the remote end.

Input is the path to list. This is optional and default to a blank string.

The function is not recursive and only lists the Store-structure in the path specified. 
This method is to be overridden by the inheriting class.

Returns a HASH-reference to a structure which must be of the following format upon success:

  (
    TYPEa => { NAMEa => { NAME => SCALAR, # name of item
                          TYPE => SCALAR, # either F (File) or D (Folder)
                          SIZE => SCALAR,  # in Bytes
                          DATETIME => SCALAR, # in unixtime
                       },
               NAMEb => { NAME => SCALAR,
                          TYPE => SCALAR,
                          SIZE => SCALAR,
                          DATETIME => SCALAR,
                         },
             },
   TYPEb => { etc...
            },
  )

Type in the initial key also means either F (file), D (folder) or L (link/symbolic). Some information is also repeated in the item itself for ease of 
use. 

Upon failure returns undef. Please check the error()-method for more information upon an error.

=cut

=head2 listLocal()

Lists the folder/store contents locally (local parameter).

Input is the path to list. The local parameter is added to this path-string. This is optional and default to a blank string.

The function is not recursive and only lists the Store-structure in the path specified. 
This method is already implemented here ofr local filesystems stores and does not need to be overridden.

Returns a HASH-reference to a structure which must be of the following format upon success:

  (
    TYPEa => { NAMEa => { NAME => SCALAR, # name of item
                          TYPE => SCALAR, # either F (File) or D (Folder)
                          SIZE => SCALAR,  # in Bytes
                          DATETIME => SCALAR, # in unixtime
                       },
               NAMEb => { NAME => SCALAR,
                          TYPE => SCALAR,
                          SIZE => SCALAR,
                          DATETIME => SCALAR,
                         },
             },
    TYPEb => { etc...
             },
  )

Type in the initial key also means either F (file), D (folder) or L (link/symbolic). Some information is also repeated in the item itself for ease of 
use.

Upon failure returns undef. Please check the error()-method for more information upon an error.

=cut

=head2 verify()

Verifies the operation on the store.

This method is to be overridden by the inheriting class, but it needs to verify that the put- or get- operation has been 
successfully performed and that the data is intact. If not verify method can be implemented it is to return 1 (success).

Returns 1 upon success, 0 upon failure. Check the error()-method for more information upon failure.

=cut

=head2 getLog()

Gets the log of either the get-, put- or del-operation depending upon the mode of the Store.

It returns the log-instance of a SmartLog-class that belongs to either the get-, put- or del-StoreProcess operation.

=cut

=head2 getParams()

Return the parameter group instance of the get-command for the store.

Returns a reference to a Parameter-class og subclass instance.

=cut

=head2 putParams()

Return the parameter group instance of the put-command for the store.

Returns a reference to a Parameter-class og subclass instance.

=cut

=head2 delParams()

Return the parameter group instance of the delete-command for the store.

Returns a reference to a Parameter-class og subclass instance.

=cut

=head2 exitcode()

Returns the exitcode of either the GET-, PUT- or DEL-StoreProcess instance (depends on store-mode). The exitcode is harvested from the executed command in the 
StoreProcess-class when it returns. See the StoreProcess-class for more information.

Returns the exitcode upon success, undef upon failure. Please check the error()-method for more information upon failure.

=cut

=head2 timeout()

Gets or sets the timeout of the GET-, PUT- or DEL-StoreProcess instances (it is the same for all in every case).

Input is the timeout value upon a set. No input accepted upon get.

It returns 1 upon successful set, the timeout value upon successful get.

See the StoreProcess-class for more information on the timeout-option.

=cut

=head2 metadata()

Set or get the Store's metadata.

One input accepted: metadata. HASH-reference. Optional (get) and Required (set). If set to undef or not a 
HASH-reference when set, it will fail with undef in return.

Will return the metadata if no input is specified, it will set the metadata if the metadata-parameter is set 
and it is a HASH-reference (and then return the set HASH-reference). It will return undef upon failure. 
Check the error()-method for more information upon a failure.

=cut

=head2 wait()

Gets or sets the wait time of the GET-, PUT- or DEL-StoreProcess instances (it is the same for all in every case).

Input is the wait time value upon a set. No input accepted on get.

It returns 1 upon successful set, the wait value upon successful get.

See the StoreProcess-class for more information on the wait-option.

=cut

=head2 isRunning()

Returns if the Store-instance is running either a GET-, PUT- or DEL-operation (depends on the mode of the store).

No input accepted.

Returns 1 if a store operation is running, 0 if no operation running or that no operation has started yet.

=cut

=head2 isOpen()

Returns if the store has been opened or not?

Returns 1 if it has been opened, 0 if not.

=cut

=head2 mode()

Returns the current mode that the store is in.

The possible modes are:

  NOP = 0
  GET = 1
  PUT = 2
  DEL = 3

These modes can also be referenced by the variables STORE_MODE_NOP, STORE_MODE_GET, STORE_MODE_PUT and STORE_MODE_DEL.

=cut

=head2 alive()

Returns the latest timestamp from any activity of the store-process (either get-, put- or del dependent upon mode).

No input is accepted.

Upon success returns the time in unixtime without locale. Upon failure returns undef. Please check the
error()-method for more information upon failure. Typical reason for failure is that neither get-, put- or del-
process has been started or are running anymore.

=cut

=head2 success()

Returns the success of the last GET-, PUT- or DEL-operation.

No input is accepted. 

Returns 1 if the last operation was successful, 0 if not or if the store was not opened or no operation run yet.

Upon a 0, one can check the error()-method for more information (if any).

=cut

=head2 ceaseOperations()

Stops either a GET-, PUT- or DEL-operation on a store (depends on mode).

No input is accepted.

Returns 1 upon successfully ceasing operation of a GET-, PUT- or DEL-operation, 0 if not.

It will also return 0 if store is not opened yet or no GET-, PUT- or DEL-operation is running. In such cases one can check 
the error()-method for more information.

=cut

=head2 error()

Returns the last error of the store (if any).

No input is accepted.

Return value is a SCALAR.

=cut
