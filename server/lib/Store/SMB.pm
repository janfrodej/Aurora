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
# Store::SMB: class of a SMB Store (CIFS)
#
# Uses: smbclient-command line utility
#
package Store::SMB;
use parent 'Store';

use strict;
use StoreProcess::Shell;
use Time::Local;
use File::Basename;

# defines the store, parameters needed for
# the store and returns 1
sub open_define {
   my $self = shift;

   # only run if store not opened yet
   if (!$self->isOpen()) {
      # get params instances
      my $get = $self->{getparams};
      my $put = $self->{putparams};
      my $del = $self->{delparams};
      my $extra = $self->{extra};

      # get auth mode, although we only accept pw and 
      # if needed read from file into string
      my $mode=$self->{authmode};

      # define parameters for samba get
      $get->addVariable("cmd","/usr/bin/smbclient");
      $get->addVariable("usernameswitch","-U","\\-U");
      $get->addGroup("usergr",undef,undef,1);
      $get->get("usergr")->addVariable("domain","WORKGROUP","[a-zA-Z0-9\\.\\-]+",0,0);
      $get->get("usergr")->addVariable("slash","/","\\/");
      $get->get("usergr")->addVariable("username","DUMMY","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
      $get->get("usergr")->addVariable("percent","\%");
      $get->get("usergr")->addVariable("password","DUMMY","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",0,0);
      $get->addVariable("cswitch","-c");
      $get->addGroup("comgr");  
      $get->get("comgr")->addVariable("command1","recurse ; prompt ; cd");
      $get->get("comgr")->addVariable("altremote","/dev","[^\\000]*",undef,undef,undef,1); # cd to remote - last slash, ensure we are in the deepest folder possible
      $get->get("comgr")->addVariable("command2","; lcd");
      $get->get("comgr")->addVariable("local","/dev/null","[^\\000]+",1,0,undef,1); 
      $get->get("comgr")->addVariable("command3","; mget");
      $get->get("comgr")->addVariable("name","DUMMY",".*",undef,undef,undef,1); # filename or foldername
      $get->addGroup("hostgr",undef,undef,1);
      $get->get("hostgr")->addVariable("doubleslash","//");
      $get->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
      $get->get("hostgr")->addVariable("slash","/");
      $get->get("hostgr")->addVariable("share","share","[a-zA-Z0-9\\.\\-]{3,63}",1,0,1);

      # define parameters for samba put
      $put->addVariable("cmd","/usr/bin/smbclient");
      $put->addVariable("usernameswitch","-U","\\-U");
      $put->addGroup("usergr",undef,undef,1);
      $put->get("usergr")->addVariable("domain","WORKGROUP","[a-zA-Z0-9\\.\\-]+",0,0);
      $put->get("usergr")->addVariable("slash","/","\\/");
      $put->get("usergr")->addVariable("username","DUMMY","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
      $put->get("usergr")->addVariable("percent","\%");
      $put->get("usergr")->addVariable("password","DUMMY","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",0,0);
      $put->addVariable("comswitch","-c");
      $put->addGroup("comgr");
      $put->get("comgr")->addVariable("command1","recurse ; prompt ; cd");
      $put->get("comgr")->addVariable("altremote","/dev","[^\\000]*",undef,undef,undef,1); 
      $put->get("comgr")->addVariable("command2","; lcd");
      $put->get("comgr")->addVariable("local","/dev/null","[^\\000]+",1,0); 
      $put->get("comgr")->addVariable("command3","; mput");
      $put->get("comgr")->addVariable("name","DUMMY",".*",undef,undef,undef,1); # filename or foldername
      $put->get("comgr")->addVariable("command4","; lcd \"/tmp\" ; put "); # smbclient is notoriously unreliable to give proper exitcodes, so
                                                                           # to check for potential problems with the area we put to we add
      $put->get("comgr")->addVariable("rndfile","/dev/null"); # a put and rm command of a random file, which actually gives a proper exitcode
      $put->get("comgr")->addVariable("command5"," ; rm");
      $put->get("comgr")->addVariable("rndfile","/dev/null");
      $put->addGroup("hostgr",undef,undef,1);
      $put->get("hostgr")->addVariable("doubleslash","//");
      $put->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
      $put->get("hostgr")->addVariable("slash","/");
      $put->get("hostgr")->addVariable("share","share","[a-zA-Z0-9\\:\\.\\-]{3,63}",1,0);

      # define parameters for samba del
      $del->addVariable("cmd","/usr/bin/smbclient");
      $del->addVariable("usernameswitch","-U","\\-U");
      $del->addGroup("usergr",undef,undef,1);
      $del->get("usergr")->addVariable("domain","WORKGROUP","[a-zA-Z0-9\\.\\-]+",0,0);
      $del->get("usergr")->addVariable("slash","/");
      $del->get("usergr")->addVariable("username","DUMMY","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
      $del->get("usergr")->addVariable("percent","\%");
      $del->get("usergr")->addVariable("password","DUMMY","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",0,0);
      $del->addVariable("cswitch","-c");
      $del->addGroup("cmdgr");
      $del->get("cmdgr")->addVariable("delcmd","deltree");
      $del->get("cmdgr")->addVariable("remote","/dev/null","[^\\000]+",1,0,undef,1); 
      $del->addGroup("hostgr",undef,undef,1);
      $del->get("hostgr")->addVariable("doubleslash","//");
      $del->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
      $del->get("hostgr")->addVariable("slash","/");
      $del->get("hostgr")->addVariable("share","share","[a-zA-Z0-9\\:\\.\\-]{3,63}",1,0);

      $extra->addVariable("remote","/dev/null","[^\\000]+",1,0); # attempt again this time with the whole path (will fail if type is file)
      $extra->addVariable("maxprotocol","","[a-zA-Z0-9\\_]*",0,0);

      if ($mode == $Store::AUTH_PWFILE) {
         # needs a file with the password
         $extra->addVariable("passwordfile","/dev/null","[^\\000]+\.pwfile",1,0,1,undef,1); # param is sandboxed
      }

      return 1;
   } else {
      # failure - already open
      $self->{error}="Store already open. Unable to define it.";
      return 0;
   }
}

# creates necessary instances and
# sets parameters of StoreProcesses
sub open_create {
   my $self = shift;

   # not do this if store already open
   if (!$self->isOpen()) {
      my $mode = $self->{authmode};
      my $extra = $self->{extra};
      my $get = $self->{getparams};
      my $put = $self->{putparams};
      my $del = $self->{delparams};

      # create random file to put/rm
      my $rndfile=sectools::randstr(32);
      open (FH,">","/tmp/".$rndfile);
      print FH "Give me an exitcode please";
      close (FH);
      $self->{rndfile}="/tmp/".$rndfile;
      # set value in store
      $put->get("rndfile")->value($rndfile);

      if ($mode == $Store::AUTH_PWFILE) {
         # password is read from file
         my $pwfile=$extra->get("passwordfile")->value();
         my $pw="DUMMY"; # default failsafe...
         if (open (FH,"$pwfile")) {
            # read contents
            $pw=<FH>;
            close (FH);
         }
         # clean pw
         $pw=~s/[\r\n]//g;
         # check that pw passes regex of password
         my $check=$get->get("password")->regex();
         my $qcheck=qq($check);
         if ($pw !~ /^$qcheck$/) {
            # password in file does not fulfill its requirement - we do not accept this
            $self->{error}="Parameter \"password\" does not fulfill its regexp being read from file $pwfile.";
            return 0;
         }
         # update password value in get, put and del
         $self->setParam("password",$pw);
      } 

      if ($extra->get("maxprotocol")->value() ne "") {
         # max protocol defined. Set it
         $get->addVariableBefore("cswitch","maxproto1","-m");
         $get->addVariableAfter("maxproto1","maxproto2",$extra->get("maxprotocol")->value());

         $put->addVariableBefore("cswitch","maxproto1","-m");
         $put->addVariableAfter("maxproto1","maxproto2",$extra->get("maxprotocol")->value());

         $del->addVariableBefore("cswitch","maxproto1","-m");
         $del->addVariableAfter("maxproto1","maxproto2",$extra->get("maxprotocol")->value());
      }

      # get remote value
      my $remote=$extra->get("remote")->value();
      # separate last known folder from item name (file or folder)
      my $name=basename($remote);
      my $folder=dirname($remote);
      $self->setParam("altremote",$folder);
      $self->setParam("name",$name);

      # remove potential slash at end
      $remote =~ s/^(.*)\/$/$1/g;
      # set the new remote setting for del
      $del->get("remote")->value($remote);

      # create the StoreProcess instances
      $self->{get}=StoreProcess::Shell->new(pars=>$self->{getparams}, timeout=>$self->{pars}{timeout}, wait=>$self->{pars}{wait});
      $self->{put}=StoreProcess::Shell->new(pars=>$self->{putparams}, timeout=>$self->{pars}{timeout}, wait=>$self->{pars}{wait});
      $self->{del}=StoreProcess::Shell->new(pars=>$self->{delparams}, timeout=>$self->{pars}{timeout}, wait=>$self->{pars}{wait});
  
      return 1;  
   } else {
      # failure - already open
      $self->{error}="Error! Store already open. Unable to create processes...";
      return 0;
   }
}

sub remoteSize {
   my $self = shift;

   # must be opened to proceed
   if ($self->isOpen()) {
      $self->{mode}=$Store::STORE_MODE_REMOTE_SIZE;
      my $get=$self->{getparams};
      my $extra=$self->{extra};
      my $remote=$extra->get("remote")->value();
      # remove trailing slashes
      $remote=~s/^(.*)\/$/$1/g;
      my $cmd=Parameter::Group->new();
      # define size check command
      $cmd->addVariable("cmd","/usr/bin/smbclient");
      $cmd->addVariable("usernameswitch","-U","\\-U");
      $cmd->addGroup("usergr",undef,undef,1);
      $cmd->get("usergr")->addVariable("domain",$get->get("domain")->value());
      $cmd->get("usergr")->addVariable("slash","/");
      $cmd->get("usergr")->addVariable("username",$get->get("username")->value());
      $cmd->get("usergr")->addVariable("percent","\%");
      $cmd->get("usergr")->addVariable("password",$get->get("password")->value());
      if ($get->exists("maxproto1")) { 
         $cmd->addVariable("maxproto1",$get->get("maxproto1")->value()); 
         $cmd->addVariable("maxproto2",$get->get("maxproto2")->value()); 
      }
      $cmd->addVariable("cswitch","-c");
      $cmd->addGroup("cmdgr");
      $cmd->get("cmdgr")->addVariable ("command","recurse ; prompt ; ls \"$remote\"");
      $cmd->addGroup("hostgr",undef,undef,1);
      $cmd->get("hostgr")->addVariable("doubleslash","//");
      $cmd->get("hostgr")->addVariable("host",$get->get("host")->value());
      $cmd->get("hostgr")->addVariable("slash","/");
      $cmd->get("hostgr")->addVariable("share",$get->get("share")->value());
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
      $self->{sizeremotelog}=$log;
      # ensure we were successful
      if ($calc->success()) {
         my $size=0;
         my ($mess,$time);
         while (my $l=$log->getNext()) {
            ($mess,$time)=@{$l};

             # only take size from lines that are of correct format - ignore folders, symlinks etc.
            if ($mess =~ /^[\s\t]{2}[^\000]+[\s\t]+[AN]{1}[\s\t]+(\d+)[\s\t]+.*$/) {
               # add size to existing calculation.
               $size=$size+$1;
            }
         }

         # return calculated size
         return $size;
      } else {
         # unable to acquire size
         $self->{error}="Unable to get remote size: ".$calc->error();
         return undef;
      }
   } else {
      $self->{error}="Store not opened yet. Unable to get remote size.";
      return undef;
   }
}

sub listRemote {
   my $self = shift;
   my $path = shift || "/";

   # must be opened to proceed
   if ($self->isOpen()) {
      $self->{mode}=$Store::STORE_MODE_REMOTE_LIST;
      my $get=$self->{getparams};
      my $cmd=Parameter::Group->new();
      # add end slash if missing
      if ($path =~ /^.*[^\/]{1}$/) { $path.="/"; }
      # remove non-allowed characters - quotemeta does not work, so we must remove quotation and enter/new line.
      $path=~s/[\"\'\n\r]//g;
      # add wildcard to ensure listing of items in given folder
      $path.="*";
      # define size check command

      $cmd->addVariable("cmd","/usr/bin/smbclient");
      $cmd->addVariable("usernameswitch","-U","\\-U");
      $cmd->addGroup("usergr",undef,undef,1);
      $cmd->get("usergr")->addVariable("domain",$get->get("domain")->value());
      $cmd->get("usergr")->addVariable("slash","/");
      $cmd->get("usergr")->addVariable("username",$get->get("username")->value());
      $cmd->get("usergr")->addVariable("percent","\%");
      $cmd->get("usergr")->addVariable("password",$get->get("password")->value());
      if ($get->exists("maxproto1")) { 
         $cmd->addVariable("maxproto1",$get->get("maxproto1")->value()); 
         $cmd->addVariable("maxproto2",$get->get("maxproto2")->value()); 
      }
      $cmd->addVariable("cswitch","-c");
      $cmd->addGroup("cmdgr");
      $cmd->get("cmdgr")->addVariable("command","prompt ; ls \"$path\"");
      $cmd->addGroup("hostgr",undef,undef,1);
      $cmd->get("hostgr")->addVariable("doubleslash","//");
      $cmd->get("hostgr")->addVariable("host",$get->get("host")->value());
      $cmd->get("hostgr")->addVariable("slash","/");
      $cmd->get("hostgr")->addVariable("share",$get->get("share")->value());
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
      $self->{listremotelog}=$log;
      # ensure we were successful
      if ($calc->success()) { 
         my %result;
         my ($mess,$time);
         while (my $l=$log->getNext()) {
            ($mess,$time)=@{$l};

            # get entries with files, folders etc.
            if ($mess =~ /^[\s\t]{2}([^\000]+)[\s\t]+([AND]{1})[\s\t]+(\d+)[\s\t]+[^\s\t]+[\s\t]+([^\s\t]+)[\s\t]+(\d+)[\s\t]+(\d{2})\:(\d{2})\:(\d{2})[\s\t]+(\d{4}).*$/) {
               # save to structure
               my $name=$1;
               my $type=$2;
               $type=(uc($type) eq "D" ? "D" : "F"); # either directory or file type 
               my $size=$3;
               my $month=$4;
               my %m=( "Jan"=>1, "Feb"=>2, "Mar"=>3, "Apr"=>4, "May"=>5, "Jun"=>6, "Jul"=>7, "Aug"=>8, "Sep"=>9, "Oct"=>10, "Nov"=>11, "Dec"=>12 ); 
               $month=$m{$month};
               my $day=$5;
               my $hour=$6;
               my $min=$7;
               my $sec=$8;
               my $year=$9;
               $name=~s/^(.*[^\s]{1})\s+$/$1/;

               if ($name =~ /^[\.]{1,2}$/) { next; } # we are not interested in . and ..
               my @l;
               push @l,$sec; # second
               push @l,$min; # minute
               push @l,$hour; # hour
               push @l,$day; # day
               push @l,int($month)-1; # month
               push @l,$year; # year
               my $datetime=sprintf ("%d",timelocal(@l));
               $result{$type}{$name}{type}=$type;
               $result{$type}{$name}{size}=$size;
               $result{$type}{$name}{datetime}=$datetime;
               $result{$type}{$name}{name}=$name;
            }
         }

         # return result listing
         return \%result;
      } else {
         # unable to list
         $self->{error}="Unable to list remote folder: ".$calc->error();
         return undef;
      }
   } else {
      $self->{error}="Store not opened yet. Unable to list remote folder.";
      return undef;
   }
}

sub close {
   my $self=shift;

   if ($self->isOpen()) {
      # do some extra cleanup of tmp-files
      unlink ($self->{rndfile});

      return 1;
   } 

   # call super close - let it handle return result if closed
   return $self->SUPER::close();
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Store::SMB> - Class to define a SMB store that perform ftp-like operations between a local- and remote location.

=cut

=head1 SYNOPSIS

Used in the same way as the Store-class. See the Store-class for more information.

=cut

=head1 DESCRIPTION

Class to perform ftp-like operations on a SMB/CIFS-share between a local- and remote location.

The class is a wrapper around the smbclient-utility.

It is used in the same way as the Store-class. See the Store-class for more information.

=cut

=head1 CONSTRUCTOR

=head2 new()

Constructor is inherited from the Store-class. See the Store-class for more information.

It returns the instantiated class.

=cut

=head1 METHODS

=head2 open_define()

Defines the parameters used on the SMB-store. This methods is inherited from the Store-class. See the Store-class for more
information.

=cut

=head2 open_create()

Creates the necessary StoreProcess-instances used by the SMB-store.

It basically creates StoreProcess::Shell-instances for both GET-, PUT- and DEL-operations and inputs the necessary Parameter::Group-class
parameters.

This method has overridden a Store-class method. See the Store-class for more information.

=cut

=head2 remoteSize()

Calculates the size of the remote area designated by the parameter "remote".

It uses the smbclient-command "ls" recursively to list the folder and sub-folders and then add the size 
of the elements found.

Returns the size in Bytes. See the Store-class for more information on this method.

=cut

=head2 listRemote()

Lists a designated folder on the remote Store.

Input parameter is "path". If none given it lists the root of the remote area. Because the smbclient-utility command does 
not accept escaped meta-characters, it is not allowed to have doubleslash, slash, cr or nl in the path-name. This is a 
limitation due to security to avoid potential injection.

Uses the smbclient-command "ls" to list the folder in question.

Returns a HASH-reference structure upon success. Please the Store-class for more information on this method.

=cut

