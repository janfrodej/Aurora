<!--
        Copyright (C) 2019-2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
        Copyright (C) 2019-2024 Bård Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway

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
# AURORA diagnostic routines

This document outlines diagnostic routines for system operators to analyze
and pinpoint why the AURORA-system has failed (we, the designers and coders, 
categorically denies any such poppycock).

There are many points where the AURORA-system might fail and while this 
documentation is not exhaustive it will offer a framework and overview 
whereby diagnostics might be carried through on such issues.

The AURORA-system generally looks like this:

![AURORA-system overview](../media/aurora-overall_diagram.png)

When faults happen, the next step is identifying where in the system the problem resides. Beyond this 
overview illustration above, read the "[General Overview Introduction](../overview/general.md#introduction)" for 
more general information about the system.

## AURORA-services overview

On the AURORA-server the AURORA-system consists of the following services that collectively is 
known as the AURORA-system:

- AURORA REST-server (handles all REST-calls from the web-client or any other place. Its the main contact-point of the AURORA-system).
- Log-service (collects log-entries in a SQLite file and inserts them into the main AURORA-database)
- Maintenance-services (various maintenance tasks for the system, such as deleting datasets, cleaning up etc.)
- Notification-service (handles sending notifications to users, escalation and voting)
- Store-service (handles distribution-operations on datasets, retries etc.)

These can be viewed running in the following manner:

	aurora01:~# ps auxw|grep -i aurora
	sys-aur+ 11242  0.0  1.1 115568 45916 ?        S    Aug04   0:02 ./restsrvc.pl AURORA REST-Server Daemon
	sys-aur+ 11273  0.0  0.5 187108 23484 ?        S    Aug04   0:47 ./logsrvc.pl AURORA Log-Service Daemon
	sys-aur+ 11272  0.0  0.5 160345 26371 ?        S    Aug04   0:47 ./maint_gen.pl AURORA MAINT_GEN Daemon
	sys-aur+ 11274  0.0  0.5 160345 26371 ?        S    Aug04   0:47 ./maint_perm.pl AURORA MAINT_PERM Daemon
	sys-aur+ 11275  0.0  0.5 160345 26371 ?        S    Aug04   0:47 ./maint_meta.pl AURORA MAINT_META Daemon
	sys-aur+ 11276  0.0  0.7 304532 29464 ?        S    Aug04   3:22 ./notsrvc.pl AURORA Notification-Service Daemon
	sys-aur+ 11280  0.0  0.7  84048 29556 ?        S    Aug04   0:47 ./storesrvc.pl AURORA Store-Service Daemon

These services are started by cron-job entries that are typically located in /etc/cron.d/. This is an example of such a 
cron-job file:

	# AURORA REST-server
	*/1 * * * * sys-aurora /local/app/aurora/isrunning.sh /local/app/aurora/dist/restsrvc restsrvc.pl aurorasrvc >> /var/log/aurora/aurora.log 2>&1
	# check that Aurora log-service is running, if not start
	*/2 * * * * sys-aurora /local/app/aurora/isrunning.sh /local/app/aurora/dist/logsrvc logsrvc.pl auroralogsrvc >> /var/log/aurora/logsrvc.log 2>&1
	# check that Aurora notification-service is running, if not start
	*/2 * * * * sys-aurora /local/app/aurora/isrunning.sh /local/app/aurora/dist/notsrvc notsrvc.pl auroranotsrvc >> /var/log/aurora/notsrvc.log 2>&1
	# check that Aurora maintenance-services is running, if not start
	*/2 * * * * sys-aurora /local/app/aurora/isrunning.sh /local/app/aurora/dist/mainsrvc maint_gen.pl auroramaint_gen >> /var/log/aurora/maint_gen.log 2>&1
	*/2 * * * * sys-aurora /local/app/aurora/isrunning.sh /local/app/aurora/dist/mainsrvc maint_perm.pl auroramaint_perm >> /var/log/aurora/maint_perm.log 2>&1
	*/2 * * * * sys-aurora /local/app/aurora/isrunning.sh /local/app/aurora/dist/mainsrvc maint_meta.pl auroramaint_meta >> /var/log/aurora/maint_meta.log 2>&1
	# check that Aurora store-service is running, if not start
	*/2 * * * * sys-aurora /local/app/aurora/isrunning.sh /local/app/aurora/dist/storesrvc storesrvc.pl aurorastoresrvc >> /var/log/aurora/storesrvc.log 2>&1

