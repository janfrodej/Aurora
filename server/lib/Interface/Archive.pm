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
# Interface::Archive - Class for rendering archives to AURORA datasets
#
package Interface::Archive;
use parent 'Interface';

use strict;
use FileInterface;
use sectools;
use POSIX;

sub new {
   my $class=shift;
   # invoke parent
   my $self=$class->SUPER::new(@_);

   # set redirect statement
   if (!exists $self->{pars}{redirect}) { $self->{pars}{redirect}="2>&1"; }
   # set location of echo binary
   if (!exists $self->{pars}{echo}) { $self->{pars}{echo}="/bin/echo"; }

   # define options
   my $o=$self->{options};
   $o->{"location"}{format}="[ABSOLUTE PATH]";
   $o->{"location"}{regex}="[^\000]+";
   $o->{"location"}{length}=4096;
   $o->{"location"}{mandatory}=1;
   $o->{"location"}{default}="/tmp";
   $o->{"location"}{description}="Absolute path to where archive files are created and stored.";

   $o->{"script"}{format}="[URL]";
   $o->{"script"}{regex}="[^\000]+";
   $o->{"script"}{length}=4096;
   $o->{"script"}{mandatory}=1;
   $o->{"script"}{default}="https://localhost/dl.cgi";
   $o->{"script"}{description}="URL to download script for archives";

   # set type. not application/tar or similar, but
   # the MIME return is the URL link to the tar-set.
   $self->{type}="text/uri-list";

   # set format - this is to be overridden by inheriting class.
   $self->{format}="unknown";

   # set multiple to 0. We only render one MIME-result independant of the number of paths
   $self->{multiple}=0;

   return $self;
}

