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
# Parameter::Variable: class to represent a variable in a parameter.
#
package Parameter::Variable;
use parent 'Parameter';
use strict;

sub new {
   # instantiate
   my $class = shift;

   my @opts=@_;

   my $self=$class->SUPER::new(@opts);

   # get raw options values
   my %opt=@opts;
   if (exists $opt{value}) { $self->value($opt{value}); }
   if (exists $opt{required}) { $self->required($opt{required}); }
   if (exists $opt{regex}) { $self->regex($opt{regex}); }
   if (exists $opt{sandbox}) { $self->sandbox($opt{sandbox}); }
   if (exists $opt{preescape}) { $self->preEscape($opt{preescape}); }

   $self->{type}="Variable";

   return $self;
}

sub value {
   my $self=shift;

   if (@_) {
      # set
      my $value=shift;
      $self->{value}=$value;
   } 
   # get or set
   return $self->{value};
}

sub required {
   my $self=shift;

   if (@_) {
      # set
      my $req=shift;
      $req=(defined $req && $req =~ /^[01]{1}$/ ? $req : 0);
      $self->{options}{required}=$req;
   } 

   # get or set
   return $self->{options}{required} || 0;
}

sub regex {
   my $self=shift;

   if (@_) {
      # set
      my $re=shift;
      $re=(defined $re && $re =~ /^.*$/ ? $re : ".*");
      $self->{options}{regex}=$re;
   } 

   # get or set
   return $self->{options}{regex} || ".*";
}

sub sandbox {
   my $self=shift;

   if (@_) {
      # set
      my $sb=shift;
      $sb=(defined $sb && $sb =~ /^[01]{1}$/ ? $sb : 0);
      $self->{options}{sandbox}=$sb;
   } 

   # get or set
   return $self->{options}{sandbox} || 0;
}

sub preEscape {
   my $self=shift;

   if (@_) {
      # set
      my $pe=shift;
      $pe=(defined $pe && $pe =~ /^[01]{1}$/ ? $pe : 1);
      $self->{options}{preescape}=$pe;
   } 

   # get 
   return (defined $self->{options}{preescape} ? $self->{options}{preescape} : 1);
}

sub toHash {
   my $self=shift;

   my %h;
   $h{name}=$self->name();
   $h{value}=$self->value();
   $h{regex}=$self->regex();
   $h{private}=$self->private();
   $h{required}=$self->required();
   $h{escape}=$self->escape();
   $h{preescape}=$self->preEscape();
   $h{quote}=$self->quote();

   return \%h;
}

sub toString {
   my $self=shift;

   my $value=$self->{value};

   # check if value is to be escaped or not
   if ($self->escape()) {
      $value=quotemeta($value);
      # check to see if pre-escape has been disabled or not?
      if (!$self->preEscape()) {
        # we are not to pre-escape - remove any backslashes in the beginning of the string
        $value=~s/^\\//g;
      }
   }

   # check if value is to be quoted or not
   if ($self->quote()) {
      $value="\"".$value."\"";
   }

   return $value || "";
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Parameter::Variable> - Class to define a variable in the Parameter-classes.

=cut

=head1 SYNOPSIS

   use Parameter::Variable;

   # instantiate
   my $v=Parameter::Variable->new(name=>"myvariable",value=>"myvalue",regex=>"\\w+");
   # get value
   my $val=$v->value();
   # set value
   my $v->value("myNewValue");
   # get as string
   my $s=$v->toString();
   
=cut

=head1 DESCRIPTION

Class to define a variable in the Parameter-classes. It can contain a value and a set of attributes of 
that value. 

Current attributes (besides what it inherits from the Parameter-class): value, required and regex.

=cut

=head1 CONSTRUCTOR

=head2 new()

Sets up the parameter-classes and returns an instance of the class.

It accepts the following options:

=over

=item

B<value> The value of the Parameter::Variable-instance. Defaults to a blank value.

=cut

=item

B<required> Sets if the variable is required or not? Defaults to 0. 1 means true, 0 means false. Required means 
that the variable needs to have a value set. The enforcement of this attribute is up to the user of the 
Parameter-classes to execute.

=cut

=item

B<regex> Set the regex setting of the variable. Defaults to ".*" which accepts all. The enforcement of the 
regex-setting is not done by this class and must be executed by the user of the Parameter-classes.

=cut

=back

This method is inherited from the Parameter-class. Please refer to 
that class for more in-depth documenation of the new()-constructor.

Returns an instance of the Parameter::Variable-class.

=cut

=head1 METHODS

=head2 regex()

Get or set the regex of the variable.

In the case of set accepts one input: regex. It must be a valid perl regex-expression.

It does not check the regex or do anything with it besides storing it. It is up to the 
user of the Parameter-class to check and enforce the regex.

In both get and set scenarios returns the current regex-value for the variable.

=cut

=head2 required()

Get or set the required attribute of the variable.

In the case of set accepts one input: required. 1 means true, 0 means false. If none 
was set for the variable in the first place it defaults to 0.

In both get and set scenarios returns the current required-value for the variable.

=cut

=head2 sandbox()

Get or set the sandbox attribute on the variable.

In the case of set accepts one parameter: sandbox. 1 means true, 0 means false. Default is 0 (false).

What sandbox means is up to the user of the class to define and enforce. The Parameter-classes 
does not define or enforce it.

In both get and set scenarios returns the current sandbox-value for the variable.

=cut

=head2 preEscape()

Get or set pre-escape attribute on the variable.

In the case of set accepts one parameter: preescape. 1 means true, 0 means false. Default is 1 (true).

The preescape-value is only used if escape() has been set to true. In any other case it is ignored. What 
the preescape-value means is that in the case of escaping, there shall be no backslashes in the beginning 
of the string. These are removed when calling the toString()-method of this class.

In both get and set scenarios returns the current preescape-value for the variable.

=cut

=head2 toHash()

Return all the attributes of the variable as a hash.

Accepts no input.

Returns the following as a HASH-reference:

   toHash => (
               name => SCALAR,
               value => SCALAR,
               regex => SCALAR,
               private => SCALAR,
               required => SCALAR,
               escape => SCALAR,
               preescape => SCALAR,
               quote => SCALAR
             )

=cut

=head2 toString()

Convert the variable into a string.

Accepts no input.

Returns the value of the variable as a string, escaped and quoted according to the 
settings of the variable.

=cut

=head2 value() 

Set or get the value of the variable.

In the case of set, accepts one input: value. 

In both set and get scenarios returns the current value of the variable.

=cut
