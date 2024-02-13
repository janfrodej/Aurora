#!/usr/bin/perl -Tw
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

# taint check env path
$ENV{PATH}=~/(.*)/;
$ENV{PATH}=$1;

# CONSTANTS
my $TITLE       = "Download Archived Dataset";
my $CSS         = "./system.css";
my $TOUCH	= "/usr/bin/touch";
my $EXPFOLDER   = "/web/aurora_dropzone";
my $EXPPREFIX   = "archive";

# instantiate CGI-class
my $s=CGI->new(); 

# get cookie var
my $cookie = $s->param("cookie");
$s->delete ("cookie");

# wash cookie
$cookie =~ /([a-z|A-Z|0-9]{64})/;
$cookie = $1;

if ($cookie =~ /[a-z|A-Z|0-9]{64}/) {
   my $fname = glob ("$EXPFOLDER/${EXPPREFIX}_*_*_$cookie.*");
   if ($fname !~ /^.*\.lock$/) {
      if (-e "$fname") {
         # taint check fname
         $fname =~ /(.*)/;
         $fname = $1;
         # get format of file 
         my $qcookie = qq($cookie);
         my $format = $fname;
         $format =~ s/.*$qcookie\.(.*)/$1/;
         # get size of file
         my $size = (stat($fname))[7];
         # make a timestamp on archive
         my @ltime = localtime (time());
         my $time = sprintf ("%4d%02d%02d",$ltime[5]+1900,$ltime[4]+1,$ltime[3]);

         # start to send output string
         print( $s->header( -type=>'' || 'application/octet-stream',
                            -content_disposition=>"attachment; filename=${EXPPREFIX}_$time.$format",
                            -content_length=>$size,
                          ),
              );

         if (open ARCH,"<$fname") {
            my $bytes;
            my $buffer;
            while ($bytes = sysread ARCH,$buffer,2**14) {
               print $buffer;
            }

            # close file for reading
            close ARCH;
            # archive still of interest - update timestamp on it
            qx ($TOUCH "$fname"); 
         } else {
            message ("Error! Unable to read archived dataset...");
         }
      } else {
         message ("Error! No such archived dataset exists ($EXPFOLDER/${EXPPREFIX}_*_*_$fname)...");
      }
   } else {
      message ("Error! This archived dataset is still being generated...");
   }
} else {
   message ("Error! Not a valid cookie...");
}

sub message {
   my $str = shift;

   print $s->header(-charset=>'UTF-8');
   print $s->start_html(-title => $TITLE,
                        -style=>{ src=>$CSS });

   print "<DIV CLASS=\"message\">$str</DIV>";
}
