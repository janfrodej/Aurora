#!/usr/bin/perl -w
#
# Copyright 2019-2024 Jan Frode Jæger, NTNU, Trondheim, Norway
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
# Interface: Placeholder-class that defines an interface for a dataset in AURORA
#
package Interface;

use strict;
use POSIX;
use Time::HiRes qw(time);
use Settings;
use AuroraDB;
use SysSchema;

our %CHILDS;

sub new {
   my $class=shift;
   my $self={};
   bless ($self,$class);

   my %pars=@_;
   if ((!$pars{cfg}) || (!$pars{cfg}->isa("Settings"))) { $pars{cfg}=Settings->new(); }
   if ((!$pars{db}) || (!$pars{cfg}->isa("AuroraDB"))) { $pars{db}=AuroraDB->new(); }
   if (!$pars{timeout}) { $pars{timeout}=3600; } # default to an hour timeout, 0=no timeout

   $self->{pars}=\%pars;

   # set to not rendering
   $self->{isrendering}=0;

   # define options - this is to be overridden in the inheriting class
   my %o;
   #$o{"option"}{format}="[TRUE/FALSE]";
   #$o{"option"}{regex}="[0-1]{1}";
   #$o{"option"}{length}=1;
   #$o{"option"}{mandatory}=1;
   #$o{"option"}{default}=0;
   #$o{"option"}{description}="Sets if placeholder needs to do this or not.";

   $self->{options}=\%o;

   $self->{renderresult}="";

   # set type - to be overridden
   $self->{type}="application/octet-stream";

   # set distinguishable - to be overridden
   $self->{distinguishable}=1;
   # set multiple - to be overridden
   $self->{multiple}=1;

   return $self;
}

sub render {
   my $self=shift;
   my $id=shift || 0;
   my $userid=shift || 0;
   my @p;
   my $paths=shift || \@p;

   my $method=(caller(0))[3];

   if (!$self->isRendering()) {
      # check that options are ok
      my $options=$self->options();
      if ($self->check()) {
         # we are ready to start rendering
         $self->{isrendering}=1;
         $self->{renderresult}="";
         $self->{rendersize}=0;

         # clean relative paths
         for (my $i=0; $i < @{$paths}; $i++) {
            my $path=$paths->[$i] || "";

            # clean path
            $path=$SysSchema::CLEAN{pathsquash}->($path);
            # remove leading slash
            $path=~s/^\/(.*)$/$1/g;

            # set new value
            $paths->[$i]=$path;
         }
         # ensure we have at least one entry
         if (@{$paths} == 0) { push @{$paths},"."; }

         # create a one-way pipe
         pipe (my $read, my $write); 
         # save read handle          
         $self->{read}=$read;
         # save a timestamp
         $self->{alive}=time();
         # fork a child to handle the rendering process
         my $pid=fork();
         if (!defined $pid) {
            # failed to fork
            $self->{error}="$method: Unable to fork a process to render interface: $!";
            return 0;
         } elsif ($pid == 0) {
            # child - set name
            $0="AURORA ".ref($self)." rendering of $id";
            # reset child-list
            %CHILDS=();
            close ($read);
            # set autoflush
            $write->autoflush();
            # write initial timestamp
            print $write time()." INFO Started Rendering of Interface ".ref($self)."\n";
            # store write handler
            $self->{write}=$write;
            # execute the doRender()-method that performs the actual rendering
            $self->doRender($id,$userid,$paths);
            # attempt to close write-handle - not interested in result, just to have closed it safely
            eval { close ($write); };
            # end child
            exit(0);
         } else {
            # parent
            # save pid to list
            $CHILDS{$pid}=undef;
            # reap children
            $SIG{CHLD}=sub { foreach (keys %CHILDS) { my $p=$_; next if defined $CHILDS{$p}; if (waitpid($p,WNOHANG) > 0) { $CHILDS{$p}=$? >> 8; } } };
            # close write handle in this process
            eval { close ($write); };
            # save child pid of process reading filehandler
            $self->{pid}=$pid;
            # get its creation time
            my $ctime=(stat "/proc/$pid/stat")[10] || 0;
            # save it
            $self->{ctime}=$ctime;
            return 1;
         }
      } else {
         # check failed - error already set
         return 0;
      }
   } else {
      # still rendering..
      $self->{error}="$method: A Rendering- og Unrendering-process is already running.";
      return 0;
   }

   return 1;
}

