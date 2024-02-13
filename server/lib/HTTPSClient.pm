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
# HTTPSClient: package to perform transactions with a HTTPS Server
#
package HTTPSClient;

use strict;
use IO::Socket::SSL;
use Net::HTTP;
use Net::HTTPS;
use Content::JSON;
use POSIX qw (strftime);
use AuroraVersion;

# constructor
sub new {
   # instantiate
   my $self = {};
   my $class = shift;
   bless ($self,$class);

   # get pars
   my %pars=@_;

   # set defaults if not specified - these are for Net::HTTPS
   if (!exists $pars{KeepAlive}) { $pars{KeepAlive}=1; }
   # these are for IO::Socket::SSL
   if (!exists $pars{SSL_hostname}) { my $h=$pars{Host}; $h=~s/^(.*)\:\d+$/$1/; $pars{SSL_hostname}=$h; }
   if (!exists $pars{SSL_key_file}) { $pars{SSL_key_file}=undef; }
   if (!exists $pars{SSL_cert_file}) { $pars{SSL_cert_file}=undef; }
   if (!exists $pars{SSL_ca_file}) { $pars{SSL_ca_file}=undef; }
   if (!exists $pars{SSL_verify_mode}) { $pars{SSL_verify_mode}=undef; } # standard client setting to verify server
   # HTTPSClients parameters - all lower case
   if (!exists $pars{useragent}) { 
      $self->{useragent}="HTTPSClient/1.0"; 
   } else {
      $self->{useragent}=$self->{pars}{useragent};
      delete ($self->{pars}{useragent});
   }
   if (!exists $pars{converter}) { 
      $self->{converter}=Content::JSON->new(); 
   } else {
      if ($pars{converter}->isa("Content")) {
         $self->{converter}=$pars{converter};
         delete ($pars{converter});
      } else {
         $self->{converter}=Content::JSON->new();
      }
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

      # convert body from Content-class format
      my $converter=$self->{converter};
      if (!(defined $converter->decode($body))) {
         $self->{error}="Failed decoding ".$converter->type()." server response: ".$converter->error();
         return undef;
      }

      # set content
      my $content=$converter->get();

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

   # get content converter
   my $converter=$self->{converter};

   # main do-method - create header
   my $useragent=$self->{useragent} || "";
   my %header=(
               "User-Agent"   => $useragent,
               "Content-Type" => $converter->type()."; charset=utf-8",
               "Accept"       => $converter->type(),
              );

   # add some env variables to send with the request
   $params{"CLIENT_AGENT"}="Perl CGI Aurora Web-Client";
   $params{"CLIENT_VERSION"}=$AuroraVersion::VERSION;
   $params{"CLIENT_USERAGENT"}=$useragent;

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
      $converter->set(\%params);
      $content=$converter->encode();
      if (defined $content) {
         # removing utf8-flag (raw stream)
         utf8::encode($content);
         # success
         $client->write_request(POST=>"/$vmethod",%header,$content);
      } else {
         # failure
         $self->{error}="Failed to encode parameters to ".$converter->type().": ".$converter->error();
         return 0;
      }
   } else {
      # unsupported method
      $self->{error}="Unsupported server method \"$hmethod\" specified";
      return 0;
   }

   # get response
   my (%code,$mess,%h) = $client->read_response_headers();

   my $errcodes=0;
   foreach (keys %code) {
      # check if we have any errors
      if (($_ =~ /^\d+$/) && ($_ >= 400) && ($_ <= 599)) {
         $errcodes=1;
         last;
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
   } elsif ($errcodes) {
      # typical fatal message - get status message
      my $msg=$resp{"errstr"} || "";
      $self->{error}=$msg;
      return 0;
   } else {
      # errors of another kind - concatenate...
      foreach (keys %code) {
         $self->{error}.=$code{$_}." ";
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

# get last error message
sub error {
   my $self = shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<HTTPSClient> - HTTPS Client to connect to a HTTPS-Server and execute POST- and GET- methods.

=cut

=head1 SYNOPSIS

   use HTTPSClient;

   # instantiate
   my $c=HTTPSClient->new (Host=>"localhost:2000",
                           SSL_verifycn_name => "server.domain.name.no",
                           SSL_verifycn_scheme => "https",
                           SSL_key_file => "./private.key",
                           SSL_cert_file => "./public.key",
                           SSL_ca_file => "./DigiCertCA.crt",
                          );

   # attempt connect
   if (!$c->connect()) {
      print "Error! Unable to connect: ".$c->error()."\n";
   }

   # execute a POST method
   my %resp;
   if (!$c->lazydo ("/whatEverServerMethod",\%resp,methodpar1=>"blipp",methodpar2=>"blapp",methodparN=>"whatever")) {
      print "Error! Unable to execute method: ".$c->error();
   } else {
      use Data::Dumper;
      print "RESULT: ".Dumper(\%resp);
   }    

=cut

=head1 DESCRIPTION

HTTPS Client class to connect to a HTTPS-server and execute POST- and GET- methods. It takes a Content-class as the parameter upon
instantiation and uses that to convert the parameters into the defined Content-class type for the server.

Upon a response the module then decode the return using the same Content-class type before returning the response as a HASH to the caller.

=cut


=head1 CONSTRUCTOR

=head2 new()

Instantiates the class.

Accepts the following parameters:

=over

=item

B<Host> Hostname of the HTTPS-server to connect to, including the port. Specified in the format: HOSTNAME:PORT.

=cut

=item

B<SSL_hostname> Same as Host-parameter. See Net::HTTPS for documentation.

=cut

=item

B<SSL_key_file> Sets the private key to use by the client. Includes full path and filename. Defaults to undef. See Net::HTTPS for documentation.

=cut

=item

B<SSL_cert_file> Sets the public key to use by the client. Includes full path and filename. Defaults to undef. See Net::HTTPS for documentation.

=cut

=item

B<SSL_ca_file> Sets the CA file name to use by the client (.crt). Includes full path and filename. Defaults to undef. See Net::HTTPS for documentation.

=cut

=item

B<SSL_verify_mode> Sets the verify mode to use for the connection. See Net::HTTPS for documentation.

=cut

=item

B<KeepAlive> Sets the keepalive-flag for the connection. Defaults to 1. See Net::HTTP for documentation.

=cut

=item

B<useragent> Sets the useragent string to appear as for the HTTPS-server. Default to "HTTPSClient/1.0".

=cut

=item

B<converter> Sets the Content-class type to use for the conversions to and from the HTTPS-server. Defaults to Content::JSON. See Content for documentation.

=cut

=back

Besides this the constructor accepts any SSL parameter that the Net::HTTPS module accepts. See Net::HTTPS for more documentation.

=cut

=head1 METHODS

=head2 connect()

Attempts to connect to the HTTPS-server. It first connects with an unencrypted HTTP-connection and then upgrades to an SSL-connection when successful.

Returns 1 if successful, 0 when failure. Check the error()-method for more details in such cases.

=cut

=head2 connected()

Checks to see if the client is connected to the HTTPS-server or not?

Returns 1 if it is, 0 if not.

=cut

=head2 disconnect()

Disconnects from the HTTPS-server if already connected.

Returns 1 if successful, 0 if disconnected already.

=cut

=head2 do()

Executes a HTTP POST- og GET-method on the HTTPS-server and returns the result.

This method is not meant to be called directly, but can be if one so chooses to have the hassle with it.

The methods take these parameters in the following order:

=over

=item

B<servermethod> The URL of the method to execute on the server. Eg. "/resource/getall". Defaults to "/status/alive".

=cut

=item

B<httpmethod> The HTTP method to use when executing the server-method. Defaults to "POST", but also accepts GET.

=cut

=item

B<response> A HASH-reference where the response from the server is placed after decoding.

=cut

=item

B<parameters> A HASH of parameters to the HTTPS-server. It is encoded into the Content-class type before being sent to the HTTPS-server. Defaults to undef.

=cut

=back

This method takes the above parameters and then encodes the parameters based on the Content-class set for the instance and the executes a POST- or GET to the HTTPS-server. It then reads 
the response from the server and decodes it into HASH using the same Content-class instance. The resulting HASH is returned in the "response"-parameter above.

The method returns 1 upon successfully executing method on the HTTPS-server or 0 upon failure. Please check the error()-method for more information upon failure.

The response is read, as already mentioned, by looking at the HASH reference submitted to the method in the first place (parameter response).

=cut

=head2 lazydo()

A wrapper around the do()-method that is easier and quicker to use and that only performs HTTP POST-calls.

It takes these parameters in the following order:

=over

=item

B<servermethod> The URL of the method to execute on the server. See the do()-method.

=cut

=item

B<response> A HASH-reference where the response from the server is placed after decoding. See the do()-method.

=cut

=item

B<parameters> A HASH of parameters to the HTTPS-server. See the do()-method.

=cut

=back

This method executes the servermethod on the HTTPS-server by calling the do()-method. 

The server response is returned in the already mentioned response-parameter.

The method returns 1 upon success, 0 upon failure. Please call the error()-method for more information on the failure.

=cut

=head2 error()

Returns the last error message from the class.

=cut
