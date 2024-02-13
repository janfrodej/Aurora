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
Notification-service overview
=============================

The notification-service is an AURORA-service to handle the receiving and 
sending of messages, manage message user-feedback (confirmations) and
escalation upon lack of user-feedback.

The service consists of a folder structure with single files for each event 
or change in the notification timeline and folders for each separate 
notification.

The default location of the service's files and folders are in "/local/app/aurora/notification".

Some definitions:

  - Notification - is a message sent by someone or from somewhere in the AURORA-system.
  - Notice - is a message sent by the Notification-service to a user of the AURORA-system through some transport type.

Folder Structure
----------------

Each new notification in AURORA has its own folder that consists of 32 random characters 
(a-zA-Z0-9). These 32 characters uniquly identifies the notification in question.

In addition to these folders for each notification, there is a folder called "Ack". This 
folder contains files that are used by the acknowledgement/feedback mechanism of the 
notification-service when the user accepts a notification. He can acknowledge a 
notification in the sense that he has read it or to accept a change being made (such as 
deleting a dataset).

The folder structure looks like this:

	Ack
	RANDOMIDa
	RANDOMIDb
	.
	.
	RANDOMIDz

Ack-folder
----------

The Ack-folder contains files for notifications that needs to or can be 
acknowledged/accepted.

This folder is used in cases where the user needs to vote over something happening, 
such as, and particularly, deleting datasets. This mechanism is in place to 
ensure that no important happens, in this case deletion, without 
someone having cast votes to ok it. It also protects against critical operations 
happening when the user that created a dataset no longer exists and the group or 
someone higher up in the entity tree needs to and requires control of the process.

The votes needed for various operations are defined in the AURORA system-wide 
configuration file. In addition it is possible to define how many votes various 
users have on specific levels in the entity tree. This makes it possible for 
eg. a research group to say that our members have a certain number of votes 
on this group in the entity tree and can accept a dataset deletion themselves.

As a default a user has only 1 vote and dataset deletion needs 2 votes. This means 
that no single user can accept a dataset being deleted. This behaviour can be 
modified as outlined above.

Each acknowledgement from a specific user gets an Ack-file created in the 
Ack-folder. In this way the Ack-file is personal and tied to a specific user. 
The Ack-file is named in the following manner:

	NOTRANDOMID_USERRANDOMID

where NOTRANDOMID is the random and unique id of the notification in question 
(32 characters) and USERRANDOMID is the random id (rid) of the user that has 
this rid assigned (also 32 characters, a-zA-Z0-9).

The signalling into the notification-service through the Ack-files are done
with the ack web-script touching the Ack-file in question and thereby modifying 
its timestamp. The Notification-script then knows that it has received an
acknowledgement from a specific user. When a Notice is sent to a user where 
voting is necessary an Ack-file is created and the Notice will be modified 
to contain the link to the ack web-script and the rid that he/she needs to vote. 
In addition, if any voting has already taken place, the Notice will contain the 
votes that have already been cast and who cast them? This will make the 
decision process easier for the group on the specific Escalation-level.

Notification Files
------------------

The notification files are written in the YAML-format and the names of the 
files are in the following format:

	RANDOMID_UNIXTIME.MS_EVENTTYPE

RANDOMID is a random string of 32 characters (a-zA-Z0-9) that identifies the 
notification in question. UNIXTIME is the unix datetime of when the event 
happened (for which the file was written) and MS is the hi-resolution or
microsecond part of the datetime stamp. EVENTTYPE designates the type of
event that the specific file pertains to. These event-types are recognized:

- Message
- Escalation
- Notice
- Ack
- Fin

