package AuroraVersion;

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

our $VERSION="2.2";

1;

__END__

=encoding UTF-8

=head1 NAME

C<AuroraVersion> Package to define the AURORA-system version used by the other parts of the system.

=cut

=head1 SYNOPSIS

   use AuroraVersion;

   my $VERSION=$AuroraVersion::VERSION;

=cut

=head1 DESCRIPTION

This package defines the AURORA-version of the distribution in question. It is used by the other parts of the system, both 
the REST-server and the Web-client to define their version. It only contains a version-definition and nothing more.

This package is to be modified by the developers with the version number in question upon a new AURORA release.

=cut

=head1 METHODS

No methods available.

=cut
