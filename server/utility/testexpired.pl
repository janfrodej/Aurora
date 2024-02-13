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
use Settings;
use SysSchema;
use AuroraDB;

# settings instance
my $CFG=Settings->new();
$CFG->load();

# database instance
my $db=AuroraDB->new(data_source=>$CFG->value("system.database.datasource"),user=>$CFG->value("system.database.user"),
                     pw=>$CFG->value("system.database.pw"));

# connect to database
$db->getDBI();

# update db-connection
if (!$db->connected()) {
   print "Unable to connect to DB: ".$db->error()."\n";
   exit(1);
}

my $time=time();

# get all datasets which have expired (both open and closed), so we can create a remove or close notification
my @md=("AND"); # all of the basic criteria has to be true
push @md,{$SysSchema::MD{"dataset.removed"} => { "=" => 0 }};
push @md,{$SysSchema::MD{"dataset.expire"} => { "<=" => $time }};
# do not select datasets that are still open and that are automated ones - they are to be handled
# by the Store-service primarily. Failed distributions and their datasets are to be handled by
# the failed distributions algorithm.
push @md,["NOT",
            ["AND",{$SysSchema::MD{"dataset.status"} => { "=" => $SysSchema::C{"status.open"} }},
                   {$SysSchema::MD{"dataset.type"} => { "=" => $SysSchema::C{"dataset.auto"} }},
            ],
         ];

my $expired=$db->getEntityByMetadataKeyAndType (\@md,undef,undef,$SysSchema::MD{"dataset.created"},"ASC",undef,[$db->getEntityTypeIdByName("DATASET")]);

use Data::Dumper;
print Dumper($expired);
