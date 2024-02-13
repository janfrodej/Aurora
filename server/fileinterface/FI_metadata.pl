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
use Digest::SHA;
use Rcs;
use YAML::XS;
use Time::HiRes qw (time);
use File::Path qw(make_path);

my $fi = FileInterface->new();

my $SHA = "SHA-256";
my $datasha = "data.$SHA";
my $setsha = "system.dataset.$SHA";
my $metafile = "meta/aurora.yml";

my $METADATAAGE = $fi->Settings->value('FileInterfaceMetadataAge')      || 86400; # A day

my @datasets = @ARGV;
unless (@datasets) {
    my $sets = $fi->dbi->selectall_arrayref(
        "
            select D.entity 
            from      FI_DATASET D
            join      PERMTYPE   T on T.PERMTYPE=D.perm
            left join ENTITY     E on E.entity=D.entity
            where T.PERMNAME='DATASET_READ' and E.entity is not NULL 
            ",
        );
    @datasets = map { $$_[0]; } @$sets if $sets;
}
#
foreach my $id (@datasets) {
    my $now = time;
    my $dataset = $fi->dataset($id);
    my $private = $fi->absolute($dataset->fiprivate);
    chdir($private) or warn "chdir($id): $!" and next;
    #
    # Write check file if not exists
    unless (-e $datasha) {
        my $err;
        unless (-e "$datasha.tmp") {
            $err = system("find data/ -type f -print0 | LC_ALL=C sort -z | xargs -r0 sha256sum -b -z >$datasha.tmp.part");
        }
        if ($err == 0 ) {
            rename("$datasha.tmp.part", "$datasha.tmp");
            my $sha = Digest::SHA->new($SHA);
            if (open(BIN, '<', "$datasha.tmp") and open(TXT, '>', "$datasha.txt.tmp")) {
                my $buffer;
                while (sysread(BIN, $buffer, 2**16)) {
                    $sha->add($buffer);
                    $buffer =~ s/\0/\r\n/g;
                    print(TXT $buffer);
                }
                if ($dataset->adb->setEntityMetadata($id, { $setsha => [$sha->hexdigest] })) {
                    rename("$datasha.tmp", $datasha);
                    rename("$datasha.txt.tmp", "$datasha.txt");
                }
                else { warn "Failed to register $SHA: ".$dataset->adb->{error}; }
            }
            else { warn "Failed to open(): $!\n"; }
        }
        else {
            if ($err == -1) { warn "failed to execute: $!"; }
            else            { warn "child exited with value $? ($!)"; }
            unlink("$datasha.tmp.part");
        }
    }
    #
    # Updata metadata file if old or dont exists
    my $mtime = (stat $metafile)[9] || 0;
    if (!$mtime or $mtime < time() - $METADATAAGE*(0.5+rand(0.5))) { # Load distibution
        my $metadata = $dataset->adb->getEntityMetadata($id);
        my $rcs = Rcs->new("");
        if ($metafile =~ m|^(.*)/|) {
            make_path($1);
            $rcs->pathname($1);
        }
        $rcs->file($metafile);
        $rcs->bindir('/usr/bin');
        if ($metadata) {
            $rcs->co('-l') if -e "$metafile,v";
            YAML::XS::DumpFile("$metafile.tmp", $metadata);
            rename("$metafile.tmp", $metafile);
            $rcs->ci('-u', "-t-Metadata for Aurora dataset $id", '-mAuroa@'.time());
        }
    }
}