sub doRender {
   my $self=shift;
   my $id=shift || 0;
   my $userid=shift || 0;
   my $paths=shift;

   # get write handler
   my $write=$self->{write};

   # do whatever rendering necessary, write to write-handler and return when finished. 
   
   # set that this process is rendering 
   print $write time()." MERENDERING 1\n";

   my $finished=0;
   my $error=0;
   my $count=0;
   while (1) {
      # do whatever
      $count++;
      if ($error) {
         print $write time()." ERROR $!\n";
         last;
      } elsif (!$finished) {
         print $write time()." INFO Wheels go round and round\n";
         if ($count >= 20) { print $write time()." SUCCESS 1234\n"; last; } 
      } else {
         print $write time()." MIME ThisIsMyRenderedResultOfGivenMIMEType\n";
         print $write time()." SUCCESS ALL\n";
         last;
      }
      # wait one second
      select (undef,undef,undef,1);
   }

   return;
}

sub unrender {
   my $self=shift;
   my $id=shift || 0;
   my $userid=shift || 0;
   my @p;
   my $paths=shift || \@p;

   my $method=(caller(0))[3];

   if (!$self->isRendering()) {
      # check that settings and options are ok
      my $options=$self->options();
      if ($self->check()) {
         # we are ready to start unrendering
         $self->{isrendering}=1;
         $self->{renderresult}="";
         $self->{rendersize}=0;

         # clean relative paths
         for (my $i=0; $i < @{$paths}; $i++) {
            my $path=$paths->[$i] || "";

            # clean path
            $path=$SysSchema::CLEAN{pathsquash}->($path);
            # remove leading slash
            $path=~s/^\/(.*)$//g;

            # set new value
            $paths->[$i]=$path;
         }
         # ensure we have at least one entry
         if (@{$paths} == 0) { push @{$paths},"."; }

         # create a one-way pipe
         pipe (my $read, my $write); 
         # save read handle          
         $self->{read}=$read;
         # save a timestamp
         $self->{alive}=time();
         # fork a child to handle the unrendering process
         my $pid=fork();
         if (!defined $pid) {
            # failed to fork
            $self->{error}="$method: Unable to fork a process to unrender interface: $!";
            return 0;
         } elsif ($pid == 0) {
            # child
            $0="AURORA ".ref($self)." unrendering of $id";
            %CHILDS=();
            eval { close ($read); };
            # set autoflush
            $write->autoflush();
            # write initial timestamp
            print $write time()." INFO Started Unrendering of Interface ".ref($self)."\n";
            # store write handler
            $self->{write}=$write;
            # execute the doUnrender()-method that performs the actual unrendering
            $self->doUnrender($id,$userid,$paths);
            # end child
            exit(0);
         } else {
            # parent
            # save to childs pid to list
            $CHILDS{$pid}=undef;
            # reap children
            $SIG{CHLD}=sub { foreach (keys %CHILDS) { my $p=$_; next if defined $CHILDS{$p}; if (waitpid($p,WNOHANG) > 0) { $CHILDS{$p}=$? >> 8; } } };
            # close write handle in this process
            eval { close ($write); };
            # save child pid of process reading filehandler
            $self->{pid}=$pid;
            # get its creation time
            my $ctime=(stat "/proc/$pid/stat")[10] || 0;
            # save it
            $self->{ctime}=$ctime;
            return 1;
         } 
      } else {
         # check failed - error already set
         return 0;
      }
   } else {
      # still rendering..
      $self->{error}="$method: A Unrendering- or Rendering-process is already running.";
      return 0;
   }

   return 1;
}

