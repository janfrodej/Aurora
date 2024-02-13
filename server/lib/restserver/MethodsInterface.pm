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
# MethodsInterface: Interface-entity methods for the AURORA REST-server
#
package MethodsInterface;
use strict;
use RestTools;
use POSIX;
use Interface::Archive::tar;
use Interface::Archive::zip;
use Interface::CIFS;
use Interface::URL;

our %CHILDS;

sub registermethods {
   my $srv = shift;

   $srv->addMethod("/deleteInterface",\&deleteInterface,"Delete an interface.");
   $srv->addMethod("/enumInterfaces",\&enumInterfaces,"Enumerates all interfaces.");
   $srv->addMethod("/getInterface",\&getInterface,"Gets an interfaces metadata.");
   $srv->addMethod("/moveInterface",\&moveInterface,"Move interface to another group.");
   $srv->addMethod("/renderInterface",\&renderInterface,"Renders an interface.");
   $srv->addMethod("/setInterfaceName",\&setInterfaceName,"Sets/changes an interfaces name.");
   $srv->addMethod("/unrenderInterface",\&unrenderInterface,"Unrenders an interface.");
}

sub deleteInterface {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="INTERFACE";
   MethodsReuse::deleteEntity($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub enumInterfaces {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="INTERFACE";
   MethodsReuse::enumEntities($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("interfaces",$mess->value("interfaces"));
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub getInterface {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $interface=$Schema::CLEAN{entity}->($query->{id});

   # check if interface exists and is the right type
   if ((!$db->existsEntity($interface)) || ($db->getEntityType($interface) != ($db->getEntityTypeIdByName("INTERFACE"))[0])) {
      # does not exist 
      $content->value("errstr","Interface $interface does not exist or is not a INTERFACE entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # we have a valid interface id, not perms needed to get its metadata
   my $md=$db->getEntityMetadata($interface);

   if (!defined $md) {
      # failed
      $content->value("errstr","Unable to read interface $interface\'s metadata: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   # we have the metadata ...
   my $class=$md->{$SysSchema::MD{"interface.class"}} || "UNKNOWN";
   my $name=$md->{$SysSchema::MD{name}} || "UNKNOWN";

   # retrieve all classparams for this interface
   my $qpbase=qq($SysSchema::MD{"interface.parbase"});
   my %classparam;
   foreach (grep { $_ =~ /^$qpbase\.[a-zA-Z0-9]+$/ } keys %{$md}) {
      my $key=$_;
      # get parameter name
      $key=~/^$qpbase\.([a-zA-Z0-9]+)$/;
      my $name=$1 || "dummy";
      
      if (($name ne "cfg") && ($name ne "db")) {
         $classparam{$name}=$md->{$key};
      }
   }

   # instantiate interface class to get more metadata
   my $iface; 
   my $err;
   local $@;
   eval { $iface=$class->new(cfg=>$cfg,%classparam); };
   $@ =~ /nefarious/;
   $err = $@;
   $err=(defined $err ? ": $err" : "");
   
   if (!defined $iface) {
      # failed
      $content->value("errstr","Could not instantiate render interface $interface ($class)$err");
      $content->value("err",1);
      return 0;
   }

   # we have an instance - make return info
   my %i;
   #get interface MIME-type
   $i{"type"}=$iface->renderType();
   # is it distinguishable?
   $i{"distinguishable"}=$iface->distinguishable();
   # does it produce more than one MIME-result?
   $i{"multiple"}=$iface->multiple();
   # set the metadata retrieved
   $i{"class"}=$class;
   $i{"name"}=$name;
   # add classparam
   $i{"classparam"}=\%classparam;
   # return the info
   $content->value("interface",\%i);
   # no errors
   $content->value("errstr","");
   $content->value("err",0);

   return 1;
}

sub moveInterface {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{parent}=$query->{parent};
   $opt{type}="INTERFACE";
   $opt{parenttype}="GROUP";
   MethodsReuse::moveEntity($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub setInterfaceName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{duplicates}=undef; # no duplicates in entire tree
   $opt{type}="INTERFACE";
   $opt{name}=$query->{name};
   # attempt to set name
   MethodsReuse::setEntityName($mess,\%opt,$db,$userid,$cfg,$log);

   # check result
   if ($mess->value("err") == 0) {
      # success
      $content->value("name",$mess->value("name"));
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # failure
      $content->value("errstr",$mess->value("errstr"));
      $content->value("err",1);
      return 0;
   }
}

sub renderInterface {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $interface=$Schema::CLEAN{entity}->($query->{id});
   my $id=$Schema::CLEAN{entity}->($query->{dataset}); 
   my $paths=$query->{paths};

   # check if interface exists and is the right type
   if ((!$db->existsEntity($interface)) || ($db->getEntityType($interface) != ($db->getEntityTypeIdByName("INTERFACE"))[0])) {
      # does not exist 
      $content->value("errstr","Interface $interface does not exist or is not a INTERFACE entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check if dataset id exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   if ((defined $paths) && (ref($paths) ne "ARRAY")) {
      # does not exist 
      $content->value("errstr","Paths is not an array. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["DATASET_READ"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the DATASET_READ permission on the DATASET $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # get interface class-name
   my $md=$db->getEntityMetadata($interface);

   if (!defined $md) {
      # failed
      $content->value("errstr","Unable to read interface $interface\'s metadata: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   my $class=$md->{$SysSchema::MD{"interface.class"}} || "UNKNOWN";

   # retrieve all classparams for this interface
   my $qpbase=qq($SysSchema::MD{"interface.parbase"});
   my %classparam;
   foreach (grep { $_ =~ /^$qpbase\.[a-zA-Z0-9]+$/ } keys %{$md}) {
      my $key=$_;
      # get parameter name
      $key=~/^$qpbase\.([a-zA-Z0-9]+)$/;
      my $name=$1 || "dummy";

      if (($name ne "cfg") && ($name ne "db")) {
         $classparam{$name}=$md->{$key};
      }
   }

   # we have parameters, perms and are ready to render interface - first create interface instance
   my $iface; 
   my $err;
   local $@;
   eval { $iface=$class->new(cfg=>$cfg,%classparam); };
   $@ =~ /nefarious/;
   $err = $@;
   $err=(defined $err ? ": $err" : "");
   
   if (!defined $iface) {
      # failed
      $content->value("errstr","Could not instantiate render interface $interface ($class)$err");
      $content->value("err",1);
      return 0;
   }

   # we have a render instance - start the rendering
   if (!$iface->render($id,$userid,$paths)) {
      # something failed
      $content->value("errstr","Could not start rendering interface: ".$iface->error());
      $content->value("err",1);
      return 0;
   }

   # we are rendering - wait a little bit (up to 1 sec) to see if we have a result or not
   my $time=time()+1;
   while ($iface->isRendering()) {
      my $now=time();

      if ($now > $time) { last; }

      # sleep
      select (undef,undef,undef,0.2);
   } 

   # check success
   if ($iface->isRendering()) {
      # we still do not have a result - check if I am the one who started the rendering
      if ($iface->meRendering()) {
         # I initiated the actual rendering, so we need to fork a parent process that can monitor/wait for it
         my $pid=fork();
         if (!defined $pid) {
            # failed forking
            $content->value("errstr","Unable to fork process to handle monitoring the rendering: $!");
            $content->value("err",1);
            return 0;
         } elsif ($pid == 0) {
            # child - wait for the process by calling the isRendering()-method
            %CHILDS=();
            while ($iface->isRendering()) {
               # we dont need to do anything besides waiting, isRendering() is doing the work
               select (undef,undef,undef,1);
            }
            # we are finished - exit
            exit(0);
         } else {
            # parent - clean up and exit
            # reap children
            $SIG{CHLD}=sub { foreach (keys %CHILDS) { my $p=$_; next if defined $CHILDS{$p}; if (waitpid($p,WNOHANG) > 0) { $CHILDS{$p}=$? >> 8; } } };
            # update parent child list
            $CHILDS{$pid}=undef;
#            waitpid (-1,WNOHANG);
            # defined return message
            $content->value("rendered",0); # still rendering 
            $content->value("type",$iface->renderType()); # return MIME type of potential result
            my @result;
            $content->value("result",\@result); # we set the result blank, since it it still rendering
            $content->value("errstr","");
            $content->value("err",0);
            return 1;
         }
      } else {
         # it is not me rendering, so lets just exit
         $content->value("rendered",0); # still rendering 
         $content->value("type",$iface->renderType()); # return MIME type of potential result
         my @result;
         $content->value("result",\@result); # we set the result blank, since it is still rendering
         $content->value("errstr","");
         $content->value("err",0);
         return 1;
      }
   } elsif ($iface->renderSuccess()) {
      # we have a successful result - return it
      $content->value("rendered",1); # finished rendering
      $content->value("type",$iface->renderType()); # return MIME type of result
      $content->value("result",\@{$iface->renderResult()}); # set the MIME rendering result
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # we have a failure
      $content->value("errstr","We had a failure during rendering: ".$iface->renderError());
      $content->value("err",1);
      return 0;
   } 
}

sub unrenderInterface {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   my $interface=$Schema::CLEAN{entity}->($query->{id});
   my $id=$Schema::CLEAN{entity}->($query->{dataset}); 
   my $paths=$query->{paths};

   # check if interface exists and is the right type
   if ((!$db->existsEntity($interface)) || ($db->getEntityType($interface) != ($db->getEntityTypeIdByName("INTERFACE"))[0])) {
      # does not exist 
      $content->value("errstr","Interface $interface does not exist or is not a INTERFACE entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # check if dataset id exists and is the right type
   if ((!$db->existsEntity($id)) || ($db->getEntityType($id) != ($db->getEntityTypeIdByName("DATASET"))[0])) {
      # does not exist 
      $content->value("errstr","Dataset $id does not exist or is not a DATASET entity. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   if ((defined $paths) && (ref($paths) ne "ARRAY")) {
      # does not exist 
      $content->value("errstr","Paths is not an array. Unable to fulfill request.");
      $content->value("err",1);
      return 0;
   }

   # user must have ALL of the perms on ANY of the levels
   my $allowed=hasPerm($db,$userid,$id,["DATASET_READ"],"ALL","ANY",1,1,undef,1);
   if (!$allowed) {
      # user does not have the required permission or something failed
      if (!defined $allowed) {
         $content->value("errstr","Something failed trying to check users permissions: ".$db->error().". Unable to fulfill request.");
         $content->value("err",1);
         return 0;
      } else {
         $content->value("errstr","User does not have the DATASET_READ permission on the DATASET $id. Unable to fulfill the request.");
         $content->value("err",1);
         return 0;
      }
   }

   # get interface class-name
   my $md=$db->getEntityMetadata($interface);

   if (!defined $md) {
      # failed
      $content->value("errstr","Unable to read interface $interface\'s metadata: ".$db->error());
      $content->value("err",1);
      return 0;
   }

   my $class=$md->{$SysSchema::MD{"interface.class"}} || "dummy";

   # retrieve all classparams for this interface
   my $qpbase=qq($SysSchema::MD{"interface.parbase"});
   my %classparam;
   foreach (grep { $_ =~ /^$qpbase\.[a-zA-Z0-9]+$/ } keys %{$md}) {
      my $key=$_;
      # get parameter name
      $key=~/^$qpbase\.([a-zA-Z0-9]+)$/;
      my $name=$1 || "dummy";

      if (($name ne "cfg") && ($name ne "db")) {
         $classparam{$name}=$md->{$key};
      }
   }

   # we have parameters, perms and are ready to render interface - first create interface instance
   my $iface; 
   my $err;
   local $@;
   eval { $iface=$class->new(cfg=>$cfg,%classparam); };
   $@ =~ /nefarious/;
   $err = $@;
   $err=(defined $err ? ": $err" : "");
   
   if (!defined $iface) {
      # failed
      $content->value("errstr","Could not instantiate render interface $interface ($class)$err");
      $content->value("err",1);
      return 0;
   }

   # we have a render instance - start the unrendering
   if (!$iface->unrender($id,$userid,$paths)) {
      # something failed
      $content->value("errstr","Could not start unrendering interface: ".$iface->error());
      $content->value("err",1);
      return 0;
   }

   # we are unrendering - wait a little bit (up to 1 sec) to see if we have a result or not
   my $time=time()+1;
   while ($iface->isRendering()) {
      my $now=time();

      if ($now > $time) { last; }

      # sleep
      select (undef,undef,undef,0.2);
   } 

   # check success
   if ($iface->isRendering()) {
      # we still do not have a result - check if I am the one who started the unrendering
      if ($iface->meRendering()) {
         # I initiated the actual rendering, so we need to fork a parent process that can monitor/wait for it
         my $pid=fork();
         if (!defined $pid) {
            # failed forking
            $content->value("errstr","Unable to fork process to handle monitoring the unrendering: $!");
            $content->value("err",1);
            return 0;
         } elsif ($pid == 0) {
            # child - wait for the process by calling the isRendering()-method
            %CHILDS=();
            while ($iface->isRendering()) {
               # we dont need to do anything besides waiting, isRendering() is doing the work
               select (undef,undef,undef,1);
            }
            # we are finished - exit
            exit(0);
         } else {
            # parent - clean up and exit
            # add child pid to list
            $CHILDS{$pid}=undef;
            # reap children
            $SIG{CHLD}=sub { foreach (keys %CHILDS) { my $p=$_; next if defined $CHILDS{$p}; if (waitpid($p,WNOHANG) > 0) { $CHILDS{$p}=$? >> 8; } } };
#            waitpid (-1,WNOHANG);
            # defined return message
            $content->value("unrendered",0); # still unrendering 
            $content->value("type",$iface->renderType()); # return MIME type of potential result
            $content->value("errstr","");
            $content->value("err",0);
            return 1;
         }
      } else {
         # it is not me unrendering, so lets just exit
         $content->value("unrendered",0); # still unrendering 
         $content->value("type",$iface->renderType()); # return MIME type of potential result
         $content->value("errstr","");
         $content->value("err",0);
         return 1;
      }
   } elsif ($iface->renderSuccess()) {
      # we have a successful result - return it
      $content->value("unrendered",1); # finished unrendering
      $content->value("type",$iface->renderType()); # return MIME type of result
      $content->value("errstr","");
      $content->value("err",0);
      return 1;
   } else {
      # we have a failure
      $content->value("errstr","We had a failure during unrendering: ".$iface->renderError());
      $content->value("err",1);
      return 0;
   } 
}

1;

__END__

=encoding UTF-8

=head1 INTERFACE METHODS

=head2 deleteInterface()

Delete interface entity.

Input parameters:

=over

=item 

B<id> Interface entity ID from database of interface to delete.

=cut

=back

This methods requires that the user has the INTERFACE_DELETE permission on the interface being deleted.

=cut

=head2 enumInterfaces()

Enumerates all the interfaces.

No input accepted.

Upon success returns the following structure:

  interfaces => (
                   INTERFACEIDa => STRING # key-value pair. The key is the name of the field and STRING is the textual value of the key
                   .
                   .
                   INTERFACEIDn => ( .. )
                )

=cut

=head2 getInterface()

Gets an interface.

Input parameters are:

=over

=item

B<id> Interface entity ID from database of interface to retrieve. INTEGER. Required.

=cut

=back

Returns the following structure upon success:

  interface => (
                 type => STRING            # MIME render type
                 distinguisable => INTEGER # 1 for TRUE, 0 for FALSE.
                 multiple => INTEGER       # 1 for TRUE, 0 for FALSE. Does it produce more than one mime-result?
                 class => STRING # textual name of a render class, eg. Interface::CIFS.
                 name => STRING  # textual display name of this renderer - often the same as the class
                 classparam => HASH # subkey hash with parameters for the class instantiation. key->value.
               )

=cut

=head2 moveInterface()

Move an interface to another group.

Input parameters are this:

=over

=item

B<id> Group interface ID from the database of the object being moved. INTEGER. Required.

=cut

=item

B<parent> Group parent ID from database where the specified dataset is to be moved. INTEGER. Required.

=cut

=back

This method requires that the user has the INTERFACE_MOVE permission on the interface being moved and 
the INTERFACE_CREATE permission on the new parent.

=cut

=head2 renderInterface()

Renders an interface to a dataset.

Input parameters:

=over

=item

B<id> Interface entity ID from the database of the interface to use for the rendering. INTEGER. Required.

=cut

=item

B<dataset> Dataset entity ID from the database of the dataset that is the source of the render. INTEGER. 
Required.

=cut

=item

B<paths> A set of relative paths in dataset of the folders to include in the render. ARRAY of STRING. 
Optional. If not specified will render the entire dataset. 

=cut

=back

This method requires that the user has the DATASET_READ permission on the dataset being rendered.

This method can render any interface that the AURORA system is using. An interface is a way of getting 
access to a dataset, it may be as a ZIP- or TAR-file or as a URL and so on.

Upon success this method will return different structure dependant upon the status of the rendering. The 
rendering process might take time.

If the rendering was started successfully, but did not finish immediately, the structure will look like this:

  rendered => INTEGER # this will be 0 signifying that it is still not rendered (=still rendering).
  type => STRING # MIME-type of the rendered result
  result => ARRAY of STRING # this is the rendered MIME-result - it may point to places where the rendered result can be downloaded.

If the rendering has completed successfully, the structure will look like here:

  rendered => INTEGER # this will now be 1, as it is finished rendering.
  type => STRING # MIME-type of the rendered result.
  result => ARRAY of STRING # contains the rendered MIME-result - it might point elsewhere...

So, if a rendering of an interface is not finished yet, the user of will have to call this method several 
times with the same input (especially the paths-parameter). Differing paths-sets can create differing 
renders, although the order of the paths does not matter (it is sorted ascending). Eventually the 
method will return the "rendered"-parameter as completed/finished successfully.

=cut

=head2 setInterfaceName()

Set the display name of the interface.

Input parameters:

=over

=item

B<id> Interface entity ID from the database of the interface to change name. INTEGER. Required.

=cut

=item

B<name> The new interface name to set. STRING. Required. Does not accept blank string and the new name must not 
conflict with any existing interface name in the entire tree (including itself).

=cut

=back

Method requires the user to have the INTERFACE_CHANGE permission on the computer changing its name.

=cut

=head2 unrenderInterface()

Unrenders an interface to a dataset.

Input parameters:

=over

=item

B<id> Interface entity ID from the database of the interface to use for the rendering. INTEGER. Required.

=cut

=item

B<dataset> Dataset entity ID from the database of the dataset that is the source of the render. INTEGER. 
Required.

=cut

=item

B<paths> A set of relative paths in dataset of the folders to include in the render. ARRAY of STRING. 
Optional. If not specified will render the entire dataset.

=cut

=back

This method requires that the user has the DATASET_READ permission on the dataset being rendered.

It is important to get the parameters correct in order to unrender a interface that has already been 
rendered. Especially the "paths"-parameter needs to have the exact same relative paths, or else it will
not work.

Upon success will return the following structure:

  unrendered = INTEGER # 0 = not unrendered, 1 = unrendered
  type = STRING # MIME-type of the render

This method can be called multiple times to check if it is finished rendering.

=cut
