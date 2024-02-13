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

my %URL = (
    create_dataset     => 'create',
    manage_datasets    => 'manage',
    permissions        => 'permissions&id=%d',
    metadata           => 'metadata&id=%d',
    close              => 'close&id=%d',
    );

my $id = 0;
$id = $1 if $ENV{QUERY_STRING} =~ s/^(\d+)\-//;
my $verb = $ENV{QUERY_STRING} || "NOOP";

my $url = $URL{lc($verb)} or complain("Don't know how to $verb".($id ? "($id)" : ""));

no warnings qw(redundant); # sprinf complais about redundant parameters from 5.22.0
my $redirect = "./?route=".sprintf($url, $id);

print CGI->redirect($redirect);
exit;

sub complain {
    my $message = shift;
    my $cgi = CGI->new();
    print( $cgi->header(),
           $cgi->start_html("Aurora verb vrapper error"),
           $message,
           $cgi->end_html(),
        );
    exit;
}