sub doUnrender {
   my $self=shift;
   my $id=shift || 0;
   my $userid=shift || 0;
   my $paths=shift;

   # get write handler
   my $write=$self->{write};

   # do whatever unrendering necessary, write to write-handler and return when finished. 
   
   # set that it is this process unrendering
   print $write time()." MERENDERING 1\n";


   my $finished=0;
   my $error=0;
   my $count=0;
   while (1) {
      # do whatever
      $count++;
      if ($error) {
         print $write time()." ERROR $!\n";
         last;
      } elsif (!$finished) {
         print $write time()." INFO Cleaning here and there\n";
         if ($count >= 20) { print $write time()." SUCCESS 0\n"; last; } 
      } else {
         print $write time()." MIME INVALID\n";
         print $write time()." SUCCESS ALL\n";
         last;
      }
      # wait one second
      select (undef,undef,undef,1);
   }

   return;
}

sub abortRender {
   my $self=shift;
   my $wait=shift || 20;

   my $method=(caller(0))[3];

   if ($self->{isrendering}) {
      my $pid=$self->{pid};
      my $ctime=$self->{ctime};
      my $cctime=(stat "/proc/$pid/stat")[10] || 0;
      if ($ctime == $cctime) {
         # process is running and the same - kill process gently
         eval { kill ("SIGKILL",$pid); };
         # wait a little bit
         my $timeout=time()+$wait; # wait up N seconds for soft kill
         while (1) {
            my $ctime=(stat "/proc/$pid/stat")[10] || 0;
  
            if (($ctime == 0) || (time() > $timeout)) { last; } # killed or timed out wait
         }
         
         # check if it is gone - if not hard kill
         my $cctime=(stat "/proc/$pid/stat")[10] || 0;
         if ($ctime == $cctime) { # matches what we know from before, hard-kill
            eval { kill("-SIGKILL",$pid); };
         }
 
         # change flags
         $self->{isrendering}=0;
         $self->{merendering}=0;
         $self->{rendersuccess}=0;
         $self->{renderresult}="";
         $self->{rendersize}=0;
         $self->{rendererr}="$method: Rendering- or Unrendering process aborted by user.";

         # close read handle
         my $read=$self->{read};
         eval { close($read); };

         # return success
         return 1;
      } 
      # not the same process, nothing to abort
      return 0;
   } else {
      # no rendering running
      return undef;
   }
}

sub renderResult {
   my $self=shift;

   my $method=(caller(0))[3];

   # only proceed if rendering was successful
   if ($self->renderSuccess()) {
      # successful - return render mime result as a LIST
      my @list;
      if ($self->multiple()) {
         @list=split("\n",$self->{renderresult});
      } else { 
         push @list,$self->{renderresult}; 
      }
      return \@list;
   } else {
      # rendering failed or never ran...error already set
      return undef;
   }
}

