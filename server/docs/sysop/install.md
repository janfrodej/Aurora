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
# AURORA Installation

This document shows how to install AURORA to your system and 
various aspects to consider when doing so.

It is meant for system operators with a good knowledge of the Linux 
operating system and other services, so the documentation will not 
be in-depth, step-by-step instructions for the most part.

## Requirements

The AURORA-system as a whole has the following requirements:

- Linux-server to run the AURORA REST-server and belonging services (notification, log, store and maintenance-services, file interface).
- Apache-server to run the AURORA web-client from (version 2.4 or higher)
- MySQL-server for the database (version 7 or higher)
- Perl (version 5.22 or higher)
- Perl-libraries (see separate section for a complete list)
- Pandoc for viewing AURORAs markdown-documentation (version 1.16 or higher)
- Various utilities (lftp ftp-utility, ssh and sshpass, sftp, rsync, scp, smbclient)
- SQLite 3 og higher
- pod2html utility

The versions listed are the version base that has been tested and found working. It may be that older 
versions will work, such as with MySQL, Apache or Perl. AURORA was developed and tested on Ubuntu all the 
way from version 16.04 LTS, but we recommend using Ubuntu 22.04 LTS both the AURORA-server (which also runs the REST-server).

I should also be noted that AURORA is made to be database neutral and that any database 
that is ANSI SQL-compliant should work. We have taken efforts to use as basic SQL as possible in most 
places. This said, MySQL is what has been used and found to be working. Using another database 
engine in also subject to it existing a DBI-driver in Perl for that engine.

## Setting up the AURORA-database

One of the first tasks that should be done is setting up the AURORA-database. It is used by almost all parts of 
the AURORA-system in one way or the other.

The AURORA-system was developed using a MySQL-database and we will only provide instructions for getting 
this in place. That said, the AuroraDB-library that does all the handling of database operations was written 
with general SQL, so it should be possible to replace MySQL with any other SQL-compliant database of choice 
provided that a DBI-driver exists for Perl.

We have provided the MySQL database-template for creating the database as part of the AURORA distribution. It 
can be found in "database/aurora.sql". It is a MySQL-dump of the structure of the database and the basic, necessary 
data put in place.

It can be imported into your MySQL-server after having created the database with necessary permissions by using 
the mysql-command utility thus:

	mysql -u root -p -h my.mysql.host MYAURORADB < aurora.sql

or in a similar vein. We assume that the sysop is familiar enough with the MySQL-server solution that we will not 
provide anymore detailed information on this.

## Installing Linux-server

On the Linux-server that is going to run the AURORA-systems services one should install a 
Linux flavour of choice.

After this has been done, one needs to install the following (if it not already part of 
that installation):

- Perl with core libraries
- Perl libraries
    - Bytes::Random::Secure
    - charnames
    - Data::Dumper
    - DBD::mysql
    - DBD::SQLite
    - DBD::SQLite::Constants
    - DBI
    - Digest::MD5
    - Digest::SHA
    - Email::MIME
    - Email::Sender::Simple
    - Email::Sender::Transport::Sendmail
    - Encode
    - File::Basename
    - File::Copy
    - File::Find
    - File::Path
    - FileHandle
    - HTTP::Daemon
    - HTTP::Daemon::SSL
    - HTTP::Message
    - HTTP::Status
    - IO::Socket::SSL
    - IPC::Open2
    - IPC::Open3
    - JSON
    - JSON::XS
    - Mail::Sendmail
    - MIME::Base64
    - Net::DNS
    - Net::FTP
    - Net::LDAP
    - Net::HTTP
    - Net::HTTPS
    - Net::SMTP
    - POSIX
    - threads
    - Symbol
    - Sys::Hostname
    - Term::ReadKey
    - Time::HiRes
    - Unicode::Escape
    - Unicode::String
    - UUID
    - YAML::Tiny
    - YAML::XS
- lftp utility (version 4.8.1. or higher)
- ssh
- sshpass
- sftp
- scp
- rsync
- smbclient (version 4.3.11 or higher)
- SQLite 3
- xxhash

After these things have been installed it is time to install the AURORA-system itself.

## Installing the AURORA-system

### Folder locations

Before starting to install it is advantagous to make some considerations as to where to 
put the various files that makes up the AURORA-system.

There are some defaults that are defined accordingly:

- AURORA library folder - /usr/local/lib/aurora
- AURORA systems folder - /local/app/aurora
- AURORA config folder - /etc/aurora.d

These defaults can be changed in various ways. The exception is the AURORA library folder,
which is always expected to be found in /usr/local/lib/aurora, however we recommend 
solving this by making a symlink to the lib-folder of the AURORA version you are running, eg.:

	ln -s /usr/local/lib/aurora /local/app/aurora/dist/lib

As goes the the systems and config-folder, they can be changed with the following 
environment variables:

- AURORA_PATH (AURORA systems folder)
- AURORA_CONFIG (AURORA config folder)

in addition to these folders, AURORA has the following locations that should be considered 
and their defaults:

- /local/app/aurora/log.db (AURORA local log-database). Can be modified by config - "system.log.filename"
- /local/app/aurora/notification (AURORA notification queue). Can be modified by config - "system.notification.location"
- /local/app/aurora/distributions (AURORA distribution queue). Can be modified by config - "system.dist.location"

Please note that these locations are not affected by the environment variables if set in the config-files. If 
not specified in the config-files, it will use the AURORA_PATH as the base for the folder locations and add 
"log.db", "notification" and "distributions".

When it comes to the the /etc/aurora.d (or $AURORA_CONFIG) folder, it can contain several config-files. All the files 
in this folder are processed alphanumerically (case sensitive) and they have to be YAML-files (ending in .yaml). The last file 
processed  takes precedence over individual settings in another. So if you defined "system.dist.location" in the file A.yaml 
and B.yaml, the setting in the B.yaml will take precedence.

The processing order of the config-files are:

1. /usr/local/lib/aurora/config.yaml (AURORA distribution defaults)
2. /etc/aurora.d (or $AURORA_CONFIG if set).

The AURORA-system will not complain if it doesn't find any config-files, but obviously the services will have issues with not 
having the configuration settings they need.

All of this said, we recommend the following locations:

- /local/app/aurora (AURORA systems folder, its default)
- /local/app/aurora/dist (AURORA systems git repo dist)
- /usr/local/lib/aurora -> /local/app/aurora/dist/lib (AURORA lib-folder)
- /etc/aurora.d (AURORA config folder, its default)
- /local/app/aurora/log.db (AURORA local log database). This location should always be locally on server, not on nfs or similar.
- /local/app/aurora/distributions (AURORA distribution queue)
- /local/app/aurora/notification (AURORA notification queue)

### Syncing with the GIT-repo

The AURORA-system is distributed as a git-repository located at:

	ssh://git@git.it.ntnu.no:7999/fagit/aurora.git

The latest version in the master-branch (or any other branch of choice), should 
be sync'ed into the AURORA-system folder under "dist" (eg. /local/app/aurora/dist).

Alternately one can choose to keep all version as one upgrades by first syncing them into 
another folder, such as "release/AURORA_VERSION" and then symlink to dist from there:

	ln -s release/AURORA_VERSION -> dist

### Creating SSL certs

The AURORA REST-server needs to have a set of SSL-certs for it to encrypt the traffic 
that is has with clients.

These certs should be generated according to your organizations routines on this and preferrably 
signed with a certificate authority so that the clients do not get any issues validating it. We 
highly recommend buying signed certificates with a proper CA (DigiCert, Thawte, GeoTrust etc.).

Please also remember that the certs needs to be made in the domain name of the REST-server, eg. 
rest.aurora.it.ntnu.no (if that is used to connect to it).

The SSL certs can be placed whereever the admin wants to, but remember to update the configuration 
file settings for their location. The certs also needs to be readable by the user and/or group that 
the AURORA REST-server runs as.

It should also be remarked that the AURORA REST-server is not fond of SSL certificates where the 
public key/crt has the whole certificate-chain included. In order for the SSL libraries to work it 
requires that only the public signed or unsigned key is included. If this is not done, the connecting 
client will get SSL handshake errors.

Here are an example of generating SSL-certificates and the certificate signing request (to be sent to the CA):

	openssl req -new -newkey rsa:2048 -nodes -out rest_aurora_it_ntnu_no.csr -keyout rest_aurora_it_ntnu_no.key -subj "/C=NO/ST=Sør-Trøndelag/L=Trondheim/O=NTNU/OU=NTNU-IT/CN=rest.aurora.it.ntnu.no"

If you want to manually enter the information about the certificate, you can skip adding the "-subj" option:

	openssl req -new -newkey rsa:2048 -nodes -out rest_aurora_it_ntnu_no.csr -keyout rest_aurora_it_ntnu_no.key

### Putting in place the AURORA-system folder

Now, the default path for the AURORA-system is:

	/local/app/aurora

We therefore recommend that one pulls the AURORA-branch version that one wants down to a sub-
folder of this called "dist":

	/local/app/aurora/dist

Please note that if one wants to put the AURORA-system folder somewhere else, one needs to 
change the following environment-variable(s) system-wide (eg. through /etc/profile) - see the 
section on "Folder locations".

### Copying the log.db-file in place

A empty log.db-file is located in the distribution under logsrvc/log.db. Copy this file to the location where you 
intend to have it. We suggest either the AURORA-system folder (default /local/app/aurora).

You can copy the empty log.db file in place by doing the following (assuming the AURORA release is located in 
/local/app/aurora/dist):

	cp /local/app/aurora/dist/logsrvc/log.db /local/app/aurora/

