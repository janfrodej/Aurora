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
use FileInterface;
use Data::Dumper;

my $fi = FileInterface->new();

my $SOFTBEAT = 1;
my $HARDBEAT = 3600;
my $last = 0;

while (1) {
    my $now = time();
    my $out_of_date = $fi->purge_needed;
    my $do_hardbeat = $last < $now - $HARDBEAT ? 1 : 0;
    if ($out_of_date or $do_hardbeat) {
        $fi->purge;
        my $purge_done = time();
        my $purgetime = $purge_done - $now;
        $fi->purge_hrlinks;
        my $hrtime = time() - $purge_done;
        $last = $now;
        # warn "$now purged($out_of_date/$do_hardbeat) in ${purgetime}+${hrtime}\n";
        my @complaints = $fi->yell(">");
        warn map { time()."\t$_\n"; } @complaints if @complaints;
    }
    sleep($SOFTBEAT);
}
