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
# AURORA development considerations and solutions

This document shows considerations as relates to developing the AURORA-system and 
how this can be done in the best possible manner.

In order to execute the development of AURORA in the best possible manner, we have 
created a set of docker-definitions that will make it possible to test the 
entire system while coding on you own machine.

There are several ways to be coding the AURORA-system and this goes to what 
preferences that the individual coder may have. In any event, we recommend that 
you have the AURORA git repo synchronized to a folder on your computer and that 
this folder is then bound/shared into the docker containers (the docker solution 
includes a configuration-script that setup all of this).

The advantage of this scheme is that you can change the code in whatever branch that 
you wish and this branch is then directly exposed into the docker containers.

Please note that this solution is meant to accomodate a setup on a Linux host, not 
on Windows. While it might work in Windows, we have not made any attempts to accomodate this 
or tested it.

## How to install the AURORA docker containers

In the AURORA repo under the folder "devdockers" it is included a tar.gz-file that includes the 
whole package needed to setup a complete AURORA-system on your own computer.

In order to install these dockers, you do the following:

1. Have the AURORA git code/repo sync available in some folder on your computer.
1. Create a folder somewhere on your computer (eg. /home/USER/aurora).
1. Copy the aurora_dockers.tar.gz to the new folder.
1. Unpack the aurora_dockers.tar.gz file by writing:

        tar -xvf aurora_dockers.tar.gz

1. Run the config-script in the unpacked files:

        ./config

1. Answer all the questions asked, but be careful to get the working folder/AURORA docker root 
location (the one you created for the tar-set above)`and the AURORA git code locations correctly. These 
locations are written into the configuration of the dockers, so it needs to be correct. Also say yes 
to all patching and creation of FileInterface structure as well as other folder areas needed.
1. Start the aurora-db container by going into the aurora-db-folder and cat the ref.txt file:

        cd aurora-db
        cat ref.txt

1. Write the command for running the container as referenced in the ref.txt-file.
1. Inside the aurora-db container, do the following:

        mysql
        create database auroradev;
        create user 'auroradev'@'10.0.10.%' identified by 'Auroradev1234';
        grant all privileges on auroradev.* to 'auroradev'@'10.0.10.%';
        flush privileges;
        quit
        cd /root
        mysql auroradev < create_mysql.sql
        mysql auroradev < initdata.sql
        mysql auroradev < initdata_docker.sql

All the containers will run with the prompt available, so that one can go into them and check, change or debug them. All of 
the images includes a set of useful debug-tools, such as strace, tcpdump, telnet etc.

The following containers exist in the development set:

- aurora-common (this is shared by all the other images and also includes diagnostic tools and other things needed
). This container is not run, but used as a basis for all the other ones.
- aurora-computer (a laboratory computer which one can fetch data from to simulate the automated datasets mode of 
AURORA)
- aurora-db (the aurora database instance with MySQL).
- aurora-samba (samba server that offers up the AURORA FileInterface for users added through the system-file)
- aurora-server (the aurora-system itself with the REST-server, log-service, notification-service, maintenance-ser
vice and store-service).
- aurora-web (the server with apache2 and the aurora web-client)

The AURORA web-client should upon starting the aurora-web docker image be available through https://10.0.10.12 on your host machine or alternately in addition https://auroradev if you added that to your hosts-file. Please do not mess around with this name, because it is also used for configurations, web certificates and such. The certificates used are self-signed, so accept this in your browser.
