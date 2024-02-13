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
# Notice::Email: Class to send notice via email in the AURORA notification-service.
#
package Notice::Email;
use parent 'Notice';

use strict;
use Net::SMTP;

# constructor
sub new {
   my $class = shift;

   my $self=$class->SUPER::new(@_);

   # set defaults if not specified      
   my %pars=%{$self->{pars}};
   if (!exists $pars{host}) { $pars{host}="localhost"; }

   # save parameters
   $self->{pars}=\%pars;

   return $self;
}

# send a notice - to be overridden
sub send {
   my $self=shift;
   my $from=shift || ""; # senders address
   my $to=shift || ""; # the receivers address
   my $subject=shift || ""; # subject of notice
   my $notice=shift || ""; # the notice to send
   my $threadid=shift || ""; # threadid to use if possible
   my @t;
   my $threadids=shift; # previous threadids, if any
   if (ref($threadids) ne "ARRAY") { my @t; $threadids=\@t; }

   my $host=$self->{pars}{host};

   my $smtp = Net::SMTP->new ($host);

   if (!defined $smtp) {
      $self->{error}="Cannot send notice. Unable to connect to smtp-server: $!";
      return 0;
   }

   $smtp->mail($from); # who is the email from?
   if ($smtp->to($to)) { # receiver
      my $err;
      eval { 
         $smtp->data();
         $smtp->datasend("From: $from\n");
         $smtp->datasend("To: $to\n");
         $smtp->datasend("Subject: $subject\n");
         # add thread id
         $smtp->datasend("Message-ID: $threadid\n");
         my $tsize=@{$threadids};
         if ($tsize > 0) { 
            # add previous threadids
            $smtp->datasend("In-Reply-To: ".$threadids->[$tsize-1]."\n");
            $smtp->datasend("References: ".join("\r\n ",@{$threadids})."\n");
#            $smtp->datasend("Thread-Topic: ".$threadids->[0]."\n"); # always include original threadid as the topic (aim to please MS)
         } else {
#            $smtp->datasend("Thread-Topic: $threadid\n"); # always include original threadid as the topic (aim to please MS)
         }
         $smtp->datasend("\n");
         $smtp->datasend($notice);

         $smtp->dataend();

         my $msg=$smtp->message();
         $msg=~s/[\r\n]//g;

         $self->{result}=$msg || "";

         $smtp->quit();
      };
      $@ =~ /nefarious/;
      $err = $@;

      if ($@ ne "") {
         # an error occurred
         my $msg=$smtp->message();
         $msg=~s/[\r\n]//g;
         $self->{error}="Unable to send notice: $msg";
         $self->{result}="Unable to send notice: $msg";
         return 0;
      } 

      return 1;
   } else {
      $self->{error}="Unable to send notice: ".$smtp->message();
      $self->{result}="Unable to send notice: ".$smtp->message();
      return 0;
   }
}

sub error {
   my $self=shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Notice::Email> - A class to send notices as email in the AURORA notification-service

=cut

=head1 SYNOPSIS

   use Notice::Email;

   # create instance
   my $n=Notice::Email->new(host=>"oompaloompa");

   # send a notice
   $n->send("charliebucket451@yahoo.com","willy.wonka@wonka.chocolate","I WON!!!","Hi\nPlease know that I have found one of the golden tickets.");

   # get last error
   print $n->error();

=cut

=head1 DESCRIPTION

A class for sending notices as email in the AURORA notification-service.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiate class.

The method takes one input: host. This denotes the host-address of the smtp-server.

Returns a class instance.

=cut

=head1 METHODS

=head2 send()

Attempts to send a notice as an email using an smtp-server.

The from and to parameters are to be email-addresses. 

Please see the Notice placeholder-class for more information on the use of this method.

=cut

=head2 error()

Returns the last error that has happened (if any).

No input is accepted.

=cut
