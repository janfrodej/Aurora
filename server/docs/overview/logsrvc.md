<!--
        Copyright (C) 2019-2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway

        This file is part of AURORA, a system to store and manage science data.

        AURORA is free software: you can redistribute it and/or modify it under 
        the terms of the GNU General Public License as published by the Free 
        Software Foundation, either version 3 of the License, or (at your option) 
        any later version.

        AURORA is distributed in the hope that it will be useful, but WITHOUT ANY 
        WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
        FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

        You should have received a copy of the GNU General Public License along with 
        AURORA. If not, see <https://www.gnu.org/licenses/>. 
-->
# Log-service overview

The Log-service is a service to receive log-messages from the AURORA-system 
and ensure their safe delivery to the database used by it. It consist of 
an SQLite database that resides locally on the AURORA-server and which then 
are read and processed and then put into the database used by the system 
in general. All parts of the AURORA-system sends its logs to the SQLite 
file, which then are processed by the Log-service.

The reason for this design is to allow for the safe storage of log-
messages, even in the event of critical events that cripple the main 
database of the system and/or network availability. It also allows for 
a easier drop-and-forget design for sending log-messages by the 
various AURORA-services.

## Design

The design of the Log-server is very simple. It is basically a loop that monitors changes in 
the SQLite file and if it has changed, it reads the contents and tries to deliver them to 
the system database.

It works after a all-or-nothing design, so that if some log-entries fails it will assume all 
log-entries failed. It will then roll back any changes that were made and try again after a 
little wait period.

Any errors or failures are logged to the service itself (it was that thing about the hen and 
the egg).
