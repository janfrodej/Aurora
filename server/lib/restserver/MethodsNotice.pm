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
# MethodsNotice: Notice-entity methods for the AURORA REST-server
#
package MethodsNotice;
use strict;
use RestTools;

sub registermethods {
   my $srv = shift;

   $srv->addMethod("/deleteNotice",\&deleteNotice,"Delete a notice.");
   $srv->addMethod("/enumNotices",\&enumNotices,"Enumerate all notices.");
   $srv->addMethod("/moveNotice",\&moveNotice,"Move notice to another group.");
   $srv->addMethod("/setNoticeName",\&setNoticeName,"Set display name of a notice.");
}

sub deleteNotice {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{type}="NOTICE";
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

sub enumNotices {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{type}="NOTICE";
   MethodsReuse::enumEntities($mess,\%opt,$db,$userid);

   # check return value
   if ($mess->value("err") == 0) {
      # success 
      $content->value("notices",$mess->value("notices"));
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

sub moveNotice {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{parent}=$query->{parent};
   $opt{type}="NOTICE";
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

sub setNoticeName {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # call general method
   my $class=ref($content);
   my $mess=$class->new();
   my %opt;
   $opt{id}=$query->{id};
   $opt{duplicates}=undef; # do duplicates in entire tree
   $opt{type}="NOTICE";
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

1;

__END__

=encoding UTF-8

=head1 NOTICE METHODS

=head2 deleteNotice() - Delete a notice

Delete a notice.

Input parameters:

=over

=item

B<id> Notice entity ID from the database of the notice to delete. INTEGER. Required.

=cut

=back

This method requires that the user has the NOTICE_DELETE permission on the notice in question.

=cut

=head2 enumNotices() - B<Enumerate all notices>

Enumerates all the notice entities in the database.

No input accepted.

Upon success the return structure is as follows:

  notices => (
               NOTICEIDa => STRING # key->value, where key is the notice entity ID and STRING is the display name of the notice-entity.
               .
               .
               NOTICEIDx => STRING
             )

=cut

=head2 moveNotice() - Move notice to another group parent

Move notice to another group parent.

Input parameters:

=over

=item

B<id> Notice entity ID from the database of the notice to move. INTEGER. Required.

=cut

=item

B<parent> Parent group entity ID from the database of the group which will be the new parent of the notice. INTEGER. 
Required.

=cut

=back

The method requires the user to have NOTICE_MOVE permission on the notice being moved and NOTICE_CREATE on the parent 
group it is being moved to.

=cut

=head2 setNoticeName()

Set/change the name of the notice.

Input parameters:

=over

=item

B<id> Notice entity ID from the database of the notice to change name. INTEGER. Required.

=cut

=item

B<name> The new notice name to set. STRING. Required. Does not accept blank string and the new name must not
conflict with any existing notice name on the entire entity tree (including itself).

=cut

=back

Method requires the user to have the NOTICE_CHANGE permission on the notice in question.

=cut

