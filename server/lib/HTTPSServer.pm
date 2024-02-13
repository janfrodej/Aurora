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
# HTTPSServer - Package for setting up at HTTPS-server that answers requests based on methods and forks out
#               processes to deal with the requests.
#
package HTTPSServer;

use strict;
use POSIX;
use IO::Socket::SSL;
use HTTP::Daemon;
use HTTP::Daemon::SSL;
use HTTP::Status;
use HTTP::Message;
use Content::JSON;
use Settings;
use Time::HiRes qw(time); # use high-res time for everything
use UUID qw(uuid);
use SysSchema;

our %CHILDS;

sub new {
   my $class=shift;
   my $self={};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # set defaults if not specified - from IO::Socket::INET or from version 6.05 of HTTP::Daemon - IO:Socket::IP.
   if (!exists $pars{Listen}) { $pars{Listen}=5; }
   if (!exists $pars{Timeout}) { $pars{Timeout}=300; }
   if (!exists $pars{Family}) { $pars{Family}=AF_INET6; } # by default force ipv6 and ipv4
   if (!exists $pars{LocalPort}) { $pars{LocalPort}=1000; } # we default to force binding to port 1000 on both ipv4 and ipv6
   # set default from IO::Socket::SSL
   if (!exists $pars{SSL_key_file}) { $pars{SSL_key_file}=undef; }
   if (!exists $pars{SSL_cert_file}) { $pars{SSL_cert_file}=undef; }
   if (!exists $pars{SSL_ca_file}) { $pars{SSL_ca_file}=undef; }
   if (!exists $pars{SSL_verify_mode}) { $pars{SSL_verify_mode}=SSL_VERIFY_NONE; } # this is a server so as default we do not client cert ver.
   # set defaults for HTTPSServer
   if (!exists $pars{converter}) { 
      $self->{converter}=Content::JSON->new(); 
   } else {
      if ($self->{pars}{converter}->isa("Content")) {
         $self->{converter}=$pars{converter};
         delete ($pars{converter});
      } else {
         $self->{converter}=Content::JSON->new();
      }
   }
   if (!exists $pars{servername}) { 
       $self->{servername}="MyServerService"; 
   } else {
      $self->{servername}=$pars{servername};
      delete ($pars{servername});
   }
   if (!exists $pars{settings}) {
      $self->{settings}=Settings->new();
   } else {
      # save settings instance
      if ($pars{settings}->isa("Settings")) {
        $self->{settings}=$pars{settings};
      } else {
         $self->{settings}=Settings->new();  
      }
      delete ($pars{settings});
   }
   if (!exists $pars{log}) {
      $self->{log}=Log->new();
   } else {
      # save settings instance
      if ($pars{log}->isa("Log")) {
        $self->{log}=$pars{log};
      } else {
         $self->{log}=Log->new();  
      }
      delete ($pars{log});
   }
   # get/set syslogger
   if (!exists $pars{syslog}) {
      $pars{syslog}=SystemLogger->new(ident=>"HTTPSServer.pm",priority=>"ERR");
      $pars{syslog}->open();
   } else {
      if (!$pars{syslog}->isa("SystemLogger")) {
         $pars{syslog}=SystemLogger->new(ident=>"HTTPSServer.pm",priority=>"ERR");
         $pars{syslog}->open();
      }
   }
   # save parameters
   $self->{pars}=\%pars;

   $self->{methods}=undef;
   $self->{handler}=undef;

   return $self;
}

sub bind {
   my $self = shift;

   if (!$self->bound()) {
      # attempt to bind
      # We will do a normal http-server connection here and upgrade to ssl on client connect as per
      # recommendation in the IO::Socket::SSL documentation
      my %options=%{$self->{pars}};
      my $srv=HTTP::Daemon->new (%options);
      my $error=$@ || "";

      if (defined $srv) {
         $self->{srv}=$srv;
         # success
         return 1;
      } else {
         # unable to bind
         $self->{error}="Unable to bind to https-server: $error";
         return 0;
      } 
   } else {
      # the server is already bound
      $self->{error}="Unable to bind to https-server since we are already bound";
      return 0;
   }
}

