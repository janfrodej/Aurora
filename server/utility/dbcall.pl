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
use lib qw(/usr/local/lib/aurora);
use AuroraDB;
#use AuroraDBbt;
use Data::Dumper;
use Settings;
use Time::HiRes qw(time);

# set UTF-8 encoding on STDIN/STDOUT
binmode(STDIN, ':encoding(UTF-8)');
binmode(STDOUT, ':encoding(UTF-8)');

my $CFG=Settings->new();
$CFG->load("system.yaml");

my $db=AuroraDB->new(
    data_source=>$CFG->value("system.database.datasource"),
    user=>$CFG->value("system.database.user"),
    pw=>$CFG->value("system.database.pw")
);

$db->getDBI();

if (@ARGV) { display(@ARGV); }
else {
    while (<>) {
	chomp;
	display(split);
    }
}

sub display {
    my $method = shift or die "useage TestIT";
    map { $_ = /^<undef>$/ ? undef : (/^[\[\{]/ ? eval($_) : $_); } @_;
    print "$method(\t".Dumper(@_).") =\t";
    print TestIT("\t", $db->$method(@_));
}

sub TestIT {
    my $name = shift;
    my @text = ();
    if (defined $name) {
	if (@_ == 1 and !defined $_[0]) {
	    push @text, "$name FAILURE: ", defined($db->{error}) ? $db->{error} : '--undef--', "\n";
	}
	else {
	    push @text, "$name SUCCESS: ", TestIT(undef, $name, 0, @_), "\n";
	}
    }
    else {
	my $name = shift;
	my $level = shift() + 1;
	my $pf = $name . ("\t" x $level);
	if (@_ != 1) {
	    push @text, "(\n";
	    foreach my $elem (@_) {
		push @text, $pf, TestIT(undef, $name, $level, $elem), ",\n";
	    }
	    push @text, $pf if @_;
	    push @text, ")\n";
	}
	else {
	    my $result = shift;
	    if (!defined($result)) {
		push @text, "<undef>";
	    }
	    elsif (my $ref = ref($result)) {
		if ($ref eq "SCALAR") {
		    push @text, "\\'$result'";
		}
		elsif ($ref eq "ARRAY") {
		    push @text, "[\n";
		    foreach my $elem (@$result) {
			push @text, $pf, TestIT(undef, $name, $level, $elem), ",\n";
		    }
		    push @text, $pf, "]";
		}
		elsif ($ref eq "HASH") {
		    push @text, "{\n";
		    foreach my $key (sort keys %$result) {
			push @text, $pf, "$key => ", TestIT(undef, $name, $level, $$result{$key}), ",\n";
		    }
		    push @text, $pf, "}";
		}
		else {
		    push @text, Dumper($result);
		}
	    }
	    else {
		push @text, "'$result'";
		if (length($result) < 12) {
		    push @text, sprintf("[%s]", join('',reverse split('', unpack("b*", $result))));
		}
	    }
	}
    }
    push(@text, "()") unless @text;
    return @text;
}
