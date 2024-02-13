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
# Store::SFTP: class of a SFTP Store
#
# Uses: sftp-, sshpass- and ssh-utilities.
#
package Store::SFTP;
use parent 'Store';

use strict;
use StoreProcess::Shell;
use Time::Local;
use sectools;

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
 
      # get auth mode
      my $mode=$self->{authmode};

      if (($mode == $Store::AUTH_PW) || ($mode == $Store::AUTH_PWFILE)) {
         # define parameters for sftp get
         $get->addVariable("sshpass","/usr/bin/sshpass");
         $get->addVariable("sshpasswitch","-p","\\-p");
         $get->addVariable("password","dummy","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",1,0);
         $get->addVariable("cmd","/usr/bin/sftp");
         $get->addVariable("sshoptions","-o PasswordAuthentication=yes -o StrictHostKeyChecking=yes -o PubkeyAcceptedKeyTypes=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa");
         $get->addVariable("batchswitch","-b"); 
         $get->addVariable("getbatch","/dev/null",undef,undef,1);
         $get->addGroup("hostgr",undef,undef,1);
         $get->get("hostgr")->addVariable("username","dummy","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $get->get("hostgr")->addVariable("at","\@","\\\@");
         $get->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);

         # define parameters for sftp put
         $put->addVariable("sshpass","/usr/bin/sshpass");
         $put->addVariable("sshpasswitch","-p","\\-p");
         $put->addVariable("password","dummy","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",1,0);
         $put->addVariable("cmd","/usr/bin/sftp");
         $put->addVariable("sshoptions","-o PasswordAuthentication=yes -o StrictHostKeyChecking=yes -o PubkeyAcceptedKeyTypes=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa");
         $put->addVariable("batchswitch","-b"); 
         $put->addVariable("putbatch","/dev/null",undef,undef,1);
         $put->addGroup("hostgr",undef,undef,1);
         $put->get("hostgr")->addVariable("username","dummy","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $put->get("hostgr")->addVariable("at","\@","\\\@");
         $put->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);

         # define parameters for sftp del
         $del->addVariable("sshpass","/usr/bin/sshpass");
         $del->addVariable("sshpasswitch","-p","\\-p");
         $del->addVariable("password","dummy","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",1,0);
         $del->addVariable("cmd","/usr/bin/sftp");
         $del->addVariable("sshoptions","-o PasswordAuthentication=yes -o StrictHostKeyChecking=yes -o PubkeyAcceptedKeyTypes=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa");
         $del->addVariable("batchswitch","-b");
         $del->addVariable("delbatch","/dev/null",undef,undef,1);
         $del->addGroup("hostgr",undef,undef,1);
         $del->get("hostgr")->addVariable("username","dummy","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $del->get("hostgr")->addVariable("at","\@","\\\@");
         $del->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
      } else { # key or keyfile
         # define parameters for sftp get
         $get->addVariable("cmd","/usr/bin/sftp");
         $get->addVariable("options","-i","[\\-a-zA-Z]*");
         if ($mode == $Store::AUTH_KEY) {
            $get->addVariable("privatekeyfile","/dev/null","[^\\000]+\.keyfile"); 
         } else {
            # the mode is a keyfile, setting is required.
            $get->addVariable("privatekeyfile","/dev/null","[^\\000]+\.keyfile",1,0,undef,undef,1); # param is to be sandboxed
         }
         $get->addVariable("sshoption1","-o");
         $get->addVariable("sshoption2","PasswordAuthentication=no");
         $get->addVariable("sshoption3","-o");
         $get->addVariable("sshoption4","StrictHostKeyChecking=yes");
         $get->addVariable("batchswitch","-b"); 
         $get->addVariable("getbatch","/dev/null",undef,undef,1);
         $get->addGroup("hostgr",undef,undef,1);
         $get->get("hostgr")->addVariable("username","dummy","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $get->get("hostgr")->addVariable("at","\@","\\\@");
         $get->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);

         # define parameters for sftp put
         $put->addVariable("cmd","/usr/bin/sftp");
         $put->addVariable("options","-i","[\\-a-zA-Z]*");
         if ($mode == $Store::AUTH_KEY) {
            $put->addVariable("privatekeyfile","/dev/null","[^\\000]+\.keyfile");
         } else {
            # the mode is a keyfile, setting is required.
            $put->addVariable("privatekeyfile","/dev/null","[^\\000]+\.keyfile",1,0,undef,undef,1); # param is to be sandboxed 
         }
         $put->addVariable("sshoption1","-o");
         $put->addVariable("sshoption2","PasswordAuthentication=no");
         $put->addVariable("sshoption3","-o");
         $put->addVariable("sshoption4","StrictHostKeyChecking=yes");
         $put->addVariable("batchswitch","-b"); 
         $put->addVariable("putbatch","/dev/null",undef,undef,1);
         $put->addGroup("hostgr",undef,undef,1);
         $put->get("hostgr")->addVariable("username","dummy","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $put->get("hostgr")->addVariable("at","\@","\\\@");
         $put->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);

         # define parameters for sftp del
         $del->addVariable("sshcmd","/usr/bin/ssh");
         $del->addVariable("usernameswitch","-l");
         $del->addVariable("username","root","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $del->addVariable("certswitch","-i");
         if ($mode == $Store::AUTH_KEYFILE) {
            # keyfile required
            $del->addVariable("privatekeyfile","","[^\\000]+\.keyfile",1,0,undef,undef,1); # param is to be sandboxed
         } else {
            # keyfile is not required, written from param
            $del->addVariable("privatekeyfile","","[^\\000]+\.keyfile",0,0);
         }
         $del->addVariable("sshoption1","-o");
         $del->addVariable("sshoption2","PasswordAuthentication=no");
         $del->addVariable("sshoption3","-o");
         $del->addVariable("sshoption4","StrictHostKeyChecking=yes");
         $del->addVariable("sshportswitch","-p");
         $del->addVariable("port","22","\\d+",undef,0);
         $del->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
         $del->addVariable("rmcmd","rm");
         $del->addVariable("rmoptions","-Rf");
         $del->addVariable("remote","/dev/null","[^\\000]*",0,0,1,undef,undef,undef,undef,0);
      }

      # define the extras - order does not matter
      $extra->addVariable("knownhosts","","[^\000-\037\177]*",0,0);
      # add local and remote here, since they are not in the command itself
      $extra->addVariable("remote","/dev/null","[^\\000\r\n\"\']*",1,0);
      $extra->addVariable("local","/dev/null","[^\\000\r\n\"\']*",1,0);

      if ($mode == $Store::AUTH_PWFILE) {
         # password is to be read from file, passwordfile required
         $extra->addVariable("passwordfile","/dev/null","[^\\000]+\.pwfile",1,0,undef,undef,1); # param is to be sandboxed
         # password is no longer required and private
         $get->get("password")->required(0);
         $get->get("password")->private(1);
         $put->get("password")->required(0);
         $put->get("password")->private(1);
         $del->get("password")->required(0);
         $del->get("password")->private(1);
      }
      if ($mode == $Store::AUTH_KEY) {
         # privatekey/identity is to come from input, required
         $extra->addVariable("privatekey","dummy",".*",1,0);
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

      # create sftp batch-files
      my $r1=sectools::randstr(32);
      my $r2=sectools::randstr(32);
      # create files
      my $local=$extra->get("local")->value();
      my $remote=$extra->get("remote")->value();
      if (open (FH,">","/tmp/$r1")) {
         # if paths ends in slash, this is interpreted as a folder
         my $loc=$local;
         if ($local =~ /^.*\/$/) { 
            # go into folder before putting
            print FH "lcd $local\n";
            $loc="."
         } 
         my $rem="\"".$remote."\"";
         if ($remote =~ /^.*\/$/) { 
            # go into folder before putting
            print FH "cd $remote\n";
            $rem="*"
         } 

         print FH "get -arp $rem \"$loc\"\n";
         close (FH);
      }
      if (open (FH,">","/tmp/$r2")) {
         # if paths ends in slash, this is interpreted as a folder
         my $loc="\"".$local."\"";
         if ($local =~ /^.*\/$/) { 
            # go into folder before putting
            print FH "lcd $local\n";
            $loc="*"
         } 
         my $rem=$remote;
         if ($remote =~ /^.*\/$/) { 
            # go into folder before putting
            print FH "cd $remote\n";
            $rem="."
         } 
         
         print FH "put -arp $loc \"$rem\"\n";
         close (FH);
      }
      # update file names
      $get->get("getbatch")->value("/tmp/$r1");
      $put->get("putbatch")->value("/tmp/$r2");
      $del->get("remote")->value($remote);

      # check knownhosts parameter
      if ($extra->exists("knownhosts")) {
         # we are to use a knownhosts file - create random name
         my $randstr=sectools::randstr(32);
         # save name of file for later use and removal
         $self->{knownhostsfile}="/tmp/$randstr";
         # create file with key
         my $kh=$extra->get("knownhosts")->value();
         # remove backslashes
         $kh=~s/\\//g;
         if (open (FH,">","/tmp/$randstr")) {
            print FH "$kh\n";
            close (FH);
         }
         # append sshoptions
         my $opt="UserKnownHostsFile=/tmp/$randstr";
         # set it in both get and put
         $get->addVariableAfter("sshoption4","sshoption5","-o");
         $put->addVariableAfter("sshoption4","sshoption5","-o");
         $del->addVariableAfter("sshoption4","sshoption5","-o");
         $get->addVariableAfter("sshoption5","sshoption6",$opt);
         $put->addVariableAfter("sshoption5","sshoption6",$opt);
         $del->addVariableAfter("sshoption5","sshoption6",$opt);
      }

      if ($mode == $Store::AUTH_PWFILE) {
         # password is read from file
         my $pwfile=$extra->get("passwordfile")->value();
         my $pw="DUMMY";
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
         # update password value in both get, put and delete         
         $self->setParam("password",$pw);
      } 

      if ($mode == $Store::AUTH_KEY) {
         # key comes from input and then written to file
         # make the privatekey file
         my $randstr=sectools::randstr(32);
         # save name of file for later use and removal
         $self->{privatekeyfile}="/tmp/$randstr";
         # create file with key
         if (open (FH,">","/tmp/$randstr")) {
            print FH $extra->get("privatekey")->value()."\n";
            close (FH);
         }
         # set it in both get and put
         $self->setParam("privatekeyfile","/tmp/$randstr");     
      }

      # create the StoreProcess instances
      $self->{get}=StoreProcess::Shell->new(pars=>$self->{getparams}, timeout=>$self->{pars}{timeout}, wait=>$self->{pars}{wait});
      $self->{put}=StoreProcess::Shell->new(pars=>$self->{putparams}, timeout=>$self->{pars}{timeout}, wait=>$self->{pars}{wait});
      $self->{del}=StoreProcess::Shell->new(pars=>$self->{delparams}, timeout=>$self->{pars}{timeout}, wait=>$self->{pars}{wait});
  
      return 1;  
   } else {
      # failure - already open
      $self->{error}="Store already open. Unable to create processes.";
      return 0;
   }
}

# get the size of the remote data
# in bytes, use ssh, since sftp does not have recursive ls.
sub remoteSize {
   my $self = shift;

   # must be opened to proceed
   if ($self->isOpen()) {
      $self->{mode}=$Store::STORE_MODE_REMOTE_SIZE;
      my $get=$self->{getparams};
      my $extra=$self->{extra};
      my $cmd=Parameter::Group->new();
      # get authentication mode
      my $mode=$self->{authmode};
      # setup command to check size
      if (($mode == $Store::AUTH_PW) || ($mode == $Store::AUTH_PWFILE)) {
         # define size check command
         $cmd->addVariable("sshpass","/usr/bin/sshpass");
         $cmd->addVariable("sshpasswitch","-p","\\-p");
         $cmd->addVariable("password",$get->get("password")->value());
         $cmd->addVariable("cmd","/usr/bin/ssh");
         my $i=1;
         while (my $opt=$get->get("sshoption$i")) {
            my $val=$opt->value();
            $i++;
            $cmd->addVariable ("sshoption$i",$val);
         }
         $cmd->addGroup("hostgr",undef,undef,1);
         $cmd->get("hostgr")->addVariable("username",$get->get("username")->value());
         $cmd->get("hostgr")->addVariable("at","\@","\\\@");
         $cmd->get("hostgr")->addVariable("host",$get->get("host")->value(),".*",1,1);
         $cmd->addGroup("lsgr");
         $cmd->get("lsgr")->addVariable("lscmd","ls -lLR");
         $cmd->get("lsgr")->addVariable("remote",$extra->get("remote")->value(),"[^\\000]*",0,0,1,0);
      } else { # key or keyfile
         # define size check command by using privatekey
         $cmd->addVariable("cmd","/usr/bin/ssh");
         $cmd->addVariable("options","-i ".$get->get("privatekeyfile")->value());
         my $i=1;
         while (my $opt=$get->get("sshoption$i")) {
            my $val=$opt->value();
            $i++;
            $cmd->addVariable ("sshoption$i",$val);
         }
         $cmd->addGroup("hostgr",undef,undef,1);
         $cmd->get("hostgr")->addVariable("username",$get->get("username")->value());
         $cmd->get("hostgr")->addVariable("at","\@","\\\@");
         $cmd->get("hostgr")->addVariable("host",$get->get("host")->value());
         $cmd->addGroup("lsgr");
         $cmd->get("lsgr")->addVariable("lscmd","ls -lLR");
         $cmd->get("lsgr")->addVariable("remote",$extra->get("remote")->value(),"[^\\000]*",0,0,1,0);
      }

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
      $self->{sizeremotelog}=$log;
      # ensure we were successful
      if ($calc->success()) {
         my $size=0;
         my ($mess,$time);
         while (my $l=$log->getNext()) {
            ($mess,$time)=@{$l};

             # only take size from lines that are of correct format - ignore folders, symlinks etc.
            if ($mess =~ /^-[^\s\t]+[\s\t]+\d+[\s\t]+[^\s\t]+[\s\t]+[^\s\t]+[\s\t]+(\d+).*$/) {
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
      $self->{error}="Store is not open. Unable to get remote size.";
      return undef;
   }
}

sub listRemote {
   my $self = shift;
   my $path = shift || ".";

   # must be opened to proceed
   if ($self->isOpen()) {
      $self->{mode}=$Store::STORE_MODE_REMOTE_LIST;
      $path=~s/[\r\n\"\']//g;
      my $get=$self->{getparams};
      my $cmd=Parameter::Group->new();
      # get authentication mode
      my $mode=$self->{authmode};
      # setup command to check size
      if (($mode == $Store::AUTH_PW) || ($mode == $Store::AUTH_PWFILE)) {
         # define size check command
         $cmd->addVariable("sshpass","/usr/bin/sshpass");
         $cmd->addVariable("sshpasswitch","-p","\\-p");
         $cmd->addVariable("password",$get->get("password")->value());
         $cmd->addVariable("cmd","/usr/bin/ssh");
         my $i=1;
         while (my $opt=$get->get("sshoption$i")) {
            my $val=$opt->value();
            $i++;
            $cmd->addVariable ("sshoption$i",$val);
         }
         $cmd->addGroup("userhost",undef,undef,1);
         $cmd->get("userhost")->addVariable("username",$get->get("username")->value());
         $cmd->get("userhost")->addVariable("at","\@","\\\@");
         $cmd->get("userhost")->addVariable("host",$get->get("host")->value());
         $cmd->addGroup("lsgr");
         $cmd->get("lsgr")->addVariable("lscmd","ls -lan --time-style=+\"%Y%m%d %H%M%S\"");
         $cmd->get("lsgr")->addVariable("remote",$path,"[^\\000]*",0,0,1,0);
      } else { # key or keyfile
         # define size check command by using privatekey
         $cmd->addVariable("cmd","/usr/bin/ssh");
         $cmd->addVariable("keyoption","-i");
         $cmd->addVariable("keyfile",$get->get("privatekeyfile")->value());
         my $i=1;
         while (my $opt=$get->get("sshoption$i")) {
            my $val=$opt->value();
            $i++;
            $cmd->addVariable ("sshoption$i",$val);
         }
         $cmd->addGroup("userhost",undef,undef,1);
         $cmd->get("userhost")->addVariable("username",$get->get("username")->value());
         $cmd->get("userhost")->addVariable("at","\@","\\\@");
         $cmd->get("userhost")->addVariable("host",$get->get("host")->value());

         $cmd->addGroup("lsgr");
         $cmd->get("lsgr")->addVariable("lscmd","ls -lan --time-style=+\"%Y%m%d %H%M%S\"");
         $cmd->get("lsgr")->addVariable("remote",$path,"[^\\000]*",0,0,1,0);
      }

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
      $self->{listremotelog}=$log;
      # ensure we were successful
      if ($calc->success()) {
         my %result;
         my ($mess,$time);
         while (my $l=$log->getNext()) {
            ($mess,$time)=@{$l};

            # get files, folders, attributes etc.
            if ($mess =~ /^([-dl]){1}[^\s\t]+[\s\t]+\d+[\s\t]+\d+[\s\t]+\d+[\s\t]+(\d+)[\s\t]+(\d{8})[\s\t]+(\d{6})[\s\t]{1}(.+)[\r\n]*$/) {
               # save to structure
               my $type=$1;
               $type=(uc($type) eq "D" ? "D" : (uc($type) eq "L" ? "L" : "F")); # either directory, link or file type 
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
         $self->{error}="Unable to list remote folder: ".$calc->error();
         return undef;
      }
   } else {
      $self->{error}="Store is not open. Unable to list remote folder.";
      return undef;
   }
}

sub close {
   my $self=shift;

   if ($self->isOpen()) {
      # do some extra cleanup of the possible tmp-files
      if ($self->{knownhostsfile}) {
         unlink ($self->{knownhostsfile});
      }
      if ($self->{privatekeyfile}) {
         unlink ($self->{privatekeyfile});
      }
      # remove batch files
      my $batch1=$self->{getparams}->get("getbatch")->value();
      my $batch2=$self->{putparams}->get("putbatch")->value();
      unlink ($batch1);
      unlink ($batch2);

      return 1;
   } 

   # call super close - let it handle return result if closed
   return $self->SUPER::close();
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Store::SFTP> - Class to define SFTP store that perform sftp operations between a local- and remote location.

=cut

=head1 SYNOPSIS

Used in the same way as the Store-class. See the Store-class for more information.

=cut

=head1 DESCRIPTION

Class to perform sftp-operations between a local- and remote location.

The class is a wrapper around the scp-command utility.

Because of limitiations in the scp-command this class does not accept the characters carriage return, 
new line or quote or doublequote in the "remote" and "local"-parameters since it compromises the security of 
running commands on the command-line. If this is a problem for the filenames or folders being used, please use 
another Store-class for the transfer.

These additional parameters are special to the SFTP-class and are to be used with the open()-method:

=over

=item

B<knownhosts> The knownhosts-file entry that identifies the host that one connects to. It is basically the publickey 
in the same format as in a SSH knownhosts-file. When this option is specified it creates a random file 
in /tmp that contains the host-name and the publickey when the open()-method is called. It also appends 
the sshoptions-parameter in both the get- and put-command to add the option "-o UserKnownHostsFile" and 
sets it to the temporary file. This means that the host-parameter should not be changed after the open()-
method has been called as it could make the host-name in the temporary knownhosts-file invalid. When the 
DESTROY-method is called it unlinks the temporary knownhosts-file.

=cut

=item

B<passwordfile> This parameter must be specified if the authentication mode set to the new()-method is
AUTH_PWFILE. It basically defines the location and name of the file to read the password from for the user 
connecting through SSH to get/put data on the remote location.

=cut

=item

B<privatekey> This parameters must be specified if the authentication mode set to the new()-method is 
AUTH_KEY. The key specified here is in the same format as in the .ssh/id_rsa-file. The parameter is written 
to a random file in /tmp that is used as the privatekey/identity file when connecting through SSH to the remote 
location. When the DESTROY()-method is called it unlinks the temporary privatekey-file.

=cut

=back

It is used in the same way as the Store-class. See the Store-class for more information.

=cut

=head1 CONSTRUCTOR

=head2 new()

Constructor is inherited from the Store-class. See the Store-class for more information.

It returns the instantiated class.

=cut

=head1 METHODS

=head2 open_define()

Defines the parameters used on the SFTP-store. This methods is inherited from the Store-class. See the Store-class for more
information.

=cut

=head2 open_create()

Creates the necessary StoreProcess-instances used by the SFTP-store.

It basically creates StoreProcess::Shell-instances for both GET-, PUT- and DEL-operations and inputs the necessary Parameter::Group-class
parameters.

This method has overridden a Store-class method. See the Store-class for more information.

=cut

=head2 remoteSize()

Calculates the size of the remote area designated by the parameter "remote".

It uses the ssh-utility and the command "ls" to recursively list the folder and sub-folders and then add the size 
of the elements found.

Returns the size in Bytes. See the Store-class for more information on this method.

=cut

=head2 listRemote()

Lists a designated folder on the remote Store.

Input parameter is "path". If none given it lists the root of the remote area.

Uses the ssh-utility and the command "ls" to list the folder in question.

Returns a HASH-reference structure upon success. Please the Store-class for more information on this method.

=cut

