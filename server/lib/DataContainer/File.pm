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
# Class: DataContainer::File - class to represent a general file and methods on it
#
package DataContainer::File;
use parent 'DataContainer';

use strict;

sub open {
   my $self = shift;

   # get name
   my $name = shift || $self->{pars}{name};

   if (!$self->opened()) {
      # check mode flags
      my $flag="";
      if ($self->mode() == $DataContainer::MODE_READ) {
         # read
         $flag="<";
      } elsif ($self->mode() == $DataContainer::MODE_READWRITE) {
         # read and write, but no clobbering
         $flag="+<";
      } elsif ($self->mode() == $DataContainer::MODE_OVERWRITE) {
         # overwrite and read
         $flag="+>";
      } elsif ($self->mode() == $DataContainer::MODE_APPEND) {
         # append and read
         $flag="+>>";
      } else {
         # set read as default
         $flag="<";
      }
 
      # open file for writing. File is overwritten
      my $FH;
      if (open ($FH,$flag,$self->{pars}{location}."/".$name)) {
         # success
         $self->{opened}=1;
         $self->{FH}=$FH;
         return 1;
      } else {
         # failed to open file
         $self->{error}="Unable to open file ".$self->{pars}{location}."/$name: $!";
         return 0;
      }
   } else {
      # already opened
      $self->{error}="Unable to open since the file is already open.";
      return 0;
   }
}

sub close {
   my $self = shift;

   my $name=$self->{pars}{name};

   if ($self->opened()) {
      my $FH=$self->{FH};

      if (close ($FH)) {
         # success
         $self->{opened}=0;
         $self->{FH}=undef;
         return 1;
      } else {
         # failed to close
         $self->{error}="Unable to close file ".$self->{pars}{location}."/$name: $!";
         return 0;
      }
   }

   return 1;
}

# I: name:scalar
# O: 0 upon failure, 1 upon success
# C: Loads file into the instance. Name is filename of file to load. If called without parameters it will attempt to load default file in default location.
sub load {
   my $self= shift;
   my $name = shift || $self->{pars}{name};

   # open file for reading
   if ($self->opened()) {
      # get filehandle
      my $FH=$self->{FH};
      # go to beginning of file
      if (!seek ($FH,0,0)) {
         # failed to seek to beginning of file
         $self->{error}="Unable to set read position to beginning of file ".$self->{pars}{location}."/$name: $!.";
         return 0;
      }
      # read contents
      my $data;
      while (my $line=<$FH>) {
         $data.=$line;
      }

      # get contentcollection
      my $coll=$self->{pars}{collection};
      # clear out collection content
      $coll->reset();
      # create new Content-class instance based on ContentCollection type
      my $t=$coll->type()->new();
      my $r;
      while (defined ($r=$t->decode($data))) {
         # add to collection
         $coll->add($t);
         # create a new Content-instance
         $t=$coll->type()->new();
         if ($r ne "") {
            # set the remainder to the data
            $data=$r;
         } else {
            # no more data - end it
            $data=$r;
            last;
         }
      }

      if (!defined $r) {
         # error occured
         $self->{error}="Unable to decode data of type ".$t->type()." from file ".$self->{pars}{location}."/$name: ".$t->error();
         return 0;
      }
        
      return 1;
   } else {
      # file is not opened.
      $self->{error}="File has not been opened.";
      return 0;
   }
}

# I: name:scalar
# O: 1 - success, 0 = failure
# C: save current content-var. All parameters are optional. Name is filename to save to and it is overwritten.
sub save {
   my $self = shift;
   my $name = shift || $self->{pars}{name};

   # check that file is already open
   if ($self->opened()) {
      # get filehandle
      my $FH=$self->{FH};
      # get contentcollection
      my $coll=$self->{pars}{collection};
      # go through each element in collection and save
      $coll->resetnext();
      my $data="";
      my $e;
      my $c;
      while (defined ($c=$coll->next())) {
         # try encoding it
         if ($e=$c->encode()) {
            # success - add to data
            $data=($data eq "" ? $data : $data.$c->delimiter());
            $data.=$e;
         } else {
            # failed encoding
            $self->{error}="Unable to convert content into its correct format ".$c->type().": ".$c->error();
            # abort encoding the collection
            return 0; 
         }
      }

      if (print $FH $data) {
         # success
         return 1;
      } else {
         # failure
         $self->{error}="Unable to save contents to file ".$self->{pars}{location}."/$name: $!";
         return 0;
      }
   } else {
      # failure to open file
      $self->{error}="File has not been opened.";
      return 0;
   }
}

# I: name:scalar
# O: 1 on success, 0 on failure
# C: Attempt deletion of datacontainer. All parameters are optional and if name is not given, it is taken from the instance. To be overridden bhy inheriting class.
sub delete {
   my $self = shift;
   my $name = shift || $self->{pars}{name};

   if (!$self->opened()) {
      # attempt to delete file
      if (unlink($self->{pars}{location}."/$name")) {
         # success
         return 1;
      } else {
         # failure
         $self->{error}="Failed to delete file ".$self->{pars}{location}."/$name: $!.";
         return 0;
      }
   } else {
      # cannot delete file when filehandle is open
      $self->{error}="Unable to delete file ".$self->{pars}{location}."/$name when filehandle is open. Please close the file.";
      return 0;
   }
}

1;

__END__

=encoding UTF-8

=head1 NAME

B<DataContainer::File> Class to interface a DataContainer with a file. Placeholder and is to be overridden.

=head1 METHODS

=head2 open()

Open connection to DataContainer-file.

Accepts one parameter, "name" to specify the name of the file to open.

The method checks the mode()-method to find out which mode the DataContainer 
might be in.

Returns 1 upon success, 0 upon failure.

See documentation of the DataContainer-class for more information on this method.

=cut

=head2 close()

Attempts to close the DataContainer if possible.

Accepts no input.

Returns 1 upon success, 0 upon failure.

=cut

=head2 load()

Loads data into the DataContainer.

Optional parameter of "name" might be given. SCALAR. Optional. If specified overrides the parameter 
set by the constructor.

Returns 1 upon success, 0 upon failure. Please check the error()-method upon failure.

=head2 save()

Attempt to save data into the DataContainer.

Optional parameter "name" which specified where to store the file? If not specified, defaults to 
what was specified to the new()-constructor.

Returns 1 upon success, 0 upon failfure. Please check the error()-method upon any failure for more 
information.

=cut

=head2 delete

Removing data from the DataContainer.

Optional parameter "name" might be specified. SCALAR. Sets the name of the DataContainer. Only has 
meaning to the inheriting class, and in this case it refers to the file-name.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

=cut