sub doRender {
   my $self=shift;
   my $id=shift || 0;
   my $userid=shift || 0;
   my $paths=shift;

   sub files {
      my $folder = shift || "DUMMY";
      my $regex  = shift || ".*";
      my $appfolder = shift || 0;

      # clean away trailing slashes
      $folder =~ s/^(.*)\/+$/$1/;

      # read contents of folder
      opendir (DH,"$folder/") || return undef;
      my @items = sort {$a cmp $b} grep {/^($regex)$/} readdir DH;
      closedir DH;

      # append folder name if so specified
      if ($appfolder) {
         for (my $i=0; $i < @items; $i++) {
            $items[$i] = $folder."/".$items[$i];
         }
      }

      if (@items > 0) {
         return @items;
      } else {
         return undef;
      }
   }

   # get write handler
   my $write=$self->{write};

   # get options
   my $options=$self->options();
   # get archive location, or default
   my $location=$self->{pars}{location} || $options->{location}{default};

   # get paths in sorted order so we can make a proper sha256-sum out of them
   my $shastr="";
   # add path to shastr separated with \000s (they are not allowed in paths, so they are cleaned away in the path-string itself)
   $shastr=join("\000",sort {$a cmp $b} @{$paths});

   # make shasum
   my $shasum=sectools::sha256sum($shastr);

   # get format - set by inheriting class in new-method
   my $format=$self->{format} || "unknown";

   # some quoted versions
   my $qformat=qq($format);
   my $qid=qq($id);
   my $qshasum=qq($shasum);

   # get download script
   my $script=$self->{pars}{"script"} || $options->{"script"}{default};

   # Interface-class must be able to work stateless
   # first check if we are already rendering this archive
   my ($lock)=files("$location/","archive\_${id}\_${shasum}\_[a-z|A-Z|0-9]{64}\.$format\.lock",0);
   # then check if it already exists
   my ($exist)=files("$location/","archive\_${id}\_${shasum}\_[a-z|A-Z|0-9]{64}\.$format",0);
   if (defined $lock) {
      # archive is already rendering - wait for it
      print $write time()." MERENDERING 0\n";
      while (1) {
         my ($lock)=files("$location/","archive\_${id}\_${shasum}\_[a-z|A-Z|0-9]{64}\.$format\.lock",0);
         # then check if it already exists
         my ($exist)=files("$location/","archive\_${id}\_${shasum}\_[a-z|A-Z|0-9]{64}\.$format",0);
      
         if ((!defined $lock) && (!defined $exist)) {
            # something failed
            print $write time()." ERROR Rendering by other process failed. We do not know the reason.\n";
            return;
         } elsif (defined $lock) {
            # still rendering
            print $write time()." INFO Other process still rendering.\n";
         } elsif (defined $exist) {
            # rendering finished - get size
            my $size=(stat("$location/$exist"))[7] || 0;
            # get cookie
            $exist=~/^archive\_${qid}\_${qshasum}\_([a-z|A-Z|0-9]{64})\.$qformat$/;
            my $cookie=$1;
            # make a MIME response
            print $write time()." MIME $script?cookie=$cookie\n";
            print $write time()." SUCCESS $size\n";
            # we are finished - return
            return;
         }
         # wait two seconds
         select (undef,undef,undef,2);
      }
   } elsif (defined $exist) {
      # archive exists
      print $write time()." MERENDERING 0\n";
      # get size
      my $size=(stat("$location/$exist"))[7] || 0;
      # get cookie
      $exist=~/^archive\_${qid}\_${qshasum}\_([a-z|A-Z|0-9]{64})\.$qformat$/;
      my $cookie=$1;
      # make a MIME response
      print $write time()." MIME $script?cookie=$cookie\n";
      print $write time()." SUCCESS $size\n";
      # we are finished - return
      return;
   }

   # it is not being rendered or it has not already been rendered. Lets render it...
   print $write time()." MERENDERING 1\n";
   # make random cookie
   my $cookie=sectools::randstr(64);

   # create a unique endmarker for archiving process
   my $endmarker=sectools::randstr(32);
   my $qendmarker=qq($endmarker);

   # define destination archive-file
   my $destination="$location/archive_${id}_${shasum}_${cookie}.${format}";
   # create lock-file
   if (open (FH,">","$location/archive_${id}_${shasum}_${cookie}.${format}.lock")) {
      # writing nothing, just close it
      eval { close (FH); };
   }
 
   # get information from fileinterface
   my $fi=FileInterfaceClient->new();

   # ensure we have dataset and that it can be viewed
   if ($fi->mode($id) ne "ro") {
      # unable to start process
      my @sterr;
      my $err="";
      @sterr=$fi->yell(">"); 
      if (@sterr > 0) { $err=": @sterr"; }
      # print error messages
      print $write time(). " ERROR Unable to read dataset source$err\n";
      return;
   }

   # get source path
   my $source=$fi->datapath($id) || "/DUMMY/DUMMY";
   # start archive-process - set aread-handler
   $self->startArchiving($id,$userid,$paths,$source,$destination,$endmarker);
   # archiving started - get read and error handler
   my $aread=$self->{aread};
   # create a lines log
   my @lines;

   my $rin='';
   vec($rin,fileno($aread),1) = 1;
 
   my $rbuf="";
   my $ended=0;
   while (1) {        
      my $nfound=select (my $rout=$rin,undef,my $rfail=$rin,0.25);
      if ($nfound) {
         # check if there was anything on STDOUT/STDERR
         if (vec($rout, fileno($aread), 1)) {
            # read 
            my $data;
            my $no=sysread ($aread,$data,2048);
            if (!defined $no) {
               # error sysread
               print $write time()." INFO Unable to read STDOUT/STDERR from archive-process: $!\n";               
            } elsif ($no > 0) {
               # we have some data, update read-buffer
               $rbuf.=$data;
            } else {
               # EOF - finished with all reading
               $ended=1;
            }
         }
         # check for new lines from STDOUT/STDERR
         if ($rbuf =~ /^([^\n]*\n)(.*)$/) {
            # we have a new line
            my $line=$1;
            $line=~s/[\n]//g;
            $rbuf=$2;
            if (!defined $rbuf) { $rbuf=""; }
            # print the line to parent
            print $write time()." INFO $line\n";
            # save line
            push @lines,$line;
         }
      } 
      if (($ended) || ($nfound == -1)) {
         # finished reading/something failed....wait for child-process and harvest exitcode
         my $exitcode=0;
         my $child=$self->{apid};
         my $r=0;
         while ($r >= 0) { # wait for child-process (open3 in Interface::Archive::XYZ)
            $r=waitpid($child,WNOHANG); 
            if ($r > 0) { $exitcode=$? >> 8; }
         }
         eval { close ($aread); };
         if ($exitcode != 0) {
            # error - cleanup, remove lock-file
            unlink ("$location/archive_${id}_${shasum}_${cookie}.${format}.lock");
            unlink ("$location/archive_${id}_${shasum}_${cookie}.${format}");
            # get last line before endmarker
            my $size=@lines;
            my $error=$lines[$size-2];
            # notify
            print $write time()." ERROR Unable to render archive, exitcode $exitcode: $error\n";
            return;
         } else {
            # success - remove lock file
            if (unlink ("$location/archive_${id}_${shasum}_${cookie}.${format}.lock")) {
               # success - get size
               my $size=(stat("$location/archive_${id}_${shasum}_${cookie}.${format}"))[7] || 0;
               # notify with MIME-type
               print $write time()." MIME $script?cookie=$cookie\n";
               print $write time()." SUCCESS $size\n";
               return;
            } else {
               # failed to remove lock file - clean up
               unlink ("$location/archive_${id}_${shasum}_${cookie}.${format}");
               # notify
               print $write time()." ERROR Unable to remove lock file and get archive-file in production: $!\n";
               return;
            }
         }
      }
   } 
   return;
}