sub isRendering {
   my $self=shift;

   my $method=(caller(0))[3];

   if ($self->{isrendering}) {
      # rendering, but are we finished?
      my $read=$self->{read};
      # keep reading while there are lines
      while (1) {
         # do a non-blocking check if we have any input
         my $rin='';
         vec($rin,fileno($read),1) = 1;
         my $nfound=select ($rin,undef,undef,0);
         if ($nfound) {
            # get the latest line
            my $line=<$read>;
            # ensure some content
            $line=$line || "";
            # check line
            if ($line =~ /^([\d\.]+)\s+INFO\s+(.*)$/) { $self->{alive}=$1; next; }
            elsif ($line =~ /^([\d\.]+)\s+ERROR\s+(.*)$/) {
               $self->{alive}=$1; 
               $self->{rendererr}=$2 || ""; 
               $self->{isrendering}=0;
               $self->{rendersuccess}=0;
               eval { close ($read); }; 
               return 0; 
            }
            elsif ($line =~ /^([\d\.]+)\s+MIME\s+(.*)$/) {
               $self->{alive}=$1; 
               $self->{renderresult}=($self->{renderresult} eq "" ? $2 : $self->{renderresult}."\n".$2);
               next; 
            }
            elsif ($line =~ /^([\d\.]+)\s+SUCCESS\s+(\d+)$/) {
               $self->{alive}=$1;
               $self->{rendersize}=$2; 
               $self->{isrendering}=0; 
               $self->{rendersuccess}=1;
               # close read-handle safely. Not interested in result
               eval { close ($read); }; 
               return 0; 
            }
            elsif ($line =~ /^([\d\.]+)\s+MERENDERING\s+([0-1]{1})$/) {
               $self->{alive}=$1; 
               $self->{merendering}=$2;
               next;
            }
         } elsif ($nfound == -1) {
            # failure to read pipe, abort...
            $self->abortRender();
            return 0;
         }
         # no new input, check that process is still running
         my $pid=$self->{pid};
         my $ctime=$self->{ctime};
         my $cctime=(stat "/proc/$pid/stat")[10] || 0;
         if ($ctime == $cctime) {
            # process still running and we are presumably still rendering, check timeout
            my $time=time();
            my $alive=$self->{alive} || 0;
            my $timeout=$self->{pars}{timeout};
            if (($timeout == 0) || ($time < ($alive+$timeout))) {
               # still rendering and not timed out yet.
               return 1;
            }
            # we have timed out - kill process
            $self->abortRender();
            return 0; 
         } else { 
            # process does not exist or is not the same
            # double check that nothing is left in read-buffer
            $nfound=select ($rin,undef,undef,0);
            if ($nfound) { next; } # there has arrived more in the buffer, read again.           
            # nothing more in buffer, flag rendering as ended
            $self->{isrendering}=0;
            # close filehandle, if possible
            eval { close ($read); };
            return 0;
         }
      }
   } else {
      # not rendering
      return 0;
   }
}

sub meRendering {
   my $self=shift;

   return $self->{merendering} || 0;
}

sub renderType {
   my $self=shift;

   return $self->{type} || "application/octet-stream";;
}

sub renderAlive {
   my $self=shift;

   if ($self->{isrendering}) {
      # we are rendering, return latest alive timestamp
      return $self->{alive} || 0;
   } else {
      # we are not rendering, so no alive stamp
      return undef;
   }
}

sub renderSuccess {
   my $self=shift;

   if (!$self->{isrendering}) {
      # we have finished rendering or have not rendered at all
      return $self->{rendersuccess} || 0;
   }

   # still rendering
   return undef;
}

sub renderError {
   my $self=shift;

   if ((!$self->{isrendering}) && (!$self->renderSuccess())) {
      return $self->{rendererr} || "";
   } 

   # still rendering or we have renderSuccess, so no error
   return undef;
}

sub renderSize {
   my $self=shift;

   if ((!$self->{isrendering}) && ($self->renderSuccess())) {
      return $self->{rendersize} || 0; # return size in bytes
   }

   # still rendering or we do not have any success
   return undef;
}

sub distinguishable {
   my $self=shift;

   # default is that all renders are distinguishable across differing dataset ids
   if (!defined $self->{distinguishable}) { return 1; }
   else { return $self->{distinguishable}; }
}

sub multiple {
   my $self=shift;

   # default is that all rendering returns multiple MIME-results if applicable
   if (!defined $self->{multiple}) { return 1; }
   else { return $self->{multiple}; }
}

sub options {
   my $self=shift;
 
   # make copy
   my %o=%{$self->{options}};

   return \%o;
}

