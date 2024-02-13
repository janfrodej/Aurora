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
# Store-service overview

The Store-service is an AURORA-service to handle the acquiring and distribution of data between 
computers and servers. It can handle any combination of acquire-, distribution- and deletion operations 
specified in job tasks.

It uses Store-classes when executing the acquire- and distribute operations and this enables 
plug-in support for multiple transfer standards/protocols. The Store-service therefore supports, 
among other things, the standards RSync/SSH, FTP, SFTP, SCP, SMB/CIFS and so on and so forth.

The tasks to the Store-service are stored as files in a separate distributions-folder (default location 
is /local/app/aurora/distributions). The tasks are typically created by the AURORA REST-server in 
order to accomodate operations related to the creation of datasets or to perform distribution tasks 
that the system or the user wishes to effect. Each task has its own folder and a symlink to that 
folder is moved between various phase-folders dependent upon status (INITIALIZED,ACQUIRING,DISTRIBUTING,
DELETING and FAILED).

The Store-service also handles retries, creating notifications when needed (handled by the notification-
service as per usual). In the event of retries when a distribution task stops responding, it will also 
handle the harvesting and cleaning up of old processes. A running and functioning task will at all times 
update an alive-tag in the task-folder that specified the last time the sub-process did anything. This 
forms the basis of timeout handling and retries because of this.

Some definitions:

  - Acquire - the operation of fetching data from a location.
  - Delete - the operation of deleting data fomr a remote location.
  - Distribute - the operation of putting data to a location.
  - Distribution(s) - a term also used to signify both acquire- and distribute operations. Distinguished from distribute-operations by context of the sentence.
  - Get - synonym for acquire or fetch.
  - Operation - some action that are performed either remotely or locally in the AURORA storage-area.
  - Put - synonym for distribute.
  - Task - a job or collection of acquire- and/or distribute operations to execute.

## Folder Structure

Each task in the Store-service has its own folder. The name of the folder is in the following format:

	USERID,DATASETID,TASKID

USERID is the AURORA database user id of the user that had the task created (by the AURORA-system 
nonetheless). DATASETID is the AURORA database id of the dataset that the task is operating on. TASKID 
is a random number of 32 characters (a-zA-Z0-9) that uniquly identifies the distribution task/job.

In addition to these task-folders it exists these folders for the various phases that the task may be 
in:

- INITIALIZED - the task is initialized and ready to execute.
- ACQUIRING - the task is performing acquire-operation(s).
- DISTRIBUTING - the task is performing distribute-operation(s).
- DELETING - the task is performing delete-operation(s).
- FAILED - the task has failed permanently after exhausting its retries. Manual intervention needed.

Inside these folders there will be a symlink that points to the tasks folder, but that symlink will only 
exist inside one of these folders at a time (atomic move being used).

This is an example of the distributions-folder might look like:

	drwxr-xr-x  2 sys-aurora sys_aurora 4096 Aug 10 11:54 3,1784,OV6rcGqXIytPF6TQTjN0c2Z9SO95YijX
	drwxr-xr-x  2 sys-aurora sys_aurora 4096 Aug 10 11:54 3,1785,I3j7tsZDl3D8QVmHzHTc4sNIqixjQSNJ
	drwxr-xr-x  2 sys-aurora sys_aurora 4096 Aug 10 11:54 ACQUIRING
	drwxr-xr-x  2 sys-aurora sys_aurora 4096 Feb 24 15:40 DELETING
	drwxr-xr-x  2 sys-aurora sys_aurora 4096 Feb 24 15:43 DISTRIBUTING
	drwxr-xr-x  2 sys-aurora sys_aurora 4096 Aug 10 11:54 FAILED
	drwxr-xr-x  2 sys-aurora sys_aurora 4096 Aug 10 09:44 INITIALIZED

And inside eg. the FAILED-folder might look like this:

	lrwxrwxrwx  1 sys-aurora sys_aurora   71 Aug 10 09:39 3,1784,OV6rcGqXIytPF6TQTjN0c2Z9SO95YijX -> /local/app/aurora/distributions/3,1784,OV6rcGqXIytPF6TQTjN0c2Z9SO95YijX
	lrwxrwxrwx  1 sys-aurora sys_aurora   71 Aug 10 09:44 3,1785,I3j7tsZDl3D8QVmHzHTc4sNIqixjQSNJ -> /local/app/aurora/distributions/3,1785,I3j7tsZDl3D8QVmHzHTc4sNIqixjQSNJ

As one can see the name of the symlink is the same as the name of the folder of the task.

Inside a task folder one would have the following files:

- alive_UNIXTIME.MS - continuly written to by the operation being executed. This is how the Store-service know if a operation has timed out or not.
- ctime_STARTTIME - the process start time of the operation being executed. Matches what the operating system reports of the process start-time.
- DATA - Contains all the operations and its parameters that are to be executed. Written in YAML-format that is easily readable and changable in the case of manual intervention being needed.
- ERROR - Contains the complete Store-process log of the last Store-class used when the fault occured. Handy for fault-finding missions.
- phase_PHASENAME - the current phase that the task is in (eg. INITIALIZED, ACQUIRING etc.).
- pid_NO - NO is the process id (pid) of the process executing operations.
- retry_NO - NO is the retry count of the task. As a default a task will not retry more than 2 times. Retries might happen due to failures or due to timeouts.
- status_STATUS - STATUS is the current status name (eg. ACQUIRING, DISTRIBUTING, FAILED etc.).
- todo_OP1,OP2..OPn - the operations to perform and their order, either acquiring or distributing. Each operation is comma-separated and one can specify as many as one wants to (but typically just acquire,distribute).