In this case any output to STDERR can be read by checking files in /var/log/aurora. This is particularly of interest if one or more of the 
services are not running or they fail to start.

This is the connection between various parts of the AURORA-system:

	AURORA-system (REST-server, notification-, maintenance-, store- and log-services)  --->  MySQL database
	      |                               
	     sudo
	      |
	FileInterface
	      |
	  Storage Area (NFS)
	
	----------------------------------------------------------------
	SAMBA-server
	     |
	  Storage Area (NFS)
	----------------------------------------------------------------
	Web-client  -->  AURORA REST-server

It should be noted that the SAMBA-server might be any protocol that shares out filesystems in any way, such as FTP, SFTP, SSHFS etc. 
This is the big advantage of the FileInterface that its mechanisms are built upon standard POSIX filesystem features and therefore 
can be exported in any number of known and standardized protocols.

## Checking failed Datasets

Often problems that the user experiences are related to creating and managing datasets. These 
problems might often not be related to any systems failure of AURORA or the services that it 
relies on. Often the problem are related to remote equipment (lab computers and such) or 
to something the user did wrong (specifying wrong paths and information when creating 
datasets).

### By using the dataset log

Upon any failure by a dataset, the first thing to check is the dataset log. This can 
be accessed through the web-client by going to "Manage Datasets" and then choosing the 
"View"->"Log" option (provided that one has the permissions, or else the option will not 
be there).

The dataset might fail in some way because of several reasons, so one needs to read 
through the log to see what failed. It might be an advantage to change the loglevel 
from INFORMATION to DEBUG to get better overview of what failed?

### By using the ERROR-dump in the distribution task

Some times the distribution process fails with an error than cannot be so easily 
discerned by reading the last few error messages in the dataset log. In those cases one 
needs to login to the Aurora-server as an admin and access the distribution-folder of the 
Store-service (default in /local/app/aurora/distributions).

To get information on the failed distribution process, access the dataset Log in the web-client 
by choosing "View->Log" in the "Manage Datasets"-view. Here the failed process will have its random 
task id listed.

Then do the following:

1. Locate the folder with the task in question. All tasks starts with the userid then a comma and 
then the the dataset id, then a comma and followed by the random task id:

	USERID,DATASETID,RANDOM_STRING

2. Go into the task folder and read the file called "ERROR". It will contain an entire dump of the 
collected log entries for the distribution task and will better give a picture of what happened?

## Checking the WEB-client

The web-client relies on several things being in place in order to function properly. First 
and foremost try accessing the main web page of the AURORA web-client and see what it says 
on the screen?

### Checking Access to the Settings-File

All of the Web-clients scripts will fail if they cannot access the settings-file. 
The settings file is located in the root of the web folder (/public in the git repo 
of the AURORA web-client).

The settings file must be readable and it must be correctly setup.

### Checking File Locations

In order for the Web-client to work it also needs to be placed correctly. This should 
usually not be an issue, but AURORA expects the following folder hierarchy:

- AURORA web-client actual files location ($AURORAWEB_PATH, not the document root of the web-client)
  - www (document root of the Web-client - usually symlinked from /public of the web-client git repo)
  - settings (configuration file of the feide.cgi-script)
  - release (git repo sync folder(s))

There are many ways of achieving this structure.

For more information of folder locations, have a look at the "Installation Documentation" of 
the AURORA-system.

## Checking the REST-server

To check that the REST-server is running and working properly, one can execute a rest-call 
with the AURORA REST-server and see that it responds correctly. There are two main ways 
of achieving this:

### Using curl

	curl -v -k -d '{"authtype":"AuroraID","authstr":"myname@mydomain.org,ThisIsMySecretPassword1234","id":1}' -H "Content-Type: application/json; charset=utf-8" https://aurora.it.ntnu.no:9393/getName

