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
# Store::SCP: class of a SCP Store
#
# Uses: scp-, sshpass- and ssh-utilities.
#
package Store::SCP;
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
         # define parameters for scp get
         $get->addVariable("sshpass","/usr/bin/sshpass");
         $get->addVariable("sshpasswitch","-p");
         $get->addVariable("password","dummy","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",1,0);
         $get->addVariable("cmd","/usr/bin/scp");
         $get->addVariable("options","-rp","[\\-a-zA-Z]*");
         $get->addVariable("sshoption1","-o");
         $get->addVariable("sshoption2","PasswordAuthentication=yes");
         $get->addVariable("sshoption3","-o");
         $get->addVariable("sshoption4","StrictHostKeyChecking=yes");
         $get->addVariable("sshoption5","-o");
         $get->addVariable("sshoption6","PubkeyAcceptedKeyTypes=+ssh-rsa");
         $get->addVariable("sshoption7","-o");
         $get->addVariable("sshoption8","PubkeyAcceptedAlgorithms=+ssh-rsa");

         $get->addGroup("hostgr",undef,undef,1);
         $get->get("hostgr")->addVariable("username","dummy","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $get->get("hostgr")->addVariable("at","\@","\\\@");
         $get->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
         $get->get("hostgr")->addVariable("colon",":","\\:");
         $get->get("hostgr")->addVariable("remote","/dev/null","[^\\000]*",1,0,0,undef,undef,undef,undef,0);
         $get->addVariable("local","/dev/null","[^\\000]*",1,0);
         # define parameters for scp put
         $put->addVariable("sshpass","/usr/bin/sshpass");
         $put->addVariable("sshpasswitch","-p","\\-p");
         $put->addVariable("password","dummy","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",1,0);
         $put->addVariable("cmd","/usr/bin/scp");
         $put->addVariable("options","-rp","[\\-a-zA-Z]*");
         $put->addVariable("sshoption1","-o");
         $put->addVariable("sshoption2","PasswordAuthentication=yes");
         $put->addVariable("sshoption3","-o");
         $put->addVariable("sshoption4","StrictHostKeyChecking=yes");
         $put->addVariable("sshoption5","-o");
         $put->addVariable("sshoption6","PubkeyAcceptedKeyTypes=+ssh-rsa");
         $put->addVariable("sshoption7","-o");
         $put->addVariable("sshoption8","PubkeyAcceptedAlgorithms=+ssh-rsa");

         $put->addVariable("local","/dev/null","[^\\000]*",1,0);
         $put->addGroup("hostgr",undef,undef,1);
         $put->get("hostgr")->addVariable("username","dummy","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $put->get("hostgr")->addVariable("at","\@","\\\@");
         $put->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
         $put->get("hostgr")->addVariable("colon",":","\\:");
         $put->get("hostgr")->addVariable("remote","/dev/null","[^\\000]*",1,0,0,undef,undef,undef,undef,0);

         # define parameters for delete
         $del->addVariable("sshpass","/usr/bin/sshpass");
         $del->addVariable("sshpassoptions","-p");
         if ($mode == $Store::AUTH_PW) {
            # password is required
            $del->addVariable("password","dummy","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",1,0,1);
         } else {
            # password is not required, read from file
            $del->addVariable("password","dummy","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",0,1,1);
         }
         $del->addVariable("sshcmd","/usr/bin/ssh");
         $del->addVariable("usernameswitch","-l");
         $del->addVariable("username","root","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $del->addVariable("sshportswitch","-p");
         $del->addVariable("port","22","\\d+",undef,0);
         $del->addVariable("sshoption1","-o");
         $del->addVariable("sshoption2","PasswordAuthentication=yes");
         $del->addVariable("sshoption3","-o");
         $del->addVariable("sshoption4","StrictHostKeyChecking=yes");
         $del->addVariable("sshoption5","-o");
         $del->addVariable("sshoption6","PubkeyAcceptedKeyTypes=+ssh-rsa");
         $del->addVariable("sshoption7","-o");
         $del->addVariable("sshoption8","PubkeyAcceptedAlgorithms=+ssh-rsa");

         $del->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
         $del->addVariable("testcmd","test");
         $del->addVariable("testopt","-f");
         $del->addVariable("remote","/dev/null","[^\\000]*",1,0,1,undef,undef,undef,undef,0);
         $del->addVariable("testtrue","&&");
         $del->addVariable("testtruerm","rm");
         $del->addVariable("remote");
         $del->addVariable("testfalse","||");
         $del->addVariable("testfalserm","rm");
         $del->addVariable("testfalseopt","-Rf");
         $del->addGroup("falsegr",0,0,1);
         $del->get("falsegr")->addVariable("remote");
         $del->get("falsegr")->addVariable("falsegrwc","/*",".*",undef,undef,0,0);
      } else { # key or keyfile
         # define parameters for scp get
         $get->addVariable("cmd","/usr/bin/scp");
         $get->addVariable("options","-pri","[\\-a-zA-Z]*");
         if ($mode == $Store::AUTH_KEY) {
            $get->addVariable("privatekeyfile","/dev/null","[^\\000]+\.keyfile",1,0); 
         } else {
            # the mode is a keyfile, setting is required.
            $get->addVariable("privatekeyfile","/dev/null","[^\\000]+\.keyfile",1,0,undef,undef,1); # param is to be sandboxed 
         }
         $get->addVariable("sshoption1","-o");
         $get->addVariable("sshoption2","PasswordAuthentication=no");
         $get->addVariable("sshoption3","-o");
         $get->addVariable("sshoption4","StrictHostKeyChecking=yes");
         $get->addVariable("sshoption5","-o");
         $get->addVariable("sshoption6","PubkeyAcceptedKeyTypes=+ssh-rsa");
         $get->addVariable("sshoption7","-o");
         $get->addVariable("sshoption8","PubkeyAcceptedAlgorithms=+ssh-rsa");

         $get->addGroup("hostgr",undef,undef,1);
         $get->get("hostgr")->addVariable("username","dummy","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $get->get("hostgr")->addVariable("at","\@","\\\@");
         $get->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
         $get->get("hostgr")->addVariable("colon",":","\\:");
         $get->get("hostgr")->addVariable("remote","/dev/null","[^\\000]*",1,0,0,undef,undef,undef,undef,0);
         $get->addVariable("local","/dev/null","[^\\000]*",1,0);

         # define parameters for scp put
         $put->addVariable("cmd","/usr/bin/scp");
         $put->addVariable("options","-pri","[\\-a-zA-Z]*");
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
         $put->addVariable("sshoption5","-o");
         $put->addVariable("sshoption6","PubkeyAcceptedKeyTypes=+ssh-rsa");
         $put->addVariable("sshoption7","-o");
         $put->addVariable("sshoption8","PubkeyAcceptedAlgorithms=+ssh-rsa");

         $put->addVariable("local","/dev/null","[^\\000]*",1,0);
         $put->addGroup("hostgr",undef,undef,1); 
         $put->get("hostgr")->addVariable("username","dummy","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $put->get("hostgr")->addVariable("at","\@","\\\@");
         $put->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
         $put->get("hostgr")->addVariable("colon",":","\\:");
         $put->get("hostgr")->addVariable("remote","/dev/null","[^\\000]*",1,0,0,undef,undef,undef,undef,0);

         # define parameters for rsync/ssh del/delete
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
         $del->addVariable("sshoption5","-o");
         $del->addVariable("sshoption6","PubkeyAcceptedKeyTypes=+ssh-rsa");
         $del->addVariable("sshoption7","-o");
         $del->addVariable("sshoption8","PubkeyAcceptedAlgorithms=+ssh-rsa");

         $del->addVariable("sshportswitch","-p");
         $del->addVariable("port","22","\\d+",undef,0);
         $del->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
         $del->addVariable("testcmd","test");
         $del->addVariable("testopt","-f");
         $del->addVariable("remote","/dev/null","[^\\000]*",1,0,1,undef,undef,undef,undef,0);
         $del->addVariable("testtrue","&&");
         $del->addVariable("testtruerm","rm");
         $del->addVariable("remote");
         $del->addVariable("testfalse","||");
         $del->addVariable("testfalserm","rm");
         $del->addVariable("testfalseopt","-Rf");
         $del->addGroup("falsegr",0,0,1);
         $del->get("falsegr")->addVariable("remote");
         $del->get("falsegr")->addVariable("falsegrwc","/*",".*",undef,undef,0,0);
      }

      # define the extras - order does not matter
      $extra->addVariable("knownhosts","","[^\000-\037\177]*",undef,0);

      if ($mode == $Store::AUTH_PWFILE) {
         # password is to be read from file, passwordfile required
         $extra->addVariable("passwordfile","/dev/null","[^\\000]*\.pwfile",1,0,undef,undef,1); # param is to be sandboxed
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

      my $local=$get->get("local")->value();
      my $remote=$get->get("remote")->value();
      my $loc="";
      my $rem="";
      if ($local =~ /^.*\/$/) { 
         $loc="*"
      } 
      if ($remote =~ /^.*\/$/) { 
         $rem="*"
      } 
      # insert some magic
      $get->get("hostgr")->addVariableAfter("remote","remwcmagic",$rem);
      $put->addVariableAfter("local","locwcmagic",$loc);

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
         my $pwfile=$extra->value("passwordfile");
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
         # update password value in both get and put
         $get->get("password")->value($pw);
         $put->get("password")->value($pw);
         $del->get("password")->value($pw);
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
         $get->get("privatekeyfile")->value("/tmp/$randstr");
         $put->get("privatekeyfile")->value("/tmp/$randstr");
         $del->get("privatekeyfile")->value("/tmp/$randstr");
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
# in bytes, use ssh, since scp does not have recursive ls.
sub remoteSize {
   my $self = shift;

   # must be opened to proceed
   if ($self->isOpen()) {
    $self->{mode}=$Store::STORE_MODE_REMOTE_SIZE;
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
         $cmd->addGroup("hostgr",undef,undef,1);
         $cmd->get("hostgr")->addVariable("username",$get->get("username")->value());
         $cmd->get("hostgr")->addVariable("at","\@","\\\@");
         $cmd->get("hostgr")->addVariable("host",$get->get("host")->value(),".*",1,1);
         $cmd->addGroup("lsgr");
         $cmd->get("lsgr")->addVariable("lscmd","ls -lLR");
         $cmd->get("lsgr")->addVariable("remote",$get->get("remote")->value(),"[^\\000]*",0,0,1,0);
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
         $cmd->get("lsgr")->addVariable("remote",$get->get("remote")->value(),"[^\\000]*",0,0,1,0);
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

            # only take entries from lines that are of correct format...
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

      return 1;
   } 

   # call super close - let it handle return result if closed
   return $self->SUPER::close();
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Store::SCP> - Class to define SCP store that perform SCP operations between a local- and remote location.

=cut

=head1 SYNOPSIS

Used in the same way as the Store-class. See the Store-class for more information.

=cut

=head1 DESCRIPTION

Class to perform SCP-operations between a local- and remote location.

It is used in the same way as the Store-class. See the Store-class for more information.

These additional parameters are special to the SCP-class and are to be used with the open()-method:

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

Defines the parameters used on the SCP-store. This methods is inherited from the Store-class. See the Store-class for more
information.

=cut

=head2 open_create()

Creates the necessary StoreProcess-instances used by the SCP-store.

It basically creates StoreProcess::Shell-instances for both GET- and PUT- operations and inputs the necessary Parameter::Group-class
parameters.

This method has overridden a Store-class method. See the Store-class for more information.

=cut

=head2 remoteSize()

Returns the size of the are designated by the "remote"-parameter and its sub-folders.

It uses ssh and the "ls" command to get the size of the remote area and its subfolders.

Returns the size in Bytes. Please see the Store-class for more information on this method.

=cut

=head2 listRemote()

Lists the designated folder on the remote area.

Input parameters is path. If none is given it defaults to the root of the Store area.

It uses ssh and the "ls" command to get the folder listing.

Returns a HASH-reference structure upon success. Please see the Store-class for more information on 
this method.

=cut


