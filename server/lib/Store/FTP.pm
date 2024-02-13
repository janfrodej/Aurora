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
# Store::FTP: class of a FTP Store
#
# Uses: lftp-command line utility
#
package Store::FTP;
use parent 'Store';

use strict;
use Time::Local;
use StoreProcess::Shell;

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

      # define parameters for ftp get
      $get->addVariable("cmd","/usr/bin/lftp",".*");
      $get->addVariable("scrsw","-df");
      $get->addVariable("getscript","/dev/null",".*");

      # define parameters for ftp put
      $put->addVariable("cmd","/usr/bin/lftp",".*");
      $put->addVariable("scrsw","-df");
      $put->addVariable("putscript","/dev/null");

      # define parameters for ftp delete
      $del->addVariable("cmd","/usr/bin/lftp",".*");
      $del->addVariable("scrsw","-df");
      $del->addVariable("delscript","/dev/null");

      # add local and remote here, since they are not in the command itself
      $extra->addVariable("remote","/dev/null","[^\\000\\n\\r\\\"\\\']*",1,0,1);
      $extra->addVariable("local","/dev/null","[^\\000\\n\\r\\\"\\\']*",1,0,1);
      # add username, password and host here, since they are not in the command itself
      $extra->addVariable("username","anonymous","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
      $extra->addVariable("password","DUMMY","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",1,0);
      $extra->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);

      if ($mode == $Store::AUTH_PWFILE) {
         # needs a file with the password
         $extra->addVariable("passwordfile","/dev/null","[^\\000]+\.pwfile",1,0,undef,undef,1); # param is sandboxed
         # password is no more required
         $extra->get("password")->required(0);
         # password is also private
         $extra->get("password")->private(1);
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

      my $r1=sectools::randstr(32);
      my $r2=sectools::randstr(32);
      my $r3=sectools::randstr(32);
      # create files
      my $local=$extra->get("local")->value();
      my $remote=$extra->get("remote")->value();
      my $host=$extra->get("host")->value();
      my $user=$extra->get("username")->value();
      my $pw=$extra->get("password")->value();
      if (open (FH,">","/tmp/$r1")) {
         print FH "open -u $user,$pw ftp://$host\n";
         print FH "mirror -c \"$remote\" \"$local\"\n";
         print FH "exit\n";
         close (FH);
      }
      if (open (FH,">","/tmp/$r2")) {
         print FH "open -u $user,$pw ftp://$host\n";
         print FH "mirror -cR \"$local\" \"$remote\"\n";
         print FH "exit\n";
         close (FH);
      }
      if (open (FH,">","/tmp/$r3")) {
         print FH "open -u $user,$pw ftp://$host\n";
         print FH "rm -r -f \"$remote\"\n";
         print FH "exit\n";
         close (FH);
      }
      # update file names
      $get->get("getscript")->value("/tmp/$r1");
      $put->get("putscript")->value("/tmp/$r2");
      $del->get("delscript")->value("/tmp/$r3");

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
         my $check=$extra->get("password")->regex();
         my $qcheck=qq($check);
         if ($pw !~ /^$qcheck$/) {
            # password in file does not fulfill its requirement - we do not accept this
            $self->{error}="Parameter \"password\" does not fulfill its regexp being read from file $pwfile.";
            return 0;
         }
         # update password value in both get and put
         $self->setParam("password",$pw);
      } 

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
      my $extra=$self->{extra};
      my $cmd=Parameter::Group->new();

      my $remote=$extra->get("remote")->value();
      my $host=$extra->get("host")->value();
      my $user=$extra->get("username")->value();
      my $pw=$extra->get("password")->value();
      # write temporary script-file
      my $tmpfile="/tmp/".sectools::randstr(32);
      open (FH,">",$tmpfile);
      print FH "open -u $user,$pw ftp://$host\n";
      print FH "find -l \"$remote\"\n";
      print FH "exit\n";
      close (FH);
      # define list command
      $cmd->addVariable("cmd","/usr/bin/lftp");
      $cmd->addVariable("scrsw","-f");
      $cmd->addVariable("script",$tmpfile);

      # run calculation - set a sensible timeout, less than global timeout - a little bit
      my $timeout=($self->{pars}{timeout} < 300 ? $self->{pars}{timeout}-30 : 300);
      my $calc=StoreProcess::Shell->new(pars=>$cmd, timeout=>$timeout, wait=>$self->{pars}{wait});
      $calc->execute();
      # wait for result or timeout
      while (($calc->isrunning()) || (!$calc->isemptied())) {
      }
      # unlink tmp-file
      unlink ($tmpfile);
      # get log
      my $log=$calc->getlog();         
      $log->resetNext();
      # save log
      $self->{sizeremotelog}=$log;
      # ensure we were successful
      if ($calc->success()) {
         my $size=0;
         my ($mess,$time);
         while (my $l=$log->getNext()) {
            ($mess,$time)=@{$l};

             # only take size from lines that are of correct format - ignore folders, symlinks etc.
            if ($mess =~ /^\-[^\t\s]+[\t\s]+[^\s\t]+[\t\s]+(\d+).*$/) {
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
   my $path = shift || "";

   # must be opened to proceed
   if ($self->isOpen()) {
      $self->{mode}=$Store::STORE_MODE_REMOTE_LIST;
      $path=~s/[\r\n\"\']//g;
      my $extra=$self->{extra};
      my $cmd=Parameter::Group->new();
      my $host=$extra->get("host")->value();
      my $user=$extra->get("username")->value();
      my $pw=$extra->get("password")->value();
      # write temporary script-file
      my $tmpfile="/tmp/".sectools::randstr(32);
      open (FH,">",$tmpfile);
      print FH "open -u $user,$pw ftp://$host\n";
      print FH "cd \"$path\"\n";
      print FH "cls -l --time-style=+\"%Y%m%d %H%M%S\"\n";
      print FH "exit\n";
      close (FH);
      # define list command
      $cmd->addVariable("cmd","/usr/bin/lftp");
      $cmd->addVariable("scrsw","-f");
      $cmd->addVariable("getscript",$tmpfile);

      # run calculation - set a sensible timeout, less than global timeout - a little bit
      my $timeout=($self->{pars}{timeout} < 300 ? $self->{pars}{timeout}-30 : 300);
      my $calc=StoreProcess::Shell->new(pars=>$cmd, timeout=>$timeout, wait=>$self->{pars}{wait});
      $calc->execute();
      # wait for result or timeout
      while (($calc->isrunning()) || (!$calc->isemptied())) {
      }
      # unlink tmp-file
      unlink ($tmpfile);
      # get log
      my $log=$calc->getlog();
      $log->resetNext();
      # save log
      $self->{listremotelog}=$log;
      # ensure we were successful
      if ($calc->success()) {
         my %result;
         my ($mess,$time);
         while (my $l=$log->getNext()) {
            ($mess,$time)=@{$l};

             # only take size from lines that are of correct format - ignore folders, symlinks etc.
            if ($mess =~ /^([\-dl]{1})[^\t\s]+[\t\s]+[^\s\t]+[\t\s]+[^\t\s]+[\t\s]+[^\t\s]+[\t\s]+([\d]+)[\t\s]+(\d+)[\t\s]+(\d+)[\t\s]{1}(.*)$/) {
               # save to structure
               my $type=$1;
               $type=(uc($type) eq "D" ? "D" : (uc($type) eq "L" ? "L" : "F")); # either link, directory or file type 
               my $size=$2;
               my $dt=$3.$4;
               $dt=$Schema::CLEAN{datetimestr}->($dt);
               my $name=$5;
               $name=~s/^\/(.*)$/$1/g; # removing preceeding slashes
               $name=~s/^(.*)\/$/$1/g; # removing trailing slashes
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

         # return structure
         return \%result;
      } else {
         # unable to acquire size
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
      my $batch1=$self->{getparams}->get("getscript")->value();
      my $batch2=$self->{putparams}->get("putscript")->value();
      my $batch3=$self->{delparams}->get("delscript")->value();
      unlink ($batch1);
      unlink ($batch2);
      unlink ($batch3);

      return 1;
   } 

   # call super close - let it handle return result if closed
   return $self->SUPER::close();
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Store::FTP> - Class to define FTP store that perform ftp-operations between a local- and remote location.

=cut

=head1 SYNOPSIS

Used in the same way as the Store-class. See the Store-class for more information.

=cut

=head1 DESCRIPTION

Class to perform ftp-operations between a local- and remote location.

The class is a wrapper around the lftp-command utility.

Because of limitiations in the lftp-command this class does not accept the characters carriage return, 
new line or quote or doublequote in the "remote" and "local"-parameters since it compromises the security of 
running commands on the command-line. If this is a problem for the filenames or folders being used, please use 
another Store-class for the transfer.

It is used in the same way as the Store-class. See the Store-class for more information.

=cut

=head1 CONSTRUCTOR

=head2 new()

Constructor is inherited from the Store-class. See the Store-class for more information.

It returns the instantiated class.

=cut

=head1 METHODS

=head2 open_define()

Defines the parameters used on the FTP-store. This methods is inherited from the Store-class. See the Store-class for more
information.

=cut

=head2 open_create()

Creates the necessary StoreProcess-instances used by the SFTP-store.

It basically creates StoreProcess::Shell-instances for GET-, PUT- and DEL-operations and inputs the necessary Parameter::Group-class
parameters.

This method has overridden a Store-class method. See the Store-class for more information.

=cut

=head2 remoteSize()

Calculates the size of the remote area designated by the parameter "remote".

The FTP-module uses the lftp-command "find" to recursively list the folder and sub-folders and then add the size 
of the elements found.

Returns the size in Bytes. See the Store-class for more information on this method.

=cut

=head2 listRemote()

Lists a designated folder on the remote Store.

Input parameter is "path". If none given it lists the root of the remote area.

Uses the lftp-command "cls" to list the folder in question.

Returns a HASH-reference structure upon success. Please the Store-class for more information on this method.

=cut


