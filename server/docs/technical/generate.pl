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

my $HTML_LICENSE="".
"<!--\n".
"	Copyright (C) 2019-2022 Jan Frode Jæger <jan.frode.jaeger\@ntnu.no>, NTNU, Trondheim, Norway\n".
"	Copyright (C) 2019-2022 Bård Tesaker <bard.tesaker\@ntnu.no>, NTNU, Trondheim, Norway\n".
"\n".
"       This file is part of AURORA, a system to store and manage science data.\n".
"\n".
"       AURORA is free software: you can redistribute it and/or modify it under\n". 
"       the terms of the GNU General Public License as published by the Free\n". 
"       Software Foundation, either version 3 of the License, or (at your option)\n". 
"       any later version.\n".
"\n".
"       AURORA is distributed in the hope that it will be useful, but WITHOUT ANY\n". 
"       WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS\n". 
"       FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.\n".
"\n".
"       You should have received a copy of the GNU General Public License along with\n". 
"       AURORA. If not, see <https://www.gnu.org/licenses/>.\n".
"\n".
"-->\n";

my $input=$ARGV[0];

my @files;
# manually add the MethodsReuse.pm-file
push @files,"../../lib/restserver/MethodsReuse.pm";
if (!defined $input) {
   # get all relevant modules
   my @folders=("../../lib/",
                "../../lib/Authenticator",
                "../../lib/Content",
                "../../lib/DataContainer",
                "../../lib/GroupInfo",
                "../../lib/HTTPSClient",
                "../../lib/Interface",
                "../../lib/Interface/Archive",
                "../../lib/Notice",
                "../../lib/Parameter",
                "../../lib/Store",
                "../../lib/StoreProcess",
               );
   foreach (@folders) {
      my $folder=$_;

      if (opendir (DH,"$folder")) {
         # read folder contents, only .pm-modules
         my @f=grep { !/^\.{1,2}$/ && /^.*\.pm$/ } readdir (DH);
         # closedir
         closedir (DH);
         # go through all file and add to files list
         foreach (@f) {
            my $file=$_;
            push @files,"$folder/$file";
         }
      } else {
         # problem opening folder
         print "ERROR! Unable to open folder \"$folder\": $!\n";
      }
   }
} else {
   # add file from input
   push @files,$input;
}

# go through each file and convert
my @packages;
foreach (@files) {
   my $file=$_;
   my $outfile=$file;

   # strip file down to name and .html
   $outfile=~s/^.*\/([^\/\.]+)\.([^\/]+)$/$1\.html/;

   my $package=qx(/bin/grep -m 1 -ie "^\s*package" \"$file\");
   $package=~s/^\s*package\s+([^\;]+)\;[^\r\n]*[\r\n]+$/$1/;
   push @packages,$package;

   # try to convert
   print "Converting file: $file (package: $package)\n";
   my $r=qx(/usr/bin/pod2html --infile=$file --outfile="$package\.html");
   # check if successful
   if ($? == 0) {
      # doc generated succesfully from pod to html, add gnu license info in the file
      if (open (FH,"$package\.html")) {
         # read the files contents
         my $content=join("",<FH>);
         # close file after reading
         close (FH);
         # open tmp file to write to
         if (open (FH,">","/tmp/licenseadd.html")) {
            # open for business - add license and then the actual content
            print FH $HTML_LICENSE;
            print FH $content;
            # close temp file
            close(FH);
            # move temp file to actual file
            rename ("/tmp/licenseadd.html","$package\.html");
         } else {
            print "ERROR! Unable to open temporary file for writing license. Unable to continue...\n";
         }
      }
   }
}

# remove tmp-file
unlink ("./pod2htmd.tmp");

# auto-generate markdown index-file
if (open (MD,">","./index.md")) {
   # generate markdown file 
   print "Auto-generating index.md markdown file\n";
   print MD "# AURORA TECHNICAL DOCUMENTATION\n\n";
   print MD "## REST-server documentation:\n\n";
   print MD "- [REST-server documentation](./AuroraRestServer.html)\n\n";
   print MD "## Class documentation:\n";
   my $letter='-';
   foreach (sort {uc($a) cmp uc($b)} @packages) {
      my $package=$_;

      my $ch=uc(substr($package,0,1));

      if ($ch ne $letter) { print MD "\n### $ch\n\n"; $letter=$ch; }
      
      print MD "- [$package](./${package}.html)\n";      
   }
   # close file
   close (MD);
}