It will respond by outputting the name of entity with id 1 (ROOT-node, top of the entity tree). 
In order to execute this operation, the REST-server also needs to talk to the AURORA database,
so it is a good way to both check the response of the REST-server as well as the database 
connectivity for AURORA. Any failure will make the service respond with an appropriate 
message which can then be investigated further.

### Using restcall-script

	/local/app/aurora/dist/utility/restcall.pl

The restcall.pl.script enables the administrator to execute rest-calls with the AURORA REST-server and it will
ask the user for credentials upon starting and then continue in a loop until the the user aborts.

It will come up and ask for what REST-call to issue followed by the calls JSON-data like this:

	getName {"id"=1}

the utility supports the full JSON-capabilities and will either ignore wrong statements or issue 
error messages.

One can abort restcall.pl by using CTRL+C or by writing "." and hit ENTER instead of issuing a REST-call. See the 
restcall.pl-utility for more information.

This method requires access/authentication privileges on the AURORA REST-server in order to execute. Other than 
that it does the same as the curl-method. See above.

If everything is working ok these 2 methods should generate a response similar to this (this is from the restcall-script):

	getName: $VAR1 = {
	  'errstr' => '',
	  'name' => 'ROOT',
	  'delivered' => '1597235964.10694',
	  'err' => 0,
	  'received' => '1597235963.46528'
	};

Here the "name" of the root-node in the entity has been returned as "ROOT". Everything is working ok with the 
REST-server and the database it uses. If the curl-method was used, the response will be in JSON along these lines:

	{"received":1597236895.15618,"errstr":"","name":"ROOT","delivered":1597236896.43785,"err":0}

Possible issues with the eg. the database connection might generate the following response:

	getName: $VAR1 = {
	  'delivered' => '1597236123.76828',
	  'received' => '1597236123.5402',
	  'err' => 1,
	  'errstr' => 'REST-server is not connected to database. Unable to proceed.'
	};

whereby in this example the REST-server clearly indicates that it has issues contacting the database-server. The 
JSON version when using curl will be like this:

	{"err":1,"delivered":1597236870.77786,"received":1597236870.6613,"errstr":"REST-server is not connected to database. Unable to proceed."}

## Checking the AURORA Log-service

The AURORA Log-service ensures that any log-activity for the database is read from the local server sQLite-file and processed 
into it.

It is a very small and simple service that basically at short intervals checks for any updates to the SQLite-file and if so, 
pushes those entries into the log of the database.

For more information about the log-service, check the [overview documentation](../overview/logsrvc.md) for it.

### Check that the SQLite database file is present

In order for the log-service to function and the various parts of AURORA to be able to log any entries, the SQLite database file 
needs to have been created and be writable.

We recommend that the SQLite database file is writable as a specific AURORA-system user, the same one as the AURORA-system is 
running as.