sub bound {
   my $self = shift;

   my $srv=$self->{srv};

   if (defined $srv) {
      # it is bound to interface
      return 1;
   } else {
      # not bound
      return 0;
   }
}

sub addMethod {
   my $self = shift;
   my $method = shift;
   my $func = shift;
   my $desc = shift || "";
   
   if ($method !~ /^[a-zA-Z\/]+$/) {
      # wrong format
      $self->{error}="Unable to add method because the method name is wrongly formatted";
      return 0;
   }

   # register method
   $self->{methods}{$method}{method}=$method;
   $self->{methods}{$method}{func}=$func;
   $self->{methods}{$method}{desc}=$desc;

   return 1;
}

sub removeMethod {
   my $self = shift;
   my $method = shift;

   if ($method !~ /^[a-z\/]+$/) {
      # wrong format
      $self->{error}="Unable to remove method because the method name is wrongly formatted";
      return 0;
   }

   if (exists $self->{methods}{$method}) {
      # remove method
      delete ($self->{methods}{$method});
      return 1;
   } else {
      $self->{error}="Method \"$method\" does not exist and cannot therefore be removed";
      return 0;
   }
}

sub setDBHandler {
   my $self = shift;
   my $handler = shift;

   if (defined $handler) {
      # success - store handler
      $self->{dbhandler}=$handler;
      return 1;
   } else {
      # failure
      $self->{error}="Unable to set DB handler because it is undef";
      return 0;
   }
}

sub setAuthHandler {
   my $self = shift;
   my $handler = shift;

   if (defined $handler) {
      # success - store handler
      $self->{authhandler}=$handler;
      return 1;
   } else {
      # failure
      $self->{error}="Unable to set Authentication-handler because it is undef";
      return 0;
   }
}

