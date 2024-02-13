#!/usr/bin/perl -w
# Copyright (C) 2019-2024 Bård Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway
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
use strict;

# Print the entity tree with perm info.
#
# Perm info format:
#     <role>: -[<denybits>] +[<grant bits>]
#
# It takes tree optional parameters (0 may be used as placeholde):
#  * subject
#    - prints the subect and its roles at the top
#    - changes the perm info to that relevant for the subject:
#        >[<inherited permission bits>]
#        -[<deny bits>](<due to role>) = [<permission after deny bits is applied>]
#        +[<grant bits>](<due to role>) = [<permission after grant bits is applied>]
#        =[<resultant permission bits>]
#  * object
#    - print the object and its path at the top
#    - List only that branch
#  * depth
#    - List the descendants of the object in depth levels. 
#    - Default is full tree 
#
# An additional object parameter may be given, showing only that branch.

use Data::Dumper;

use lib qw(/usr/local/lib/aurora);
use AuroraDB;
use Settings;
my $CFG=Settings->new();
$CFG->load("system.yaml");
my $adb=AuroraDB->new(
    data_source=>$CFG->value("system.database.datasource"),
    user=>$CFG->value("system.database.user"),
    pw=>$CFG->value("system.database.pw")
);
my $db = $adb->getDBI() or die $adb->error;

if (!$adb->connected()) {
   # not connected, something is wrong
   print "$0 Copyright (C) Bård Tesaker, NTNU, 2019-\n\n";
   print "Syntax:\n\n";
   print "   $0 [subject] [object] [depth]\n\n";
   print "Shows the AURORA entity tree and the permissions that are valid for the given subject on the given object to the given depth, or the whole tree and its entities' permissions.\n";
   exit(1);
}

my $entity = $db->selectall_hashref('select * from ENTITY', 'entity');
my $perm   = $db->selectall_hashref('select * from PERM', ['permobject','permsubject']);
my $perms  = $db->selectall_hashref('select * from PERMTYPE', ['PERMTYPE']);
my $member = $db->selectall_hashref('select * from MEMBER', ['membersubject','memberobject']);
my $meta   = $db->selectall_hashref('select * from METADATA natural left join METADATAKEY', ['entity','metadatakey','metadataidx']);

my $verbose = shift if @ARGV and $ARGV[0] eq '-v';
my $subject = shift;
my $object = shift || 1;
my $depth = shift;
    
my $childs = {};
foreach my $this (sort { $a <=> $b } keys %$entity) {
    my $parent = $$entity{$this}{entityparent};
    next if $parent == $this;
    push(@{$$childs{$parent}}, $this);
}

my $roles = {};
if ($subject) {
    my $this = $subject;
    while ($this) {
	addroles($this, $roles);
	my $parent = $$entity{$this}{entityparent};
	last if $parent == $this;
	$this = $parent;
    }
    my @roles = sort { $a <=> $b } keys %$roles;
    print "Subject: $subject, roles: @roles\n";
}

my @path = ($object);
until ($path[0] == 1) {
    unshift(@path, $$entity{$path[0]}{entityparent});
}
print "Object: $object, path: @path\n" if @path > 1;


my $PREFIX = "\t";
my $ATTR = " * ";
tree('', '', $depth, @path);

sub tree {
    my $prefix = shift;
    my $mask = shift;
    my $depth = shift;
    my $object = shift;
    #
    print "$prefix$object\n";
    if ($subject) {
	print "$prefix$ATTR>".mask($mask)."\n";
	my $dirty = 0;
	foreach my $role (sort { $a <=> $b } keys %{$$perm{$object}}) {
	    next unless $$roles{$role};
	    my $bits = $$perm{$object}{$role}{permdeny};
	    next unless defined($bits) and $bits =~ /[^\0]/;
	    $mask = clearbits($bits, $mask);
	    print "$prefix$ATTR-".mask($bits)."($role)\n"; # = ".mask($mask)."\n";
	    $dirty = 1;
	}
	foreach my $role (sort { $a <=> $b } keys %{$$perm{$object}}) {
	    next unless $$roles{$role};
	    my $bits = $$perm{$object}{$role}{permgrant};
	    next unless defined($bits) and $bits =~ /[^\0]/;
	    $mask = setbits($bits, $mask);
	    print "$prefix$ATTR+".mask($bits)."($role)\n"; # = ".mask($mask)."\n";
	    $dirty = 1;
	}
	print "$prefix$ATTR=".mask($mask)."\n" if $dirty;
    }
    else {
	foreach my $role (sort { $a <=> $b } keys %{$$perm{$object}}) {
	    my $grant = mask($$perm{$object}{$role}{permgrant});
	    my $deny  = mask($$perm{$object}{$role}{permdeny});
	    print "$prefix$ATTR$role: -$deny +$grant\n";
	}
    }
    #
    if (@_) {
	tree("$prefix$object$PREFIX", $mask, $depth, @_);
    }
    elsif (--$depth) {
	foreach my $child (@{$$childs{$object}}) {
	    tree("$prefix$object$PREFIX", $mask, $depth, $child);
	}
    }
}

sub addroles {
    my $role = shift;
    my $roles = shift;
    $$roles{$role} = 1;
    if (exists $$member{$role}) {
	foreach my $group (keys %{$$member{$role}}) {
	    addroles($group, $roles);
	}
    }
}

sub setbits {
    my $bits = shift;
    my $mask = shift;
    return $mask if !defined($bits) or $bits eq '';
    return $mask | $bits;
}
sub clearbits {
    my $bits = shift;
    my $mask = shift;
    return $mask if !defined($bits) or $bits eq '';
    my $invert = "\377" x length($mask);
    return $mask & ($invert ^ $bits);
}

sub mask {
    my $bits = shift;
    $bits = '' unless defined($bits);
    my @bits = split('', unpack("b*", $bits));
    if ($verbose) {
	my $i = 0;
	my @perms = ();
	foreach my $bit (@bits) {
	    push(@perms, "$i:".($perms->{$i}{PERMNAME} || "?")) if $bit;
	    $i++;
	}
	return sprintf("[%s](@perms)", join('', @bits));
    }
    else {
	return sprintf("[%s]", join('', @bits));
    }
}
