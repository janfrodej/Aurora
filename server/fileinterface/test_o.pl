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

use Data::Dumper;
use lib qw(/usr/local/lib/aurora); 
use FileInterface; 

my $fi;
my $r;;
while (<>) {
    chomp;
    unless (/./) {
	if (ref $fi) {
	    $fi->delayed;
	    $fi->teardown if ref($fi);
	    $fi = undef;
	}
	next;
    }
    $fi = FileInterface->new() unless defined $fi;    
    my @line = split;
    my $id = shift(@line);
    my $method = shift(@line);
    $r = $id eq '.' ? $fi : $fi->any($id) unless $id eq '+';
    $r = $r->$method(@line) if $method;
    print Dumper($r);
    print join("\n", $fi->yell, "") and $fi->yell('<') if $fi->yell;
}