sub loop {
   my $self = shift;

   if ($self->bound()) {
      my $srv=$self->{srv};
      my $converter=$self->{converter};
      my $L=$self->{pars}{syslog};
      while (my ($c, $peer_addr) = $srv->accept()) {
         my $pid;
         # fork out a child
         $pid = fork();
         # only do this if its the child process
         if ($pid == 0) {
            $L->log("We are in the child...upgrading to ssl...","DEBUG");
            %CHILDS=();
            # set new fork name
            $0=$0." FORK";
            # we are the child - run db handler
            my $type=ref($converter);
            my $mess=$type->new();
            # set received time
            $mess->value("received",time());
            my $cfg=$self->{settings};
            my $log=$self->{log};
            # upgrade connection to ssl in the child as per recommendation in the IO::Socket::SSL docs
            my $verify=$self->{pars}{SSL_verify_mode};
            my %options=%{$self->{pars}};
            if (!(HTTP::Daemon::ClientConn::SSL->start_SSL($c,SSL_server=>1,%options))) {
               # failed to ssl handshake
               $self->{error}="Unable to perform SSL handshake with client - aborting connection: $IO::Socket::SSL::SSL_ERROR";
               # send message to client
               $mess->value("errstr","Unable to perform SSL handshake: $IO::Socket::SSL::SSL_ERROR");
               $mess->value("err",1);
               $self->message ($c,$mess,426); # upgrade required
               $c->close();
               undef ($c);
               exit(0); 
            }
            $L->log("Upgraded successfully to SSL...","DEBUG");
            # db instance
            my $db;
            # statsaved variable
            my $statsaved=0;
            # continue in this loop as long as child is connected with keep-alive flag   
            while (my $r = $c->get_request()) {
               # reset message hash on each loop start
               $mess->reset();
               # set received time
               $mess->value("received",time());

               # add general header info that are there for all responses
               my %header;
               $header{"Access-Control-Allow-Origin"}=$r->header("Origin")||"*"; # set the same as the request origin, see CORS
               $header{"Access-Control-Allow-Credentials"}=$r->header("Access-Control-Allow-Credentials")||"true"; 

               $L->log ("We got a request - checking...","DEBUG");
               # run db handler
               my $dbhandler=$self->{dbhandler};
               if (defined $dbhandler) {
                  # handler seems ok - run it before proceeding
                  $db=$dbhandler->($mess,$db,$cfg,$log);
                  if (!defined $db) {
                     $self->message ($c,$mess,503,\%header); # service unavailable
                     last;
                  }
               } else {
                  $mess->value("errstr","No database-handler has been defined for the server. Unable to proceed.");
                  $mess->value("err",1);
                  $self->message ($c,$mess,503,\%header); # service unavailable
                  last;
               }
               my $method=$r->method();
               $L->log("Method is: $method","DEBUG");

               # get uri path
               my $path=$r->uri->path();
               # clean path - only allow a-z and slash 
               $path=~s/([a-zA-Z\/]+)/$1/;

               my $query;
               if ($method eq "POST") {
                  # get content
                  my $content=$r->content();
                  # flag as utf-8 (from raw-stream)
	          utf8::decode($content);
                  # convert content
                  if (defined $converter->decode($content)) {
                     $query=$converter->get();
                  } else {
                     # unable to decode
                     $mess->value("errstr","Unable to decode parameters: ".$converter->error());
                     $mess->value("err",1);
                     $self->message ($c,$mess,400,\%header); # Bad Request
                     next;
                  }
               } elsif ($method eq "OPTIONS") {
                  # cors preflight request handling

                  # construct response header fields
                  # based upon preflight request
                  if (defined $r->header("Access-Control-Request-Method")) {
                     $header{"Access-Control-Allow-Methods"}="POST,OPTIONS"; # only allowed HTTP-methods
                  } 
                  if (defined $r->header("Access-Control-Request-Headers")) {
                     # a bit of cheatin' right now
                     $header{"Access-Control-Allow-Headers"}=$r->header("Access-Control-Request-Headers");
                  }

                  # this is just a header request - drop the message body in response
                  $self->message($c,undef,200,\%header); # OK!
                  next;
               } else {
                  $mess->value("errstr","The requested HTTP-method \"$method\" does not exist");
                  $mess->value("err",1);
                  $self->message ($c,$mess,405,\%header); # method not allowed
                  next;
               }

               # ADD SYSTEM-environment variables in query
               $query->{"SYSTEM_REMOTE_ADDR"}=$c->peerhost() || "0.0.0.0";
               $query->{"SYSTEM_REMOTE_PORT"}=$c->peerport() || 0;

               # check for cookie information that might contain
               # session information
               my $cookiestr=$r->header("Cookie");
               my %cookie;
               if (defined $cookiestr) {
                  # remove unwanted characters
                  $cookiestr=~s/[\r\n]//g;
                  # split cookiestr in key->value pairs
                  my @pairs=split(/\;\s+/,$cookiestr);
                  # go through each key->value pair and add to cookie-hash
                  foreach (@pairs) {
                     my $pair=$_;
                     # split match in key and value
                     my ($key,$value) = split (/\=/,$pair);
                     # update cookie-hash
                     $cookie{$key}=$value;
                  }
                  # substitute/add authtype and authstr.
                  # Cookie takes precedence over JSON-params on these two
                  if ((exists $cookie{"authtype"}) && (exists $cookie{"authstr"})) { 
                     $query->{authtype}=$cookie{authtype};
                     $query->{authstr}=$cookie{authstr}; 
                  }
               }

               $L->log ("Checking for Auth Handler and running it","DEBUG");

               my $ahandler=$self->{authhandler};
               my $userid;
               if (defined $ahandler) {
                  # we have a auth handler
                  $userid=$ahandler->($mess,$query,$db,$cfg,$log);
                  $L->log ("Back from running auth handler","DEBUG");
                  if (!$userid) {
                     $L->log ("No userid.","WARNING");
                     # something went wrong - end keep alive loop.
                     $self->message ($c,$mess,401,\%header); # Unauthorized
                     last;
                  }
                  # we have a userid, check if it was requested the generation of an 
                  # UUID
                  if (($query->{authuuid}) && ($query->{authtype} ne "Crumbs")) {
                     # generate an UUID and include in response to user
                     if ($db->connected()) {
                        # get crypt salt for given user
                        my $md=$db->getEntityMetadata($userid);
                        if (!defined $md) {
                           $mess->value("err",1);
                           $mess->value("errstr","Unable to get user metadata when creating UUID: ".$db->error());
                           $self->message ($c,$mess,500,\%header); # Internal Server Error
                           last;
                        }
                        # get user uuid counter
                        my $count=$md->{$SysSchema::MD{crumbsuuid}.".counter"}||0;
                        # we only allow up to 10 unique UUIDs at the same time
                        # so create a circular list in the metadata
                        $count=($count >= 10 ? 1 : $count+1);
                        # get current salt or generate a new one
                        my $salt=$cfg->value("system.auth.crumbs.salt")||"dummy";
                        # set salt to existing value or a new one
                        my %nmd;
                        # generate UUID
                        my $uuid=uuid()||"dummy";
                        # make a crypt version of the uuid
                        my $cuuid=crypt($uuid,$salt)||"dummy";
                        # store base64 encrypted uuid in metadata and save now-time (timeout)
                        my $now=time();
                        $nmd{$SysSchema::MD{crumbsuuid}.".counter"}=$count; # increase counter
                        $nmd{$SysSchema::MD{crumbsuuid}.".$count.uuid"}=$cuuid; # save crypted uuid
                        $nmd{$SysSchema::MD{crumbsuuid}.".$count.created"}=$now; # save created datetime to be able to refuse uuids that are too old
                        $nmd{$SysSchema::MD{crumbsuuid}.".$count.timeout"}=$now; # timeout value
                        # save to AURORA database
                        if ($db->setEntityMetadata($userid,\%nmd)) {
                           # success - return saved uuid (not encoded) to requester
                           $mess->value("authuuid",$uuid);
                        } else {
                           # failure 
                           $mess->value("err",1);
                           $mess->value("errstr","Unable to save created UUID: ".$db->error());
                           $self->message ($c,$mess,500,\%header); # Internal Server Error
                           last;
                        }
                     } else {
                        # undefined dbi-instance
                        $mess->value("err",1);
                        $mess->value("errstr","Unable to contact AURORA database: ".$db->error());
                        $self->message ($c,$mess,503,\%header); # Service Unavailable
                        last;
                     }   
                  }
               } else {
                  $L->log("No authentication handler exists. Cannot authenticate. Connection will be closed","WARNING");
                  $mess->value("errstr","No authentication handler exists. Cannot authenticate. Connection will be closed.");
                  $mess->value("err",1);
                  $self->message ($c,$mess,500,\%header); # Internal server error
                  # exit keep-alive loop if no auth handler is present
                  last;
               }

               # save connection info
               if ((!$statsaved) && (defined $query)) {
                  my $dbi=$db->getDBI();
                  # get values of interest
                  my $now=time();
                  # separate out values
                  my $ua=$dbi->quote($SysSchema::CLEAN{envvalue}->($query->{CLIENT_SYSINFO}{userAgent}));
                  my $client=$dbi->quote($SysSchema::CLEAN{envvalue}->($query->{CLIENT_AGENT}));
                  my $clientver=$dbi->quote($SysSchema::CLEAN{envvalue}->($query->{CLIENT_VERSION}));
                  my $call=$dbi->quote($SysSchema::CLEAN{envvalue}->($path));
                  my $ipaddr=$dbi->quote($SysSchema::CLEAN{envvalue}->($query->{SYSTEM_REMOTE_ADDR}));
                  # insert stat values into statlog
                  if ($db->doSQL("INSERT INTO STATLOG (timedate,query,client,clientver,useragent,ipaddr) ".
                                 "VALUES ($now,$call,$client,$clientver,$ua,$ipaddr)")) {
                     # success, mark it as saved to db and do not do it anymore for this connection
                     $statsaved=1;
                  }
               }

               # set userid in fork process name
               $0=$0." ($userid)";

               $L->log ("Userid is $userid","DEBUG");
               $L->log ("Will attempt to find method to run...","DEBUG");
               $L->log ("Path is: $path","DEBUG");
                   
               # check if method wanted exists
               if (exists $self->{methods}{$path}) {
                  my $func=$self->{methods}{$path}{func};
                  if (defined $query) { 
                     # call function ref for method and input self,http request instance, method-name and query data.
                     $L->log ("Trying to run: $path","DEBUG");
                     # invoke server method and include:
                     # Content-instance, parameter hash, db-instance and userid context
                     if ($func->($mess,$query,$db,$userid,$cfg,$log,$L)) {
                        # success
                        $self->message ($c,$mess,200,\%header); # OK                        
                     } else {
                        # failure of some kind, check the err code
                        if ($mess->value("err") > 1) {
                           # this is a erroralias errorcode, check its location
                           my $code=$mess->value("err");
                           my $loc=$code % 10;
                           if ($loc == 0) {
                              # server internal
                              $self->message ($c,$mess,500,\%header); # Internal server error
                           } elsif ($loc == 1) {
                              # server external
                              $self->message ($c,$mess,503,\%header); # Service unavailable 
                           } elsif ($loc == 2) {
                              # client
                              $self->message ($c,$mess,400,\%header); # Bad Request 
                           } else {
                              # failsafe fallback
                              $self->message ($c,$mess,400,\%header); # Bad Request 
                           }
                        } else {
                           # legacy error message
                           $self->message ($c,$mess,400,\%header); # Bad Request 
                        }
                     }
                     $L->log ("Returned from Server-method: $path","DEBUG");
                     next;
                  }
               } else {
                  $mess->value("errstr","The requested REST-server method \"$path\" does not exist");
                  $mess->value("err",1);
                  $self->message ($c,$mess,404,\%header); # Not found
                  next;
               }
            } # keep-alive get-request loop

            $c->close(); 
            undef ($c); 
            exit(0);
         } elsif (defined $pid) { # end of fork /start of parent
            # parent
            # save pid to CHILDS-list
            $CHILDS{$pid}=undef;
            # reap children
            $SIG{CHLD}=sub { foreach (keys %CHILDS) { my $p=$_; next if defined $CHILDS{$p}; if (waitpid($p,WNOHANG) > 0) { $CHILDS{$p}=$? >> 8; } } };
            # undef c
            undef($c); 
         } # end of parent
      } # while accept/listen loop
      return 1;
   } else {
      # server no bound yet
      $self->{error}="Unable to service requests right now since the server is not bound yet";
      return 0;
   }
}