Not all of these files will exist when a task is created (such as alive, ctime and so on). They will be 
created as soon as sub-process handling the task has been created and are running.

All the files that start with a name and then an underscore and some other info, such as alive_UNIXTIME.ms are 
called tag-files, where the name is the name of the tag and the value after the underscore is the tags 
value. This scheme has the advantage that task information can be written atomically by renaming the 
file (creation is not atomic).

A task folder might typically look like this:

	-rw-r--r--  1 sys-aurora sys_aurora    0 Aug 10 09:44 alive_1597053281.03391
	-rw-r--r--  1 sys-aurora sys_aurora    0 Aug 10 09:44 ctime_1597045460
	-rw-r--r--  1 sys-aurora sys_aurora  521 Aug 10 09:44 DATA
	-rw-r--r--  1 sys-aurora sys_aurora 1254 Aug 10 09:44 ERROR
	-rw-r--r--  1 sys-aurora sys_aurora    0 Aug 10 09:44 phase_FAILED
	-rw-r--r--  1 sys-aurora sys_aurora    0 Aug 10 09:44 pid_3322
	-rw-r--r--  1 sys-aurora sys_aurora    0 Aug 10 09:44 retry_2
	-rw-r--r--  1 sys-aurora sys_aurora    0 Aug 10 09:44 status_FAILED
	-rw-r--r--  1 sys-aurora sys_aurora    0 Aug 10 09:44 todo_ACQUIRING

## DATA-file 

The data file is written in YAML-format can therefore easily be read or edited by a sysop (in cases where 
manual intervention is needed).

This is an example of a DATA-file from a distribution task:

	---
	get:
	  '1':
	    classparam:
	      authmode: '4'
	    computer: 1204
	    name: RSyncSSH fetch data from computer
	    param:
	      domain: WIN-NTNU-NO
	      host: 10.150.2.7
	      knownhosts: 10.150.2.7 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOZCGZKwmOKA8l03rz48fMyywXdxNixGEUnJmt6d6nSGRyHGImmnBbsEAjOuhGDb+G2KCgt5htYYysIQhP+3uJU=
	      port: '22'
	      privatekeyfile: /creds/DAD/id_rsa
	      remote: /cygdrive/d/Data/
	      share: ntnu
	      username: Administrator
	    store: '1370'

The structure starts with what operation the sub-structure relates to. In this case it is a get-
operation (acquire). Below that every operation is numbered and in the example over there is 
only 1 operation. Theoretically one could have several get-operations here, although it is hard 
to imagine the need to fetch data several times or from various places for one dataset. This might 
be more of interest in the case of put-operations (distribute).

Below the numbered operation we basically have 4 keys: 

- classparam (parameters to the Store-class being used that alters its behaviour).
- computer (AURORA database id of the computer that the operation relates to).
- name (textual name of the operation - just accessories/decoration for the operation)
- param (parameters to the opening of the Store-class being used. It also defines the remote-parameter).
- store (AURORA database id of the store to use - it basically defines which Perl Store-class to use).

The classparam in the example above just defines "authmode". This defines how the operation is to authenticate 
in order to execute its operation(s). This authmode class-parameter are defined in the Store-class placeholder 
and exists in several Store-classes and have the following meaning:

1. Authenticate with password.
2. Authenticate with password file.
3. Authenticate with a key
4. Auhenticate with a key-file.

In the example one has chosen to use "authmode" number 4, which means to authenticate using a key-file. 
The location of this file is specified in the "param" sub-key and is called "privatekeyfile". How the 
various Store sub-classes chooses to handle the authmode-parameter in practice is up to that sub-class, 
but it is expected that it can handle those 4 modes if supported by the utility or command being run (eg. 
FTP does not support using key- or key-file).

In any event, in order to use a Store-class, one needs to know which paramerers it expect to be there 
to work (and one can also inquire the Store-class to know). All of this is handled in the AURORA 
entity tree by specifying StoreCollections that define what operations to run (acquire/distribute) and 
the parameters to the Store-class being used.

## ERROR-file

The ERROR-file is written to the task-folder in the event of a fatal error in the processing of the task.

The error-file will contain a complete dump of the Store-process log that it was operating on when 
the failure occured. This will make it possible to further investigate and find out what made the 
Store-service task fail.

## Process-tree

When an operation is running on a task, it will start by forking out a sub-process to handle it. This 
sub-process will parse the YAML-data from the DATA-file and execute the Store-classes in the order 
specified there.

The Store-class will also be forking out sub-processes to handle its operation (a bit dependent 
upon which Store-class we are talking about) and it will basically consist of a sub-process or fork for 
the command being run (if the Store-class is a wrapper around a command-line utility). Another fork 
will then sit and read STDOUT of this command and pipe it on to the Store-class being run as part of 
the main operation.

Typically the process tree for a single operation will look like this:

	Store-service (storesrvc.pl)
	   Fork to handle task-operation (main process for the task)
              Fork to run command that executes operation (separate process (thread or fork)).
              Fork to handle collecting pipe-data from the command-process.

The main-process of the task will run a loop while waiting on the Store-process to do its job. It 
will read the last alive-timestamp from the Store-process and update the alive-tag in the Store-service 
task folder so that the Store-service itself can know if it has heard any lifesigns from the task-
operation.

All errors and the main events from the task-operation is logged to the AURORA database through the 
Log-service.

