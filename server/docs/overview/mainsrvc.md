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
# Maintenance-services overview

The maintenance-services is AURORA-services to do various cleanup- and administration 
operations for the AURORA-system.

They checks if datasets are about to expire and creates notifications within the given 
notification-intervals (14 days before, 7 days before 1 day before etc.). They also checks
if any dataset have expired and if any are overdue its expiration date without 
being removed.

Furthermore they clean up and handle notifications that have ended, distributions that have 
failed for the last time, as well as cleaning up web client interfaces and fileinterface tokens.

## Order of operations

The various operations of the Maintenance-tasks are sub-grouped into separate services in 
the following manner:

1. MAINT_GEN (general maintenance-operations)
  - Check for datasets that are about to expire (and create notificaitons where necessary)
  - Check for datasets that have expired (both open and closed ones).
  - Clean up and deal with notifications that have ended (notification-event FIN exists).
  - Check for Store-service distribution-tasks that have failed and nothing happened for a long time.
  - Clean up web-client interfaces (remove zip- and tar etc.)
  - Clean up expired FileInterface-tokens.
  - Sanity check/update of entity-metadata.
  - Cleaning up the database.
2. MAINT_PERM (permission-related maintenance-operations)
  - Check the database sequence-table for integrity issues and correct when necessary
  - Update the PERM_EFFECTIVE-tables when necessary to reflect changes in permissions
3. MAINT_META (updating of metadata-related tables)
  - Update the synthetic table of metadata.

However, dependent upon the settings in the AURORA-config file(s) the various operations might be 
skipped while being checked, because it is not yet their time to be executed or they have been disabled 
entirely.

Each operation has their own "interval"-setting in the config file (see the sysop-documentation
and how to install AURORA).

## Creation of notifications

The maintenance-services will in several cases create new notifications for the Notification-service 
to handle. The most commons ones are:

- Creating notifications when datasets are about to expire.
- Creating notifications when datasets *have* expired.

These two maintenance-operations are sort of complementary, where one deals with datasets that soon 
will expire, while the other deals with datasets that are actually expired.  

The expired datasets operation will create a special notification that will allow the owner(s) and member(s) of 
the owner group, and according to their setup, to vote if it is acceptable to remove the dataset in question.

Each time a notification has been created the Maintenance-service will save the time that it was created 
to avoid multiple creation events. This is true for both sets that are about to expire and sets that have 
expired. The handling of notifications that are not received or responded to is not part of the things that 
the maintenance-service handles, but are left to the notification-service (through escalation-events).

## Cleaning up notifications

When a notification has ended its "life-cycle" the Notification-service will write a FIN-event to the 
end of it signalling that its work is at an end.

The MAINT_GEN-service will regulary scan the notification-folders to see if it is able to locate any 
notifications that have the FIN-event on them. In such cases it will investigate further in order to 
determine if thet type of notification is related to a special notification-type or not. The notification-
type determines if it is to be just cleaned up and removed, or something else is going to happen.

A typical special notification-type is the "dataset.remove"-type, which is basically for signalling the 
wish to remove a dataset. When a FIN-event has been written to such a type of notification, it potentially 
signals that it is ready to be removed.

When a "dataset.remove" notification has reached its FIN-event, the MAINT_GEN-service will do the following:

- Check if the notification has been cancelled for removal (it is then tagged as such by the Notification-service).
- If not cancelled it will proceed to remove the dataset.
- If it was cancelled it will create a new notification informing about the cancellation.

When a "dataset.close"-notification has reached its FIN-even, the maintenance-service will do the following:

- Check if the notification has been cancelled or not?
- If not cancelled it will proceed to close the dataset.
- If it was cancelled it will create a new notification informing about the cancellation.

## Failed distribution-tasks

This maintenance-operation checks for Store-service tasks that have a status as "failed" as well as being 
the phase "failed". If both are met and the retries have been exhausted, this operation will deal with 
the fallout and handling of that.

## Cleaning up web-client interfaces

This operation cleans away any temporary files or data for the various web-client interfaces.

## Cleaning up expired FileInterface-tokens 

Tokens created through the FileInterface are temporary and have a set expire date and needs to at some point to be removed. 

This maintenance-operation will identify tokens that have expired and proceed to remove them. It will add a log-entry on the 
dataset in question if it removes a token.

## Sanity check/update of entity-metadata

Sanity checks and writes/updates the METADATA-table in the database with information from the ENTITY-table, 
more specifically: entity ID of itself, entity type ID of itself and entity parent ID of itself.

It will also change values in the metadata for these keys that are not consistent with whats in the 
ENTITY-table.

## Check the database sequence-table for integrity issues

Check the database ENTITY_SEQUENCE-table for integrity issues and attempts corrections if needed.

The ENTITY_SEQUENCE-table is important to the functioning of the Aurora-system and ensures that several of 
the database queries returns results that are consistent with whats in the database. 

## Update the PERM_EFFECTIVE-tables

Checks the database for any changes in PERMISSIONS and render the PERM_EFFECTIVE-tables with the correct 
information.

## Update the synthetic table of metadata

Updates the METADATA_COMBINED-table in the database with all the information from the METADATA-table, as well as 
data synthetically created for entities where necessary. Examples of such information is the textual name of 
an entites parent, as well as the textual name of the computer that was the origin of a dataset.

The METDATA_COMBINED-table is used for several things in the Aurora-system and specifically when searching for 
datasets and one needs a bit search options than what the METADATA-table provides on each, individual entity.

## Cleaning up the database

This consists of removing connection- and tunneling logs in the system that has expired/passed the threshold for 
storage time. The default value is 3 months, but can be overridden in the config-file of AURORA.

This cleaning removes entries from the STATLOG- and LOG-tables respectively. 
