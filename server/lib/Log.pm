#!/usr/bin/perl -Tw
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
# Class: Log - class to handle logging without having to deal with Content::Log
#
package Log;

use strict;
use ContentCollection;
use Content::Log;
use DataContainer::DBI;

sub new {
   # instantiate
   my $class = shift;
   my $self = {};
   bless ($self,$class);

   my %pars;
   %pars=@_;

   # check values, set defaults
   if (!$pars{location}) { $pars{location}=""; }  # DBI data_source 
   if (!$pars{name}) { $pars{name}="DUMMY"; } # table name to write data to
   if (!$pars{user}) { $pars{user}=""; } # DBI user to connect as
   if (!$pars{pw}) { $pars{pw}=""; } # DBI password to connect as
      
   # save parameters
   $self->{pars}=\%pars;

   # set last error message
   $self->{error}="";

   # return instance
   return $self;
}

sub send {
   my $self = shift;
   my %pars = @_;

   # name parameter to method overrides name-parameter of the instance
   my $name;
   if (exists $pars{name}) {
      $name=$pars{name};
      # remove hash key since it is not to be saved to DataContainer
      delete ($pars{name});
   } else {
      $name=$self->{pars}{name} || "";
   }

   # ensure sensible defaults that are required
   $pars{entity}=$pars{entity} || 0;
   $pars{logmess}=$pars{logmess} || "";
   $pars{loglevel}=$pars{loglevel} || $Content::Log::LEVEL_INFO;
   $pars{logtag}=$pars{logtag} || "NONE";
   
   # create Content instance
   my $c = Content::Log->new();
   $c->set(\%pars);   

   # create ContentCollection that DataContainer-class requires
   my $coll=ContentCollection->new(type=>$c);
   # add content
   $coll->add($c);

   # create DataContainer instance
#   my $dc=DataContainer::DBI->new(location=>$self->{pars}{location},name=>$name,user=>$self->{pars}{user},
#                                  pw=>$self->{pars}{pw},pwfile=>$self->{pwfile},collection=>$coll);
   my $dc=DataContainer::DBI->new(name=>$name,collection=>$coll,%{$self->{pars}});

   # set mode - no meaning to DBI DataContainer as of now
   $dc->mode($DataContainer::MODE_OVERWRITE);

   # open container for saving
   if (!$dc->open()) {
      # unable to open datacontainer
      $self->{error}="Unable to open DataContainer for logging: ".$dc->error();
      return 0;
   }

   if ($dc->save()) {
      # success - close container
      $dc->close();
      return 1;
   } else {
      # something failed
      $dc->close();
      $self->{error}="Failed to send log entry: ".$dc->error().".";
      return 0;
   }   
}

sub receive {
   my $self = shift;

   my $name = $self->name();

   # create Content instance
   my $c = Content::Log->new();
   # create ContentCollection instance
   my $coll=ContentCollection->new(type=>$c);

   # create DataContainer instance
#   my $dc=DataContainer::DBI->new(location=>$self->{pars}{location},name=>$name,user=>$self->{pars}{user},
#                                  pw=>$self->{pars}{pw},pwfile=>$self->{pwfile},collection=>$coll,orderby=>"idx");
   my $dc=DataContainer::DBI->new(name=>$name,collection=>$coll,orderby=>"idx",%{$self->{pars}});


   # set mode to append - no meaning to DBI DataContainer as of now
   $dc->mode($DataContainer::MODE_READ);

   # open the datacontainer
   if (!$dc->open()) {
      # failed to open datacontainer
      $self->{error}="Unable to open DataContainer for receiving log entries: ".$dc->error();
      return undef;
   }

   if ($dc->load()) {
      # success - return contentcollection upon success
      $coll->resetnext();
      $dc->close();
      return $coll;
   } else {
      # something failed
      $dc->close();
      $self->{error}="Failed to receive log entries: ".$dc->error().".";
      return undef;
   }      
}

sub delete {
   my $self = shift;
   my $coll = shift;

   my $name = $self->name();
 
   if ((!defined $coll) || (!$coll->isa("ContentCollection"))) {
      # create Content instance
      my $c = Content::Log->new();
      # create ContentCollection instance
      $coll=ContentCollection->new(type=>$c);
   }

#   my $dc=DataContainer::DBI->new(location=>$self->{pars}{location},name=>$name,user=>$self->{pars}{user},
#                                  pw=>$self->{pars}{pw},pwfile=>$self->{pwfile},collection=>$coll);
   my $dc=DataContainer::DBI->new(name=>$name,collection=>$coll,%{$self->{pars}});

   # set mode to append - no meaning to DBI DataContainer as of now
   $dc->mode($DataContainer::MODE_READWRITE);

   # open container for deleting
   if (!$dc->open()) {
      # unable to open datacontainer
      $self->{error}="Unable to open DataContainer for deleting data: ".$dc->error();
      return 0;
   }

   # delete the content in the contentcollection
   if ($dc->delete()) {
      # success 
      return 1;
   } else {
      # something failed
      $self->{error}="Failed to delete data: ".$dc->error().".";
      return 0;
   }         
}

