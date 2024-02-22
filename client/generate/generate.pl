#!/usr/bin/perl -w
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
# generate.pl: Generate web-client documentation based upon several sources.
#
use strict;
use POSIX;
use Data::Dumper;
use File::Basename;
use Cwd 'abs_path';

my $SCRIPTPATH=dirname(abs_path(__FILE__));
my $CODEPATH=$SCRIPTPATH . "/..";

print "CODEPATH: $CODEPATH\n";

my $GREP="/usr/bin/grep";

my $orgfold=$ENV{PWD};
chdir("$CODEPATH/src");

my @res=qx($GREP -Pe "\\s+Description\\:\\s*[^\\n]" *.svelte 2>&1);
if ($? != 0) {
   print "Error! Unable to check descriptions of the svelte source-files: $!\n";
   exit (1);
}

my @libres=qx($GREP -Pe "\\/\\/\\s+Description\\:\\s*[^\\n]" _*.js 2>&1);
if ($? != 0) {
   print "Error! Unable to check descriptions of the svelte library (_*.js) source-files: $!\n";
   exit (1);
}

chdir($orgfold);

# we can go through what we found and harvest component descriptions
my %comps;
push @res,@libres;
foreach (@res) {
   my $line=$_;

   if (($line =~ /^([^\:]+)\:\s+Description:\s*([^\n]+)/) ||
       ($line =~ /^([^\:]+)\:\s*\/\/\s*Description:\s*([^\n]+)/)) {
      my $file=$1;
      $file=~s/^\.\/(.*)$/$1/;
      my $descr=$2;
      $comps{$file}{description}=$descr;
   }
}

# go through each component and harvest which other components it uses
foreach (keys %comps) {
   my $comp=$_;

   my @imports=qx($GREP -Pe "\\s+import\\s+(\\\{\\s*\[^\\\}\]+\\\}|[^\\s]+)\\s+from\\s+\[^\\;\]+" "$CODEPATH/src/$comp");
   my $errcode=$?;
  
   if ($errcode != 0) {
      if (@imports > 0) {
         print "Error! Unable to check imports for file $comp: $! ($errcode)\n";
         print "@imports\n";
      }
      next;
   }
   # go through matches
   $comps{$comp}{import}={};
   foreach (@imports) {
      my $line=$_;
      if ($line =~ /\s+import\s+(\{\s*([^\}]+)\}|[^\s]+)\s+from\s+[\'\"]{1}([^\'\"]+).*/) {
         my $imps=$1;
         my $file=$3;
         $file=~s/^\.\/(.*)$/$1/;
         # clean imps
         $imps =~ s/[\{\}]//g;

         # we are not interested in internal svelte imports
         if ($file =~ /^(svelte|svelte\/[^\'\"]+)/) { next; }

         # add all imports for this file
         my @mods;
         foreach (split(",",$imps)) {
            my $imp=$_;
            $imp=~s/^\s*([^\s]+)\s*$/$1/;
            push @mods,$imp;
         }
         # add data to hash
         $comps{$comp}{import}{$file}=\@mods;
      }
   }
   if (!defined $comps{$comp}{import}) { $comps{$comp}{import}=[]; }
}

# open top.md and read its contents
my $TOP;
my $TOPDATA="";
if (open($TOP,"$SCRIPTPATH/top.md")) {
   $TOPDATA=join("",<$TOP>);
   close ($TOP);
} else {
   print "Error! Unable to read top.md-file: $!. Unable to continue...\n";
   exit(1);
}

# open middle.md and read its contents
my $MIDDLE;
my $MIDDLEDATA="";
if (open($MIDDLE,"$SCRIPTPATH/middle.md")) {
   $MIDDLEDATA=join("",<$MIDDLE>);
   close ($MIDDLE);
} else {
   print "Error! Unable to read middle.md-file: $!. Unable to continue...\n";
   exit(1);
}

# open bottom.md and read its contents
my $BOTTOM;
my $BOTTOMDATA="";
if (open($BOTTOM,"$SCRIPTPATH/bottom.md")) {
   $BOTTOMDATA=join("",<$BOTTOM>);
   close ($BOTTOM);
} else {
   print "Error! Unable to read bottom.md-file: $!. Unable to continue...\n";
   exit(1);
}

# open webclient documentation file for writing
my $DOC;
if (!open($DOC,">","$CODEPATH/public/docs/webclient/index.md")) {
   # failed to open writing to webclient documentation
   print "Error! Unable to open webclient documentation file for writing: $a...\n";
   exit(1);
}

# write top.md to webclient documentation
print $DOC $TOPDATA."\n\n";

# write library overview
foreach (sort {$a cmp $b} keys %comps) {
   my $component=$_;

   if ($component =~ /\.svelte$/) { next; }

   # write to the webclient-documentation
   print $DOC "- **\\$component**: - ".$comps{$component}{description}."\n";
}

# write middle.md to webclient documentation

print $DOC "\n\n$MIDDLEDATA";

# print component overview header
print $DOC "\n## Component overview\n\n";
foreach (sort {$a cmp $b} keys %comps) {
   my $component=$_;

   if ($component !~ /\.svelte$/) { next; }

   # write to the webclient-documentation
   print $DOC "- **$component**: ".$comps{$component}{description}."\n";
}

# generate component use-chart
print $DOC "\n## Component use/imports\n\n";
print $DOC "This is an overview of which components are used by a component and only consists of those that are main ones\n".
           "of the project itself. All _-libraries and svelte internal libraries have med removed from this overview.\n\n";
foreach (sort {$a cmp $b} keys %comps) {
   my $component=$_;

   # we only show svelte components...
   if ($component !~ /\.svelte$/) { next; } 

   my @mods = grep { $_ =~ /\.svelte$/ } keys %{$comps{$component}{import}};

   if (@mods > 0) {
      print $DOC "- **$component**:\n";
      foreach (sort {$a cmp $b} @mods) {
         my $mod=$_;
         # we are only interested in .svelte components here
         if ($mod !~ /\.svelte$/) { next; }
         # print name of component as a sub level bullet list
         print $DOC "  - $mod\n";
      }
   } else {
      print $DOC "- **$component**: NO USE OF APPLICATION COMPONENTS.\n";
   }
}

# write the bottom.md to the webclient documentation.
print $DOC "\n\n".$BOTTOMDATA;

close ($DOC);

#print Dumper(\%comps);
