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
use strict;

use lib qw(/usr/local/lib/aurora);
use AuroraDB;
use Settings;
use FileInterface;
use Log;
use DistLog;
use Content::Log;
use Data::Dumper;
use Time::HiRes qw(time);

unless (@ARGV) {
    warn "
    $0 Copyright (C) Bård Tesaker, NTNU, 2022

    Usage:  $0 dataset [dataset ...]

    Shows the necessary steps to undelete the given datasets.
    \n";
    exit(1);
}

my $fi = FileInterface->new;

my $stores = $fi->storeprobe;
my $base   = $fi->base;
my $dbi    = $fi->dbi;

foreach my $entity (@ARGV) {
    warn("$entity:\tInvalid entity!\n") and next unless $entity =~ /^\d+$/;
    my $scaled = sprintf( "%03d/%03d/%d",
                          ($entity / 1000000) % 1000,
                          ($entity / 1000) % 1000,
                          $entity,
        );
    my @found = ();
    my %seen = ();
    foreach (keys %$stores) {
        my ($mode,$store) = split(/-/);
        if (opendir DIR, "/Aurora/$_/$scaled") {
            # Check for alias
            my ($dev,$inode) = stat(DIR) or next;
            next if $seen{$dev}{$inode};
            $seen{$dev}{$inode} = 1;
            #
            foreach (readdir DIR) {
                next unless /^([a-zA-Z0-9]+)(.*)$/;
                push(@found, { cookie  => $1,
                               deleted => $2,
                               store   => $store,
                               mode    => $mode,
                     });
            }
        }
    }
    if    (@found == 0) { warn("$entity:\tNo deleted set found!\n"); }
    elsif (@found > 1)  { warn("$entity:\tMultiple sets found: ".Dumper(\@found)); }
    else {
        my $set = shift(@found);
        my $path = sprintf( "%s/fi-%s/%s/%s",
                            $base,
                            $set->{store},
                            $set->{mode},
                            $scaled,
            );
        if ($set->{deleted}) {
            my $now     = time();
            my $cookie  = $set->{cookie};
            my $deleted = $set->{deleted};
            my $mode    = $set->{mode};
            my $store   = $set->{store};
            #
            my $perm    = $fi->mode2perm($mode);
            $perm =~ /^\d+$/ or warn "mode2perm($mode) return '$perm'!" and next;
            #
            my $cookie_q = $dbi->quote($cookie);
            my $store_q  = $dbi->quote($store);
            #
            #
            warn "$entity:\tResurrecting... \n";
            #
            # Reinstate in File Interface:
            # - Move into position
            rename("$path/$cookie$deleted", "$path/$cookie")
                or warn("rename($path/$cookie$deleted, $path/$cookie): $!") and next;
            # - Link into view
            symlink("../../../$mode-$store/$scaled", "$base/view/$scaled")
                or warn("symlink(../../../$mode-$store/$scaled, $base/view/$scaled): $!") and next;
            # - Register in cache
            $fi->dbi->do("insert into FI_DATASET values($entity,$store_q,$perm,$cookie_q,1)")
                or warn("dbi->do(insert into FI_DATASET values($entity,$store_q,$perm,<cookie>,1): ".$fi->dbi->errstr) and next;
            #
            # Update AuroraDB status
            $fi->adb->setEntityMetadata( $entity, { 'system.dataset.time.removed' => 0, 'system.dataset.time.expire' => 9999999999 })
                or warn("adb->setEntityMetadata( $entity, ...): ".Dumper($fi->adb->error)) and next;
            #
            # log the event on success
            my $cfg = $fi->Settings;
            my $log = Log->new(
                location => $cfg->value("system.log.location"),
                name     => $cfg->value("system.log.tablename"),
                user     => $cfg->value("system.log.username"),
                pw       => $cfg->value("system.log.password")
                );
            my $logmessage = createDistLogEntry(
                event  => "RESURRECT",
                fromid => "UNKNOWN",
                uid    => 1,
                toloc  => $entity,
                );
            $log->send(
                entity   => $entity,
                loglevel => $Content::Log::LEVEL_DEBUG,
                logtag   => 'MANUAL DISTLOG',
                logmess  => $logmessage,
                );
            $log->send(
                entity   => $entity,
                loglevel => $Content::Log::LEVEL_INFO,
                logtag   => 'MANUAL',
                logmess  => "Dataset $entity is undeleted manually with utility/undelete.pl",
                );
        }
        else {
            warn("$entity:\t$path is not deleted!\n");
        }
    }
}
