#!/usr/bin/perl -w
# Copyright (C) 2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
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
use strict;

use CGI;
use CGI::Carp qw(fatalsToBrowser);
use YAML::XS qw(Load);
use Net::OAuth2::Profile::WebServer;
use JSON::WebToken;
use Bytes::Random::Secure;
use MIME::Base64;

my $AUTHTYPE="OAuthAccessToken";

# get settings
my $domain = $ENV{"SERVER_NAME"} || "";
if (!open (FH,"/web/virtualhosts/$domain/settings/feide.yaml")) {
   die "ERROR! Unable to read settings file for FEIDE authentication: $!";
}
# read file
my $yaml=join("",<FH>);
# close file
eval { close (FH); };
# decode YAML content
my $cfg=yaml_decode($yaml);
if (!$cfg) { die; }

# set UTF-8 encoding on STDIN/STDOUT
binmode(STDIN, ':encoding(UTF-8)');
binmode(STDOUT, ':encoding(UTF-8)');

# instantiate CGI
my $c = CGI->new();
print "Content-Type: text;\r\n\r\nCGI error $!/$@" and exit unless $c;

if ((defined $c->param("state")) && (defined $c->param("code"))) {
   # possible return from authorization
   my $ostate=$c->param("state") || "";
   my $code=$c->param("code") || "";

   # compare state with saved state
#   my $cstate=$data{state} || "";

#   if (($cstate ne "") && ($ostate eq $cstate)) {
   if (1) {
      # this is the return from an authorization - lets attempt to get access token.
      # setup oauth access token request
      my $auth = Net::OAuth2::Profile::WebServer->new
         ( name           => 'FEIDE 2.0',
           client_id      => $cfg->{"oauth.clientid"},
           client_secret  => $cfg->{"oauth.clientsecret"},
           site           => $cfg->{"oauth.site"},
           scope          => $cfg->{"oauth.scope"},
           authorize_path    => $cfg->{"oauth.authorizepath"},
           access_token_path => $cfg->{"oauth.tokenpath"},
           redirect_uri => $cfg->{"oauth.redirecturi"},
         );

      # attempt to get an access token
      my %info;
      $info{code}=$code;
#      $info{state}=$cstate;
      $info{state}=$ostate;

      my $atoken;
      $atoken=$auth->get_access_token($info{code});
      my $token=$atoken->{NOA_access_token};
      my $expire=$atoken->{NOA_expires_at} || 0;
      my $idtoken=$atoken->{NOA_attr}{id_token} || "";

      # reset cgi params
      $c->delete("state");
      $c->delete("code");

      # message variable
      my $feidemsg="";
      my $feideerr=1;
      my $uuid="";

      # call AURORA REST-server with token and return a crumb uuid
      my $r=HTTPSClient::Aurora->new(Host=>$cfg->{"aurora.rest.server"},%{$cfg->{"aurora.rest.sslparams"}});
      if (!$r->connect()) {
         $feideerr=2;
         $feidemsg="ERROR! ".$c->error()."\n";
      } else {
         # call doAuth REST-method and receive a crumb uuid if successful
         my %params;
         $params{"authuuid"}=1; # get uuid to replace FEIDE token
         $params{"ip"}=$ENV{"REMOTE_ADDR"}; # add real ip of caller 
         $params{"port"}=$ENV{"REMOTE_PORT"}; # add real port of caller 
         my %resp;
         $r->doAuth(\%resp,authtype=>$AUTHTYPE,authstr=>$token,%params);
         $uuid="";
         if ($resp{err} != 0) {
            $feideerr=2;
            $feidemsg="ERROR! ".$resp{errstr}."\n";
         } else {
            # successfully called REST-server - get crumb uuid
            $uuid = $resp{authuuid} || "";
         }
      }

      # get current cookie state
      my %vals=$c->cookie($cfg->{"www.cookiename"});

      # check cookie vals for sqlstruct. If that is broken, reset the cookie
      # because we are dealing with an old cookie format
      if ((exists $vals{sqlstruct}) && ($vals{sqlstruct} eq "[\"AND\"")) {
         # reset all values in the whole cookie - it is faulty
         %vals=();
      }

      # store crumb uuid in cookie, it needs to be base64 encoded for this to work for perl cgi->cookie (for all values in the cookie)
      $vals{authstr}=encode_base64($uuid,"");
      # update cookie with a newer timestamp and add all old values
      my $cookie=$c->cookie(-name=>$cfg->{"www.cookiename"},-expire=>$cfg->{"www.cookie.timeout"},-domain=>$ENV{SERVER_NAME},-secure=>1,-path=>"/",-samesite=>"Lax",-value=>\%vals);

      # check if we had an error or not
      if ($feideerr > 1) {
         # we had an error - do not redirect
         print $c->header(-cookie=>$cookie);
         print $c->start_html();
         print "ERROR! $feidemsg\n";
         print $c->end_html();
      } else {
         # no error, redirect with cookie to AURORA login page
         # nothing more needs to be done as login is contained in cookie
         print $c->redirect(-uri=>$cfg->{"www.base"},-cookie=>$cookie);
      }
   }
   exit;
} 