sub check {
   my $self=shift;

   my $method=(caller(0))[3];

   my $options=$self->options();
   my $cfg=$self->{pars}{cfg};

   # go through options
   my @omissing;
   foreach (keys %{$options}) {
      my $key=$_;

      my $opt=$self->{pars}{$key};
      my $format=$options->{$key}{format} || "";
      my $regex=$options->{$key}{regex} || ".*";
      my $qregex=qq($regex);
      my $length=$options->{$key}{length} || 1;
      my $mandatory=$options->{$key}{mandatory} || 0;
      my $default=$options->{$key}{default};
      my $desc=$options->{$key}{desc} || "";
    
      if (($mandatory) && (!defined $opt) && (!defined $default)) {
         # undefined, no default, but needed
         push @omissing,$key;
         next;
      }

      if (!defined $opt) { $opt=$default; }

      # chop to max length
      $opt=substr($opt,0,$length);

      if ($opt !~ /^$qregex$/) {
         # fails regex check
         push @omissing,$key;
         next;
      }
   }

   # check if we have any missing or not
   # meeting requirements
   if (@omissing > 0) {
      # some are not meeting requirements
      $self->{error}="$method: Failed requirement(s) of options. The following were missing and/or failed their requirements: @omissing";
      return 0;
   }

   # we have success
   return 1;
}

