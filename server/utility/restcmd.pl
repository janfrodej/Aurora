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
use strict;
use Data::Dumper;

# process parameter input
my %opts;
my $pos=-1;
my $valpos=-1;
foreach (@ARGV) {
   my $arg=$_;
   $arg=~s/^\s+(.*)\s+$/$1/;
   $pos++;

   if ($arg =~ /^\-(\w+)$/) {
      my $lcarg=lc($1);
      $opts{$lcarg}=(defined $ARGV[$pos+1] ? $ARGV[$pos+1] : "");
      $valpos=$pos+1;
   } elsif ($pos != $valpos) {
      # this is interpreted as the REST-call and its arguments
      my @r;
      push @r,$ARGV[$pos];
      for (my $i=$pos+1; $i < @ARGV; $i++) {
         push @r,$ARGV[$i];
      }
      $opts{r}=\@r;
      last;
   }
}

if (@ARGV == 0) {
   print "$0 - Call any AURORA REST-server method from the command line.\n";
   print "\n";
   print "Syntax:\n";
   print "   $0 [OPT] [OPTVALUE] [REST-CALL] [PARAMETERS]\n";
   print "\n";
   print "The following options are available:\n\n";
   print "   -t Sets the authtype to use (AuroraID, OAuthAccessToken etc.). Defaults to AuroraID.\n";
   print "   -s Sets the authstr to use.\n";
   print "   -h Sets the hostname of the REST-server\n";
   print "   -o Sets the port number of the REST-server. Defaults to 9393\n";
   print "   -k Sets the path and name of the private key that $0 uses.\n";
   print "   -p Sets the path and name of the public key that $0 uses.\n";
   print "   -c Sets the path and name of the CA that $0 uses.\n";
   print "   -v Sets verbose mode on the utility. Value that evaluates to true or false. Both JSON and Dumper-output of input and output data\n\n";
   exit(0);
}

if (!exists $opts{t}) { $opts{t}="AuroraID"; }
if (!exists $opts{s}) { print "ERROR! Missing authstr-parameter\n"; exit(1); }
if (!exists $opts{h}) { print "ERROR! Missing host-parameter\n"; exit(1); }
if (!exists $opts{o}) { $opts{o}=9393; }
if (!exists $opts{k}) { print "ERROR! Missing private key-parameter\n"; exit(1); }
if (!exists $opts{p}) { print "ERROR! Missing public key-parameter\n"; exit(1); }
if (!exists $opts{c}) { print "ERROR! Missing CA-parameter\n"; exit(1); }
if (!exists $opts{v}) { $opts{v}=0; }

my $c=HTTPSClient::Aurora->new( Host=>$opts{h}.":".$opts{o},
#                                SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_PEER,
                                SSL_verifycn_name => $opts{h},
                                SSL_verifycn_scheme => 'http',
                                SSL_key_file=>$opts{k},
                                SSL_cert_file=>$opts{p},
                                SSL_ca_file=>$opts{c},
                               );
if (!$c->connect()) {
   die "Error! ".$c->error()."\n";
}

# go through REST-call and its arguments.
my $method="@{$opts{r}}";
$method=~s/^([^\s]+)\s+(.*)$/$1/;
my $argstr=$2;

if ($opts{v}) {
   print "METHOD: $method\n";
   print "ARGSTR: $argstr\n";
}

# convert string from json to hash
my $result=$c->decode($argstr);
if (!defined $result) {
   print "ERROR decoding arguments: ".$c->error()."\n";   
   exit(1);
} 
# lets break object boundary and get result...
my $args=$c->{content};

if ($opts{v}) {
   print "ARGS: ".Dumper($args);
}

# call REST-method
my %resp;
$c->$method(\%resp,authtype=>$opts{t},authstr=>$opts{s},%{$args});

# convert response to json and print
my $json=$c->encode(\%resp);
# its been decoded upon reception, encode again by removing utf8-flag
utf8::encode($json);

if ($opts{v}) {
   print "\n\n$method: ".Dumper(\%resp)."\n";
}

print "$json";

if ($resp{err} == 0) {
   exit(0);
} else {
   exit(1);
}

1;

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
