#!/usr/bin/perl -w
# Copyright (C) 2019-2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
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
# ISO8601: Class to handle ISO8601-time in both standard and hires-time (hires is default)
#
package ISO8601;
use strict;
use Time::HiRes qw (time);
use POSIX;
use Time::Local;
use Exporter 'import';
our @EXPORT = qw(time2iso iso2time);

sub time2iso {
   my $time = shift;
   if (!defined $time) { $time=time(); }

   my $opt = (@_ and ref($_[0]) eq "HASH") ? shift : {};
   # check format - both hires and not accepted
   if ($time !~ /^\d+((\.\d+)?)$/) {
      # incorrect format
      $time=0.00000;
   }
   my $str=strftime("%Y-%m-%dT%H:%M:%S",gmtime($time));
   my $micro=$time;
   $micro=~s/^\d+((\.\d+)?)$/$1/;
   $str.="${micro}Z";
   #
   # strip if not default extended micro format
   $str =~ s/(T..:..:..).*/$1Z/ if $opt->{second};
   $str =~ s/(T..:..).*/$1Z/    if $opt->{minute};
   $str =~ s/(T..).*/$1Z/       if $opt->{hour};
   $str =~ s/T.*//              if $opt->{date};
   $str =~ s/[-:]//g            if $opt->{basic};
   #
   return $str;
}

sub iso2time {
   my $iso = shift || "";

   my $time;
   if ($iso =~ /^(\d{4})\-?(\d{2})\-?(\d{2})T(\d{2})\:?(\d{2})\:?(\d{2})((\.\d+)?)Z$/) {
      # format success - convert to time since epoch
      my $micro=$7;
      $time=timegm($6,$5,$4,$3,$2-1,$1);
      $time.=$micro;
   } else {
      # failed format match - set 0
      $time=0.00000;
   }

   return $time;
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<ISO8601> - Class for handling conversions to/from unixtime and ISO8601 datetime

=cut

=head1 SYNOPSIS

   use ISO8601;

   # convert without instantiating
   my $dtstring=time2iso(time());
   my $unixtime=iso2time($dtstring);

=cut

=head1 DESCRIPTION

A collection of functions to handle the conversion to and from unixtime and iso8601-time.

=cut

=head1 CONSTRUCTOR

This class does not have an instantiator/constructor. The two methods are exported by default
and can be used at any time.

=cut

=head1 METHODS

=head2 time2iso()

Converts from unixtime to ISO8601-time

Accepts these parameters in the following order:

=over

=item

B<unixtime> The unixtime to be converted. SCALAR. Required.

=cut

=item

B<format> Format options to the conversion process. HASH-reference. Optional. Accepted keys in the HASH-
reference are: second, minute, hour, date and basic. All of the option keys are boolean and if evaluated 
to true will give: second (all time, including seconds), minute (all time down to and including minute),
hour (only hour time), date (only give date), basic (only give basic time).

=cut

=back

Returns an ISO-string at the end of the conversion.

=cut


=head2 iso2time()

Converts an ISO string to unix datetime.

Only accepts one parameter: isotime. SCALAR. Required.

The ISO time string is given to the method and it 
converts it to iso.

Return the unixtime to the user.

=cut