A Notification-folder might look like this:

	-rw-r--r--  1 janj janj  187 april 24 21:29 fvdazf2qxbmbnrJw5DMMT6KUXeGbRfH6_1587756543.12889_message
	-rw-r--r--  1 janj janj  157 april 30 10:49 fvdazf2qxbmbnrJw5DMMT6KUXeGbRfH6_1588236562.14731_notice
	-rw-r--r--  1 janj janj   80 april 30 11:00 fvdazf2qxbmbnrJw5DMMT6KUXeGbRfH6_1588237208.67989_escalation
	-rw-r--r--  1 janj janj   78 april 30 11:00 fvdazf2qxbmbnrJw5DMMT6KUXeGbRfH6_1588237214.29851_escalation
	-rw-r--r--  1 janj janj   79 april 30 11:00 fvdazf2qxbmbnrJw5DMMT6KUXeGbRfH6_1588237221.14481_escalation
	-rw-r--r--  1 janj janj   78 april 30 11:00 fvdazf2qxbmbnrJw5DMMT6KUXeGbRfH6_1588237227.8576_escalation
	-rw-r--r--  1 janj janj   79 april 30 11:00 fvdazf2qxbmbnrJw5DMMT6KUXeGbRfH6_1588237234.52456_escalation
	-rw-r--r--  1 janj janj   79 april 30 11:00 fvdazf2qxbmbnrJw5DMMT6KUXeGbRfH6_1588237240.99572_escalation
	-rw-r--r--  1 janj janj  156 april 30 11:00 fvdazf2qxbmbnrJw5DMMT6KUXeGbRfH6_1588237247.7499_notice
	-rw-r--r--  1 janj janj   77 april 30 11:04 fvdazf2qxbmbnrJw5DMMT6KUXeGbRfH6_1588237484.97202_escalation

Notification-Service Processing
-------------------------------

The Notification-service processes files in the various Notification-folders, but also 
handles writing new events to a Notification. Five Notification-events are recognized : 
Message, Escalation, Notice, Ack and Fin.

A Message-event is an event that only happens once for a given notification and basically 
contains the message itself that is needed to be sent.

An Escalation-event is an event where the needed voting or notices has not been fulfilled and
the system escalates the notification-task up the entity tree in order to ensure that 
someone is notified and/or responds to the notice. The level-setting of the escalation points to 
a group id in the entity tree. The only divergence from this behaviour is in the case of 
dataset- and user- entities. In the case of a dataset entity, the id of the dataset is the start 
of the Notification-task (and the user that created it is the primary receiver). In the case of 
a user entity, the user in that entity is the primary receiver. After this intial divergence the 
dataset- or user-notification is escalated up the entity tree along group-entities.

A Notice-event is an event where the message in question is sent to a user in the AURORA-
system. A Notice-event is created for each user, as well as for each type of notice-transport 
or class (eg. Email, SMS etc.) on each Escalation-level. But only one rid is created for each 
user, independent upon notice-transport type in the case of voting/acknowledgement (see the 
Ack-folder paragraph).

An Ack-event is an event where a user has voted on a Notice that he/she has received. The 
Ack-event is processed by the Notification-service and any votes are added to the 
notification process. When sufficient votes have been achieved the operation is marked as 
accepted and in the case of eg. dataset deletion, the Maintenance-service will perform the 
deletion when sufficient votes have been cast.

A Fin-event is an event that marks that the Notification-service is finished processing 
the notification (the Maintenance-service will pick it up from there and do clean-up and other 
things if needed).

Because each change to the life of a notification is written to event-files, the Notification-
service can be interrupted or crashed, but will resume its operation where it left off as 
soon as it is restarted by reading and processing the event-files of a Notification. In other 
words the state is in the files.

In addition to having a limited number of events for each notification, a notification that are 
created also have a type. This type defines certain attributes that relates to the notification, such 
as the number of votes needed to confirm it and the subject-heading to use when sending notices related 
to it. These notification-types are defined and set up in the settings-files for AURORA (see the 
installation-documentation for AURORA). What is important here is that for those notification-types that 
have a votes-setting larger than 0 (no votes needed), the Notification-service will require the users 
that have a relationship with the datasets in question to vote in order to accept what the notification is 
about or not (such as deleting a dataset).

The users of the AURORA-system will subscribe to various Notice-types (ways of notifying the users) and in 
addition have a set number of votes for the entity-level that the notification are sent on. Only when the 
required number of votes defined for the given notification-type has been achieved, will the potential next
step for the dataset commence (such as actually deleting it).

If not enough votes have been received on notifications that requires them, the notification will be 
escalated up the entity tree and other users will be brought in to respond to it according to what has 
been configured in the entity tree.