sub startArchiving {
   my $self=shift;
   my $id=shift || 0;
   my $userid=shift || 0;
   my $paths=shift;
   my $source=shift;
   my $destination=shift;
   my $endmarker=shift;

   my $oldfolder = getcwd();
   $oldfolder =~ /(.*)/;
   $oldfolder = $1;

   # change to folder to be backed up
   if ($source eq "/") { 
      pipe (my $read, my $write); 
      $self->{aread}=$read; 
      print $write "Source folder invalid ($source). Not allowed to proceed of security reasons.\nEXITCODE 1 $endmarker\n"; 
      return;
   }
 
   if (!chdir ("$source")) {
      pipe (my $read, my $write); 
      $self->{aread}=$read; 
      print $write "Unable to change directory to source folder ($source): $!\nEXITCODE 1 $endmarker\n"; 
      return;
   }

   # get binary 
   my $binary=$self->{pars}{binary};

   # construct sources (if needed)
   my $sources="";
   foreach (@{$paths}) {
      my $path=$_;

      $sources.=" ".quotemeta($path);
   }

   # get redirect and echo
   my $redirect=$self->{pars}{redirect} || "";
   my $echo=$self->{pars}{echo} || "";

   my $read;
   my $pid=open $read,"-|","$binary $source$sources $destination $redirect ; $echo \"EXITCODE \$\? $endmarker\" $redirect";
   # process running in background - store info
   $self->{apid}=$pid;
   $self->{actime}=(stat ("/proc/$pid/stat"))[10] || 0;
   # save pipe
   $self->{aread}=$read;
   chdir ($oldfolder);
   return;
}

