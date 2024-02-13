# Aurora

AURORA or Archive, Upload Research Objects for Retrieval and Alteration is a science data storage and retrieval system meant to keep 
track of science data generated and attach relevant metadata to them. It also facilitates easy use of the stored datasets 
through many standardized services.

It is being developed at NTNU (Norwegian University of Science and Technology) in Trondheim by Jan Frode Jæger and
Bård Tesaker. It has been released with a GNU GPL v.3 license and no support will be given at this point. We will be uploading 
newer versions as they become available.

It features:

- The ability to download data from laboratory computers in the background after they have been generated (socalled automated acquire).
- The ability to download data from laboratory computers while its being generated (socalled manual acquire).
- The ability to add dynamic metadata to the stored datasets. The limit to the metadata is only in terms of database size and practical limits as it is completely flexible.
- A rich and flexible ability to define permissions for datasets, including adding them to research groups and other organizational units. This means that datasets will be owned by the group, not the user which makes the management of them better and safer.
- The ability to automatically copy the stored dataset on to other locations by policy.
- Offers a full log of what has been done to the datasets and which files it contains, their md5 sum and more.
- Offers an easy to use web-interface to the stored datasets, creating new datasets, viewing and editing metadata,
- Offers plugin support for transport protocols both to and from locations. The support now includes: FTP, SFTP, SCP, RSync over SSH and Samba/CIFS. In the future we hope to offer support for the most popular cloud platforms like OneDrive, Google Drive, Amazon S3 etc.
- Offers plugin support for dataset access/retrieval. The support now includes: Samba/CIFS, ZIP- and TAR-sets, URL/Web-access.
- Supports most major platforms: Windows, Mac OS, Linux, Unix etc. Most functionality is available through web-interface or standardized transport and retrieval protocols.
- Utilizes standardized and established technologies for data transport and storage that are also open source and thereby offering high uptime and low cost.
- Better security for science laboratories by eliminating the need for external HDs or USB drives to move data out of the lab.
- Automatic notification of upcoming deletion and deleted datasets. Also when notifications are not received or confirmed, the system will automatically escalate the notification to the group(s) that owns the datasets in a hierarchical fashion.
- Standardized REST-interface to the AURORA-system that easily can allow new services and systems to access it.
- Has the ability to manage and control the opening of remote control tunnell access to laboratory computers.
- Has an embedded Lua engine in the client that makes it possible to write scripts that interface with the AURORA REST API. 
- Free to use.

AURORA consists of mainly a server and a web-client. 

The server runs the REST-server and its constituent services. It has been written in Perl. It must be run 
on a Linux operating system and has been thorougly tested with Ubuntu.

The client has been written in Svelte utilizing javascript and typescript and is built to a bundle for 
backwards-compability all the way to Windows XP and Firefox version 52 (laboratory computers that control 
instruments are often not that new). It uses a rollup setup and the resulting bundle and its structure will 
then run in the client browser and interface with the AURORA REST API through javascript fetch-calls.

The backend/REST-server uses a database to store all relevant information about datasets and users. The 
interface with the database has been written as open and general SQL as possible and should allow for the 
use of several database engines, however, as it is right now we advise the use of MySQL/MariaDB.

The data of the system is being written to filesystems available on the server that runs the REST API. So 
here we are talking about any POSIX compliant filesystem, either locally or over NFS or similar. This 
arrangement makes the datasets of the system easily available over many standardized protocols.

Since the AURORA-server has several services that constitutes the system itself, it means that the 
AURORA-server can have many of its services down for upgrade or configuration without the availability 
overall suffering. One can also take down the whole REST-server and the client web-server and still the data 
of the datasets will be available to users through the POSIX filesystem and its attached services (cifs/samba, 
nfs, ssh/terminal etc.). This is one of the strengths of the system. It should also be possible to run 
several servers with the REST-server, barring certain sub-services, for greater redundancy and availability, 
but while we have planned for this scenario we have not tested it as of yet.

The whole system can also be developed and tested by using an included set of docker containers (see the 
server/devdockers folder).

For an overview of the system see here:

![Overview Documentation](server/docs/overview/index.md)

For installation, development and diagnostic documentation see here:

![Sysop Documentation](server/docs/sysop/index.md)

For technical documentation of the system see here:

![Technical Documentation](server/docs/technical/index.md)

For user- and interface documentation of the Svelte web-client see here:

![User Documentation](client/public/docs/user/index.md)

When it comes to the automated dataset archiving option where AURORA fetches data from the laboratory 
computer for the user, we recommend using the RSync/SSH plugin of AURORA (which have been most 
extensively tested and offers all the bells and whistles) and a SSH-server on the computer in question. 
We have had great success with using the free version of CopSSH, but now one can also go for the free 
Cygwin system (see ![here](https://www.cygwin.com/)) and build the client one wants. We have also tested this with 
good results. The essence is that the client that is to be archived data from needs a SSH-server 
running on it and a copy of Rsync. For Mac OS and Linux/Unix this is less of a problem, but for Windows 
one needs to have a system like CopSSH and Cygwin, except for the latest incarnations of Windows that offers 
a SSH-server (Windows 10 and 11). We have not had the pleasure of testing this solution, but should in theory work as 
well. In any case, relying only on one client is in many cases preferrable, because it reduces the overall 
complexity of installation and maintenance compared to having several packages. On this note, it might be said 
that Cygwin offers both 32- and 64-bit versions for Windows and can be made to work with even Windows XP.

Also we are still working on making certain parts of the system better scalable than what it is right now. 
This applies specifically to the database and things that has to do with permissions. This does not scale 
as well as we would like, but solutions are in the pipeline. Also we are considering replacing permissions 
masks through Perl vec with regular bitmasks in the database, since newer versions of MySQL also support 
bitmasks of quite extended size.

Other things that we are working on changing is the way in which SQL calls search the entity tree which now 
relies on multiple counts of views that are sub-optimal. Since we didn't have access to recursion through SQL 
WITH-calls earlier, this is something we are now looking into since we are utilizing a newer MySQL/MariaDB 
version. This current design also affects the efficiency of the permissions as mentioned above.

Please also be advised that since the system was developed at NTNU it will have some parts of it that are 
configured and aimed for being used in that environment. We have not had the time or resources to 
adapt this release for a more generalized setting, but most of the system should be usable with minor 
adaptations/configuration to any environment. We only have a "mandate" for releasing the code base with a 
GNU GPL v.3 license and can offer no support or help from the university side.

The setup and deployment might also seem a bit complex and we are working on reducing the complexity of 
AURORA, but as it stands, this is how it is. However, the installation is well documented and the development 
docker containers will also be a source of seeing how the system is put together.

We are thankful for any feedback on serious security bugs or similar. Feedback on wishware or suggestions for 
further development and changes are also welcome, but we cannot promise any priority to making it happen since 
we are not allowed to give any support or resources to anything outside NTNUs needs.
