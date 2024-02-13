#!/usr/bin/perl -tw
# Copyright (C) 2024 Bård Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway
# Copyright (C) 2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
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

use Data::Dumper;
use Cwd;

$ENV{PATH} = '/usr/bin';

my $path = $ENV{PATH_TRANSLATED};
(my $title = $ENV{REQUEST_URI}) =~ s/\.md//i;
my $html = "Woops - no data!";
my $md = "";
if ($path =~ /^([\/a-z0-9_+.-]+\.md)$/i) {
    $md = $1;
    if (open PANDOC, '-|', 'pandoc', '-s', '--toc', $md) {
        $html = join('', <PANDOC>);
        close(PANDOC);
    } else {
        $html = "open(pandoc $md): $!";
    }
} else {
    $html = "Invalid path: $path";
}

my $cgi = CGI->new();
print( $cgi->header( 
	   -charset => "utf-8",
       ),
       $cgi->start_html(
	   -title => "Aurora $title",
	   -style => {
               src => "/docs/pandoc.css",
	   },
       ),
       head(),
       $html,
       tail(), 
       $cgi->end_html(),
    );

sub head {
    return "Aurora $title".$cgi->hr();
}
sub tail {
    return $cgi->hr()."For further questions, contact ".$cgi->a({-href=>"https://hjelp.ntnu.no"},  "hjelp.ntnu.no");
}