# we have no authorization, no token or token is not valid anymore

# make a random state
my $state=randstr();

# save state 
#$data{state}=$state;

# setup oauth authorization request
my $auth = Net::OAuth2::Profile::WebServer->new
   ( name              => 'FEIDE 2.0',
     client_id         => $cfg->{"oauth.clientid"},
     client_secret     => $cfg->{"oauth.clientsecret"},
     site              => $cfg->{"oauth.site"},
     scope             => $cfg->{"oauth.scope"},
     state             => $state,
     authorize_path    => $cfg->{"oauth.authorizepath"},
     access_token_path => $cfg->{"oauth.tokenpath"},
     redirect_uri      => $cfg->{"oauth.redirecturi"},
     login_hint	       => 'feide|all',
   );

# authorize user
print $c->redirect(-uri=>$auth->authorize());

# create a random string of n chars
sub randstr {
   # size of random string
   my $size = shift || 32;

   # string to contain the random chars
   my $str="";

   # generate random string
   my $r=Bytes::Random::Secure->new(Bits=>64, NonBlocking=>1);
   $str = $r->string_from("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",$size);
 
   # taint check the values
   $str=~/([a-zA-Z0-9]+)/;
   $str=$1;

   return $str;
}

sub yaml_decode {
   my $content=shift || "";

    # try to convert content from YAML
   my $err;
   my $h;
   eval { $h=Load($content); };
   $@ =~ /nefarious/;
   $err = $@;

   if ($err eq "") {
      # decoding was a success - return structure it was converted into
      return $h
   } else {
      # an error occured
      print "ERROR! Unable to convert content from YAML: $err.\n";
      return undef;
   }
}

#
# HTTPSClient: package to perform transactions with a HTTPS Server
#
package HTTPSClient::Aurora;
use strict;
use IO::Socket::SSL;
use Net::HTTP;
use Net::HTTPS;
use JSON;
use POSIX qw (strftime);

# constructor
sub new {
   # instantiate
   my $self = {};
   my $class = shift;
   bless ($self,$class);

   # get pars
   my %pars=@_;

   # set defaults if not specified - these are for Net::HTTPS
   if (!$pars{KeepAlive}) { $pars{KeepAlive}=1; }
   # these are for IO::Socket::SSL
   if (!$pars{SSL_hostname}) { my $h=$pars{Host}; $h=~s/^(.*)\:\d+$/$1/; $pars{SSL_hostname}=$h; }
   if (!$pars{SSL_key_file}) { $pars{SSL_key_file}=undef; }
   if (!$pars{SSL_cert_file}) { $pars{SSL_cert_file}=undef; }
   if (!$pars{SSL_ca_file}) { $pars{SSL_ca_file}=undef; }
   if (!$pars{SSL_verify_mode}) { $pars{SSL_verify_mode}=undef; } # standard client setting to verify server
   # HTTPSClients parameters - all lower case
   if (!$pars{useragent}) { 
      $self->{useragent}="HTTPSClient/1.0"; 
   } else {
      $self->{useragent}=$self->{pars}{useragent};
      delete ($self->{pars}{useragent});
   }

   # save parameters
   $self->{pars}=\%pars;

   return $self;
}

### METHODS

# connect to a server
sub connect {
   my $self = shift;

   if (!$self->connected()) {
      my %options=%{$self->{pars}};
      # connect as a HTTP-connection first, then upgrade to SSL
      my $client=Net::HTTP->new(%options);
      my $error=$@ || "";
   
      if (defined $client) {
         $self->{client}=$client;
         if ($self->connected()) {
            # upgrade to SSL
            if (!(Net::HTTPS->start_SSL($client,SSL_server=>0,%options))) {
               $self->{error}="Failed to SSL handshake with server: $IO::Socket::SSL::SSL_ERROR";
               return 0;
            }
            $self->{client}=$client;

            return 1;
         } else {
             $self->{error}="We have a client-instance, but we are not connected to any server: $error"; 
             return 0;
         }
      } else {
         $self->{error}="Could not create any client-instance or connect: $error";
         return 0;
      }   
   } else {
      $self->{error}="Already connected. Cannot connect again";
      return 0;
   }
}

# check if connected
sub connected {
   my $self = shift;

   my $client=$self->{client};

   # check IO::Socket connected method
   if ((defined $client) && ($client->connected())) {
      # the client instance exists and it is connected
      return 1;
   } else {
      return 0;
   }
}

# disconnect from server
sub disconnect {
   my $self = shift;

   if ($self->connected()) {
      $self->{client}=undef; 
      return 1;
   } else {
      $self->{error}="Cannot disconnect since we are disconnected already";
      return 0;
   }
}