Either this or copy it to the place you intend to have it and configure the logsrvc-settings in the 
settings-file accordingly (see the chapter on [Configuring the log-database](#file-interface)).

### Making user and group accounts

It is recommended to run the AURORA-system as a local user- and group accounts to avoid them running in 
the root-context.

We therefore recommend creating a user and a group account:

- sys-aurora (user)
- sys_aurora (group)

This documentation will from here on assume that these two accounts have been created for the purpose of 
the AURORA-system.

### Starting the AURORA-services

The next step is then to start the various services that makes up the AURORA-system with the REST-server 
as the main contact point:

- /local/app/aurora/dist/restsrvc/restsrvc.pl (REST-server)
- /local/app/aurora/dist/logsrvc/logsrvc.pl (Log-service)
- /local/app/aurora/dist/notsrvc/notsrvc.pl (Notification-service)
- /local/app/aurora/dist/storesrvc/storesrvc.pl (Store-/Distribution-service)
- /local/app/aurora/dist/mainsrvc/maint_gen.pl (General maintenance-service)
- /local/app/aurora/dist/mainsrvc/maint_perm.pl (Permission related maintenance-service)
- /local/app/aurora/dist/mainsrvc/maint_meta.pl (Metadata related maintenance-service)

It should not matter in which order you start these services in, since they are self-contained and the 
signalling between them is also handled in such a way that it should not create any issues. This said, you 
must obviously expect reduced service in the AURORA-system if not all components have been started.

It is recommended to redirect the STDOUT and STDERR to a separate file for each service in eg. /var/log/ 
(the redirection should append to log-file). Please note that most logging that these services do will 
happen through syslog, so the redirection to /var/log is only to capture critical errors that makes one 
of the services crash.

In addition to starting the service-parts, one also needs to put in place the file interface.

In order for the file interface to run with the necessary root permissions and the AURORA-system running as 
a specific, local user and group, one must add a file in the /etc/sudoers.d-folder with content along this 
line:

	sys-aurora ALL=(ALL) NOPASSWD: /local/app/aurora/dist/fileinterface/AuroraFileInterface

## Configuring the AURORA-system

The configuration file(s) for the AURORA-system is/are located in mainly two places (see the section on 
folder locations above):

1. /usr/local/lib/aurora/config.yaml
2. /etc/aurora.d (or $AURORA_CONFIG).

The configuration file(s) is/are processed in the order above. The "/etc/aurora.d"-folder can contain several 
YAML-configuration files and they are processed alphanumerically (case sensitive) and 
the last file's individual settings gets precedence. So if eg. "system.dist.location" is defined in both A.yaml 
and B.yaml, the setting for it in B.yaml takes precedence. Only files that end in ".yaml" will be processed.

Here is an explanation of the various settings:

### Configuring the REST-server

This configures on which interface the AURORA REST-server on the REST-server can be 
contacted/used. It also sets its number of listen instances, port and SSL key for 
encryption (compulsory).

	system.rest.host            : "localhost"
	system.rest.port            : 9393
	system.rest.listen          : 10
	system.rest.timeout         : 3600
	system.rest.privatekey      : "/local/app/aurora/certs/aurora.it.ntnu.no-2019.key"
	system.rest.publickey       : "/local/app/aurora/certs/aurora.it.ntnu.no-2019.crt"
	system.rest.enableipv6      : 1

The "system.rest.enableipv6" sets if the server is to bind to both ipv4 and ipv6. The default is 1 (yes). If only ipv4 
is available this setting needs to be changed to 0.

### Configuring the database

	system.database.host       : "mysql.wherever.no"
	system.database.datasource : "DBI:mysql(mysql_auto_reconnect=>1):database=aurora;host=mysql.wherever.no"
	system.database.user       : "MYSQL_USERNAME"
	system.database.pw         : "MYSQL_PASSWORD"

### Configuring the File Interface

These are the settings related to the file interface:

	system.fileinterface.user   : "USER"
	system.fileinterface.pw     : "PASSWORD"

USER is the username and PASSWORD is the password for the user that is allowed sudo (in order to elevate 
ones rights to root when running the fileinterface).

### Configuring limbo for zombies

When USER-entities are deleted they are converted to USER-entities with Zombie-names and data as part of 
the GDPR-process. It is possible to also specify that when a USER-entity is deleted, it is to be moved to 
a limbo folder where all deleted users can reside for all posterity.

This settings is:

	system.user.retiregroup     : 333

And when it is set, sets the group entity ID to which the deleted user is to be moved.

### Configuring Authentication methods

This setting configures which authentication methods are accepted by the REST-server (and 
refers to available Authenticator sub-classes):

	system.auth.methods : [ "AuroraID","OAuthAccessToken","Crumbs" ]

This setting can therefore be used to enable or disable authentication methods for the 
AURORA REST-server.

### Configuring the groupinfo-settings

Groupinfo is a set of classes that can be used by Authenticator-classes to check which group 
memberships a user has upon validation. This information can then be written to the AURORA 
database.

Settings are:

	system.auth.groupinfo.classes             : [ "NTNU" ]
	system.auth.groupinfo.interval            : 600

"classes" sets the groupinfo classes that are available/enabled to be used. "interval" sets 
the interval for how often (in seconds) the Authenticator-class using the groupinfo-module 
should update the groupinfo in the AURORA database memberships. This is to avoid having to 
do this everytime a REST-method is called. The default is every 10 minutes (600 seconds).

### Configuring the log-success setting

This setting tells the AURORA-system which Authentiator modules are allowed to log a successful authentication to 
the AURORA system-log.

	system.auth.log.success                   : [ "AuroraID", "OAuthAccessToken" ]

This setting does not need to be changed. Do not change it unless you know what you are doing.

### Configuring the Authenticator-settings

The Authenticator-classes have a set of settings that are global to all of them such as proxy-hosts and proxy-modules, 

	system.auth.proxy.hosts                   : [ "webhotell03.it.ntnu.no", "webhotell04.it.ntnu.no", "webhotell05.it.ntnu.no", "w>
	system.auth.proxy.modules                 : [ "OAuthAccessToken" ]

The "system.auth.proxy.hosts" setting is to set which hosts are allowed to send a real ip with their requests. This settings can 
be used to allow authenticator processes that are not completely run from a client's computer to send the real ip behind authentication requests. 

The "system.auth.proxy.modules" set which Authenticator-classes are allowed to use the proxy hosts function. As of now, only the 
OAuthAccessToken-class is able to do that. 

Please leave the "...proxy.modules" settings alone if you do not really know what you are doing. The main settings that can 
be changed is the "...proxy.hosts" setting.

### Configuring the OAuthAccessToken authentication method

One of the Authenticator sub-classes, OAuthAccessToken, supporting the OAuth protocol 
has a set of settings that needs to be specified if the method is to be used for 
authentication:

	system.auth.oauthaccesstoken.audience     : "9c27ff7d-2f39-4343-8e6d-b5ab54372a5e"
	system.auth.oauthaccesstoken.host         : "auth.dataporten.no:443"
	system.auth.oauthaccesstoken.endpoint     : "/userinfo"
	system.auth.oauthaccesstoken.emailfield   : [ "user","email" ]
	system.auth.oauthaccesstoken.namefield    : [ "user","name" ]
	system.auth.oauthaccesstoken.userfield    : [ "user","userid_sec" ]
	system.auth.oauthaccesstoken.createuser   : 1
	system.auth.oauthaccesstoken.createsorted : 1
	system.auth.oauthaccesstoken.userparent   : 17
	system.auth.oauthaccesstoken.usergroup    : 84

Audience sets the audience used with the OAuth-service and needs to match the answer from the 
OAuth-server. "host" is the host to check the users credentials with by using the access 
token delivered to the REST-server (typically from the AURORA web-client). The emailfield, 
namefield and userfield sets where in the return HASH-structure from the host, one finds the 
users email, full name and username.

"createuser" sets if the user is to be created if he does not exist already in AURORA (1 
for TRUE, 0 for FALSE). "createsorted" enables or disables if the users are to be sorted in 
sub-groups upon creation (A-Z groups). "userparent" sets the parent for the created user account, while 
"usergroup" sets the group that the newly created user is to be a member of. Both of 
these refers to entity ids from the database on the entity tree.

### Configuring the Crumbs authentication method

Crumbs supports authenticating using UUIDs. Crumbs is a special authentication method native to 
AURORA since AURORA supports swapping in an auth set of any other type in exchange for an UUID via 
the Crumbs-method. This is to facilitate client-side reactive web-clients that needs to store 
credentials locally and which therefore becomes available to every javascript piece running there. 
Swapping in a set of credentials for an UUID helps protect the original set of credentials.

Settings needed are:

	system.auth.crumbs.timeout  : 14400
	system.auth.crumbs.lifespan : 43200
	system.auth.crumbs.salt     : "SALT"

"timeout" is the validity length (in seconds) of the crumbs UUID before it times out and one needs 
to login again. A Crumbs UUID can have its validity extended by using it to run REST-server methods 
and for each time the timestamp of the UUID will be updated, thus ensuring that it does not 
time out. "Lifespan" sets the maximum validity length of an UUID, regardless of the updates of the 
timestamp of the UUID by using it. "Lifespan" therefore sets a hard limit on how long it can exist, before 
the user actually has to login again.

The "salt" is the salt used to crypt the UUID in the metadata of the AURORA user of which it is associated. 
A new, random salt can be generated by running the command line utility "mksalt.pl" located in the 
utility-folder.

The salt is the same for all users and UUIDs to ensure that one can make general SQL searches to find 
an UUID of a user. The crypting of the UUID is done to avoid the possibility of being able to read 
the UUID out of the database raw.

### Configuring the log-database

The AURORA-system logs its event first to a database-file locally to avoid any potential 
connection issues. The Log-service then pull this database and puts the events into the 
main database.

The local database is configured by the following settings:

	system.log.filename                       : "/local/app/aurora/log.db"
	system.log.location                       : "DBI:SQLite:dbname=/local/app/aurora/log.db"
	system.log.tablename                      : "log"
	system.log.username                       : ""
	system.log.password                       : ""

It is possible to change this and use another database, provided that the it exists a DBD-driver for 
it. The SQL used by the Log-service is deliberately made quite basic, so as to support a wide array 
of database engines.

### Configuring the Store-service

These are the Store-service related settings:

	system.dist.location                        : "/local/app/aurora/distributions"
	system.dist.timeout                         : 86400
	system.dist.maxretry                        : 2

"timeout" sets the timeout in seconds for Store-service sub-processes that are not responding anymore (no life 
sign through the ALIVE-tag in the Store-service task's folder). When this timeout is reached, the Store-service 
will kill the stalled process and retry (if the retry counter has not reached its maximum, which are set 
by the "maxretry"-setting. It sets the maximum times to retry a failed task operation.

"location" sets the absolute path to the distributions-folder of the Store-service.

### Configuring the Notification-service

These are the settings for the notification-service. Some of them are pretty evident. The "wwwuser" 
and "wwwgroup" informs the Notification-service about which username and group the web-server runs as. 
This is important in order to ensure that the files in the Ack-folder is written with the correct 
privileges so that they can be touch'ed by the Web-clients ack-script.

The "wait"-setting is the time to wait before escalating a notification that has not been ack'ed. Please 
note that in some scenarios the escalation may be immediate (check the documentation on the 
notification-service for more information).

	system.notification.location              : "/local/app/aurora/notification"
	system.notification.wwwuser               : 33
	system.notification.wwwgroup              : 33
	system.notification.wait                  : 259200
	system.notification.from                  : "noreply@ntnu.no"
	system.notification.acklink               : "https://www.mydomain.org/ack.cgi"
	system.notification.types                 :
		user.create : 
			votes             : 0
			subject           : "AURORA create user"
		dataset.close : 
			votes             : 2
			subject           : "AURORA close dataset"
		dataset.info :
			votes             : 0
			subject           : "AURORA dataset information"
		dataset.remove :
			votes             : 2
			subject           : "AURORA remove dataset"
		dataset.expire :
			votes             : 0
			subject           : "AURORA dataset expiring"
		distribution.acquire.failed :
			votes             : 0
			subject           : "AURORA acquire failed"
		distribution.acquire.success :
			votes             : 0
			subject           : "AURORA acquire successful"
		distribution.distribute.failed :
			votes             : 0
			subject           : "AURORA distribute failed"
		distribution.distribute.success :
			votes             : 0
			subject           : "AURORA distribute successful"
		distribution.delete.failed :
			votes             : 0
			subject           : "AURORA delete failed"
		distribution.delete.success :
			votes             : 0
			subject           : "AURORA delete successful"
	system.notification.classes               : [ "Email" ]
	system.notification.class.email.params    :
		host            : "smtp.ansatt.ntnu.no"

The "from"-setting defines who the sender is in the case of email Notices.

The various "types" are structures that define types of Notifications. In other words what 
are the Notificaiton related to (is is a dataset deletion, a acquire that failed and so on). 
This structure defines those types and which subject they will have when sending Notice-messages and 
also what number of votes these various types have (please read up on the Notification-service for more 
information). In most cases it should not be necessary to change the "type"-structures.

The ".class.email"-strucure defines settings to the email Notice-class and in this case only the "host" 
is a setting being used.

### Configuring the Maintenance-services

In order for the AURORA Maintenance-servicse to do their work, they need to have certain settings in place 
to know how to clean up and maintain the AURORA-system:

	system.maintenance.dist.timeout                      : 2592000
	system.maintenance.interface.tmp.timeout             : 1209600
	system.maintenance.statlog.lifespan                  : 7776000
	system.maintenance.tunnellog.lifespan                : 7776000
	system.maintenance.userlog.lifespan                  : 7776000

The "...dist.timeout" sets the timeout threshold for distribution tasks that have failed for the last time (retried up to the setting in "system.dist.maxretry") and have the status "failed" as well as the phase "failed". When this threshold is met with inactivity on such a task, the MAINT_GEN-service will attempt to generate Notification(s) to deal with the issue. The value is in seconds. 

The "system.maintenance.interface.tmp.timeout" sets the grace period before any cleaning away of rendered interfaces is performed.

The "...statlog.lifespan", "...tunnellog.lifespan" and "...userlog.lifespan" sets the lifespan/time that the system stores connection logs (statlog), tunneling logs (tunnellog) and user logs (userlog) for the system. They all default to 3 months if nothing is 
specified. A value of zero or lower will be interpreted as store the logs forever. The unit for all of them are seconds.

	system.maintenance.operations.expire.interval         : 18000
	system.maintenance.operations.expired.interval        : 18000
	system.maintenance.operations.notification.interval   : 18000
	system.maintenance.operations.distribution.interval   : 18000
	system.maintenance.operations.interface.interval      : 18000
	system.maintenance.operations.token.interval          : 18000
	system.maintenance.operations.sequence.interval       : 3600
	system.maintenance.operations.permeffective.interval  : 5
	system.maintenance.operations.metadata.interval       : 30
	system.maintenance.operations.entitymetadata.interval : 300
	system.maintenance.operations.dbcleanup.interval      : 86400

The operations-intervals above defines how often the various maintenance operations are to be run (in seconds). In most cases the defaults should be sufficient. The maintenance-services basically runs in a loop and will check if it is to run the various operations if enough time has passed (ie. interval) between the previous time and now. Since the maintenance services executes operations in an incremental fashion, it might not always reach doing an operation exactly within the interval time set. It will then do it as soon as it has the time 
again and the interval has been passed.

Please also note that one can effectively disable one of the operations by setting the interval to 0. This is practical when debugging, having issues with the services or one just needs to stop one of the operations from running for a while. 

### Configuring web-settings

These are settings of the AURORA web-client that the various services of the AURORA-system needs to know in order to work properly:

	system.www.base : "https://www.aurora.it.ntnu.no"

The configuration-files for the Web-client is located elsewhere together with its installation, so the rest of the AURORA-system needs to know its URL-base in order to refer to it.

## Installing the Apache-server

One does not need to use Apache as the Web-server, but this is the server that AURORA has been tested 
and developed with.

This documentation will therefore concentrate on installing and configuring Apache for AURORA. We will 
not go into the details of putting Apache in place, this can be perused by reading the Apache 
documentation.

Suffice to say that one needs to have it installed and one needs to enable the following Apache modules:

- env
- actions
- ssl
- mpm_itk

### Virtualhost-entry for the AURORA web-client

For the domain that one uses for the AURORA web-client, one needs to add a virtualhost-entry along 
these lines:

	<VirtualHost IPv4-ADDRESS:443 [IPv6-ADDRESS]:443>
	    ServerName www.aurora.it.ntnu.no
	    AssignUserID www-aurora www_aurora
	    SSLEngine on
	    SSLCertificateFile /etc/apache2/ssl.crt/www.aurora.it.ntnu.no.crt
	    SSLCertificateChainFile /etc/apache2/ssl.crt/terena_ssl_ca_3.pem
	    SSLCertificateKeyFile /etc/apache2/ssl.key/www.aurora.it.ntnu.no.key
	
        # document root of the cgi-scripts
	    DocumentRoot /web/virtualhosts/www.aurora.it.ntnu.no/www/
	
	    # Set env path to AURORA web-client folder (not document root)
	    SetEnv AURORAWEB_PATH /web/virtualhosts/www.aurora.it.ntnu.no
	
	    # add support for markdown files as index-files (accumulate within a context)
	    DirectoryIndex index.html index.html.var index.htm index.cgi index.php index.php3  index.shtml
	    DirectoryIndex index.md
	
	    # add markdown rendering support
	    Action markdown "/docs/pandoc.cgi"
	    Addhandler markdown .md
	
	    # general directory settings
	    <Directory "/web/virtualhosts/www.aurora.it.ntnu.no/www/">
	        AuthType None
	        Require all granted
	        Options ExecCGI
	        AllowOverride All
	        AddHandler cgi-script .cgi .py
	    </Directory>
	
	    <Directory /web/virtualhosts/www.aurora.it.ntnu.no/www/>
	        Options +FollowSymlinks -SymLinksIfOwnerMatch
	    </Directory>
	
	</VirtualHost>

We will not go into detail of the meaning of these settings as they should be familiar to anyone that know Apache (if not this would be a good opportunity to start studying).

Please refer to the section on installing the Web-client and its sub-section on "Folder locations" when it comes to tuning the above settings.

It is important that the AURORAWEB_PATH environment variable is available to the installation. This is to know the root of the Web-client installation.

## Installing the AURORA web-client

On the apache-server in the relevant folder, one needs to install the files for the AURORA 
Web-client.

This is done by building the sources that are available from the git repo of the 
svelte web-client.

In order to do this, do the following:

1. Create a folder somewhere that is to be the build folder for the web-client source.
1. Sync or copy the git repo files of the Svelte web-client into that folder.
1. Go down into the folder "webclient" and write "npm install" and hit enter. Let it install all the packages needed as specified in the package.json-file (into the node_modules folder).
1. Write "npm run dev" and hit enter. This will build the 
javascript bundle into the "public"-folder that can be used to run the web-client. Wait until the script says that it is ready to serve requests:
1. Cancel the npm-script by using CTRL+C.
1. Copy the wasmoon web assembly file from node_modules/wasmoon/bin/wasmoon to public/wasmoon.wasm (the code expects it there)
1. Run the "tarme.sh"-script. It will create the tar-bundle that should be used for the web-site (aurora.tar.gz).
1. Copy the tar-bundle, aurora.tar.gz, to the web-server and place it in the document-root
1. Un-tar the bundle on the web-server by writing "tar -xvf aurora.tar.gz".
1. Configure the settings.yaml-file and also have a look at the feide.yaml 
configuration-file that are located in the $AURORAWEB_PATH/settings-folder.

### Folder locations

Before starting to install the web-client it is advantagous to make some considerations as 
to where to put the various files.

There are some defaults that are defined accordingly:

- AURORA web-client root - $AURORAWEB_PATH (set in the web-server virtualhost definition for Apache)
- AURORA web-client git dist - $AURORAWEB_PATH/release
- AURORA web-client document root - $AURORAWEB_PATH/www -> $AURORAWEB_PATH/release/aurorasvelte/public
- AURORA web-client config - $AURORAWEB_PATH/settings
- AURORA web-client certs - $AURORAWEB_PATH/certs

The main thing here is to set the $AURORAWEB_PATH to the correct absolute path on the web-server. It should also be noted that it is not equivalent to DOCUMENT_ROOT. $AURORAWEB_PATH should not be directly exposed on the web-server.

### Syncing with the GIT repo

The Web-client comes from the same git-repo as the rest of the AURORA-system. Please see the 
"Syncing with the GIT repo"-subsection under "Installing the AURORA-system".

Ensure that the git repo is placed under the web-client folder called $AURORAWEB_PATH/release (see the section 
called "Folder locations" above).

### Solving dependencies and libraries

The web-server running the AURORA Web-client needs to have Perl installed and in addition these dependencies (they are 
only related to the feide.cgi-script for authenticating with Oauth/FEIDE):

- Perl with core libraries
- Perl libraries
    - Bytes::Random::Secure
    - CGI
    - CGI::Carp
    - JSON::WebToken
    - MIME::Base64;
    - Net::OAuth2::Profile::WebServer
    - YAML::XS
- pandoc utility

### Generating SSL certs

The AURORA web-clients feide.cgi-script needs to have a set of SSL-certs for it to encrypt the traffic that is has with the AURORA REST-server.

These certs should be generated according to your organizations routines on this, but does not need to be signed.

The SSL-certs of the feide.cgi-script should be placed in the $AURORAWEB_PATH/certs-folder (see the section on folder locations). The certs also needs to be readable by the user and/or group that the web-server runs as (when invoking feide.cgi). Please also take care to protect the private key, so that no one that uses the same web-server can access it.

Here is an example of openssl-syntax to create a set of certificates for feide.cgi:

	openssl req -x509 -sha256 -nodes -days 730 -newkey rsa:2048 -out rest.aurora_it_ntnu_no.crt -keyout rest.aurora_it_ntnu_no.key -subj "/C=NO/ST=Sør-Trøndelag/L=Trondheim/O=NTNU/CN=rest.aurora.it.ntnu.no"

If you want to manually enter the information about the certificate, you can skip adding the "-subj" option:

	openssl req -x509 -sha256 -nodes -days 730 -newkey rsa:2048 -out rest.aurora_it_ntnu_no.crt -keyout rest.aurora_it_ntnu_no.key

The exact location of the certs can be set by changing the configuration files setting:

	aurora.rest.sslparams :
	  SSL_key_file         : "/ABSOLUTE/PATH/TO/AURORA/WEBCLIENT/certs/private.key"
	  SSL_cert_file        : "/ABSOLUTE/PATH/TO/AURORA/WEBCLIENT/certs/public.key"
	  SSL_ca_file          : "/ABSOLUTE/PATH/TO/AURORA/WEBCLIENT/certs/DigiCertCA.crt"

The paths must be specified as absolute paths on the web-server.

Also be aware that the AURORA client does not like chained certificates and each file should only contain the private key, the public key and the CA.

## Configuring the AURORA web-client

The configuration file(s) for the AURORA web-client are located in the $AUROAWEB_PATH/settings-folder. 

These are the settings of the AURORA web-client:

### Svelte AURORA web-client itself

There is a few settings that needs to be configured in the AURORA web-client itself. The 
configuration file is located in the document root of the web-server or as related to 
the git repo of the web-client in the /public-folder. The file is called "settings.yaml".

These are the relevant settings to configure:

	aurora.rest.server      : "rest.aurora.it.ntnu.no:9393"

This sets where the rest-server can be reached.

#### General settings

	www.domain              : "www.yourauroradomain"
	www.base                : "https://www.auroradomain"
	www.cookiename          : "AuroraSvelteCookieName"
	www.cookie.timeout      : 31536000
	www.timeout             : 36000
	www.tree.timeout        : 120
	www.makeannouncements   : true
	www.helppages           : "/docs/user/"
	www.webmaster           : "help@myauroradomain"
	www.maintenance         : false

These settings means: "www.domain" is the domain name where the AURORA 
web-client can be reached. "www.base" is the root domain where AURORA 
is located, including the https-designator. "www.cookiename" is the name 
that is used for the web-clients cookie. "www.cookie.timeout" is the amount 
of time in seconds that the web-client cookie is valid for. "www.timeout" is the 
lifespan of the AURORA web-login before it needs to be renewed. "www.tree.timeout" is 
the length of time, in seconds, before the manage entity tree cache needs to 
be renewed/reloaded from the REST-server. "www.makeannouncements" sets if the 
site announcements are to be shown or not? It is either true or false. 
"www.helppages" sets where the user documentation for the web-client is located? 
"www.webmaster" is the email address to use for getting help with the system. 
"www.maintenance" is a flag for specifying if the system is being maintained or 
not? Valid values are either true or false. If set to true, if will be impossible 
to login and a message/image will appear saying that the system is being 
maintained.

#### Privacy-settings

These are web links to get further information regarding privacy matters and are linked to in the "privacy.cgi"-file of the Web-client.

	privacy.www.questions   : "https://innsida.ntnu.no/wiki/-/wiki/Norsk/Personvern+-+kontaktpersoner"
	privacy.www.ombud       : "https://innsida.ntnu.no/wiki/-/wiki/Norsk/Personvernombud+NTNU"

The ".www.questions" link is for general questions about privacy in your organization. The ".www.ombud" is the link to information about the 
privacy ombuds-man in your organization. These two settings might be the same link for you?


### OAUTH Authenticator-settings

These are settings related to the feide.cgi-script of the AURORA-system (used for OAuth2 auth with FEIDE). Most of them are self-evident. The "SSL_verify_mode" sets the mode with which the REST-client validates the server. You choose to uncomment this mode and the default will ensure that the server certificate is validated (which is preferred of security reasons). The "SSL_verifycn_name" obviously sets which cn name to validate by using the "SSL_verify_mode" (or its default). You can find the configuration-file for the feide.cgi-script in "/ABSOLUTE/PATH/TO/AURORA/WEBCLIENT/settings"-folder. The configuration file is called feide.yaml.

Please note that the REST-server runs only as HTTPS-server, so fiddling with these settings 
to attain non-https connection is bound to spell your doom.

	aurora.rest.server    : "rest.yourdomain:9393"
	aurora.rest.sslparams :
	  SSL_verify_mode      : null
	  SSL_verifycn_name    : "rest.yourdomain"
	  SSL_verifycn_scheme  : "https"
	  SSL_key_file         : "/ABSOLUTE/PATH/TO/AURORA/WEBCLIENT/certs/private.key"
	  SSL_cert_file        : "/ABSOLUTE/PATH/TO/AURORA/WEBCLIENT/certs/public.key"
	  SSL_ca_file          : "/ABSOLUTE/PATH/TO/AURORA/WEBCLIENT/certs/DigiCertCA.crt"

#### General settings

	www.base                : "https://yourdomain"
	www.cookiename          : "AuroraSvelteCookieName"
	www.cookie.timeout      : 31536000

#### OAuth-server settings

	oauth.script            : "/feide.cgi"
	oauth.clientid          : "9c27ff7d-2f39-4343-8e6d-b5ab54372a5e"
	oauth.clientsecret      : "242343242424234234i23o32230942039832"
	oauth.scope             : "email userid-feide profile openid"
	oauth.authorizepath     : "https://auth.dataporten.no/oauth/authorization"
	oauth.tokenpath         : "https://auth.dataporten.no/oauth/token"
	oauth.redirecturi       : "https://youdomain/feide.cgi"

## Configuring the file interface

The file interface is a file structure for accesssing the dataset data in Aurora. 
It is based symlinks and mounts, typically implemented by NFS automount and UFS-like filesystems. The FileInterface has four roles:

- storages
	data storage that holds the data sets, typicaly NFS volumes. A name is assigned to each set.
	
- view
	is a catalog of the data sets, typically a NFS volume

- manager
	is responsible of maintaining the structure of the view and storages.

- clients
	transfers data to and from datasets, prefferably over NFS. Typical klienst may be Samba and ftp servers, linux compute nodes etc. 

All functions may be hosted on one single computer provided it support some kind of loopback mount. It is recommended not to mix clients with other roles to utillize the NFS rootsquash security feature.

### Storages

A storage is a directory (base) consisting of two subdirectorys, "rw" and "ro". The the "ro" catalog should allways be mounted readonly in the fileinterface structure. The recommended export options for a storage is:
- base to manager as rw,norootsquash
- base/rw to clients as rw,rootsquash
- base/ro to clients as ro,rootsquash

If the storage server do not support to split rw and ro, base may be exported rw,rootsquash to trusted clients. The ro mount option must then be applied for the "ro" mount below.


### View

The view is simply a directory. The recommended export options for the view is:

- view to manager as rw,norootsquash
- view to clients as ro,rootsquash


### Manager

The manager consists of a fileinterface file structure, a perl library (FileInterface.pm) to manipulate the structure and a wrapper service for privilege separation. The root path may be configured but defaults to "/Aurora" and vil be reffered to as such.

#### File structure

/Aurora is the base of the interface and is typically a local folder with a automount map attached. The following should be present in /Aurora:

- view - rw mount of the view

For each of the storages (store)

- fi-store - rw mount of its base
- rw-store - rw mount of base/rw
- ro-store - ro mount of base/ro

#### FileInterface.pm

This contains methods for manipulating the file structure. It has to run as root, and a small wrapper service (AuroraFileInterface) is provided for privilege escalation using sudo by default.

The restsrvc.pl rest server by default use the sudo option (as sys-aurora). This have to be configured in the /etc/sudoers(.d/*) like this:

    sys-aurora ALL=(ALL) NOPASSWD: /local/app/aurora/dist/fileinterface/AuroraFileInterface


### Client

For clients not running on the manager computer (recommended) mounts a similar mount stucture as the [manager](#file-structure) with the following exceptions:

- the view is mounted ro
- no fi-store is mounted

The appropriate datasets will be available for the clients user (username) as /Aurora/view/access/user/username

An samba config may look like this

    [aurora]
        comment         = Aurora file share
        path            = /Aurora/view/access/user/%U
        force user      = %U
        read only       = no
        create mask     = 0666
        directory mask  = 02777
        follow symlinks = yes
        unix extensions = no 
        browseable      = no
        guest ok        = no
        acl allow execute always = yes
        hide dot files  = no

### FileInterface configuration

The primary /etc/aurora/aurora.yaml configuration entries for the file interface is:

- fileinterface.root

