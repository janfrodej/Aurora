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
# Class: DataContainer::DBI - class for loading and storing to a DB through the DBI interface and methods on it
#
package DataContainer::DBI;
use parent 'DataContainer';

use strict;
use DBI;

sub new {
   my $class = shift;
   # invoke parent new
   my $self=$class->SUPER::new(@_);

   # set extra parameter defaults
   if (!$self->{pars}{name})   { $self->{pars}{name}="DUMMY"; } # table name to write data to
   if (!$self->{pars}{user})   { $self->{pars}{user}="";  }     # user name to connect as
   if (!$self->{pars}{pw})     { $self->{pars}{pw}=""; }        # pw to connect with
   if (!$self->{pars}{pwfile}) { $self->{pars}{pwfile}=""; }    # pwfile to read pw to connect with

   $self->{dbi}=undef;

   return $self;
}

sub open {
   my $self = shift;

   # the modes of the datacontainer have no meaning in this open-method.

   if (!$self->opened()) {
      # get values for connect
      my $pw="";
      my $data_source=$self->{pars}{location};
      my $user=$self->{pars}{user};
      # select either direct pw or pwfile
      if ($self->{pars}{pw} ne "") {
         # set pw directly
         $pw=$self->{pars}{pw};
      } else {
         # only read from pwfile if pwfile has a value
         if ($self->{pars}{pwfile} ne "") {
            # read database password from file
            if (!open FH,"$self->{pars}{pwfile}") {
               $self->{error}="Unable to login to database. Cannot fetch database password from file \"".$self->{pars}{pwfile}."\" ($!)...";
               return 0;
            } else {
               $pw = <FH>;
               close FH;
               # clean password
               $pw =~ s/\r|\n//g;
            }
         }
      }

      # open database
      my %opt;
      $opt{RaiseError}=0; # is also default, but in case
      $opt{PrintError}=0; # please be silent
      # extra or overriding parameters
      foreach (keys %{$self->{pars}}) {
         my $key = $_;
         if (($key ne "pwfile") &&
             ($key ne "pw") && 
             ($key ne "user") &&
             ($key ne "name") &&
             ($key ne "location")) {
            $opt{$key} = $self->{pars}{$key};
         }
      }
      my $dbi = DBI->connect($data_source, $user, $pw,\%opt);
      # check if it opened/connected properly
      if (!$dbi) {
         $self->{error}="Unable to login to database: ".DBI::errstr().". Location: $data_source User: $user";
         return 0;
      } else {
         # success 
         $self->{dbi}=$dbi;
         $dbi->{RaiseError}=0;
         return 1;
      }
   } else {
      $self->{error}="Already opened a connection to a database. Close connection first.";
      return 0;
   }
}

sub opened {
   my $self = shift;

   # check that we have a dbi instance
   my $dbi = $self->{dbi};
   if (defined $dbi) {      
       # check db handler Active flag
      if ($dbi->{Active}) {
         return 1;
      }
   }

   # all other scenarios fails
   return 0;
}

sub close {
   my $self = shift;

   # ensure we are connected
   if ($self->opened()) {
      my $dbi=$self->{dbi};
      
      # try to disconnect only if connection is active
      if ($dbi->{Active}) {
         if (!$dbi->disconnect()) {
            $self->{error}="Problem while disconnecting from database: ".$dbi->errstr().".";
            return 0;
         } 
      }
   }

   # we accept "disconnect" in all other scenarios
   return 1;
}

sub load {
   my $self= shift;
   my $name = shift || $self->{pars}{name}; # table to load from

   # ensure we are connected
   if ($self->opened()) {
      # get dbi handler
      my $dbi=$self->{dbi};

      # connected to database - read entire content of table
      my $coll=$self->get();
      my $c=$coll->type()->new();

      # build up a list of db fields to ask for
      my $fields="";
      foreach ($c->fields()) {
         my $f=$_;
         $fields=($fields eq "" ? $fields : $fields.",");
         $fields.="$f";
      }
      # create statement
      my $oby=$self->{pars}{orderby};
      my $qoby=qq($oby);
      my $orderby=(defined $oby ? " ORDER BY $oby" : "");
      if ((defined $oby) && ($fields !~ /.*$qoby.*/)) {
         # add orderby field to statement
         $fields=($fields eq "" ? $oby : $fields.",$oby");
      }
      my $statement="SELECT $fields FROM `$name`$orderby";
      my $sql = $dbi->prepare ($statement);

      if ($dbi->err()) { 
         # failed to prepare sql statement
         $self->{error}="Unable to prepare sql statement \"$statement\": ".$dbi->errstr();         
         return 0; 
      }

      # execute query;
      $sql->execute() or $self->{error}="Unable to execute statement \"$statement\": ".$dbi->errstr();

      # check if failed or not.
      if ($dbi->err()) {
         # return failed
         $self->{error}="Failed to load data from database: ".$dbi->errstr();
         return 0;
      } else {
         # success - process data, but clear collection first
         $coll->reset();
         while (defined (my $h=$sql->fetchrow_hashref())) {
            # create a new content object
            my $c=$coll->type()->new();
            # set content of Content object to fetched hash
            $c->set($h);
            # add Content object to collection
            $coll->add($c); 
         }
         # check if we failed or not
         if ($dbi->err()) {
            # we had an error - reset contentcollection and return failure
            $coll->reset();
            # set error
            $self->{error}="Failed to load data because of failure to fetch a row: ".$dbi->errstr();
            return 0;
         }
         # finished - return success
         return 1;
      }
   } else {
      # not connected to database
      $self->{error}="No connection open to any database. Please open connection first.";
      return 0;
   }
}