sub name {
   my $self = shift;

   if (@_) {
      # this is a set
      my $name=shift || "";
      $self->{pars}{name}=$name;
      return 1;
   } else {
      # this is a get
      return $self->{pars}{name} || "";
   }
}

sub location {
   my $self = shift;

   if (@_) {
      # this is a set
      my $l=shift || "";
      $self->{pars}{location}=$l;
      return 1;
   } else {
      # this is a get
      return $self->{pars}{location} || "";
   }
}

sub user {
   my $self = shift;

   if (@_) {
      # this is a set
      my $l=shift || "";
      $self->{pars}{user}=$l;
      return 1;
   } else {
      # this is a get
      return $self->{pars}{user} || "";
   }
}

sub pw {
   my $self = shift;

   if (@_) {
      # this is a set
      my $l=shift || "";
      $self->{pars}{pw}=$l;
      return 1;
   } else {
      # this is a get
      return $self->{pars}{pw} || "";
   }
}

sub pwfile {
   my $self = shift;

   if (@_) {
      # this is a set
      my $l=shift || "";
      $self->{pars}{pwfile}=$l;
      return 1;
   } else {
      # this is a get
      return $self->{pars}{pwfile} || "";
   }
}

sub error {
   my $self = shift;

   # return error message
   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Log> - Class to handle AURORA REST-server logging through a Content::Log-class in an a easy way.

=cut

=head1 SYNOPSIS

   use Log;

   # instantiate
   my $db="/path/to/db/file.db";
   my $log=Log->new(location=>"DBI::SQLite::dbname=$db",name=>"log",user=>"",pw=>"");

   # send log entry
   if (!$log->send(entity=>123,loglevel=>$Content::Log::LEVEL_FATAL,logmess=>"This went sideways!",logtag=>"SOMETAG")) {
      print "Failure: ".$log->error();
   } else {
      print "Success!";
   }

   # load log entries
   my $coll=$log->receive();

=cut

=head1 DESCRIPTION

Class to handle AURORA REST-server logging through a Content::Log-class in a easy and quick way.

=head1 CONSTRUCTOR

=head2 new()

Class constructor.

Required parameters are location (dbi data_source), name (database table name to save to), user (username to connect as), pw (password to connect with). Optional parameter is pwfile (file to read pw to connect with from), but this requires the pw parameter to not be specified or blank.

Returns the class instance.

=cut

=head1 METHODS

=head2 send()

Sends a log entry.

Possible parameters are (in the shape of key=>value pairs): logtime (hires time of log event), entity (id of entity from database), loglevel (loglevel from Content::Log), logtag (tag for message, optional) and logmess (log message to be sent).

Required parameters are none, but it is advised to answer at least entity and logmess. Time is automatically taken from current time if not answered and loglevel defaults to Content::Log::LEVEL_INFO.

Upon successful send returns 1 and upon failure 0.

Error message of a failure can be read by calling the error()-method.

=cut

=head2 receive()

Receives data from DataContainer into Content::Log-instances in a ContentCollection.

No input required.

Returns ContentCollection instance upon success, undef upon failure.

=cut

=head2 delete()

Deletes all the content of the ContentCollection specified.

Input is the ContentCollection instance that are to be deleted from the database.

The deletion process is transactional, so either all entries in the ContentCollection is deleted or none. It will perform a
rollback on any failure.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

=cut

=head2 name()

See DataContainer-class for an explanation of this method.

The name attribute here means table-name.

=cut

=head2 location()

See DataContainer-class for an explanation of this method.

The location attribute here means DBI data_source.

=cut

=head2 user()

Returns or sets the user name wherewith to connect to the database.

=cut

=head2 pw()

Returns or sets the password wherewith to connect to the database.

=cut

=head2 pwfile()

Returns or sets the password file to read the password from when connecting to the database.

=cut

=head2 error()

Returns the last known error message of this class.

No input required and return a scalar with the message or a blank (if none).

=cut
