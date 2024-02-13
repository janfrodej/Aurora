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
# Parameter::Group: class to handle parameter-groups (binaries and their parameters)
#
package Parameter::Group;
use parent 'Parameter';
use strict;
use Parameter::Variable;
use sectools;

sub new {
   my $class=shift;

   my @p=@_;
   my $self=$class->SUPER::new(@p);

   my %opt=@p;

   # if parent is undefined, assume this is first group and parent is itself
   if (!defined $opt{parent}) { $self->{opt}{parent}=$self; }

   # set if defined, if not default
   $self->noSpace($opt{noSpace});

   $self->{type}="Group";
   # groups are always private
   $self->private(1);

   return $self;
}

# add an object, either variable or group
sub add {
   my $self=shift;
   my $object=shift;
   my $locname=shift; # object name to add object before/after, if not the end
   my $ba=shift; # before or after given locname object?

   my $type=ref($object);

   if (($type eq "Parameter::Group") ||
       ($type eq "Parameter::Variable")) {
      # correct type - lets add it to the objects list.
      # some sanity check, never same group twice and no adding oneselves.
      my $objects=$self->{objects};

      my $pos;
      if (defined $locname) {
         # locate where within the group object to place new object
         my $p=-1;
         foreach (@{$objects}) {
            my $o=$_;
            $p++;

            if ($o->name() eq $locname) {
               # found the object
               $pos=$p;
               last;
            }
         }
      } 

      # ensure we have a valid position for the new object
      if (!defined $pos) { $pos=$self->count(); } # add to end of this object - append
      $ba=(defined $ba && $ba =~ /^[01]{1}$/ ? $ba : 1); # default to after
      $pos=($ba == 0 ? $pos-1 : $pos);
      $pos=($pos < 0 ? 0 : $pos);

      if ($object == $self) {
         # misbehaviour
         $self->{error}="Unable to add to itself.";  
         return 0;
      }
      # ensure that name is unique within group, except if a variable
      # variables can be added as many times as one wants
      my $name=$object->name();
      my $o=$self->get($name);
      if ((defined $o) && ($o->type() eq "Group")) {
         # we have a duplicate name. Group-names must be unique within all
         # parameters to ensure they can be adressable.
         $self->{error}="Duplicate name \"$name\" specified for group-object. Cannot add it to this group.";
         return 0;
      } elsif ((defined $o) && ($o != $object)) {
         # we do not allow another variable object with same name, must be the same instance
         $self->{error}="Not allowed to add two different objects with same name. An object with name $name already exists.";
         return 0;
      }
      # add object to group in the right place
      if ($pos == $self->count()) {
         # this is an append
         push @{$objects},$object; 
      } else {
         # this is an insert
         splice (@{$objects},$pos,1,$objects->[$pos],$object);
      }
      return 1;
   } else {
      $self->{error}="Wrong instance type: ".ref($object)."\n";
      return 0;
   }
}

sub remove {
   my $self=shift;
   my $name=shift; # object name to add object before/after, if not the end

   # get objects
   my $objects=$self->{objects};
   # make list of new objects
   my @nobjects;
   # set found to false, we have not located named variable
   my $found=0;
   foreach (@{$objects}) {
      my $object=$_;

      # get object name
      my $oname=$object->name();

      # check if object name is the same as input name
      if ($oname eq $name) {
         # we found the object and it can be removed, but we need to go through the whole
         # objects list to remove all instances of it
         $found=1;
         foreach (@{$objects}) {
            my $o=$_;
            
            if ((defined $o) && ($o != $object)) { 
               # this is not the object to be removed, so add it to list
               push @nobjects,$o;
            }
         }
         # we are finished going through loop - end it
         last;
      }
   }
   # check which list to use
   if ($found) { $self->{objects}=\@nobjects; return 1; }
   else { return 0; } # if not found, we leave list untouched
}

# wrapper, for ease of use
sub addGroup {
   my $self=shift;
   my $name=shift;
   my $escape=shift;
   my $quote=shift;
   my $nospace=shift;
   my $lname=shift;
   my $ba=shift;

   my $g=Parameter::Group->new(name=>$name,escape=>$escape,quote=>$quote,noSpace=>$nospace,parent=>$self);
   if ($self->add($g,$lname,$ba)) {
      # return object to work on
      return $g;
   } else {
      return undef;
   }
}