sub doUnrender {
   my $self=shift;
   my $id=shift || 0;
   my $userid=shift || 0;
   my $paths=shift;

   # get write handler
   my $write=$self->{write};

   # get options
   my $options=$self->options();

   # get archive location, or default
   my $location=$self->{pars}{"location"} || $options->{"location"}{default};

   # get paths in sorted order so we can make a proper sha256-sum out of them
   my $shastr="";
   $shastr=join("\000",sort {$a cmp $b} @{$paths});

   # make shasum
   my $shasum=sectools::sha256sum($shastr);

   # get format - set by inheriting class in new-method
   my $format=$self->{format} || "unknown";

   # Interface-class must be able to work stateless
   # first check if we are already rendering this archive
   my ($lock)=files("$location/","archive\_${id}\_${shasum}\_[a-z|A-Z|0-9]{64}\.$format\.lock",0);
   # then check if it already exists
   my ($exist)=files("$location/","archive\_${id}\_${shasum}\_[a-z|A-Z|0-9]{64}\.$format",0);

   if (defined $lock) {
      # already rendering
      print $write time()." ERROR This archive is still being rendered by other process. Unable to unrender at this time.\n";
      return;
   } elsif (defined $exist) {
      # archive exists - we can unrender it.
      if (unlink ("$location/$exist")) {
         print $write time()." INFO Interface ".ref($self)." of dataset $id has been unrendered successfully\n";
         print $write time()." MIME INVALID\n";
         print $write time()." SUCCESS 0\n";
         return; 
      } else {
         print $write time()." ERROR Unable to unrender dataset $id interface ".ref($self).": $!\n";
         return;
      }
   } else {
      print $write time()." ERROR No archive found for this dataset $id. Unable to unrender interface ".ref($self)."\n";
      return;
   }
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Interface::Archive> - A placeholder-class to handle generating archive-sets from dataset data.

=cut

=head1 SYNOPSIS

   use Interface::Archive;

   # instantiate
   my $i=Interface::Archive->new(location=>"/path/whatever",script=>"https://somedomain/script.pl");

This class is used in the same way as the Interface-class. See documentation there for more information about the use 
of this class. None of the implemented methods in this class is meant to be called by the user.

=cut

=head1 DESCRIPTION

Class to handle the generation and management of archiving-sets of AURORA datasets. This class is just a placeholder and 
is not meant to be instantiated.

The class has three methods: doRender(), startArchiving() and doUnrender(). The doRender()-method is documented in the Interface.pm-class. The doRender()-class 
in this module sets up everything needed to generate archives of a AURORA dataset, and logs the process by writing pipe-messages to the parent process.

The doRender()-class in this module calls the method startArchiving() to start the actual archiving process. This method is meant to be overridden by 
inheriting classes to adapt it to the archive type in question.

The archive-sets that are created are placed in the area denoted by the "location"-option to the new()-method. The 
MIME result generated upon a successful rendering uses the "script"-option specified to the new()-method to tell it 
which script to invoke in order to fetch the generated archive.

In the location-area where the archive-files are placed, the file names are as follows:

   archive_DATASETID_SHA256SUM_COOKIE.FORMAT.lock
   archive_DATASETID_SHA256SUM_COOKIE.FORMAT

The .lock-ending is used while the archive is being generated. Upon successful completion it is moved to the filename without the ".lock" ending.

DATASETID is the AURORA dataset id. The SHA256SUM is the SHA256-sum of all the input paths to the doRender()-method (see the documentation for the 
render()-method in the Interface-class for more details), sorted alphabetically and separated with \000-characters. This is to allow a unique 
signature for the selected archived folders in a dataset, so that the filename can be found by searching for that signature. It also allows for 
unique signature of an archive-set dependent upon which folders were selected for archiving.

COOKIE is a random 64-byte string containing only a-zA-Z0-9. This is the unique signature used to fetch the filename via the download script 
mentioned above.

FORMAT is the archive set file ending, such as "tar.gz", "zip" etc. It is to be set by the inheriting class. It defaults to "unknown".

Upon a successful render of an archive-set, the renderResult()-method (see the documentation for the Interface-class) will return the MIME formatted 
URL to the set. This MIME-response uses the script-setting mentioned above, so that the returned URL is a combination of a location and name, appended 
with the COOKIE-string mentioned above for identification:

   https://domain/script.whatever?cookie=COOKIE

The doUnrender()-method removes any archive-set that might have been generated. It is called by the Unrender()-method (see documentation of the 
Interface-class).

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates class.

Inherits from Interface-class.

Sets the need for location- and script options. Sets the MIME-type and format. The format is meant to be overridden by 
inheriting child. It default to "unknown". See Description-paragraph for more information.

It takes the following additional parameters (see Interface-class documentation for other parameters):

=over

=item

B<location> Sets the path where the archives will be generated. Required.

=cut

=item

B<script> Sets the URL to the script where one can download the generated archive by specifying the cookie. Required.

=cut

=item

B<redirect> Sets the statement to redirect STDERR to STDOUT. Optional and defaults to 2>&1.

=cut

=item

B<echo> Sets location of the echo-binary. Optional and defaults to /bin/echo.

=cut

=back

The method returns the instantiated class.

=cut

=head1 METHODS

=head2 doRender()

The actual rendering process. Inherited from Interface (see Interface-class for more information on its use and purpose). It is called by the render()-method.

The method sets up the rendering process before calling the method startArchiving() and then monitors the archiving feeding information back to the 
parent process. The startArchiving()-method is meant to be overridden by inheriting classes.

It first attempts to check if there already exists a archive-file that matches the signature of the SHA256SUM and format (see Description-paragraph). 
It also checks if there is already a rendering going on by checking for the ".lock"-extension on the files. If a rendering is already running by 
another process it will start looping waiting for it to finish. If it finishes by removing the ".lock"-extension and the final archive file emerges, it
will return a SUCCESS-level message to the parent and send the MIME-message. In will in other words behave as if it was rendering the file itself, although 
it is just hanging back and waiting for the other process to finish.

If not archive exists already, it will setup the process to start archiving itself. After setting it up, opening the dataset data, it calls the 
startArchiving()-method and have it start the archiving command or process itself. It will then read and wait for messages from that process and feeding 
this back to the parent-process (see the doRender()-method documentation in the Interface-class for more information).

This method is not meant to be called by the user.

=cut

=head2 startArchiving()

Starts the archiving command or process itself. Returns a pipe read-handler to be able to monitor the process.

This method basically starts and runs the archiving command or process that does the actual work. It is expected to return a read-handler in 
$self->{aread} so that the calling method (doRender()) can monitor its progress.

It takes these parameters in the following order: DATASETID,USERID,PATHS,SOURCE,DESTINATION,ENDMARKER.

See the doRender()-method in the documentation of the Interface-class for more information on the DATASETID,USERID and PATHS paremeters.

The SOURCE parameter is where the dataset data is located (the root of it). The DESTINATION parameter gives the location and filename where the archive 
set is to be generated/stored. ENDMARKER is a random string that is written at the end of the archiving process to make it possible for the 
doRender()-method to easy know when it ended.

The method returns no data.

This method is not to be called by the user, but by the doRender()-method. The method is meant to be overridden by the inheriting class to start that 
specific type of archiving.

=cut

=head2 doUnrender()

Does the actual unrendering of an archived dataset.

It first checks to see if the given rendering exists or not or if it is still rendering. It does this by checking for the archived dataset file.

If it is still rendering, it returns with a error-message stating that, if it cant find it it also returns with a error message saying that.

It the archived dataset exists, it removes the file and then reports back.

This method is general for the Archive-class family and shouldn't be needed to be overridden. 

See the doUnrender()-method in the Interface-class for more documentation.

=cut
