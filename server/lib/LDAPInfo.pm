#!/usr/bin/perl -w
# LDAPInfo - package to get LDAP info
#            
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
package LDAPInfo;
use strict;
use Net::LDAP;

# constructor
sub new {
   # create instance
   my $self = {};
   my $class = shift;
   bless ($self);

   # get parameters
   my %pars;
   if (@_) {
      %pars=@_;

      if (!$pars{server}) {$pars{server}="dummy.localhost";}
      if (!exists $pars{confidential}) {$pars{confidential}=1;}
      if ($pars{confidential} == 1) { 
         $pars{scheme}="ldaps"; 
         if (!exists $pars{verify}) { $pars{verify}="require"; } 
      } else { $pars{scheme}="ldap"; }
      
      # add relevant keys to its own options hash
      foreach (keys %pars) {
         my $key=$_;
         if (($key ne "confidential") &&
             ($key ne "dn") &&
             ($key ne "password") &&
             ($key ne "server")) {
            $self->{options}{$key}=$pars{$key};
         }  
      }  
      
      $self->{pars}=\%pars;
   }  

   # some internal variables
   $self->{error}="";
   $self->{ldap}=0;

   return $self;
}

# check if there were an error
sub error {
   my $self = shift;

   return $self->{error};
}

# try to bind to LDAP server
sub bind {
   my $self = shift;

   # reset error
   $self->{error}="";

   # do LDAP setup
   my $ldap;
   unless ($ldap = Net::LDAP->new($self->{pars}{server},%{$self->{options}})) {
      $self->{error}="Error! Could not create LDAP object: ".$@;
      return 0;
   } 

   my $mesg;
   $self->{ldap}=$ldap;

   my $dn=$self->{pars}{dn}||"";
   my $pw=$self->{pars}{password}||"";
   my @par;
   if ($dn) { push @par,$dn; }
   if ($pw) { push @par,password=>$pw };

   $mesg=$ldap->bind(@par);
   if ((!defined $mesg) || ($mesg->code() != 0)) {
      $self->{error}="Error doing LDAP bind: ".$mesg->error();
      return 0;
   }

   return 1;
}

# general ldap search function.
# input from base and filter to the function
sub search {
   my $self = shift;

   # get base
   my $base = shift;
   # get filter
   my $filter = shift;

   # get ldap handler
   my $ldap = $self->{ldap};

   # reset error
   $self->{error}="";

   # do search
   my $search;
   $search = $ldap->search (base => $base, filter => $filter);
   if ($search->code() != 0) {
      $self->{error}="LDAP search failed: ".$search->error();
      return undef;
   }
   # check to see if there was a hit
   my $i=0;
   my $entry;
   my %ret;
   while ($entry = $search->pop_entry()) {
      # get attributes
      foreach ($entry->attributes()) {
         my $attr = $_;
         my @values=$entry->get_value($attr);

         if (@values > 1) { $ret{$i}{$attr}=\@values; } 
         else { $ret{$i}{$attr}=$values[0]; }
      }
      $i++;
   }

   # return result
   return \%ret;
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<LDAPInfo> - Class to retrieve LDAP information from an LDAP-server.

=cut

=head1 SYNOPSIS

   use LDAPInfo;
    
   # instantiate
   my $ldap=LDAPInfo->new(server=>"localhost",dn=>"username",password=>"MYPW",confidential=>1);

   # bind
   $ldap->bind();

   # search
   my $result=$ldap->search(base=>"ou=MYOU,dc=domain,dc=topdomain",filter=>"cn=mystring*");

=cut

=head1 DESCRIPTION

Class to retrieve information from an LDAP catalogue server. It supports the most basic operations in a set of 
easy operations.

=cut

head1 CONSTRUCTOR

=head2 new()

Instantiates the class.

Accepts the followng parameters:

=over

=item

B<server> The LDAP-server address to connect to. Required.

=cut

=item

B<dn> Any DN-information to the LDAP-server such as username. Optional. Must be customized to the LDAP-server in question.

=cut

=item

B<password> Password to use when connectin as a user. Optional.

=cut

=item

B<confidential> Sets if the connection to the LDAP-server is to be secured or not? Optional. Defaults to 1. If set to 1 
will attempt to upgrade the connection to a secure connection upon bind, if 0 it will use unencrypted ldap.

=cut

=back

Returns the class instance.

=cut

=head1 METHODS

=head2 bind()

Attempts to bind to the LDAP-server. 

Accepts no input.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

=cut

=head2 search()

Searches the LDAP catalogue for information.

Accepts to input in the following order:

=over

=item

B<base> The base to use when searching the LDAP-catalogue. SCALAR.

=cut

=item

B<filter> The filter to use when searching the LDAP-catalogue. SCALAR.

=cut

=back

Upon success returns a HASH-reference to a structure as follows:

  (
     0 => {
            ATTRIBUTEa => VALUE,
            .
            .
            ATTRIBUTEz => VALUE
          }

    1 => {
           ATTRIBUTEa => VALUE,
           .
           .
           ATTRIBUTEz => VALUE

         }
   )

where the primary keys are the numbered hits that it found (from 0 - N). The HASH may be empty if there were no hits.

Upon failure it will return undef. Please check the error()-method for more information.

=cut

=head2 error()

Returns the last error message from the module.

Accepts no input.

Returns the last error message as a SCALAR.

=cut
