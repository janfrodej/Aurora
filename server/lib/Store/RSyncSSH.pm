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
# Store::RSyncSSH: class of a RSyncSSH Store
#
# Uses: RSync-, sshpass- and ssh-utilities.
#
package Store::RSyncSSH;
use parent 'Store';

use strict;
use StoreProcess::Shell;
use Time::Local;
use sectools;

sub probe {
   my $self = shift;

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
         $cmd->addVariable("password",$get->get("password")->value(),".*",0,1);
         $cmd->addVariable("cmd","/usr/bin/ssh");
         my $i=0;
         foreach (split(" ",$get->get("sshoptions")->value())) {
            my $val=$_;
            $i++;
            $cmd->addVariable("sshoption$i",$val);
         }
         $cmd->addGroup("userhost",undef,undef,1);
         $cmd->get("userhost")->addVariable("username",$get->get("username")->value());
         $cmd->get("userhost")->addVariable("at","\@","\\\@");
         $cmd->get("userhost")->addVariable("host",$get->get("host")->value());
         $cmd->addGroup("versiongr");
         $cmd->get("versiongr")->addVariable("rsyncver","rsync --version");
      } else { # key or keyfile
         # define size check command by using privatekey
         $cmd->addVariable("cmd","/usr/bin/ssh");
         $cmd->addVariable("keyoption","-i");
         $cmd->addVariable("keyfile",$get->get("privatekeyfile")->value());
         my $i=0;
         foreach (split(" ",$get->get("sshoptions")->value())) {
            my $val=$_;
            $i++;
            $cmd->addVariable("sshoption$i",$val);
         }
         $cmd->addGroup("userhost",undef,undef,1);
         $cmd->get("userhost")->addVariable("username",$get->get("username")->value());
         $cmd->get("userhost")->addVariable("at","\@","\\\@");
         $cmd->get("userhost")->addVariable("host",$get->get("host")->value());

         $cmd->addGroup("versiongr");
         $cmd->get("versiongr")->addVariable("rsyncver","rsync --version");
      }

      # run calculation - set a sensible timeout, less than global timeout - a little bit
      my $timeout=($self->{pars}{timeout} < 300 ? $self->{pars}{timeout}-30 : 300);
      my $ver=StoreProcess::Shell->new(pars=>$cmd, timeout=>$timeout, wait=>$self->{pars}{wait});
      $ver->execute();
      # wait for result or timeout
      while (($ver->isrunning()) || (!$ver->isemptied())) {
      }
      # get log
      my $log=$ver->getlog();
      $log->resetNext();
      # save log
      $self->{listremotelog}=$log;
      # ensure we were successful
      if ($ver->success()) {
         my $major="N/A";
         my $minor="N/A";
         my $patches="N/A";
         my $variant="";
         my $protocol="N/A";
         my ($mess,$time);
         while (my $l=$log->getNext()) {
            ($mess,$time)=@{$l};

            # only take lines that are of correct format
            if ($mess =~ /rsync\s+version\s+(\d+)\.(\d+)\.(\d+)([^\s]*)\s+protocol\s+version\s+(\d+)/) {
               # we have located version and protocol version
               $major=$1;
               $minor=$2;
               $patches=$3;
               $variant=$4||"";
               $protocol=$5;
               # we have what we need - exit loop
               last;
            }
         }
         # do some checks and adjust the parameters if needed
         if ((($major == 3) && ($minor == 1) && ($patches >= 3)) ||
             (($major == 3) && ($minor > 1)) ||
              ($major > 3)) {
            # this version fulfills requirements - add checksum parameter
            my $get = $self->{getparams};
            my $put = $self->{putparams};

            $get->addVariableBefore("rsyncformatopt","rsynccc","--cc=md5");
            $put->addVariableBefore("rsyncformatopt","rsynccc","--cc=md5");
         }
         return 1;
      } else {
         $self->{error}="Unable to retrieve probe information: ".$ver->error();
         return 0;
      }
   } else {
      $self->{error}="Store is not open. Unable to probe remote host.";
      return 0;
   }
}

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

      # get the authentication mode
      my $mode = $self->{authmode};

      if (($mode == $Store::AUTH_PW) || ($mode == $Store::AUTH_PWFILE)) {
         # the authentication is based on password
         # define parameters for rsync/ssh get
         $get->addVariable("rsynccmd","/usr/bin/rsync");
         # --checksum-choice=md5
         $get->addVariable("rsyncoptions","-vrtO");
         $get->addVariable("rsyncchmod","--chmod=Fugo+r,Dugo+rx");
	 $get->addVariable("rsyncformatopt","--out-format=(\%l)(\%U:\%G)(\%M)(\%C) \%n");
         $get->addVariable("safelinks","--safe-links");
         $get->addVariable("deleteextra","--delete");
         $get->addVariable("appendverify","--append-verify");
         $get->addVariable("rsyncshopt","-e");
         $get->addGroup("rsyncsh");
         $get->get("rsyncsh")->addVariable("sshpass","/usr/bin/sshpass -p");
         if ($mode == $Store::AUTH_PW) {
            # password is required
            $get->get("rsyncsh")->addVariable("password","dummy","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",1,0,1);
         } else {
            # password is not required, read from file
            $get->get("rsyncsh")->addVariable("password","dummy","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",0,1,1);
         }
         $get->get("rsyncsh")->addVariable("sshcmd","/usr/bin/ssh");  
         $get->get("rsyncsh")->addVariable("usernameswitch","-l");
         $get->get("rsyncsh")->addVariable("username","root","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $get->get("rsyncsh")->addVariable("sshoptions","-o PasswordAuthentication=yes -o StrictHostKeyChecking=yes -o PubkeyAcceptedKeyTypes=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa");
         $get->get("rsyncsh")->addVariable("sshportswitch","-p");
         $get->get("rsyncsh")->addVariable("port","22","\\d+",undef,0);

         $get->addGroup("hostgr",undef,undef,1);
         $get->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
         $get->get("hostgr")->addVariable("colon",":","\\:");
         $get->get("hostgr")->addVariable("remote","/dev/null","[^\\000]*",1,0,0,undef,undef,undef,undef,0);
         $get->addVariable("local","/dev/null","[^\\000]*",1,0);

         # define parameters for rsync/ssh put
         $put->addVariable("rsynccmd","/usr/bin/rsync");
         $put->addVariable("rsyncoptions","-vrtO");
	 $put->addVariable("rsyncformatopt","--out-format=(\%l)(\%U:\%G)(\%M)(\%C) \%n");
         $put->addVariable("safelinks","--safe-links");
         $put->addVariable("deleteextra","--delete");
         $put->addVariable("appendverify","--append-verify");
         $put->addVariable("rsyncshopt","-e");
         $put->addGroup("rsyncsh");
         $put->get("rsyncsh")->addVariable("sshpass","/usr/bin/sshpass -p");
         if ($mode == $Store::AUTH_PW) {
            # password is required
            $put->get("rsyncsh")->addVariable("password","dummy","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",1,0,1);
         } else {
            # password is not required, read from file
            $put->get("rsyncsh")->addVariable("password","dummy","[a-zA-Z0-9\\040\\!\\#\\(\\)\\*\\+\\,\\.\\=\\?\\@\\[\\]\\{\\}\\_\\-]{0,256}",0,1,1);
         }
         $put->get("rsyncsh")->addVariable("sshcmd","/usr/bin/ssh");
         $put->get("rsyncsh")->addVariable("usernameswitch","-l");
         $put->get("rsyncsh")->addVariable("username","root","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $put->get("rsyncsh")->addVariable("sshoptions","-o PasswordAuthentication=yes -o StrictHostKeyChecking=yes -o PubkeyAcceptedKeyTypes=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa");
         $put->get("rsyncsh")->addVariable("sshportswitch","-p");
         $put->get("rsyncsh")->addVariable("port","22","\\d+",undef,0);

         $put->add("local","/dev/null","[^\\000]*",1,0);

         $put->addGroup("hostgr",undef,undef,1);         
         $put->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
         $put->get("hostgr")->addVariable("colon",":","\\:");
         $put->get("hostgr")->addVariable("remote","/dev/null","[^\\000]*",1,0,0,undef,undef,undef,undef,0);

         # define parameters for rsync/ssh del/delete
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
         $del->addVariable("sshoption1","-o");
         $del->addVariable("sshoption2","PasswordAuthentication=yes");
         $del->addVariable("sshoption3","-o");
         $del->addVariable("sshoption4","StrictHostKeyChecking=yes");
         $del->addVariable("sshoption5","-o");
         $del->addVariable("sshoption6","PubkeyAcceptedKeyTypes=+ssh-rsa");
         $del->addVariable("sshoption7","-o");
         $del->addVariable("sshoption8","PubkeyAcceptedAlgorithms=+ssh-rsa");
         $del->addVariable("sshportswitch","-p",".*");
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
      } else { # key or keyfile
         # the authentication is based on key/identity
         # define parameters for rsync/ssh get
         $get->addVariable("rsynccmd","/usr/bin/rsync");
         $get->addVariable("rsyncoptions","-vrtO");
         $get->addVariable("rsyncchmod","--chmod=Fugo+r,Dugo+rx");
	 $get->addVariable("rsyncformatopt","--out-format=(\%l)(\%U:\%G)(\%M)(\%C) \%n");
         $get->addVariable("safelinks","--safe-links");
         $get->addVariable("deleteextra","--delete");
         $get->addVariable("appendverify","--append-verify");
         $get->addVariable("rsyncshopt","-e");
         $get->addGroup("rsyncsh");
         $get->get("rsyncsh")->addVariable("sshcmd","/usr/bin/ssh");  
         $get->get("rsyncsh")->addVariable("usernameswitch","-l");
         $get->get("rsyncsh")->addVariable("username","root","[a-zA-Z0-9\\_\\-]{1,32}",1,0,1);
         $get->get("rsyncsh")->addVariable("certswitch","-i");
         if ($mode == $Store::AUTH_KEYFILE) {
            # keyfile required
            $get->get("rsyncsh")->addVariable("privatekeyfile","","[^\\000]+\.keyfile",1,0,undef,undef,1); # this param is to be sandboxed
         } else {
            # keyfile is not required, written from param
            $get->get("rsyncsh")->addVariable("privatekeyfile","","[^\\000]*\.keyfile");
         }
         $get->get("rsyncsh")->addVariable("sshoptions","-o PasswordAuthentication=yes -o StrictHostKeyChecking=yes -o PubkeyAcceptedKeyTypes=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa");
         $get->get("rsyncsh")->addVariable("sshportswitch","-p");
         $get->get("rsyncsh")->addVariable("port","22","\\d+",undef,0);

         $get->addGroup("hostgr",undef,undef,1);
         $get->get("hostgr")->addVariable("host","localhost","[a-zA-Z0-9\\:\\.\\-]{1,63}",1,0);
         $get->get("hostgr")->addVariable("colon",":","\\:");
         $get->get("hostgr")->addVariable("remote","/dev/null","[^\\000]*",1,0,0,undef,undef,undef,undef,0);

         $get->addVariable("local","/dev/null","[^\\000]*",1,0);

         # define parameters for rsync/ssh put
         $put->addVariable("rsynccmd","/usr/bin/rsync");
         $put->addVariable("rsyncoptions","-vrtO");
	 $put->addVariable("rsyncformatopt","--out-format=(\%l)(\%U:\%G)(\%M)(\%C) \%n");
         $put->addVariable("safelinks","--safe-links");
         $put->addVariable("deleteextra","--delete");
         $put->addVariable("appendverify","--append-verify");
         $put->addVariable("rsyncshopt","-e");
         $put->addGroup("rsyncsh");
         $put->get("rsyncsh")->addVariable("sshcmd","/usr/bin/ssh");
         $put->get("rsyncsh")->addVariable("usernameswitch","-l");
         $put->get("rsyncsh")->addVariable("username","root","[a-zA-Z0-9\\_\\-]{1,32}",1,0);
         $put->get("rsyncsh")->addVariable("certswitch","-i");
         if ($mode == $Store::AUTH_KEYFILE) {
            # keyfile required
            $put->get("rsyncsh")->addVariable("privatekeyfile","","[^\\000]+\.keyfile",1,0,undef,undef,1); # param is to be sandboxed
         } else {
            # keyfile is not required, written from param
            $put->get("rsyncsh")->addVariable("privatekeyfile","","[^\\000]*\.keyfile");
         }
         $put->get("rsyncsh")->addVariable("sshoptions","-o PasswordAuthentication=yes -o StrictHostKeyChecking=yes -o PubkeyAcceptedKeyTypes=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa");
         $put->get("rsyncsh")->addVariable("sshportswitch","-p");
         $put->get("rsyncsh")->addVariable("port","22","\\d+",undef,0);

         $put->addVariable("local","/dev/null","[^\\000]*",1,0);

         $put->addGroup("hostgr",undef,undef,1);
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
            $del->addVariable("privatekeyfile","","[^\\000]*\.keyfile");
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
         $extra->addVariable("passwordfile","/dev/null","[^\\000]+\.pwfile",1,0,1,undef,1); # param is to be sandboxed
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
         my $curopt=$get->get("sshoptions")->value();
         my $opt=$curopt." -o UserKnownHostsFile=/tmp/$randstr";
         # set it in get and put
         $self->setParam("sshoptions",$opt);
         # delete needs to add two variables
         $self->{delparams}->addVariableAfter("sshoption8","sshoption9","-o");
         $self->{delparams}->addVariableAfter("sshoption9","sshoption10","UserKnownHostsFile=/tmp/$randstr");
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

         # update password value in get, put and delete
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
         # set it in get, put and delete
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
# in bytes
sub remoteSize {
   my $self = shift;

   # must be opened to proceed
   if ($self->isOpen()) {
      $self->{mode}=$Store::STORE_MODE_REMOTE_SIZE;
      # get a copy of the getparams, so we do not change the original
      my $cmd=$self->{getparams}->clone();
      # remove rsynccc, checksum-choice, which we do not use
      $cmd->remove("rsynccc");
      my $optorg=$cmd->get("rsyncoptions")->value();
      # add dryrun option to calculate size
      my $optnew=$optorg;
      if ($optnew !~ /^\-n(.*)$/) { $optnew=~s/^(\-)(.*)$/$1n$2/; }
      $cmd->get("rsyncoptions")->value($optnew);
      # run calculation - set a sensible timeout, less than global timeout - a little bit
      my $timeout=($self->{pars}{timeout} < 300 ? $self->{pars}{timeout}-30 : 300);
      my $get=StoreProcess::Shell->new(pars=>$cmd, timeout=>$timeout, wait=>$self->{pars}{wait});
      $get->execute();
      # wait for result or timeout
      while (($get->isrunning()) || (!$get->isemptied())) {
      }
      # revert to original rsyncoptions
      $cmd->get("rsyncoptions")->value($optorg);
      # get log
      my $log=$get->getlog();
      # save log
      $self->{sizeremotelog}=$log;
      # ensure we were successful
      if ($get->success()) {
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
         $self->{error}="Unable to get remote size: $msg";
         return undef;
      }
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
         $cmd->addVariable("password",$get->get("password")->value(),".*",0,1);
         $cmd->addVariable("cmd","/usr/bin/ssh");
         my $i=0;
         foreach (split(" ",$get->get("sshoptions")->value())) {
            my $val=$_;
            $i++;
            $cmd->addVariable("sshoption$i",$val);
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
         my $i=0;
         foreach (split(" ",$get->get("sshoptions")->value())) {
            my $val=$_;
            $i++;
            $cmd->addVariable("sshoption$i",$val);
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

            # only take lines that are of correct format
            if ($mess =~ /^([-dl]){1}[^\s\t]+[\s\t]+\d+[\s\t]+\d+[\s\t]+\d+[\s\t]+(\d+)[\s\t]+(\d{8})[\s\t]+(\d{6})[\s\t]{1}(.+)[\r\n]*$/) {
               # save to structure
               my $type=$1;
               $type=(uc($type) eq "D" ? "D" : (uc($type) eq "L" ? "L" : "F")); # either directory, link or file type 
               my $size=$2;
               my $dt=$3.$4;
               $dt=$Schema::CLEAN{datetimestr}->($dt);
               my $name=$5;
               if ($name =~ /^[\.]{1,2}$/) { next; } # we are not interested in . and ..
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

C<Store::RSyncSSH> - Class to define RSyncSSH store that perform RSync operations between a local- and remote location through 
a SSH-connection.

=cut

=head1 SYNOPSIS

Used in the same way as the Store-class. See the Store-class for more information.

=cut

=head1 DESCRIPTION

Class to perform RSync operations between a local- and remote location through a SSH-connection.

These additional parameters are special to the RSyncSSH-class and are to be used with the open()-method:

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
AUTH_KEY. The key specified here is in the same format as in the .ssh/id_rsa-file. The parameters is written 
to a random file in /tmp that is used as the privatekey/identity file when connecting through SSH to the remote 
location. When the DESTROY()-method is called it unlinks the temporary privatekey-file.

=cut

=back

It is used in the same way as the Store-class. See the Store-class for more information.

=cut

=head1 CONSTRUCTOR

=head2 new()

Constructor is inherited from the Store-class. See the Store-class for more information.

It uses the inherited new()-method.

It returns the instantiated class.

=cut

=head1 METHODS

=head2 open_define()

Defines the parameters used on the RSyncSSH-store. This methods is inherited from the Store-class. See the Store-class for more
information.

=cut

=head2 open_create()

Creates the necessary StoreProcess-instances used by the RSyncSSH-store.

It basically creates StoreProcess::Shell-instances for GET-, PUT- and DEL-operations and inputs the necessary Parameter::Group-class
parameters.

This method has overridden a Store-class method. See the Store-class for more information.

=cut

=head2 remoteSize()

Returns the size of the area designated by the remote-parameter to the open()-method.

The size is calculated by using ssh and then running the "ls" command recursively.

It returns the size in Bytes. Please see the Store-class for more information on this method.

=cut

=head2 listRemote()

Lists a designated remote folder.

Input parameter is path. If none given it defaults to the root of the store area.

The method uses ssh and the "ls" command to list the folder in the remote area.

Returns a HASH-reference structure upon success. Please see the Store-class for more information on this method.

=cut

=head2 close()

Overrides the close()-method of the placeholder Store-class.

Unlinks temporary files used when store is open. Also calls the placeholder classes close()-method.

Always returns 1.

=cut
