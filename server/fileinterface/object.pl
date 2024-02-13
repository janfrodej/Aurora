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

my $fi = FileInterface->new();
my($a,$b,$c,$d,$e,$f);

if (@ARGV) { 
    while (@ARGV) {
	call(shift);
    }
}
else {
    while (<STDIN>) {
	call($_);
    }
}

sub call {
    my $code = shift;
    eval $code;
    my @lines = ();
    my $i = 97;
    foreach ($a,$b,$c,$d,$e,$f) {
	my $v = chr($i++);
	print(Data::Dumper->Dump([$_],[$v]));
	push(@lines, "\$$v=$_") if defined $_;
    }
    push(@lines, $fi->yell('>'));
    print join( "\n", @lines, "Err: $@", "> ");
}