# message client
sub message {
   my $self = shift;     
   my $c = shift;       # http instance
   my $content = shift; # content-class instance
   my $code = shift || 200;
   my %h=();
   my $incoming = shift || \%h;

   if (!defined $c) {
      $self->{error}="Unable to send message since child http instance is undef";
      return 0;
   }
   # we allow undefined content to signal that we want a header response only
   if ((defined $content) && ((!$content) || (!$content->isa("Content")))) {
      $self->{error}="Invalid Content-instance reference. Cannot send message";
      return 0;
   }

   # add delivered time to content
   if (defined $content) { $content->value("delivered",time()); }

   # add some internal header info that the methods and server do
   # not need to bother about - overwritable by incoming header
   my %internal;
   $internal{"Access-Control-Allow-Credentials"}="false"; # we do not want to exchange cookies and other creds
   $internal{"Cache-Control"}="no-store"; # no caching of responses
   $internal{"Vary"}="Origin"; # Origin header will vary

   # merge incoming header with this header, incoming having precedence
   my %header=(%internal,%{$incoming});

   # ready to send message
   my $h;
   if (defined $content) {
      $h=HTTP::Headers->new(Content_Type=>$content->type()."; charset=utf-8",Server=>$self->{servername},%header);
   } else {
      $h=HTTP::Headers->new(Content_Type=>"text/plain; charset=utf-8",Server=>$self->{servername},%header);
   }
   my $r=HTTP::Response->new($code,"",$h);
   # only add body if content is defined
   # else assume a header-only response
   if (defined $content) {
      # create message body with information to return
      my $m=HTTP::Message->new();
      # convert content to native format
      my $cont=$content->encode();
      # remove utf8-flag (make raw-stream)
      utf8::encode($cont);
      # create content object
      $m->add_content($cont);
      # add object 
      $r->content($m->content());
   }
   # send response
   if (!$c->send_response($r)) {
      $self->{error}="Unable to send server response message: $!";
      return 0;
   }

   return 1;
}