# execute specified method server using 
# hash of parameters (key/value pairs)
sub do {

   sub decode_response {
      my $self = shift;

      # fetch body from object
      my $body = $self->{body} || "";

      # adding utf8-flag (from raw-stream)
      utf8::decode($body);

      # convert body
      if (!(defined $self->decode($body))) {
         $self->{error}="Failed decoding JSON server response: ".$self->error();
         return undef;
      }

      # set content
      my $content=$self->{content};

      my %response;
      %response = %{$content};
      return %response; 
   }

   my $self = shift;
   my $vmethod = shift || "/status/alive"; # default to some method
   my $hmethod = shift || "POST";  # HTTP method
   $hmethod=uc($hmethod);
   # ptr to hash with return value
   my $return = shift;  # hash ptr to return data to
   my %params = @_;     # hash with key/values

   # we do not have a success yet...
   $self->{success}=0;

   # ensure we are connected
   if (!$self->connected()) {
      $self->{error}="Not connected to server, unable to perform do-method";
      return 0;
   }
   # remove potential slash at beginning
   $vmethod=~s/^\/(.*)$/$1/;

   my $client = $self->{client};

   # main do-method - create header
   my %header=(
               "User-Agent"   => "AURORA restcmd",
               "Content-Type" => "application/json; charset=utf-8",
               "Accept"       => "application/json",
              );

   # do the method-request
   my $content;
   if ($hmethod eq "GET") {
      # create string from parameters
      my $str="";
      foreach (keys %params) {
         my $name=$_;
         $str.="&$name=".$params{$name};
      }
      # fix str if not empty
      if (length($str) > 0) {
         # replace first & with ?
         $str=~s/^(\&)(.*)$/\?$2/;
      }
      $client->write_request(GET=>"/$vmethod$str",%header,$content);
   } elsif ($hmethod eq "POST") {
      # encode content into native format
      $content=$self->encode(\%params);
      if (defined $content) {
         # removing utf8-flag (raw stream)
         utf8::encode($content);
         # success
         $client->write_request(POST=>"/$vmethod",%header,$content);
      } else {
         # failure
         $self->{error}="Failed to encode parameters to JSON: ".$self->error();
         return 0;
      }
   } else {
      # unsupported method
      $self->{error}="Unsupported server method \"$hmethod\" specified";
      return 0;
   }

   # get response
   my (%code,$mess,%h) = $client->read_response_headers();

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
      my $n = $client->read_entity_body($buf, 1024);
      if (!defined $n) { $self->{error}="Reading result from $vmethod-method failed ($!)!"; return 0; }
      last unless $n;
      $body.=$buf;
   }

   $self->{body}=$body;

   my %resp;
   # decode the body response
   if (!(%resp=decode_response($self))) {
      return 0;
   }

   # set return hash
   %{$return}=%resp;

   # we expect code 200 for this to be successful
   if (exists $code{200}) { 
      $self->{error}="";
      return 1;
   } elsif (exists $code{417}) {
      # typical fatal message - get status message
      my $msg=$resp{"errstr"} || "";
      $self->{error}=$msg;
      return 0;
   } else {
      # errors of another kind - concatenate...
      foreach (keys %code) {
         $self->{error}.=$code{$_};
      }
      return 0;
   }
}


# takes care of connecting to
# server and handling errors in the do-call
# lazydo only supports POST methods
sub lazydo {
   my $self = shift;
   my $vmethod = shift;
   my $response = shift;
   my %params = @_;

   # ensure we are connected
   if (!$self->connected()) {
      # not connected - try to connect
      if (!$self->connect()) {
         # we failed to connect - then we also fail to lazydo
         $self->{error}="Failed to connect to https-server: ".$self->error();
         return 0;
      }
   }

   # by this point we are connected - try to do method
   if ($self->do($vmethod,"POST",$response,%params)) {
      # success
      return 1;
   } else {
      $self->{error}=$self->error();
      return 0;
   }
}

sub encode {
   my $self = shift;
   my $content=shift || $self->{content};

    # try to convert content into JSON
   my $err;
   my $j;
   local $@;
   eval { my $a=JSON->new(); $j=$a->encode ($content); };
   $@ =~ /nefarious/ and $err = $@;

   if (!defined $err) {
      # encoding was a success - return JSON
      return $j;
   } else {
      # an error occured
      $self->{error}="Unable to convert content into JSON: $@.";
      return undef;
   }
}

sub decode {
   my $self = shift;
   my $content=shift || "";

   my $err;
   my $h;
   local $@;
   eval { $a=JSON->new(); $h=$a->decode ($content); };
   $@ =~ /nefarious/ and $err=$@;

   if (!defined $err) {
      # decoding was a success - return structure it was converted into and set instance content
      $self->{content}=$h;
      # in this class the return is always blank
      return "";
   } else {
      # an error occured
      $self->{error}="Unable to decode content of type JSON: $@";
      return undef;
   }
}

# get last error message
sub error {
   my $self = shift;

   return $self->{error} || "";
}

# DESTROY and autoloader is all we need to call methods on the REST-server

sub DESTROY {
   my $self = shift;
}

sub AUTOLOAD {
   my $self = shift;
   my $response = shift;
   my %options = @_;

   our $AUTOLOAD;
   # get method name
   (my $method=$AUTOLOAD) =~ s/^.*://;

   # call method by using lazydo
   if ($self->lazydo ($method,$response,%options)) {
      # success
      return 1;
   } else {
      # failure
      return 0;
   }
}

1;