sub save {
   my $self = shift;
   my $name = shift || $self->{pars}{name}; # table-name to save to in database

   # ensure that we are connected
   if ($self->opened()) {
      # connected to database - enumerate data fields
      # get contentcollection to write
      my $coll = $self->get();

      # disable autocommit
      my $dbi=$self->{dbi};
      if (!$dbi->begin_work()) {
         # failed to initiate transaction
         $self->{error}="Unable to initiate SQL transaction on database: ".$dbi->errstr();
         return 0;
      }

      my $data;
      if ($coll->resetnext()) {
         # go through each Content-instance in the collection and write it to the database
         my $content;
         while (defined ($content=$coll->next())) {
            # run encode to ensure defaults are being set and check for errors
            if (!$content->encode()) {
               # failed to encode - fail to save all entries
               $self->{error}="Unable to save data because of encoding failure: ".$content->error();
               eval { $dbi->rollback(); };
               return 0;
            }
            # contents fields are expected to come in the right order as specified by the Content-class used.
            # it is assumed that the database has corresponding fields that can receive the data as-is.
            # get field names in order
            my @f=$content->fields();
            my $fpos=0;
            my $fields="";
            my $values="";
            # go through each field value in order and build SQL
            $content->resetnext();
            while (defined (my $val=$content->next())) {
               # add to fieldnames list
               $fields=($fields eq "" ? $f[$fpos] : "$fields,".$f[$fpos]);
               # some assumptions are done, such that if value is purely a number it is assumed to be an integer
               if (!defined $val) { $values=($values eq "" ? "NULL" : "$values,NULL"); }
               elsif ($val =~ /^[\d\.]+$/) {
                  $values=($values eq "" ? $val : "$values,".$val);
               } else {
                  $values=($values eq "" ? $dbi->quote($val) : "$values,".$dbi->quote($val));
               }
               $fpos++;
            }
            # all values have been gathered and formatted. Ready to insert
            my $statement="INSERT INTO `$name` ($fields) VALUES ($values)";
            my $sql=$dbi->prepare ($statement);

            if ($dbi->err()) { 
               # failed to prepare
               $self->{error}="Unable to prepare sql statement \"$statement\": ".$dbi->errstr();
               # ending transaction - ignore any failure from rollback.
               eval { $dbi->rollback(); };
               return 0;
            }

            # execute query;
            $sql->execute();

            # check if failed or not.
            if ($dbi->err()) {
               # return failed
               $self->{error}="Failed to insert data into database: ".$dbi->errstr();
               eval { $dbi->rollback(); };
               return 0;
            }
         } # end of while-loop

         # we are ready to perform a commit
         if (!$dbi->commit()) {
            # we failed - rollback and return error
            eval { $dbi->rollback(); };
            $self->{error}="Unable to commit changes to database: ".$dbi->errstr();
            return 0;
         }

         # return success
         return 1;
      } else {
         # failure to call resetnext()
         $self->{error}=$coll->error();
         return 0;
      }
   } else {
      # failure to connect - error already set
      return 0;
   }
}

