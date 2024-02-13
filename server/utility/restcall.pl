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
use lib qw(/usr/local/lib/aurora);
use HTTPSClient::Aurora;
use Schema;
use SysSchema;
use Data::Dumper;
use Settings;
use Term::ReadKey;
use JSON;

# set UTF-8 encoding on STDIN/STDOUT
binmode(STDIN, ':encoding(UTF-8)');
binmode(STDOUT, ':encoding(UTF-8)');

# settings instance
my $CFG=Settings->new();
$CFG->load();

my $command=$ARGV[0]||"";

if ($command eq "-h") {
   print "$0 - Call any AURORA REST-server method\n";
   print "\n";
   print "Syntax:\n";
   print "   $0\n";
   print "\n";
   print "This script enters a loop-mode after taking REST-server authentication credentials.\n";
   print "In the loop-mode, one can enter REST-calls in the following syntax:\n";
   print "   [REST-METHOD] [PAR1=VALUE] [PAR2=VALUE] .. [PARn = VALUE]\n\n";
   print "The values can contain \"\[\]\" and \"()\" for arrays and \"\{\}\" for hashes. Keys or \n";
   print "items within the array or hash is separated with \",\" (comma)\n\n";
   print "Write \".\" and hit ENTER to exit the loop.\n";
   exit(0);
}

my $c=HTTPSClient::Aurora->new( Host=>$CFG->value("system.rest.host").":".$CFG->value("system.rest.port"),                                
#                                SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_PEER,
                                KeepAlive => 1,
                                SSL_verifycn_name => $CFG->value("system.rest.host"),
                                SSL_verifycn_scheme => 'http',                              
                                SSL_key_file=>"./certs/private.key",
                                SSL_cert_file=>"./certs/public.key",
                                SSL_ca_file=>"./certs/DigiCertCA.crt",
                               );
if (!$c->connect()) {
   die "Error! ".$c->error()."\n";
}

print "AuthType [AuroraID]: ";
my $authtype=<STDIN>;
$authtype=~s/[\r\n]//g;
if ($authtype eq "") { $authtype="AuroraID"; }

print "Email-address: ";
my $email=<STDIN>;
$email=~s/[\r\n]//g;

print "AuthStr (not visible, for AuroraID - just the pw): ";
ReadMode('noecho'); 
my $authstr=ReadLine (0);
print "\n";
$authstr=~s/[\r\n]//g;
ReadMode('normal');

# put email and authstr together of AuroraID auth type
if ($authtype eq "AuroraID") { $authstr=$email.",".$authstr; }

# loop until satisfied, then break with CTRL+C
while (1) {
   my $args;

   print "Syntax: REST-CMD [JSON-parameters] or \".\" to quit.\n\n";
   print "REST-CALL: ";
   my $arg=<STDIN>;
   $arg=~s/[\r\n]//g;
   if ($arg eq ".") { exit(0); }
   my $count=split(/(?<!\\)\s+/,$arg);
   if ($count == 0) { next; }
   # get method from call
   my $method=$arg;
   $method=~s/([^\s]+).*$/$1/;
   $arg=~s/^([^\s]+)\s+(.*)$/$2/;

   # only parse args if there is anything there
   if ($count > 1) {
      $args=decode($arg);
   }

   if (defined $args) {
      print "ARGS: ".Dumper($args);
   } else {
     print "No ARGS recognized...\n\n";
   }

   # call REST-method
   my %resp;
   my $err;
   {
      local $@; # protect existing $@    
      eval { 
         if ((defined $args) && (ref($args) eq "HASH")) { $c->$method(\%resp,authtype=>$authtype,authstr=>$authstr,%{$args}); } 
         else { $c->$method(\%resp,authtype=>$authtype,authstr=>$authstr); } 
      };
      $@ =~ /nefarious/;
      $err=$@;
   }

   if ($err eq "") {
      print "\n$method: ".Dumper(\%resp)."\n";
   } else {
      # some critical error
      print "FATAL! Problem executing REST-method $method: $err\n";
   }

   # check if we need to reconnect...
   if (!$c->connected()) {
      print "Reconnecting to REST-server...\n";
      $c=HTTPSClient::Aurora->new( Host=>$CFG->value("system.rest.host").":".$CFG->value("system.rest.port"),                                
#                                   SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_PEER,
                                   KeepAlive => 1,
                                   SSL_verifycn_name => $CFG->value("system.rest.host"),
                                   SSL_verifycn_scheme => 'http',
                                   SSL_key_file=>"./certs/private.key",
                                   SSL_cert_file=>"./certs/public.key",
                                   SSL_ca_file=>"./certs/DigiCertCA.crt",
                                 );
      if (!$c->connect()) {
         die "Error! ".$c->error()."\n";
      }
   }
}

sub decode {
   my $str=shift;

   my $err;
   my $h;
   local $@;
   eval { my $a=JSON->new(); $h=$a->decode ($str); };
   $@ =~ /nefarious/;
   $err=$@;

   if ($err eq "") {
      # decoding was a success
      return $h;
   } else {
      # an error occured
      print "Unable to decode JSON parameters: $err\n";
      return undef;
   }
}