sub addGroupAfter {
   my $self=shift;
   my $iname=shift;
   my $name=shift;
   my $escape=shift;
   my $quote=shift;
   my $nospace=shift;

   return $self->addGroup($name,$escape,$quote,$nospace,$iname,1);
}

sub addGroupBefore {
   my $self=shift;
   my $iname=shift;
   my $name=shift;
   my $escape=shift;
   my $quote=shift;
   my $nospace=shift;

   return $self->addGroup($name,$escape,$quote,$nospace,$iname,0);
}

# wrapper, for ease of use
sub addVariable {
   my $self=shift;

   my $name=shift;
   my $value=shift;
   my $regex=shift;
   my $required=shift;
   my $private=shift;
   my $escape=shift;
   my $quote=shift;
   my $sandbox=shift;
   my $lname=shift;
   my $ba=shift;
   my $preescape=shift;

   # check if exists already, then just add object
   my $ex=$self->get($name);
   if ((defined $ex) && ($ex->type() eq "Variable")) {
      # variable exists, just add to list, not create new
      return $self->add($ex,$lname,$ba);
   } else {
      # new variable
      my $v=Parameter::Variable->new(name=>$name,value=>$value,regex=>$regex,required=>$required,private=>$private,preescape=>$preescape,escape=>$escape,quote=>$quote,sandbox=>$sandbox);
      return $self->add($v,$lname,$ba);
   }
}

sub addVariableAfter {
   my $self=shift;
   my $iname=shift;
   my $name=shift;
   my $value=shift;
   my $regex=shift;
   my $required=shift;
   my $private=shift;
   my $escape=shift;
   my $quote=shift;
   my $sandbox=shift;
   my $preescape=shift;
   
   return $self->addVariable($name,$value,$regex,$required,$private,$escape,$quote,$sandbox,$iname,1,$preescape);
}

sub addVariableBefore {
   my $self=shift;
   my $iname=shift;
   my $name=shift;
   my $value=shift;
   my $regex=shift;
   my $required=shift;
   my $private=shift;
   my $escape=shift;
   my $quote=shift;
   my $sandbox=shift;
   my $preescape=shift;

   return $self->addVariable($name,$value,$regex,$required,$private,$escape,$quote,$sandbox,$iname,0,$preescape);
}

# return list of instances
sub enum {
   my $self=shift;

   my @objects=@{$self->{objects}};

   return \@objects;
}

# reset reading objects in group
sub resetGetNext {
   my $self=shift;

   $self->{pos}=-1;

   return 1;
}

# get first object in group
sub getFirst {
   my $self=shift;

   $self->{pos}=-1;

   return $self->getNext();
}

# get next object in group
sub getNext {
   my $self=shift;

   # get pos
   my $pos=$self->{pos};
   $pos=(defined $pos && $pos >= 0 ? $pos : -1);

   # ensure the next object exists
   if (exists $self->{objects}[$pos+1]) {
      $pos=$pos+1;
      $self->{pos}=$pos;
      return $self->{objects}[$pos];
   } else {
      # no more objects
      return undef;
   }
}

sub resetGetNextParameter {
   my $self=shift;

   $self->{ppos}=-1;

   return 1;
}

sub getFirstParameter {
   my $self=shift;

   $self->{ppos}=-1;

   return $self->getNextParameter();
}