Where the SQLite file is located depends upon the settings of the AURORA-configuration, which can be located in 
/etc/aurora.d/*. You are interested in the file path and name specified in "system.log.filename" (please see the installation 
documentation).

Ensure that the file in question exists and that it has the correct ownerships and attributes (readable and writable by the 
AURORA-system user).

### Check that the SQLite file is intact

If the SQLite log-file is present, you can attempt to go into it and ensure that it is not corrupted in any way.

You can do that by having the SQLite3 utility installed and then type the following on the prompt of the 
AURORA-server in question (assuming we are in the folder of the SQLite file):

	sqlite3 ./log.db

Then check that the SQLite log-database contains the necessary table by writing the following inside the SQLite 
prompt:

	.tables

Is should show you that you have the following table(s):

	log

You can look at the structure of tables by writing:

	.schema log

which shows you the schema definition of the log-table:

	CREATE TABLE log (idx INTEGER PRIMARY KEY AUTOINCREMENT,logtime UNSIGNED FLOAT,entity UNSIGNED BIGINT,loglevel UNSIGNED INT,logtag VARCHAR(64) NOT NULL DEFAULT 'NONE',logmess VARCHAR(1024));

### Check that the Log-service is up and running

It is rare that this service fails in any way, but the following will check if it is up and running. Type the following on 
the prompt of any (if several) of the AURORA-servers:

	ps auxw|grep -i logsrvc

you should then get an answer along these lines:

	sys-aurora     22088  0.0  0.7 193576 29080 pts/0    S    08:48   0:00 ./logsrvc/logsrvc.pl AURORA Log-Service Daemon

That confirms if it is running or not. 

### How to start it

Usually the installation of AURORA will ensure that you have some mechanism of ensuring that the Log-service is running. If no 
such mechanism exists, one can manually start the service by typing the following (relative to the AURORA dist-folder):

	./logsrvc/logsrvc.pl > /dev/null 2>&1 &

If you choose to, you can also let the STDOUT and STDERR be redirected to a file instead of /dev/null, eg. in /var/log. It can 
also be useful to drop the redirect completely if you are attempting failure diagnostics and want to see what the 
service says?

When the service has started it will pick up from where it left and continue to attempt to write log entries to the AURORA 
database.

## Checking the AURORA Maintenance-services

The AURORA-maintenance services are important that is running in order to clean up and handle datasets that are soon expiring or 
have expired and several other maintenance tasks (see the [overview](../overview/mainsrvc.md) documentation of the 
Maintenance-services for more information).

### Check that they are up and running

To check if the Maintenance-services are up and running type the following on the AURORA-server running it:

	ps auxw|grep -i "maint_"

It should show you a line along these lines:

	sys-aurora     22091  0.8  1.0 225768 42732 pts/0    S    08:48   2:41 ./mainsrvc/maint_gen.pl AURORA MAINT_GEN Daemon
	sys-aurora     22092  0.8  1.0 225769 42733 pts/0    S    08:48   2:41 ./mainsrvc/maint_perm.pl AURORA MAINT_PERM Daemon
	sys-aurora     22093  0.8  1.0 225770 42734 pts/0    S    08:48   2:41 ./mainsrvc/maint_meta.pl AURORA MAINT_META Daemon

This confirms if it is running or not.

### How to start them

If the Maintenance-services for whatever reason are not up and running, you can start them by typing the following (relative 
to the AURORA dist-folder):

	./mainsrvc/maint_gen.pl > /dev/null 2>&1 &
	./mainsrvc/maint_perm.pl > /dev/null 2>&1 &
	./mainsrvc/maint_meta.pl > /dev/null 2>&1 &

If you choose to, you can also let the STDOUT and STDERR be redirected to a file instead of /dev/null, eg. in /var/log. It can
also be useful to drop the redirect completely if you are attempting failure diagnostics and want to see what the
services say?

### How to stop them

Be aware that it is a symbiotic relationship between the Notification-service and the Maintenance-services in certain regards 
when it comes to handling and creating notifications. This is the case with the MAINT_GEN-service. It might therefore be a good idea to 
have both stopped before starting them again.

One also needs to be aware that the MAINT_GEN-service will cache updates to the AURORA database if it is unable to do 
them at the time in question (updating dataset about notifying about expirations, updating dataset about notifying about 
the fact that they have expired and so on and so forth). This cache is written to a YAML-file usually located in the 
AURORA_PATH-environment location (defaults to /local/app/aurora/) and is called "mainsrvc.cache". We strongly recommend 
that when needing to stop the Maintenance-service that one kills the process with a normal TERM-signal/KILL so that it can 
gracefully exit and write any remaining cache to file. This cache will again be loaded upon starting the MAINT_GEN-service 
and any remaining entries will be attempted written to the AURORA database.

### How to check their status

It is possible to get the maintenance-services to output their status by doing the following:

	kill -USR1 12345

where "12345" is the process id of the service. A status-message will then be written to syslog with INFO-loglevel and it will 
also be printed to STDOUT.

The status message contains what settings the service is running with.

### Enabling and disabling specific operations

The maintenance-services have the ability to dynamically and while running enabling and disabling the operations they 
perform. This is practical when debugging, having issues with the services or one just needs to stop one of the operations 
from running for a while without compromising more important aspects of the services.

This is done by changing the interval setting for a given maintenance-services operation to 0 in the settings file in question. 
After this has been done, one needs to force the service to reload its settings by running:

	kill -HUP 12345

where "12345" is the process id of the maintenance-service in question. Please confirm that the new settings has been loaded by 
checking the service status.

### Checking what it is doing with a dataset

All important updates or changes to a dataset is logged to the database by the Maintenance-services when it comes to 
expirations, removals and such.

You can check this change-log by going to the web-client and selecting "Manage Datasets" in the main menu. Then locate the 
dataset in question and select "Log" in the "View"-column.

You should then get a complete list of what has been done to the dataset since its creation and you can even open
up a more granular, indepth overview by selecting the loglevel "DEBUG". Any changes by the Maintenance-service will be 
prepended with the "MAINT_GEN", "MAINT_PERM" or "MAINT_META" in the message-part of the log entry.

Peruse and enjoy!

## Checking the AURORA Notification-service

The AURORA Notification-service is the service that parses and handles the notifications created by the various parts of 
the system.

It uses its own folder structure for storing what has been done to the notifications.

Please read the [overview documentation](../overview/notsrvc.md) of the Notification-service for more information about 
its design.

### Check that it is up and running

It is rare that this service fails in any way, but the following will check if it is up and running. Type the following on 
the prompt of any (if several) of the AURORA-servers:

	ps auxw|grep -i notsrvc

you should then get an answer along these lines:

	sys-aurora     22233  0.3  0.9  99460 39196 pts/0    S    08:49   1:23 ./notsrvc/notsrvc.pl AURORA Notification-Service Daemon

That confirms if it is running or not. 

### How to start it

Usually the installation of AURORA will ensure that you have some mechanism of ensuring that the Notification-service is running. If no 
such mechanism exists, one can manually start the service by typing the following (relative to the AURORA dist-folder):

	./notsrvc/notsrvc.pl > /dev/null 2>&1 &

If you choose to, you can also let the STDOUT and STDERR be redirected to a file instead of /dev/null, eg. in /var/log. It can 
also be useful to drop the redirect completely if you are attempting failure diagnostics and want to see what the 
service says?

### How to check event-history

One can check a Notifications event history by going into its folder and listing its contents:

	cd /local/app/aurora/notification/
	cd zmoaDf12o9ijSVQytQpnRVULsryFShhu

The "zmoaDf12o9ijSVQytQpnRVULsryFShhu" is the notifications task's ID. To now see what events have happened on this 
notification, list the contents of the folder that you changed into in the previous step:

	ls -la

You will then get a listing similar to this one:

	-rw-r--r-- 1 sys-aurora sys_aurora    518 Nov  7 22:13 zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783632.86401_message
	-rw-r--r-- 1 sys-aurora sys_aurora    156 Nov  7 22:13 zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783635.9145_notice
	-rw-r--r-- 1 sys-aurora sys_aurora    144 Nov  7 22:15 zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783756.68473_escalation
	-rw-r--r-- 1 sys-aurora sys_aurora    140 Nov  7 22:16 zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783761.76409_escalation
	-rw-r--r-- 1 sys-aurora sys_aurora    141 Nov  7 22:16 zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783766.85387_escalation
	-rw-r--r-- 1 sys-aurora sys_aurora    141 Nov  7 22:16 zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783771.95115_escalation
	-rw-r--r-- 1 sys-aurora sys_aurora    141 Nov  7 22:16 zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783777.04086_escalation
	-rw-r--r-- 1 sys-aurora sys_aurora    141 Nov  7 22:16 zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783782.12713_escalation
	-rw-r--r-- 1 sys-aurora sys_aurora    158 Nov  7 22:16 zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783787.37383_notice
	-rw-r--r-- 1 sys-aurora sys_aurora    187 Nov  7 22:18 zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783908.12797_escalation
	-rw-r--r-- 1 sys-aurora sys_aurora    185 Nov  7 22:18 zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783913.16264_fin

All the event-entries are listed in their correct order and you can also see what the specific events have done or their 
values by cat'ing the file in question, eg. the start-message itself:

	cat zmoaDf12o9ijSVQytQpnRVULsryFShhu_1604783632.86401_message

All files are in YAML-format and can be easily read and parsed.

## Checking the AURORA Store-service

The AURORA Store-service ensures that any distribution-operation are read, monitored and executed in a orderly and 
timely fashion.

Please see the [overview](../overview/storesrvc.md) documentation of the Store-service for more information on the 
service itself.

### Check that it is up and running

It is rare that this service fails in any way, but the following will check if it is up and running. Type the following on 
the prompt of any (if several) of the AURORA-servers:

	ps auxw|grep -i storesrvc

you should then get an answer along these lines:

	sys-aurora     22233  0.3  0.9  99460 39196 pts/0    S    08:49   1:23 ./storesrvc/storesrvc.pl AURORA Store-Service Daemon

That confirms if it is running or not. 

### How to start it

Usually the installation of AURORA will ensure that you have some mechanism of ensuring that the Store-service is running. If no 
such mechanism exists, one can manually start the service by typing the following (relative to the AURORA dist-folder):

	./storesrvc/storesrvc.pl > /dev/null 2>&1 &

If you choose to, you can also let the STDOUT and STDERR be redirected to a file instead of /dev/null, eg. in /var/log. It can 
also be useful to drop the redirect completely if you are attempting failure diagnostics and want to see what the 
service says?

### How to read the ERROR-log upon failure

When a Store-task fails for it will write an ERROR-file in its task-folder. This will contain a complete dump of all the 
transactions involved in the distribute-operation in question that was running when the task failed. The ERROR-file is 
in a normal ASCII-format with the first column being the unix datetime for the message event on the right side separated 
by a space.

You can look in the web-client in the log for the dataset in question to find the distribution task id that failed.

The error file for the given distribution task can be read by going to the Store-service's folder (we will assume it 
is in /local/app/aurora/distributions/):

	cd /local/app/aurora/distributions
	cd 3,1234,AOoPibAic5Ec700THEkv2pawu1gowhJz

The second "cd" changes folder into the folder of the distribution task in question. The last part of the folder name is the 
task id itself (AOoPibAic5Ec700THEkv2pawu1gowhJz). You will find the same task id mentioned in the dataset logs.

In order to read the ERROR-log, do something along the lines of:

	less ERROR

Parse the log and try to acertain the reason for the failure and take steps to remedy it.

### How to read the distribute-operations

What distribute operations and their parameters are executed on a dataset in a distribution task is defined in a YAML file in 
the distribution tasks folder called "DATA".

This file can be read by doing the following (we assume the AURORA-folder is set to /local/app/aurora):

	cd /local/app/aurora/notification
	cd 3,1234,AOoPibAic5Ec700THEkv2pawu1gowhJz

The second "cd" changes folder into the folder of the distribution task in question. The last part of the folder name is the 
task id itself (AOoPibAic5Ec700THEkv2pawu1gowhJz).

Now write the following to read the distribution operations:

	less DATA

### How to rerun a task

In order to rerun a distribution task that has failed for the last time, you have to go into its folder and 
then adjust one of the file tags. You should only do this if the distribution-task has failed for the last time 
and it is moved to the FAILED-folder permanently (retries have been exhausted). It would also be a good idea to 
alleviate or remedy whatever made it fail completely in the first place before attempting to rerun it.

To do this, do the following (assuming the AURORA-folder is in /local/app/aurora):

	cd /local/app/aurora/distributions
	cd 3,1234,AOoPibAic5Ec700THEkv2pawu1gowhJz

The second "cd" changes folder into the folder of the distribution task in question. The last part of the folder name is the 
task id itself (in this case - AOoPibAic5Ec700THEkv2pawu1gowhJz).

Now you change the retry-tag file to a lower value than it currently have. You can choose to decrease it one value from what it is already or just reset it altogether (set the value to 0). In order to reset it, do the following:

	mv retry_2 retry_0

This is an atomic event and as soon as the Store-service notices the change it will take up the distribution task and attempt 
to run it again.

If you only want to have the Store-service attempt to rerun it once, you would decrease the above value from 2 to 1:

	mv retry_2 retry_1

## Checking the FileInterface

### Check FileInterface mounts on manager and/or client

- Check that [/Aurora](install.md#fileinterface-configuration) is a directory
- Check that all the mounts is online
    Use "df" to check that they are mounted

        df /Aurora/*

- Check for correct mount mode
    Inspect mount parameters

        mount | grep /Aurora

- Check the exports on the storage servers

### Using the fileinterface/test.pl utillity

The test.pl utillity let you test methods on the fileinterface. It read one line at a time, parses it as "method param param ...". It then call the method with parameters both directly and trough the trough the wrapper service. Both results is presented as a hash in perl notation. The 'f' key is from the direct call, the 'c' is from the wrapper. Teminate with ctrl-d.

To check that the escalation is working, "sudo -i" to the account that is running restsrvc.pl, and run the debug method trough the fileinterface/test.pl. This should look like this:

    sys-aurora@aurora01:/$ cd /local/app/aurora/dist/fileinterface/
    sys-aurora@aurora01:/local/app/aurora/dist/fileinterface$ ./test.pl
    debug
    $VAR1 = {
          'f' => {
                   'out' => 'FileInterface=HASH(0x5639b57c41e0)->debug()$VAR1 = bless( {
                       \'cache\' => {},
                       \'yell\' => [],
                       \'FI\' => $VAR1,
                       \'adb\' => undef,
                       \'config\' => {
                               \'base\' => \'/Aurora\',
                               \'cookie_life\' => 600,
                               \'http\' => \'$HTTPROOT/view\',
                               \'cache_ttl\' => 10
                             }
               }, \'FileInterface\' );
    ',
                   'yell' => [],
                   'err' => ''
                 },
          'c' => {
                   'out' => 'FileInterfaceClient=HASH(0x5639b57e4c78)->debug()$VAR1 = bless(     {
                 \'FI\' => bless( {
                                  \'cache\' => {},
                                  \'yell\' => [],
                                  \'FI\' => $VAR1->{\'FI\'},
                                  \'config\' => {
                                                \'http\' => \'$HTTPROOT/view\',
                                                \'cookie_life\' => 600,
                                                \'cache_ttl\' => 10,
                                                \'base\' => \'/Aurora\'
                                              },
                                  \'adb\' => undef
                                }, \'FileInterface\' ),
                 \'connect\' => [
                                \'sudo\'
                              ]
               }, \'FileInterfaceClient\' );
    ',
                   'yell' => [],
                   'err' => ''
                 }
        };

For each of the two sections you have

- out - The output of method
- yell - Errors generated by the method
- err - Errors when calling the method

Except for the debug method, the output should be identical. The yell and err messages may differ. 

If the 'c' section is failing when the 'f' is not, there is probably something wrong with the escalation. See [Test escalation](#test-escalation) to test the default sudo escalation.


### Check a dataset integrity

Run the "problem" method on the dataset (97) with the [test.pl utillity](#using-the-fileinterfacetestpl-utillity) as root like this:

    aurora01:/local/app/aurora/dist/fileinterface# ./test.pl 
    problem 97
    $VAR1 = {
          'c' => {
                   'out' => 0,
                   'yell' => [],
                   'err' => ''
                 },
          'f' => {
                   'out' => 0,
                   'yell' => [],
                   'err' => ''
                 }
        };

Here the out is 0, witch is "OK". If integrity problems is found it is reported with a severity level and a error message.


### Test the wrapper service

You may run the wrapper service manually as root. The input protocol is the same as the [test.pl utillity](#using-the-fileinterfacetest.pl-utillity) utillity, but output is in yaml format without the "err" key.

    aurora01:~# /local/app/aurora/dist/fileinterface/AuroraFileInterface 
    problem 97
    ---
    result: 0
    yell: []
    ...

### Test escalation

Test the problem method on an existsing dataset with the [wrapper service](#test-the-wrapper-service) from the Aurora nonpriveleged account(sys-aurora) both with and without sudo.

    aurora01:~# su - sys-aurora
    sys-aurora@aurora01:/$ sudo /local/app/aurora/dist/fileinterface/AuroraFileInterface
    problem 97
    ---
    result: 0
    yell: []
    ...

    sys-aurora@aurora01:/$ /local/app/aurora/dist/fileinterface/AuroraFileInterface
    problem 97
    ---
    result: 'Dataset 97 opendir(/Aurora/fi-1001/rw/000/000/97): Permission denied'
    yell: []
    ...
    
Here the sudo works fine, without sudo the problem method reports permission problems.