# attributes

sub converter {
   my $self = shift;

   if (@_) {
      # set
      my $converter=shift;
      if ($converter->isa("Content")) {
         $self->{converter}=$converter;
         return $converter;
      } else {
         return undef;
      }
   } else {
      # get
      return $self->{converter};
   }
}

# set or get localaddr
sub localaddr {
   my $self = shift;

   if (@_) {
      my $addr=shift;

      $self->{localaddr}=$addr;

      return $addr;
   } else {
      return $self->{localaddr};
   }
}

sub port {
   my $self = shift;

   if (@_) {
      my $port=shift;

      $self->{port}=$port;

      return $port;
   } else {
      return $self->{port};
   }
}

sub error {
   my $self = shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<HTTPSServer> Class for defining and running a REST-server.

=cut

=head1 SYNOPSIS

   use HTTPSServer;

   # instantiate
   my $srv=HTTPSServer->new(LocalAddr=>"10.0.0.1:1234",Listen=>11,servername=>"My REST-server",SSL_key_file=>"/folder/myprivate.key",SSL_cert_file=>"/folder/mypublic.key");

   # add method to server
   $srv->addMethod("/MyServerMethod",\&MySourceCodeFunctionReference,"Some method comment");

   # set authentication handler
   $srv->setAuthHandler (\&SomeAuthFunction);

   # set database handler
   $srv->setDBHandler (\&someDatabaseFunction);

   # attempt bind
   if (!$srv->bind()) { print "Unable to bind to interface: ".$srv->error()."\n"; exit; }

   # run server loop
   while ($srv->bound()) {
      if (!$srv->loop()) {
         print "Error! ".$srv->error()."\n";
      }
   }

=cut

=head1 DESCRIPTION

Class to define and run a REST-server. It basically have methods to define an authentication handler and a 
database handler. These two should return information that is passed on to all methods in the REST-server 
defined through the addMethod()-method.

The Authentication-handler should return any ID or information that the methods of the server know to use to 
identify the credentials of the one calling the REST-method. For AURORA the handler returns either 0 for not 
authenticated or a number higher than 0 for a user ID from the AURORA database. All the methods in AURORA 
expects such a behaviour and can use that ID to identify who it is by talking to the database.

The database handler is meant to ensure that we have a valid database handler for the AURORA database that 
can be given to the method-function that handles the REST-method call. The database handler is expected to 
return this database instance (DBI-class type) or undef upon failure.

The loop-method of the HTTPSServer-class handles the waiting for connection and forking out of connections 
when a client connects. It also handles upgrading the HTTP-connection to a HTTPS or SSL-based connections. 
All connections to the server needs to be HTTPS-connections.

All calls to the HTTPSServer-class by clients are expected to be POST-type HTTP-data. It does not support 
different HTTP-method, such as GET, DELETE or what not. The type of HTTP-method being performed is instead 
defined by the method name itself, such as /getDatasetMetadata or /getName. This deviates from the 
typical REST-server implementation (where it is normal to use the HTTP-method to signify the verb of 
the resource being manipulated).

=cut

=head1 CONSTRUCTOR

=head2 new()

Constructor. Creates class-instance.

Accepts the following input parameters:

=over

=item

B<converter> Specifies a Content-instance reference that is used as the converter type for the data 
coming into the HTTPS-server. Optional. If not specified defaults to Content::JSON.

=cut

=item

B<Listen> Queue size for listen. See IO::Socket::INET. Optional. Defaults to 5.

=cut

=item

B<LocalPort> Local host port address. See IO::Socket::INET/IO::Socket::IP. Optional. Defaults to "1000".

=cut

=item

B<Log> Specifies a Log-instance reference (see AURORA Log-class). This is used to write events to the 
log if something happens and is also shared by all methods of the HTTPS-server. Optional. Creates a new 
Log-instance if none specified.

=cut

=item

B<servername> Service name of the server that is reported as "Server" in the HTTP-response. Optional. If 
not specified will default to "MyServerService".

=cut

=item

B<settings> Specified a Settings-instance (see AURORA Settings-class). It basically brings the configuration 
settings of the HTTPS-server. This instance is shared by all methods of the HTTPS-server. Optional. Creates 
a new Settings-instance if none specified (or is invalid).

=cut

=item

B<syslog> Specified a SystemLogger-instance (see AURORA SystemLogger-class). It gives a way to syslog 
when something happens for the HTTPS-server. Optional. Creates a new SystemLogger-instance if none specified 
or the reference is invalid.

=cut

=item

B<SSL_ca_file> Specifies the CA for the key set (SSL_key_file and SSL_cert_file). Optional. Defaults to 
undef. See IO::Socket::SSL.

=cut

=item

B<SSL_cert_file> Specifies the public SSL key of the HTTPS-server. Optional. Defaults to undef. See 
IO::Socket::SSL.

=cut

=item

B<SSL_key_file> Specifies the servers private SSL key. Optional. Defaults to undef. See 
IO::Socket::SSL.

=cut

=item

B<SSL_verify_mode> Sets how the certificate of the client is to be checked. Optional. Does not need to be 
changed and defaults to SSL_VERIFY_NONE (no need to verify the client in other words).

=cut

=item

B<Timeout> Sets the HTTPS-server timeout of sockets. Optional. Defaults to 300.

=cut

=back

Besides the parameters given, this method accepts any option from IO::Socket::SSL and/or 
IO::Socket::INET/IO::Socket::IP. Please note that from version 6.05 of HTTP::Daemon, it uses 
the IO::Socket::IP instead of IO::Socket::INET. This is preferred because the HTTP::Daemon then 
supports binding to both ipv4 and ipv6 addresses/interfaces.

By default this module enforces both ipv4 and ipv6 binding by setting the Family-parameter to AF_INET6. 
To bind to both ipv4 and ipv6 at the same time, only set the LocalPort-parameter and not the LocalAddr and/or 
LocalHost-parameters.

Returns an HTTPSServer-instance.

=cut

=head1 METHODS

=head2 bind()

Attempts to bind to the local address specified.

No input parameters accepted.

This method uses the parameters specified to new() and attempts to bind to the local 
interface specified. It will only bind by using a HTTP::Daemon-instance as per 
recommendation in the IO::Socket::SSL documentation. The connection will attempt upgrade 
to SSL as soon as the client has connected.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information 
upon failure.

=cut

=head2 bound()

Returns if the instance is bound to the interface or not.

No input accepted.

Returns 1 if bound, 0 if not.

=cut

=head2 addMethod()

Add a method to the HTTPS-server.

Accepts input in the following order: method-link, function-reference, comment.

The method-link is the absolute path from the server root of the REST-method being added. SCALAR. Required. 
In other words it is the link that the client needs to refer to in order to invoke that REST-method. 
Eg.: /getDatasetMetadata.

The function-reference is a reference to a Perl-function that does all the work of the REST-method. Required.
Eg.: \&MyFunctionReference.

Description is the explanation/comment to the REST-method. SCALAR. Required.

The methods added here are the methods available through the HTTPS-server.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon
failure.

=cut

=head2 removeMethod()

Removes method from the REST-server.

Input is the method-link. See the addMethod() for information on formatting of it.

If the given method-link exists it is removed as a method for the REST-server.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more 
information upon failure.

=cut

=head2 setDBHandler()

Sets the function handling retrieving a functioning database instance.

Accepts input in the following order: function reference to the function handling connecting/
retrieving the database-instance.

The function handling the authentication process is expected to receive: message-instance 
(using Content-class of the HTTPSServer, eg. Content::JSON), database instance (same as 
returned from this method), Settings-instance and Log-instance.

It is up to the user of the HTTPSServer and its methods to define what is 
considered an acceptable database-instance in return. AURORA returns a 
connected instance of the AuroraDB-class (which are passed on to the 
REST-method function).

Returns a database instance upon success, undef upon failure. Please check 
the error()-method for more information upon failure.

=cut

=head2 setAuthHandler()

Sets the function handling the authentication of the REST-server.

Accepts one input: function reference to Perl function handling the 
authentication.

The function handling the authentication process is expected to receive: message-instance 
(using Content-class of the HTTPSServer, eg. Content::JSON), database instance (same as 
returned from the function set in setDBHandler), Settings-instance and Log-instance.

When authenticated the function is expected to return a user id or 
0 upon failure.

Returns > 0 on success, 0 upon failure. Please check the error()-method 
for more information upon failure.

=cut

=head2 loop()

Main loop of the REST-server. 

This method accepts no input.

This method is the main loop of the REST-server. It sits and waits for clients to connect and 
when a connection arrives, it forks out a separate process to handle it.

The separate process for the client-connection immdiately attempts to upgrade it to HTTPS/SSL. 
When such an upgrade has been successful it goes into a HTTP-request loop that will exists for this 
one client-call or if the KeepAlive-flag has been set it will loop until the client disconnects. 

This loop handles running the database-handler and the authentication-handler. If database 
connection and authentication fails the REST-server informs the client and closes the connection 
and the loop.

If database connection and authentication were successful it invokes a REST-method function, if 
the REST-method exists, and passes these parameters to each function: 

- message-instance (Content-class instance of the HTTPS-server)
- Method-parameters as a HASH-reference (after being decoded from the data of the Content-class being used - typically JSON),  Database 
instance (typically AuroraDB-instance)
- User id from the Authentication-handler
- Settings-instance
- Log-instance
- SystemLogger-instance.

The loop receives any potential feedback from the function performing the job of the REST-method 
and sends an answer to the client.

=cut

=head2 message()

Sends a message to the client.

Input accepted: Content-instance and HTTP code.

This method basically handles sending the response back to the calling 
client and with the HTTP code specified. It is called by the 
loop()-method and should not be called directly by the user of this 
HTTPSServer-class.

Returns 1 upon success, 0 upon failure. Please check the error()-method for 
more information upon failure.

=cut

=head2 converter()

Get or set the Content-class being used for messaging between client and server.

If input is specified it is interpreted as a set and the input must be a 
valid Content-class.

Returns the Content-class upon success (also on set), undef upon failure. 
Please check the error()-method for more information upon failure.

=cut

=head2 localaddr()

Get or set the local interface address and port of the REST-server.

If a set, it accepts one input "addr". It must specify the address and 
port (if needed) of the REST-server.

Please note that changing/setting the local interface address does not 
have any effect on already bound HTTPSServer-instances.

Returns the address upon success (also on set), undef upon failure. 
Please check the error()-method for more information upon failure.

=cut

=head2 port()

Get or set the port number being used by the HTTPS-server.

If input is specified it is accepted to be a set and must be 
port number (SCALAR).

Returns the port-number (also on set).

=cut

=head2 error()

Get the last error of this class.

No input accepted.

Returns the last error message or a blank string.

=cut