sub getNextParameter {
   my $self=shift;

   # get pos
   my $pos=$self->{ppos};
   $pos=(defined $pos && $pos >=0 ? $pos : -1);

   # ensure the next object exists
   if (exists $self->{objects}[$pos+1]) {
      $pos=$pos+1;
      $self->{ppos}=$pos;
      my $object=$self->{objects}[$pos];
      my $str="";
      # groups have potentially more than one object,
      # variables only have one object - itself.
      if ($object->type() eq "Group") {
         my $space=($object->noSpace ? "" : " ");
         $object->resetGetNextParameter();
         while (1) {
            my $par=$object->getNextParameter();
            if (!defined $par) { last; }
            $str=($str eq "" ? $par : $str.$space.$par);
         }
      } else {
         # this is a Variable
         $str=$object->value();
      }
      # check if this group is to be escaped, overrides further down
      if (($object->escape()) || ($self->escape())) {
         if ($object->type() eq "Group") {
            $str=quotemeta($str);
         } else {
            # variable - let it do this itself
            $str=$object->toString();
         }
      }
      if ($object->quote()) {
         if ($object->type() eq "Group") { $str="\'$str\'"; }
         else { $str="\"$str\""; }        
      }

      return $str;
   } else {
      # no more objects
      return undef;
   }
}

# get named object, search even sub-objects
sub get {
   my $self=shift;
   my $name=shift||"";
   my $recursive=shift;
   $recursive=(!defined $recursive ? 1 : ($recursive =~ /^[0-1]{1}$/ ? $recursive : 1));

   my $objects=$self->{objects};

   # always ask parent first if this is not the top
   # this always ensures top-down searches
   if (($recursive) && ($self->{opt}{parent} != $self)) { return $self->{opt}{parent}->get($name); }

   # check if we have the object
   foreach (@{$objects}) {
      my $object=$_;

      if ($object->name() eq $name) {
         # found it - return it
         return $object;
      } elsif ($object->type() eq "Group") {
         # this is a group, search sub-object(s) without recursion
         my $o=$object->get($name,0);
         if (defined $o) { return $o; } # found a match
      }
   }  

   # could not find the object
   return undef;
}

# check if named object exists
sub exists {
   my $self=shift;
   my $name=shift;

   # reuse get
   if ($self->get($name)) {
      return 1;
   } else {
      return 0;
   }
}

# get group-instance and position within group that a given parameter exists
# if it exists
sub location {
   my $self=shift;
   my $name=shift;

   if ((defined $name) && ($name ne "")) {
      my $objects=$self->{objects};
      my $pos=-1;
      foreach (@{$objects}) {
         my $o=$_;
         $pos=$pos+1;
         if ($o->name() eq $name) {
            # found it - return it
            return [$self,$pos];
         } elsif ($o->type() eq "Group") {
            # more objects in this sub-group - check them too
            my $f=$o->location($name);
            if (defined $f->[0]) {
               # we have a match - return it
               return $f;
            }
         }
      }
      # if we come here, nothing was found
      return [undef,undef];
   } else {
      $self->{error}="Parameter name to find location of is not defined.";
      return [undef,undef];
   }
}

# enumerate all objects and their order
sub enumObjects {
   my $self=shift;

   my @pars;

   # add group itself to list
   push @pars,$self->name();

   my $objects=$self->{objects};
   foreach (@{$objects}) {
      my $object=$_;

      if ($object->type() eq "Group") {
         # get parameters in this object, both group- and variables
         my $p=$object->enumObjects();
         if (@{$p} > 0) { push @pars,@{$p} }
      } else {
         # add variable name
         push @pars,$object->name();
      }
   }

   # return result
   return \@pars;
}

# enumerate unique objects
sub enumUniqueObjects {
   my $self=shift;

   my %pars;

   # add group itself to list
   $pars{$self->name()}=1;

   my $objects=$self->{objects};
   foreach (@{$objects}) {
      my $object=$_;

      if ($object->type() eq "Group") {
         # get parameters in this object, both group- and variables
         my $p=$object->enumUniqueObjects();
         if (@{$p} > 0) { %pars=(%pars,map { $_ => 1 } @{$p}); }
      } else {
         # add variable name
         $pars{$object->name()}=1;
      }
   }

   # convert
   my @p=keys %pars;

   # return result
   return \@p;
}

# enumerate required objects (to have a value, groups never needs to have a value)
sub enumRequiredObjects {
   my $self=shift;

   my %reqs;

   my $objects=$self->{objects};
   foreach (@{$objects}) {
      my $object=$_;

      if ($object->type() eq "Group") {
         my $r=$object->enumRequiredObjects();
         if (@{$r} > 0) { %reqs=(%reqs,map { $_ => 1 } @{$r}); }
      } else {
         if ($object->required()) { $reqs{$object->name()}=1; }
      }
   }

   my @p=keys %reqs;

   return \@p;
}