sub delete {
   my $self = shift;
   my $name = shift || $self->{pars}{name}; # table name to delete all data on

   # attempt to delete from database
   if ($self->opened()) {
      # disable autocommit
      my $dbi=$self->{dbi};
      if (!$dbi->begin_work()) {
         # failed to initiate transaction
         $self->{error}="Unable to initiate SQL transaction on database: ".$dbi->errstr();
         return 0;
      }
      # get datacontainer collection
      my $coll=$self->get();
      # go through each element in collection and delete
      $coll->resetnext();
      while (my $c=$coll->next()) {
         # run encode to ensure defaults are being set and check for errors
         if (!$c->encode()) {
            # failed to encode - fail to save all entries
            $self->{error}="Unable to delete data because of encoding failure: ".$c->error();
            eval { $dbi->rollback(); };
            return 0;
         }
         # contents fields are expected to come in the right order as specified by the Content-class used.
         # it is assumed that the database has corresponding fields that can receive the data as-is.
         # get field names in order
         my @fields=$c->fields();
         my @values;
         # go through each field value in order and build SQL
         $c->resetnext();
         while (my $val=$c->next()) {
            # some assumptions are done, such that if value is purely a number it is assumed to be an integer
            if ($val !~ /^[\d\.]+$/) {
               $val=$dbi->quote($val);
            }       
     
            # add value to values
            push @values,$val;
         }          

         # build sql
         my $moderator="";
         for (my $pos=0; $pos < @fields; $pos++) {
            my $cmp=(defined $values[$pos] ? "=" : " IS ");
            $values[$pos]=(defined $values[$pos] ? $values[$pos] : "NULL");
            $moderator=($moderator eq "" ? $fields[$pos].$cmp.$values[$pos] : $moderator." AND ".$fields[$pos].$cmp.$values[$pos]);
         }

         # define delete statement for this content
         my $statement="DELETE FROM `$name` WHERE $moderator";
         # prepare statement
         my $sql = $dbi->prepare ($statement);

         if ($dbi->err()) { 
            # failed to prepare
            $self->{error}="Unable to prepare sql statement \"$statement\": ".$dbi->errstr();
            eval { $dbi->rollback(); };
            return 0;
         }
      
         # execute query;
         $sql->execute();

         # check if failed or not.
         if ($dbi->err()) {
            # return failed
            $self->{error}="Failed to delete data from database table $name: ".$dbi->errstr();
            eval { $dbi->rollback(); };
            return 0;
         }
      }

      # we are ready to perform a commit
      if (!$dbi->commit()) {
         # we failed - rollback and return error
         eval { $dbi->rollback(); };
         $self->{error}="Unable to commit deletion(s) to database: ".$dbi->errstr();
         return 0;
      }
 
      # success...
      return 1;
   } else {
      # not opened
      $self->{error}="No connection to database opened. Unable to delete.";
      return 0;
   }
}

1;

__END__

=over 1

=item B<new()>

DataContainer::DBI-class constructor. 

It calls the parent new-constructor and then sets some additional parameters for the DataContainert::DBI-class.

The location parameter is here used to mean data_source for the connect method of DBI. The name parameter is here used to mean the table name to load or save data to.

Possible extra parameters for this sub-class is:

=over 

=item

B<user> Username to connect to database with. Required.

=cut

=item

B<pw> Password to connect to database with. Required.

=cut

=item

B<pwfile> Password file to load password from. Optional if not using the pw-option. The option requires the pw-parameter to be blank or not specified.

=cut

=item

B<orderby> The field to order the select-statement by when loading the database contents. Optional and can be undef. If defined it sets the
field name of the SQL order by-statement. Please remember that whatever is specified here it is added as a field-name to SELECT as well.

=cut

=back

Returns an instantiated object.

=cut

=item B<open()>

Open connection to database.

No parameters required.

See documentation of the DataContainer-class for more information on this method.

=cut

=item B<opened()>

Returns status if database connection has been opened or not?

See documentation of the DataContainer-class for more information on this method.

=cut

=item B<close()>

Close the database connection.

See documentation of the DataContainer-class for more information on this method.

=cut

=item B<load()>

Load all data from a table in a database into the ContentCollection-instance.

Returns 1 upon success, 0 upon failure.

No parameters required, but one can override the table one reads data from by specifying one scalar parameter here.

See documentation of the DataContainer-class for more information on this method.

=cut

=item B<save()>

Saves all data from the ContentCollection-instance to the database.

Returns 1 upon success, 0 upon failure.

No parameters required, but one can override the table one saves data to by specifying one scalar parameter here.

See documentation of the DataContainer-class for more information on this method.

=cut

=item B<delete()>

Delete all entries in the ContentCollection instance from database. See documentation of the DataContainer placeholder class and the new()-method for more information on the ContentCollection.

Returns 1 upon success, 0 upon failure.

No parameters required, but one can override the table one deletes all data from by specifying one scalar parameter here.

See documentation of the DataContainer-class for more information on this method.

=cut

=back
