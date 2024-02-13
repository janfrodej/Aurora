<!--
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
# Fileinterface overview

Fileinterface is a mechanism for maintaining datasets on disk. The 
fileinterface stores each dataset in its own directory. A dataset consist 
of data and metadata, and is identifies by an unique number. The data part 
is allways stored in a subdirectory named "data". The metadata may reside 
outside the dataset directory depending on the state of the dataset.


## Datset states

A dataset has several [states]. The normal state flow of a dataset with its 
(transitions) is like this:

	(open) -> [rw] -> (close) -> [ro] -> (unlink) -> [invisible] -> (remove)

This flow may be shorted by skipping the [ro] state:

	(open) -> [rw] -> (unlink) -> [invisible] -> (remove)

## Roles

The file interface it self is divided into tree server roles:

- storage, one or more, where the data resides
- manager, a single instance, that controls the structure
- client, one or more, that gives users access to the data

The storage is divided into two:

- Dataset storage
- View

The dataset storage is where the data resides, while the view is where the 
user observes the data. The manager ties the view to the actual data 
storage by symbolic links according to the individual users access rights.

The clients (samba servers, login hosts etc) mount both the storage and the 
view, but user access is allways done trough the view.


# Dataset storage

The datasets is physiclly stored in file storages, typically on NFS file 
servers. The number of file storages depend on the scaling need. Each file
storage should be on a single file system, but is divided into a "rw" and
a "ro" directory, witch is exported separatly with ro and rw options respectively. 
A (close) implies to move the dataset from the [rw] part to the corresponding [ro] part.

Under the "ro"/"rw" the dataset is stored based its numeric id and a cookie. 
The cookie is to avoid probing for dataset access. I addititon there a 
scaling structure to avoid file count limits in directorys.

Full storage path for a dataset is like this:

    storage_path/[ro|rw]/nnn/mmm/datasetid/cookie/

nnn and mmm is the scaling structure and is assigned ( datasetid / 1000 ** n) % 1000 for n = 2 and 1 respectively. 


In the following we will use an open (rw) dataset 3876345 as an example. This is assigned to storage "0001", and given the cookie "FyVFGBQs9Y2g7kUjiqc". Storage "0001" resides on "server01" at "/exports/0001".  

Dataset 3876345 full data storage path will then be

    server01:/exports/0001/rw/003/876/3876345/FyVFGBQs9Y2g7kUjiqc/data/

where
- server01:/exports/0001 is the storage_path
- rw is the mode
- 003/876 is the scaling part
- FyVFGBQs9Y2g7kUjiqc is the cookie


## File protection

- 0711 for .../nnn/mmm/datasetid
- 0755 for .../nnn/mmm/datasetid/cookie
- 0777 for .../nnn/mmm/datasetid/cookie/data

All the above directories should be owned by root.


server01:/exports/0001/ro should be exported ro,rootsquash to all clients
server01:/exports/0001/rw should be exported rw,rootsquash to all clients

server01:/exports/0001 should be exported rw,norootsquash to the fileinterface manager 
if not local.


## Storage mount

The manager and all clients should mount all dataset exports in a common 
local base directory (/Aurora for the examples) like this:

    mount    server01:/exports/0001/rw /Aurora/rw-0001
    mount -r server01:/exports/0001/ro /Aurora/ro-0001

The manager should in addition have mounts like this:

    mount    server01:/exports/0001 /Aurora/fi-0001


# View structure

All user accesses is done trough a "view" directory structure. This is typically stored on one of the storage servers, and exported to the manager (rw, 
norootsquash) and all clients (ro,rootsquash). It should be mounted as "view" in the base directory:

   server01:/exports/view /Aurora/view

The view has two directory trees:

- dataset
- access

## Dataset view

The dataset view is a uniform path for the datsets. The dataset's view-path 
is independent of wich storage it is located. A dataset view will be like this:

    /Aurora/view/dataset/003/876/3876345 -> ../../../../../rw-0001/003/876/3876345

This way the dataset view maps the storage location (and mode) of the dataset.

## Access view

Access views is where the user access the datasets. Each user has its own directories containing links to the datasets cookie directory. The links is located under a directory "ALL".

There is currently two classes of user access:

- user, based on users unix uid
- token, based on knowledge of an access token.

For a user named "bt" with uid 23444 the following link will eksist, provided "bt" is granted "rw" access to dataset 3876345:

    /Aurora/view/access/user/bt/ALL/3876345 -> ../../../../../dataset/003/876/3876345/FyVFGBQs9Y2g7kUjiqc

"bt" may thus read and write to the directory /Aurora/view/acces/user/bt/ALL/3876345/data/. To shield the coockie from others, the .../users/bt folder should be owned by uid 23444 and have 0500 mask. The links is mantained by root at the management server.

Token based access is availabe trough /Aurora/view/access/token that contain a directory for each token. The .../acces/token directory should be owned by root with 0711 mask to hide the tokens. Example:

    /Aurora/view/access/token/r64erHiugYGjGs/ALL/387634 -> ../../../../../dataset/003/876/3876345/FyVFGBQs9Y2g7kUjiqc

Here knowledge of the token "r64erHiugYGjGs" gives access to dataset 387634. The r64erHiugYGjGs directory should be owned by root with 0755 mask.


Alongside ALL the users directory may contain:

- Method files - redirect http files to Aurora web methods
- Better named symlinks into ALL/
- Selection sets

Selection sets (not implemented) is folders with symlinks createt from a user specified select statement, like :

