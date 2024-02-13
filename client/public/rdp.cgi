#!/usr/bin/perl -w
# Copyright (C) 2024 Bård Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway
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
use CGI;
use CGI::Carp qw(fatalsToBrowser);
my $cgi = CGI->new();

my $host = $cgi->param("host");
my $file = "remote.rdp";

print( $cgi->header( 
	   -type => 'application/octet-stream',
	   -attachment => $file,
       ),
       "full address:s:$host",
    );