# enumerate private parameters (that are to be hidden from user and cannot have a value)
# only variables can be private or not, groups are always private
sub enumPrivateObjects {
   my $self=shift;

   my %privs;

   # add group to hash of privates (avoid variable repeat, use hash)
   $privs{$self->name()}=1;

   my $objects=$self->{objects};
   foreach (@{$objects}) {
      my $object=$_;

      my $r;

      if ($object->type() eq "Group") {
         $r=$object->enumPrivateObjects();
         if (@{$r} > 0) { %privs=(%privs,map { $_ => 1 } @{$r}); }
      } elsif ($object->private()) {
         # this variable is private
         $privs{$object->name()}=1;
      }
   }

   # convert hash to list
   my @p=keys %privs;

   # return list
   return \@p;
}

sub noSpace {
   my $self=shift;

   if (@_) {
      my $value=shift;

      $value=(defined $value && $value =~ /^[01]{1}$/ ? $value : 0);
      $self->{options}{nospace}=$value;
   }

   # get or set
   return $self->{options}{nospace};
}

sub toString {
   my $self=shift;

   my $objects=$self->{objects};
   my $str="";

   my $nospace=$self->noSpace();
 
   foreach (@{$objects}) {
      my $object=$_;

      # call objects toString-method
      my $res=$object->toString();

      # this groups escape overrides sub-group or variables
      if ((!$object->escape()) && ($self->escape())) {
         $res=quotemeta($res); 
      }

      # are we to put space between elements in this group?
      if ($nospace) {
         $str=$str.$res;
      } else {
         $str=($str eq "" ? $res : $str." ".$res);
      }
   }
   
   # if group quote is enabled, enclose the whole
   # thing in quotes
   if ($self->quote()) {
      $str="\'".$str."\'";
   }

   # return result
   return $str;
}