"select room,instrument,creator,time,dataset from dataset where room=D3-133" result in the followin links:
    D3-133 gcms janj 2019-03-21T23:33:56.345Z 1654 -> ../ALL/1654
    D3-133 xray bt 2019-11-23T12:45:32.367Z 2345   -> ../ALL/2345
    D3-133 xray janj 2019-01-15T10:44:12.743Z 1543 -> ../ALL/1543



# The manager

The manager is responsible of tying this together. In addition to the clients

## The managers tasks

- open, close, unlink and remove datasets
- maintain <base>/view/dataset/ acoordingly
- maintain <base>/view/access/
- maintain the method and 


# Mounting examples

The storage structure of the FileInterface is based on NFS and its "ro" and "rootsquash" export options. The tree roles (storage, manager and client) is intended run on different systems for full privelege separation. The manager role may be colocated with a storage role instace.
The view may be hosted on its ovn server, the manager or one of the storage servers.

The following is examples of exports and automount files (two data storages on separate servers):

## storage00:/etc/exports

    /exports/0000/      manager(rw,norootsquash)
    /exports/0000/rw    clients(rw,rootsquash)
    /exports/ds00/ro    clients(ro,rootsquash)
    /exports/view       manager(rw,norootsquash)
    /exports/view       clients(ro,rootsquash)

## storage01:/etc/exports

    /exports/0001/      manager(rw,norootsquash)
    /exports/0001/rw    clients(rw,rootsquash)
    /exports/0002/ro    clients(ro,rootsquash)

## manager:/etc/auto_auroramaster

    view     -rw  storage00:/exports/view
    fi-0000  -rw  storage00:/exports/0000
    rw-0000  -rw  storage00:/exports/0000/rw
    ro-0000  -ro  storage00:/exports/0000/ro
    fi-0001  -rw  storage01:/exports/0001
    rw-0001  -rw  storage01:/exports/0001/rw
    ro-0001  -ro  storage01:/exports/0001/ro

## manager:/etc/auto_auroraclient

    view     -ro  storage00:/exports/view
    rw-ds00  -rw  storage00:/exports/0000/rw
    ro-ds00  -ro  storage00:/exports/0000/ro
    rw-ds01  -rw  storage01:/exports/0001/rw
    ro-ds01  -ro  storage01:/exports/0001/ro


# Access model

The access model is quite simple. An user may be grantet access to a dataset 
in [rw] state, in [ro] state, or both. Readonly access can not be granted 
to a [rw] dataset and vice versa. 


## Rehashing of cookie

Due to the readlink() exposing the cookies, the cookie should be 
regenerated occationally. Events that should trigger this is:

- State transitions
- Access revokation
- Cookie expiry

Rehashing is done in four steps:

1. Renaming the cookie directory
    In server01:/exports/0001/rw/003/876/3876345/ renaming  
    1Wy1ZpBtiy8PFyVFGBQs9Y2g7kUjiqc to epzpNMcdTzdnrsQQtzu7iNGJlOGQ6KDz
1. Creating backward compatibility link
    1Wy1ZpBtiy8PFyVFGBQs9Y2g7kUjiqc -> epzpNMcdTzdnrsQQtzu7iNGJlOGQ6KDz
1. Updating the Aurora/view/access tree
    This may be time and I/O consumpting
1. Removing the compatibillity symlink 1Wy1ZpBtiy8PFyVFGBQs9Y2g7kUjiqc

Care should be taken to step 3 that potentially may involve a lot of I/O.


# FileInterface library

FileInterface.pm defines four classes

- FileInterface
- FileInterfaceDataset
- FileInterfaceUser
- FileInterfaceAccess

It relies on AuroraDB in for:

- class/user to entityid conversion
- Get access information
- Metadata for close()

## FileInterface

This is its external interface

Constructor:

- new(AuroraDB[, base])             # Return a FileInterface object

Methods:

- open(dataset)				# Create storage for dataset
- close(dataset)			# 
- hide(dataset)						# 
- expose(dataset)			# 
- remove(dataset)			# 
- status(dataset)			# 

- grant(dataset, user, mode)		# 
- deny(dataset, user, mode)		# 
- purge(dataset)	  		# Update permissions for a datast
- purge(user)				# Update permissions for a user

- yell()				# return any errors

- dsetpath(dataset)			# return the path to a dataset
- datapath(dataset)			# return the path to the data of a dataset

- userpath(user)			# return the path to a users view
- httpuser(user)			# return the http path to a users view
- httpdset(user, dataset)		# return the users http path to a dataset
- httpdata(user, dataset)		# return the users http path to a sets data

Parameters:

- AuroraDB AuroraDB object used for accessing the AuroraDB
- base     Local aurora root, defaults to ###TEST /fagit/nv-unix/felles/bt/aurora ###
- dataset  Dataset id or FileInterfaceDataset object
- user     userclass."/".userid, users AuroraDB entityid or FileInterfaceUser object
- mode     "rw" or "ro"


# Client-server interface

For privilege separation there is a client-server interface, with a fift class FileInterfaceClient. This is activated by calling FileInterfaceClient->new(@arg). The arg is a command to start FileInterface->server(). @arg is passed to open2() and defaults to "sudo perl -Twe 'use lib q(/Aurora/lib); use FileInterface; FileInterface->new->server;'"

For the external methods the client-server model should be transparent with the following exceptions:
- new() parameters 
- Yell messages may differ


## Privilege separation by default sudo:

    use FileInterface;
    my $fi = FileInterfaceClient->new();

The escalation is done according to the /etc/sudoers files.

## Privilege separation by ssh publickey with restricted command:

    use FileInterface;
    my $fi = FileInterfaceClient->new(qw(ssh -T root@server));

The escalation is done starting the FileInterfaceClient->server() from /root/.ssh/authorized_keys files with restricted,command options.

