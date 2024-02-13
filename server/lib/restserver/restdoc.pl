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
"       Copyright (C) 2019-2022 Jan Frode Jæger <jan.frode.jaeger\@ntnu.no>, NTNU, Trondheim, Norway\n".
"       Copyright (C) 2019-2022 Bård Tesaker <bard.tesaker\@ntnu.no>, NTNU, Trondheim, Norway\n".
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

my @infiles=("../../restsrvc/restsrvc.pl","MethodsGeneral.pm","MethodsAuth.pm","MethodsComputer.pm","MethodsDataset.pm",
             "MethodsGroup.pm","MethodsInterface.pm","MethodsNotice.pm","MethodsScript.pm","MethodsStore.pm","MethodsTask.pm",
             "MethodsTemplate.pm","MethodsUser.pm");

my $outfile="../../docs/technical/AuroraRestServer.html";
my $tmpfile=".restpod.tmp";

print "$0\n\n";
print "Generating POD-doc for REST-server to $outfile\n";

if (!open (FH,">","${outfile}.tmp")) {
   print "ERROR! Unable to open $outfile for writing: $!\n";
   exit;
}

# Merge all POD-entries together
my $pod;
foreach (@infiles) {
   my $file=$_;

   if (open (FH2,"<",$file)) {
      my @lines=<FH2>;
      close (FH2);
      print "Merging POD data from $file\n";
      my $found=0;
      foreach (@lines) {
         my $line=$_;
         if ($line =~ /^.*\_\_END\_\_.*$/) { $found=1; next; }
         elsif ($found) { $pod.=$line; }
      }
   } else { print "ERROR! Unable to open $file for reading...\n"; next; }
}

# save to temp file
open (FH2,">",$tmpfile);
print FH2 $pod;
close (FH2);

# convert to html
my $res=qx(/usr/bin/pod2html --infile=$tmpfile);

# check for errors
if ($? == 0) {
   # no errors - first add copyright
   print FH $HTML_LICENSE;
   # then add all documentation to outfile
   print FH "$res";
   rename("${outfile}.tmp",$outfile);
} else {
   # failed to convert - abort
   print "Failed to convert POD-data: $res. Aborting...\n";
}

unlink ($tmpfile);
unlink ("pod2htmd.tmp");
close (FH);