sub error {
   my $self=shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Interface> - A placeholder class for interfaces to AURORA dataset data.

=cut

=head1 SYNOPSIS

   use Interface;

   $i=Interface->new(cfg=$cfg);

   # render interface for dataset with id 192, userid 3
   $i->render(192,3);

   # unrender/remove rendering of interface
   $i->unrender(192,3);

   # check if still rendering
   $i->isRendering();

   # check if it is this process/instance that is doing the actual
   # rendering
   $i->meRendering();

   # abort rendering
   $i->abortRender();

   # check if rendering was successful
   $i->renderSuccess();

   # get render error message if rendering not successful
   $i->renderError();

   # get result of rendering, conforms to MIME type in renderType()
   my $loc=$i->renderResult();

   # get MIME rendertype
   my $type=$i->renderType();
   
   # get needed options for class
   my $opt=$i->options();

   # does interface-class produce
   # distinguishable MIME renders?
   $i->distinguishable();

   # does interface-class accept
   # multiple paths for rendering?
   $i->multiple();

   # get last error
   my $err=$i->error();

=cut

=head1 DESCRIPTION

Placeholder class for interfaces to AURORA dataset data. The Interface-classes are meant to be used to render various interface views to 
the data of a AURORA dataset and then return a location reference to that rendered interface view.

The class is meant to be overridden to offer rendering of interfaces of various types.

It offers rendering, unrendering (for those interfaces where that has meaning), checking if a rendering is still running, get which 
options are needed.

=head1 CONSTRUCTOR

=head2 new()

Contructor of class.

It takes one parameter:

=over

=item

B<db> AuroraDB-class instance for use if class needs to get or set data. Required.

=cut

=item

B<cfg> Settings-class instance that gives the configuration file where the configuration settings are residing. This option is required.

=cut

=item

B<timeout> Sets the timeout in seconds to wait for non-responsive rendering process before attempting to kill it. The default is an hour. 0 means no timeout or wait forever. Optional.

=back

This constructor is meant to be overridden by inheriting class, where one first runs the SUPER-method before setting the options hash 
for the inheriting class in question.

=cut

=head1 METHODS

=head2 render()

Attempts to start the rendering process.

It takes as input the dataset id (required), the user id (required) andrelative paths in dataset as a LIST-reference (optional, default /),

The method forks out a separate process to handle the rendering and then returns to the caller. The separate rendering process are to be 
written in the doRender()-method by the inheriting class.

Status updates on the rendering process are retrieved by the caller by running the isRendering()-method.

Returns 1 upon successfully starting rendering or 0 upon some failure. Check the error()-method for more information on a potential error.

=cut

=head2 doRender()

Performs the actual rendering process and returns status by writing to the opened write-pipe. This method is not to be called by the user, but 
by the render()-method.

It always takes these inputs: dataset id, user id and paths (LIST-reference).

The method shall always be able to check if a rendering is already running of the given path(s) by checking in a database or in a 
filesystem without the need to check for a running process or in memory. If one is running already it should wait for this to  
finish and write INFO-level messages to the parent in the meantime (thereby giving the appearance that is is doing the rendering and 
the modules method can continue to function as if they were). Upon success it should send a SUCCESS-message. For every MIME-result it is 
to send a MIME-level message with the right MIME-content (see below).
When it has successfully determined if the rendering is already running or not, it is to signal this by writing a MERENDERING-level 
message to the parent. It is to be either 1 (it is this process that is doing the actual rendering) or 0 (it is another process doing it). 
By doing this the user can determine if is another process doing the work or not and eg. thereby decide to not keep the current 
process running since it is not doing any actual work.

The actual implementation of this process is up to the inheriting class. The only requirements are that the process regularly writes to the 
opened write-pipe ($self->{write}), so that the parent process can know what is happening? The three valid formats for writing to the write-pipe are:

   time INFO somemessage
   time ERROR somemessage
   time MIME MIME-result of rendering (there might be several)
   time SUCCESS SIZE 
   time MERENDERING [0|1]

with time is meant the current time when writing to the pipe. The INFO level is to be used when the rendering process is running to update 
what is happening? If the process fails, it is to write a ERROR-level message and then clean up and end its process. If the rendering is 
successful it is to write a SUCCESS-level message and end its process. The SIZE-part of the SUCCESS-level message is the size of the 
rendered result. If that result is just MIME-strings, then it is to be 0. If the result has been generated by the render()-method, then it 
should reflect the size of whatever was generated. When a MIME-result has been generated it is to write a MIME-level message. 
The mime-message is to be followed by the MIME-result (there might be many) of the rendering as defined in the $self->{type} that 
is returned by the renderType()-method. The MERENDERING level is to be used as quickly as the process has determined that it is it who 
is doing the actual rendering/unrendering (and not waiting on another process).

The MIME-level messages should be written in the order that the paths-list is specified into the render()-method, so that the user can 
expect to get that order on the MIME-return value(s) from the renderResult()-method. This is obviously only important in cases where there is 
more than one MIME-result.

It is also recommended that an inheriting class writes a SIG-handler for SIGKILL to handle ending the process in a gentle manner and cleaning up 
although it is not required.

This method returns nothing and it is not checked by the caller (which is the child-process).

=cut

=head2 unrender()

Reverses the render process, if applicable. To be overridden by the inheriting class.

This method takes the dataset id (required), the user id (required) and paths as a LIST-reference (optional, defaults to /).

The method is to reverse any rendering process if it is applicable to the inheriting class. Eg. if the inheriting class is an interface to 
generate ZIP- or TAR-files the unrender-process might then clean up and remove those generated files. In other cases, such as with the rendering 
process just returning an URL, there might be no applicable clean up or unrender-process.

It is also good form to check if the rendering-process completed successfully before attempting a cleanup by calling the renderSuccess()-method.

In any event, this method is to always return 1 upon success, whether it did anything or not. 0 upon some possible failure and the error-message 
set in $self->{error}.

=cut

=head2 doUnrender()

Performs the actual unrendering process and returns status by writing to the opened write-pipe. This method is not to be called by the user, but 
by the unrender()-method.

It always takes the following input: dataset id, userid and paths.

The method shall always be able to check if an unrendering is already running of the given path(s) by checking in a database or in a 
filesystem without the need to check for a running process or in memory. If one is running already it should wait for this to  
finish and write INFO-level messages to the parent in the meantime (thereby giving the appearance that is is doing the rendering and 
the modules methods can continue to function as if they were). It also is to send one MIME-level message with the "INVALID" as its result. 
Upon success it should send a SUCCESS-message with the SIZE-part set to 0.
When it has successfully determined if the unrendering is already running or not, it is to signal this by writing a MERENDERING level 
message to the parent. It is to be either 1 (it is this process that is doing the actual unrendering) or 0 (it is another process doing it). 
By doing this the user can determine if is another process doing the work or not and eg. thereby decide to not keep the current 
process running since it is not doing any actual work.

The actual implementation of this process is up to the inheriting class. The only requirements are that the process regularly writes to the 
opened write-pipe ($self->{write}), so that the parent process can know what is happening? The three valid formats for writing to the write-pipe are:

   time INFO somemessage
   time ERROR somemessage
   time MIME MIME-result (it may be many)
   time SUCCESS 0
   time MERENDERING [1|0]

with time is meant the current time when writing to the pipe. The INFO level is to be used when the unrendering process is running to update 
what is happening? If the process fails, it is to write a ERROR-level message and then clean up and end its process. If the unrendering is 
successful it is to write a SUCCESS-level message with size 0 and ends its process. MIME-message is to be followed by the the uppercase word 
INVALID to signify that it no longer has a valid MIME-result to give out. A MERENDERING-level message is to be used as quickly as the 
process has determined if it is it or not that is doing the actual rendering/unrendering (and not another process).

It is also recommended that an inheriting class writes a SIG-handler for SIGKILL to handle ending the process in a gentle manner and cleaning up 
although it is not required.

This method returns nothing and it is not checked by the caller (which is the child-process).

=cut

=head2 abortRender()

Attempt to abort a rendering- or unrendering-process.

This method attempts to abort a rendering- or unrendering-process by running a soft kill on the process and then after 20 seconds if it hasn't completed, to do 
a group- or hard kill.

The method accepts one, optional input which is the time to wait for the soft kill in seconds. This will then override the default 20 seconds.

The method returns 1 upon success, 0 upon some failure and undef if no process is rendering/unrendering. Please check the error()-method for more information 
upon a 0-type failure.

=cut

=head2 renderResult()

Returns the MIME result of the rendering in conformity with the renderType()-output.

No input accepted.

It returns the MIME result if the rendering was successful, or undef if rendering still running or not successful. Check the error()-method for
any potential error-messages.

The MIME-result is returned as a LIST-reference. It may contain 1 or more MIME-results depending upon the Interface-class in question and 
which paths and options were specified to it. One can inquire about possible multiple answers by calling the multiple()-method. In any event 
this method will always return a LIST-reference.

The rendered result LIST will come in the order that the inheriting class has fed it back through pipes to the isRendering()-method. However, 
it is recommended that the order should be based upon the order of the paths-input to the render()-method. So one is to expect the same 
order as the paths-input if nothing else is stated.

If the process that was run was an unrendering-process, the MIME result should say just "INVALID".

=cut

=head2 isRendering()

Checks if the rendering- or unrendering-process is still running.

This method pulls the read-handle of the pipe with the child-process. It does this without blocking. If it hears new lines in the pipe it also 
updates the alive-timestamp retrievable in by the renderAlive()-method. It also checks to see if the rendering-/unrendering-process failed (ERROR) or 
completed successfully (SUCCESS). It sets applicable rendersuccess and rendererror information.

It will also check to see if timeout has been reached if no, new information has been received through the pipe. 
If timeout has been reached, it will kill off the rendering-/unrendering-process by calling the abortRender()-method.

The method returns 1 if rendering-/unrendering-process is still running, 0 if not.

=cut

=head2 meRendering()

Returns if it is/was this instance of the class that is/was actually doing the rendering/unrendering or not?

It accepts no input.

It will return 1 to signal that it is this process doing the actual rendering/unrendering, 0 if not.

It will also works after the rendering has completed and are to be used in cases where the rendering is so quick that 
one is not able to determine if it was this process rendering/unrendering in a isRendering()-loop.

It is not able to distinguish between if a process has run or not. It will only return 0 or 1, so take care to only call it 
after you know that you have run a rendering/unrendering in order to know that result will reflect actual circumstances. This means 
reading the read buffer by calling isRendering() for some seconds or emptying the read buffer by calling the isRendering()-method 
until it returns 0 (the latter is not feasable in cases where the rendering takes time).

=cut

=head2 renderType()

Returns the MIME return type of the interface class. 

This type is set in the new()-method.

=cut

=head2 renderAlive()

Returns the alive timestamp of the rendering-/unrendering-process if applicable.

It will return the timestamp or 0 if no timestamp has been set. If the rendering-/unrendering-process is not running it will return undef.

=cut

=head2 renderSuccess()

Returns if the rendering-/unrendering-process was a success or not.

If the rendering-/unrendering-process was successful it will return 1, 0 if not successful or never ran. 
If the renderimg-process is still running it will return undef.

=cut

=head2 renderError()

Returns the possible error message of a rendering-/unrendering-failure.

It will return the rendering/unrendering error message if the process has stopped and the rendering-/unrendering was not successful. If the rendering/unrendering was never run 
it will return a blank string.

If the rendering/unrendering is still running or it was successful it returns undef.

=cut

=head2 renderSize()

Returns the size of the rendered result.

If that result is just the MIME-string, then it should return 0. If the result is 
pointed to by the MIME-string and has been generated by the render()-method, then it should return its size in bytes.

The method returns 0 or greater if rendering has ended and it was a render-success. Otherwise it returns undef.

The size is set in the $self->{rendersize}-variable and this is what is returned by this method. The inheriting class is not to 
change this method, but send information through the SUCCESS-level message (se the doRender()- and doUnrender()-methods).

=cut

=head2 distinguishable()

Returns if the interface class is able to render MIME-results that are distinguishable across differing dataset ids.

If the interface-class will produce the same MIME result from rendering independant of the dataset id given 
to the class, the distinguishable()-method will return false. If it produces differing MIME result when giving 
different dataset ids the distinguishable()-method will return true.

No input is accepted. The return value is 1 for true, 0 for false.

The setting is read from the internal $self->{distinguishable}-variable. If no setting can be found the method 
will default to 1 (true). The internal variable is meant to be overridden by the inheriting class in the new()-method of that class. 

=cut

=head2 multiple()

Returns if the interface-class renders multiple MIME-results or not dependant upon input paths and options.

No input it accepted.

The method returns 1 for true, 0 for false. 

The settings is read from the internal $self->{multiple}-variable. If it has not been set the method will 
default to 1 (true). The internal variable is to be overridden by the inheriting class in the new()-method.

=cut

=head2 options()

Returns the options HASH-reference of all needed options for the class.

The format of the options HASH is:

   ( KEY => { format => "[SOME FORMAT EXPLANATION]",
              regex  => "SOME_REGEX_EXPRESSION",
              length => SCALAR,
              mandatory => [0|1],
              default => DEFAULT_VALUE,
              description => DESCRIPTION_OF_OPTION,
            }
   )

The inheriting class can have as many keys as it wants. This structure is defined in the new()-method of the inheriting class. Format is the 
textual explanation of the value needed on this key. Regex is the regex-expression that the value needs to meet, length is the maximum length that 
a value here can be. Mandatory sets if the value needs to be answered or not. Default sets a default value that can be used if not answered in 
the input to the render()-/unrender()-method. Description sets a textual description of the key.

Returns a hash reference to options HASH.

=cut

=head2 check()

Checks to see if the options needed fulfill requirements or not. This method is not to be called by the user.

Goes through each options specified to the new()-method and check to see if it can find any overrides in the $self->{pars}{OPTIONNAME} and 
then checks if that override meets regex.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon a failure.

=cut

=head2 error()

Returns the last error message from the class, if any.

=cut