# return number of elements in group
sub count {
   my $self=shift;

   my $no=@{$self->{objects}};

   return $no;
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<Parameter::Group> - Class to handle groups of parameters - either other sub-groups and/or variables.

=cut

=head1 SYNOPSIS

   use Parameter::Group;

   # create instance
   my $g=Parameter::Group->new();

   # create a Parameter-object
   my $v=Parameter::Variable->new();

   # add a Parameter-object to the group
   $g->add($v);

   # create a variable object and add it to the group instance
   $g=addVariable("myvariable","somevalue",".*");

   # create a sub-group-object and add it to the group instance
   $g->addGroup("mygroup");

   # add variable to subgroup
   $g->get("mygroup")->addVariable("somename","othervalue");
   
   # add variable after another named variable
   $g->addVariableAfter("myvariable","newvariablename","value");

   # add variable before another named variable
   $g->addVariableBefore("newvariablename","myvarname","a_value");

   # make a variable required and public
   $g->addVariable("mypublicvariable","somevalue",1,0);

   # create a group and tell it to quote its content parameters (sub-groups and/or variables)
   $g->addGroup("myquotedgroup",undef,1);

   # remove a named parameter
   $g->remove("mypublicvariable");

   # enumerate objects (sub-groups and variables)
   my $e=$g->enum();

   # get next parameter
   while (my $par=$g->getNextParameter()) {
      print "Parameter value is: $par\n";
   }
   
   # enumerate objects
   my $pars=$g->enumObjects();

   # enumerate unique objects
   my $uni=$g->enumUniqueObjects();

   # enumerate required objects
   my $r=$g->enumRequiredObjects();

   # enumerate private objects
   $p=$g->enumPrivateObjects();

   # get a specific named object
   my $o=$g->get("objectname");

   # check if an object exists (sub-groups or variables)
   if ($g->exists("objectname")) {}

   # get if group is to have no space between parameters or not?
   my $ns=$g->noSpace();

   # get all parameters in group as a string
   my $s=$g->toString();

   # get number of objects in group (sub-groups and/or variables)
   my $c=$g->count();

=cut

=head1 DESCRIPTION

Class to handle groups of parameters, either other sub-groups and/or variables.

This class is a sub-class of the Parameter-class. Usually when using the Parameter-class one 
only instantiates a Parameter::Group-class.

A parameter-group can contain both other sub-groups as well as parameters. It does not allow the 
creation or addition of groups or variables that have the same name as other groups and 
variables already added. This is to ensure unique naming in the entire parameter-group, so that 
one can use the objects by referring to them by name (ie. parameter-name). One can circumvent this 
requirement in several ways, but we admonish the user to adhere to a group- and parameter 
unique use.

When addressing Parameter-objects in this class, you can refer to them or get them by using 
the get()-method. It works hierarchically and will recurse into sub-groups to find the group 
or variable that you are looking for. Also methods that take parameter-name as an option 
will recurse to find the object if not otherwise stated. The expection is sub-groups where they will 
not recurse up the group-tree, only down the group-tree.

An overview of concepts:

=over

=item

B<Object> A Parameter-object that can be added to a group. It can be either a Parameter::Group or 
Parameter::Variable-class type.

=cut

=item

B<Parameter> An item returned as a single entity to the user of the Parameter-class. It can consist of one or more 
Parameter::Variable-instances. The Parameter::Group-class decides if a collection of variables and/or sub-groups 
are to be returned as one parameter. Basically anything organized under a sub-group of the main-parameter-group 
will be returned as one parameter for that sub-group.

=cut

=item

B<Group> A collection of sub-groups and/or variables. It has certain attributes that can be set on it, such as 
if it is to be escaped, quoted and/or have no space between its parameters.

=cut

=item

B<Variable> A named value that can be set in a group. It has certain attributes that can be set on it, such as 
if it is to be escaped, quoted, be private or not and so on. Please see the Parameter::Variable-class documentation for 
more info on the Parameter::Variable-type.

=cut

=back

=cut

=head1 CONSTRUCTOR

=head2 new()

The method is inherited from the parent Parameter-class, but in addition sets some 
internal settings that are unique to the Parameter::Group-class.

This method returns an instantiated class upon success. Please refer to the documentation of the 
Parameter-class for more information.

=cut

=head1 METHODS

=head2 add()

Adds a parameter object to the group.

Accepts the following input in this order:

=over

=item

B<object> Reference to the Parameter-class object to add (either Parameter::Group or 
Parameter::Variable-class).

=cut

=item

B<parname> Parameter name of where to add this object. If none given it will be added to 
the end of all current objects in the Parameter::Group-instance. This parameter is used 
together with the before/after-parameter to exactly signify where to add the object.

=cut

=item

B<beforeafter> Sets if to add the object before or after given parameter name (see the parname-
option to add(). If none given it defaults to after. The method only accepts 0 (=before) or 1 
(=after).

=cut

=back

This method returns 1 upon success, 0 upon failure. Please check the error()-method for more information 
upon failure.

=cut

=head2 remove()

Attempt to remove named parameter.

Accepts the following input: name. This is the name of the parameter to attempt to locate and remove.

This method returns 1 upon success, 0 upon failure. Please check the error()-method for more information upon failure.

Please note that all instances of a named parameter is removed when invoking this method.

=cut

=head2 addGroup()

Adds a sub-group object to the group at the end of current objects.

Accepts the following parameters in this order:

=over

=item

B<name> Name of parameter to add.

=cut

=item

B<escape> Escape the parameters in this group or not? 1 means true, 0 means false. Default is 0.

=cut

=item

B<quote> Quote the parameters in this group or not? 1 means true, 0 means false. Default is 0.

=cut

=item

B<nospace> Sets if the parameters in this group are to have no space between them or not? 1 means true, 0 means false. It defaults 
to 0 and does not remove all spacing between the parameters. In some instances groups of parameters needs to have their space removed 
and render them together.

=cut

=item

B<parname> Sets the name of the parameter where this group is to be added and it is used together with the beforeafter-option. 
It defaults to blank which means it is added to the end of all the current group-objects.

=cut

=item

B<beforeafter> Sets if the parameter is to be added before or after the name given in the "parname"-option. 0 means before, 1 
means after. This option defaults to after.

=cut

=back

Upon success this method returns the group-instance it created and undef upon failure. Please check the error()-method for more 
information upon failure.

=cut

=head2 addGroupAfter()

Adds a sub-group in this group after the given parameter name.

This method is a wrapper for the addGroup-method for ease of use.

Accepts the following parameters in this order:

=over

=item

B<aftername> The parameter-name to add the group after.

=cut

=item

B<name> Name of the group to add.

=cut

=item

B<escape> Sets if the contents of this Parameter::Group is to be escaped or not? 
Defaults to 0. Accepts 1 for true, 0 for false.

=cut

=item

B<quote> Sets if the contents of this Parameter::Group is to be quoted or not? Defaults 
to 0. Accepts 1 for true, 0 for false.

=cut

=item

B<nospace> Sets if the group is to have no space between parameters in the group. Defaults to 0. Accepts 
0 for false, 1 for true.

=cut

=back

Returns the instance of the class-created upon success, undef upon failure. Please check the error()-method 
for more information.

=cut

=head2 addGroupBefore()

Adds a sub-group in this group before the given parameter name.

This method is a wrapper for the addGroup-method for ease of use. It also works similarly to the 
addGroupAfter()-method. Check the documentation for that method for more information.

=cut

=head2 addVariable()

Adds a variable in this group.

If the variable name exists already, that Parameter::Variable-object is added to the group. Variables can be used several 
places, but all variables should still have unique names.

Accepts the following options in this order:

=over

=item

B<name> Name of variable to add. Must be unique.

=cut

=item

B<value> Value of variable that is to be added.

=cut

=item

B<regex> Regex of value that is added on variable. This regex is meant to be used when adding values on the parameter, although 
no checking is enforce in this class. It is up to the user of the class to enforce checking.

=cut

=item

B<required> Sets if the variable is required or not to have a value. 0 means false, 1 means true. Defaults to 0. This option is 
ignored if variable already exists.

=cut

=item

B<private> Sets if the variable is to be private or not. 0 means false, 1 means true. Defaults to 1. All variables are private 
if not otherwise stated. The privacy of the variable is not enforces by this class, but have to be enforced by the user of the 
Parameter-classes. Private here is meant that the normal user of an application is not allowed to change its value (protected). 
This option is ignored if variable already exists and that variable object is added.

=cut

=item

B<escape> Sets if the variable is to have its value escaped or not. 0 means false, 1 means true. Defaults to 0. Please note that if 
the group using the variable is set to be escaped, it will override the setting here. This option is ignored if variable already 
exists and that variable object is added.

=cut

=item

=item

B<preescape> Sets if the variable is to have its value preescaped or not. 0 means false, 1 means true. Defaults to 1.

=cut

B<quote> Sets if the variable is to have its value quoted or not. 0 means false, 1 means true. Default to 0. This option is 
ignored if variable already exists and that variable object is added.

=cut

=item

B<sandbox> Sets if the variable value is to be sandboxed or not. 0 means false, 1 means true. Defaults to 0. This option is 
ignored if variable already exists and that variable object is added. 

=cut

=item

B<parname> Sets parameter name of where to insert the variable. Defaults to blank which means to insert the variable at the 
end of the group.

=cut

=item

B<beforeafter> Sets if the variable is to be added before or after name set in parname. 0 means before, 1 means after. 
Defaults to after. If parname and beforeafter is undefined the variable will be appended to the group.

=cut

=back

Upon success returns 1, 0 on failure. Please check the error()-method for more information upon failure.

=cut

=head2 addVariableAfter()

Adds a variable after the given parameter name.

This is a wrapper around the addVariable()-method. It accepts options in the following order: parname (name of parameter after which to add 
this variable), name (variable name), value (value of variable), regex, required, private, escape, quote, sandbox and preescape. Please see the 
addVariable()-method for more information about the options.

Please note that if given variable name already exists, that Parameter::Variable-instance is added. If it doesn't exist, it will 
be created and then added.

Returns 1 upon success, 0 upon failure. Please see the error()-method for more information upon failure.

=cut

=head2 addVariableBefore()

Adds a variable before the given parameter name.

This is a wrapper around the addVariable()-method. It accepts options in the following order: parname (name of parameter before which to add 
this variable), name (variable name), value (value of variable), regex, required, private, escape, quote, sandbox and preescape. Please see the 
addVariable()-method for more information about the options.

Please note that if given variable name already exists, that Parameter::Variable-instance is added. If it doesn't exist, it will 
be created and then added.

Returns 1 upon success, 0 upon failure. Please see the error()-method for more information upon failure.

=cut

=head2 count()

Returns the number of Parameter-objects in the group.

No input accepted.

=cut

=head2 enum()

Enumerate the objects that the group-instance contains.

Accepts no input.

Returns a LIST-reference of Parameter-classes

=cut

=head2 enumObjects()

Enumerate the object names of the group.

Please note that object names enumerated can be repeated (for Parameter::Variable-objects) and show the actual order of the 
Parameter-group.

Returns a reference to a LIST of object names. Please note that the list can be empty.

=cut

=head2 enumPrivateObjects()

Enumerate the private objects of the group.

This returns the unique, private objects in the group and its sub-groups.

No input is accepted.

Returns a LIST-reference of object names.

=cut

=head2 enumRequiredObjects()

Enumerate the required objects of the group.

This returns the unique and required objects of the group and its sub-groups.

No input is accepted.

Returns a LIST-reference of object names.

=cut

=head2 enumUniqueObject()

Enumerate the unique objects of the group.

This returns the unique object names of the group and its sub-groups.

No input is accepted.

Returns a LIST-reference of the object names.

=cut

=head2 exists()

Checks if a given object name exists in group or its sub-groups.

Accepts one input: object name.

Returns 1 if it exists, 0 if it does not.

=cut

=head2 get()

Get a names object-instance.

Accepts one input: object name.

Returns the object-instance if the object exists in the top group or its sub-groups, undef upon 
failure. This method will go to the top-most parent-group and start asking for the 
object there while recursing down the possible groups in the Parameter-tree. It will return the 
first match from the top-down.

Please check error()-method upon failure.

=cut

=head2 getFirst()

Get the first object in the group.

Accepts no input.

Returns the object instance of the first object in the group.

=cut

=head2 getFirstParameter()

Get the first parameter of the group-instance, if any.

Accepts no input.

Returns the value of the first parameter if any. Undef if no value exists.

=cut

=head2 getNext()

Gets the next object in the group.

Accepts no input.

Gets the next object in the group after a call to getFirst(), 
resetGetNext() or getNext().

Returns an object-reference upon success, undef if there are no more objects.

=cut

=head2 getNextParameter()

Returns the next parameters value in the group.

Accepts no input.

Gets the next parameters value in the group or its sub-groups after a call to 
getFirstParameter(), resetgetNextParameter() or getNextParameter().

Returns a value upon success, undef if there are no more parameter values to fetch.

=cut

=head2 location()

Get the location of a named object within group or sub-group.

Accepts one input:

=over

=item

B<name> Name of object to get location of.

=cut

=back

Returns a LIST-reference. The list reference can be empty if the named object could not 
be found.

The LIST-reference structure is as follows:

   [GROUP-NAME,POSITION]

GROUP-NAME is the name of the first group or sub-group that contains the object (variables may 
exist in several places). POSITION is the first numbered position within GROUP-NAME that the object 
exists.

=cut

=head2 noSpace()

Get or set if group is to have no space between its parameters.

Accepts only one input: nospace. Nospace sets if the group is to have no space or not. 1 means true (no space), 0 means 
false. It defaults to 0 (parameters are to have space between them).

If no input is given, the method returns the current noSpace-setting of the group. Setting the noSpace setting returns 
the setting after it has been set.

=cut

=head2 resetGetNext()

Reset to get the next group object.

Accepts no input.

Resets the fetching of group objects by the method getNext().

Returns 1.

=cut

=head2 resetGetNextParameter()

Resets the getting of next parameter value and starts at the beginning of the
parameter list.

Accepts no input.

Always returns 1.

=cut

=head2 toString()

Convert all the group- and sub-group parameters into a string.

Accepts no input.

Returns the rendered groups parameters and their values as a string.

=cut

