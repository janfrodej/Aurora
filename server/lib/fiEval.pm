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
# fiEval - FileInterface-eval, class to eval methods with the FileInterface-class.
#
package fiEval;

use strict;
use FileInterface;

sub new {
   my $class=shift;
   my $self={};
   bless ($self,$class);

   $self->{success}=1;

   my %pars=@_;

   my $fi=$pars{fi};
   if ((!defined $pars{fi}) || (!$fi->isa("FileInterfaceClient"))) { 
      # no FileInterfaceClient-instance, attempt to create one
      my $err;
      {
         local $@; # protect existing $@
         eval { $fi=FileInterfaceClient->new(); };
         $@ =~ /nefarious/;
         $err=$@;
      }
 
      if ($err ne "") {
         # something failed
         $self->{error}="Unable to instantiate FileInterfaceClient-class: $err";
         $self->{success}=0;
      } else {
         $pars{fi}=$fi; 
      }
   }

   $self->{pars}=\%pars;

   return $self;
}

sub evaluate {
   my $self=shift;
   my $method=shift;
   my @pars=@_;

   $self->{success}=1;

   # get fi instance
   my $fi=$self->{pars}{fi};

   if (!defined $fi) {
      $self->{error}="FileInterfaceClient has not been instantiated. Unable to evaluate.";
      $self->{success}=0;
      return undef;
   }

   my $result;
   my $err;
   local $@; # protect existing $@
   eval { $result=$fi->$method(@pars); };
   $@ =~ /nefarious/;
   $err=$@;

   if (($err eq "") && ($result)) {
      # eval was a success - return result
      return $result;
   } else {
      # an error occured
      if ($err ne "") {
         $self->{error}=$err;
         $self->{success}=0;
         return undef;
      } else {
         # some issue with the result
         my $serr="";
         my @yell;
         my $err;
         local $@; # protect existing $@
         eval { @yell=$fi->yell(">"); };
         $@ =~ /nefarious/;
         $err=$@;

         my @fierr;
         if (($err eq "") && (defined $yell[0])) {
            @fierr=@yell; 
         }
         if (@fierr > 0) { $serr="@fierr"; } else { $serr=$!; }
         $self->{error}=$serr;
         $self->{success}=0;
         return undef;
      }
   }
}

sub success {
   my $self=shift;

   return $self->{success};
}

sub error {
   my $self=shift;

   return $self->{error} || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<fiEval> - FileInterface-eval class to evaluate calls to the FileInterface and catch errors.

=cut

=head1 SYNOPSIS

   use fiEval;

   # instantiate
   my $ev=fiEval->new();

   # evaluate a call to create dataset with id 314
   if (!$ev->evaluate("create",314)) {
      # something went wrong creating the dataset
      print "ERROR! Unable to create dataset: ".$ev->error()."\n";
   }

=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the fiEval-class.

Accepts one input parameter: fi. fi is the instance of the FileInterface-class to use. Optional. Recommended to state, but if 
not stated will create a new FileInterface-instance.

Returns the class-instance upon success.

=cut

=head1 METHODS

=head2 evaluate()

Evaluates a method on the fi-instance.

Input parameters are in this order: method, parameters. "Method" is the textual name of the method to call on the FileInterface-
instance. "Parameters" are one or more parameters to the method being called.

The method will return the result from the method-call upon success, undef upon some failure. Please call the error()-method 
for more information upon a failure.

=cut

=head2 success()

Returns if the last method called was finished successfully or not.

No input accepted.

Returns if the last method that was called finished successfully or not, including the 
new()-method.

Returns 1 upon success, 0 upon failure. Please check the error()-method for more information 
upon failure.

=cut

=head2 error()

Returns the last error of the fiEval-class, if any.

=cut
