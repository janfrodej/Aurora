#!/usr/bin/perl -w
# Copyright (C) 2019-2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
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
# Notice::Sendmail: Class to send notice via sendmail in the AURORA notification-service.
#
package Notice::Sendmail;
use parent 'Notice';

use strict;
use Email::MIME;
use Email::Sender::Transport::Sendmail;
use Email::Sender::Simple qw(sendmail);

# constructor
sub new {
   my $class = shift;

   my $self=$class->SUPER::new(@_);

   my %pars=%{$self->{pars}};

   # if binary location has not been set, set a default
   if (!exists $pars{binary}) { $pars{binary}="/usr/sbin/sendmail"; }

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

   # setup mail headers and data
   my @headers;
   push @headers,"From" => $from;
   push @headers,"To" => [$to];
   push @headers,"Subject" => $subject;
   push @headers,"Message-ID" => $threadid;

   my $tsize=@{$threadids};
   if ($tsize > 0) {
      push @headers,"In-Reply-To" => $threadids->[$tsize-1];
      push @headers,"References" => join("\r\n ",@{$threadids});
#      push @headers,"Thread-Topic" => $threadids->[0]; # always include original threadid as the topic (aim to please MS)
   } else {
#      push @headers,"Thread-Topic" => $threadid; # always include original threadid as the topic (aim to please MS)
   }

   # structure and encode the email
   my $email = Email::MIME->create(
         attributes => { charset => "utf-8", content_type => "text/plain", encoding => "quoted-printable" },
         header_str => \@headers,
         body_str => $notice,
   );

   # create a sender using sendmail
   my $sender = Email::Sender::Transport::Sendmail->new({ sendmail => $self->{pars}{binary} });

   # attempt to send with sendmail
   my $err;
   local $@;
   eval { sendmail($email,{transport => $sender}); };
   $@ =~ /nefarious/;
   $err=$@;
   
   if ($err eq "") {
      my $msg=$!||"";
      $msg=~s/[\r\n]/\//g;
      $self->{result}=$msg || "";
      return 1;
   } else {
#      my $msg=$err->message()||"";
      my $msg=$err||"";
      $msg=~s/[\r\n]/\//g;
      $self->{error}="Unable to send notice: $msg";
      $self->{result}="Unable to send notice: $msg";
      return 0;
   };
}

sub error {
   my $self=shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Notice::Sendmail> - A class to send notices as email through sendmail in the AURORA notification-service

=cut

=head1 SYNOPSIS

   use Notice::Sendmail;

   # create instance
   my $n=Notice::Sendmail->new(binary=>"/usr/sbin/sendmail");

   # send a notice
   $n->send("charliebucket451@yahoo.com","willy.wonka@wonka.chocolate","I WON!!!","Hi\nPlease know that I have found one of the golden tickets.");

   # get last error
   print $n->error();

=cut

=head1 DESCRIPTION

A class for sending notices as email through sendmail in the AURORA notification-service.

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiate class.

Only takes one optional parameter: binary. It specifies the full path and binary of sendmail. If not specified 
will default to "/usr/sbin/sendmail".

Returns a class instance.

=cut

=head1 METHODS

=head2 send()

Attempts to send a notice as an email using sendmail.

The from and to parameters are to be email-addresses. 

Please see the Notice placeholder-class for more information on the use of this method.

=cut

=head2 error()

Returns the last error that has happened (if any).

No input is accepted.

=cut
