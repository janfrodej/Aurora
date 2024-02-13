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
# AURORA utilities

This document outlines the various utilities that exists to perform various operations in 
the AURORA system.

The utilities are scripts of various types that makes it possible to read, write, maintain and 
manage the AURORA-system.

They are there to ease the administration and maintenance/diagnosis of the system.

As of this version we have the following utilities:

- addlogentry.pl (add log entry to the database)
- balusers.pl (balance users in sub-folders in the entity tree)
- chkint.pl (check dataset integrity)
- clearacks.pl (remove unused notification acks from AURORA)
- crblkdatasets.pl (create a bulk of randomized, test datasets in the system)
- crblkusers.pl (create a bulk of test users in the system)
- createlab.pl (create a laboratory in the entity tree and set permissions)
- createrg.pl (create a research group in the entity tree and set permissions)
- dbcall.pl (execute and test method calls in the AuroraDB.pm-library)
- dbquery.pl (execute SQL queries to the AURORAd database and receive the response in various formats).
- getentitytemplate.pl (get aggregated template for an entity)
- gettemplate.pl (get a specific, defined template)
- mkcrypt.pl (create a new, random crypt)
- mksalt.pl (create a new, random salt)
- modperm.pl (modify permissions in the entity tree)
- permtree.pl (list permissions in the entity tree)
- restcall.pl (execute and test AURORA REST-server methods)
- restcmd.pl (execute and test AURORA REST-server methods on the command-line)
- saveaccessmatrix.pl (list who have access to DATASET and COMPUTER-resources/entities)
- setperm.pl (modify permissions in the entity tree. Yes we have two utilities for this - the more the merrier)
- settemplate.pl (modify/create a template)
- undelete.pl (undeletes a FI-removed dataset if it still exists)

## addlogentry.pl

Add a log entry to the database attached to an entity, usually a dataset-entity.

Adds a log entry on the specfed entity:

	./addlogentry.pl [OPT] [OPTVALUE]

A minimum of paramteres are:

  - -id = Dataset ID to add long entry on.
  - -s = String of entry to add.

Example:

	./addlogentry.pl -id 12345 -s "Hello"

This will add a log entry to 12345.

Other available optional options are:

  -l    Integer loglevel of log entry. Defaults to INFORMATION. 
  -t    Log entry tag. Defaults to NONE.
  -tm   Timestamp of log entry (unixtime UTC). Defaults to current time.
  -im   Imitate source of log entry as one of the AURORA-services.

The "im"-tag can be used together with the "t"-tag. In such cases the imitation part of the tag comes first and the specified log 
entry tag afterwards with a space added between them.

Examples of syntax:

	./addlogentry.pl -id 12345 -s "Hello World" -l 5 -t WHATEVER -tm 1234567890 -im 2

See the addlogentry.pl-utility for more information on the various parameters. (run it without any parameters).

## balusers.pl

Balance users in sub-folders on the entity tree.

This script makes it possible to sort existing users in the entity tree that are not already sorted. After version 1.3 of
AURORA this sorting can be performed at user creation time.

The script accepts only one parameter: parent. The parent is the entity ID in AURORA of the parent of the users entities that are to 
be sorted.

What the script does is that it sort all user entities found under the given parent into sub-folders with names that are the first 
letter of users fullname. So a user called "John Doe" will be sorted into a sub-folder called "J". The script also handles names 
that have unusual first letters in their names and will in the end force all these into the uppercase A-Z letter space using 
two methods:

1. By unicode textual name. If that names start with "LATIN [SMALL|CAPITAL] LETTER [A-Z]" and possibly some optional embellishment on 
the latin letter, it be will converted into the letter of its base, latin name. So for example the unicode name of: 
"LATIN CAPITAL LETTER A WITH GRAVE" will be converted into an A and everything with "A WITH GRAVE" is ignored. Any first fullname 
letters that do not start with any of these latin letters of A-Z are ignored.
1. Any first fullname letter that has not been converted into the A-Z letter space by method no 1 are converted mathematically into 
A-Z by using their ordinal value and modulus.

Any one-letter sub-folder under the parent that do not exist already is created in the process. If the sub-folder exists already, 
it is used as destination for the user in question.

## chkint.pl

Check dataset integrity. Investigates if the dataset has completed its acquire-phase, if the data stored in the set matches what 
was remotely and if everything seems ok.

Syntax:

	chkint.pl [OPTION] [VALUE]

Example:

	chkint.pl -i 12345

The options is any valid option flag and value is its value. In the example above the "-i" options specifies the dataset entity to 
check the integrity of.

Valid flags are:

 - -i - Dataset entity id to check integrity of. INTEGER. Mandatory.
 - -f - Fix the dataset by closing it if open and set correct metadata. BOOLEAN. Optional. Defaults to FALSE. Use value 1 for TRUE, 0 for FALSE to fix dataset. If already closed, will ensure correct metadata is set and even adjust the metadata information on the size of the dataset based upon calculation of stored, local content. The option requires that the analysis has passed comparing total size between what was perceived as the remote size of the data and what is calculated locally. If checksums exists, then it will not fix the dataset if not the sizes and checksums are right.
 - -c - Set checksum type to use when checking files. Optional. Defaults to md5. Valid values: md5, sha256, xxh32, xxh64, xxh128.
 - -h - Show help screen.

The utility will go through the sets metadata, log and data area to analyze if the set is ok or not? If the set was removed at any 
point it will also conclude it is ok. It will also attempt to compare checksums between what was transferred and what is stored if 
the log contains them. One can use another checksum type if so required when analyzing the log data and this is specified with the 
"-c" flag/option.

The analysis ends with a statement along the lines of :

	Analysis Conclusion N: [OK|NOT OK]

N is here the dataset entity id. OK means that the dataset is "OK", while "NOT OK", means that it is considered not OK.

## clearacks.pl

Clears AURORA Notification Acks that have not been used

Syntax:

	clearacks.pl -y

Remove all acks that do not have a notification in the AURORA notifications folder. It therefore cleans up 
the notification-service folder.

Location of the notification folder are read from the settings-file of AURORA.

## crblkdatasets.pl

This script creates a bulk of randomized, test datasets in the system. This script uses the AURORA REST-server to 
perform its operation and requires that one logs in with a valid AURORA authentication. All the datasets will be 
AUTOMATIC datasets.

The script does not require any parameters and it will ask for all the input needed after you start it. The input asked for:

- Authentication Type. The AURORA authentication type, defaults to AuroraID.
- Email-address. The email-address or username of the user.
- Authentication-string. The Authentication string/password of the user (it will not be visible).
- Hostname of REST-server. Hostname of the REST-server to connect to.
- Port of REST-server. Port number where the REST-server is available. Defaults to 9393.
- Private key. Private key to use when connecting to the REST-server. Defaults to ./certs/private.key.
- Public key. Public key to use when connecting to the REST-server. Defaults to ./certs/public.key.
- CA key. Certificate Authority key file. Defaults to ./certs/DigiCertCA.crt.
- Number of datasets. The number of datasets that one wishes to create.
- Group/parent. The group/parent ID that is to own the dataset(s) created.
- Computer. The computer ID from which the data is to be fetched. Also important for which template are used.
- Path. The path under the data folder to fetch the data for the dataset from.

After answering these questions, the script will create the number of datasets that one has asked for.

## crblkusers.pl

Create a bulk of test users in the system. The script uses the AURORA REST-server and requires that one log in 
with valid credentials.

No input parameters are needed on the command line. All input is asked for after starting the script:

- Authentication Type. The AURORA authentication type, defaults to AuroraID.
- Email-address. The email-address or username of the user.
- Authentication-string. The Authentication string/password of the user (it will not be visible).
- Hostname of REST-server. Hostname of the REST-server to connect to.
- Port of REST-server. Port number where the REST-server is available. Defaults to 9393.
- Private key. Private key to use when connecting to the REST-server. Defaults to ./certs/private.key.
- Public key. Public key to use when connecting to the REST-server. Defaults to ./certs/public.key.
- CA key. Certificate Authority key file. Defaults to ./certs/DigiCertCA.crt.
- Parent. The parent ID that is to own the user(s) created.
- Number of users. The number of users to create.
- Start at count. The number to start at when creating the user(s). Already bulk created users number(s) must be avoided in order 
for not to have any conflicts.

The number of users asked for are then created. They will names in the form:

	User1000@localhost

But the first letter will be randomized in accordance with the user sorting scheme in AURORA and the numbering will also be incremented 
in line with the "number of users" and "start at count" input.

## createlab.pl

Create a laboratory in the entity tree and set permissions.

No command line parameters are needed and it will ask for the relevant input after being started:

- Authentication Type. The AURORA authentication type, defaults to AuroraID.
- Email-address. The email-address or username of the user.
- Authentication-string. The Authentication string/password of the user (it will not be visible).
- Hostname of REST-server. Hostname of the REST-server to connect to.
- Port of REST-server. Port number where the REST-server is available. Defaults to 9393.
- Private key. Private key to use when connecting to the REST-server. Defaults to ./certs/private.key.
- Public key. Public key to use when connecting to the REST-server. Defaults to ./certs/public.key.
- CA key. Certificate Authority key file. Defaults to ./certs/DigiCertCA.crt.
- Parent. The parent ID of the laboratory.
- Laboratory name. The textual laboratory name.

The script will then create the laboratory based on the given input. It will also create role-groups for the laboratory with 
the relevant permissions. The hiearchy and setup of the laboratory is based upon the way we do at NTNU with AURORA. Other 
schemes are possible.

## createrg.pl

Create a research group in the entity tree and set permissions.

No command line parameters are needed and it will ask for the relevant input after being started:

- Authentication Type. The AURORA authentication type, defaults to AuroraID.
- Email-address. The email-address or username of the user.
- Authentication-string. The Authentication string/password of the user (it will not be visible).
- Hostname of REST-server. Hostname of the REST-server to connect to.
- Port of REST-server. Port number where the REST-server is available. Defaults to 9393.
- Private key. Private key to use when connecting to the REST-server. Defaults to ./certs/private.key.
- Public key. Public key to use when connecting to the REST-server. Defaults to ./certs/public.key.
- CA key. Certificate Authority key file. Defaults to ./certs/DigiCertCA.crt.
- Parent. The parent ID of the research group.
- Entity ID for Lab user-role. The ID of the lab group that grants read and/or write access to the laboratory computers in question.
- Research group name. The textual laboratory name.

The script will then create the research group based on the given input. It will also create role-groups for the research group with 
the relevant permissions. The hiearchy and setup of the research group is based upon the way we do at NTNU with AURORA. Other 
schemes are possible.

## dbcall.pl

Execute and test method calls in the AuroraDB.pm-library. This utility makes it possible to run methods in the AuroraDB-library 
and perform any operation there on the active database of the installation.

It does not take any parameters, and will ask for the necessary input after being started.

On the prompt, one needs to write valid AuroraDB-method calls and their parameters. Valid methods can be perused by checking the 
technical documentation for the AuroraDB.pm-module.

Parameters are given in the following way:

- Scalars - just write the number or string in question. Use quote marks for space separated strings.
- Array - Use the []-characters to denote an array.
- Hash - use the {}-characters to denote a hash.
- Undef - is stated by using the "<undef>"-string

Combinations of hashes, arrays and scalars are permissible depending upon what the AuroraDB-method in question requires.

So eg. calling the "getEntityParent"-method and asking for the parent of the root-entity (1) is done as follows:

	getEntityParent 1

and then followed by the ENTER-key on the keyboard. The result of the method will then be dumped on the screen as such:

	getEntityParent(       $VAR1 = '1';
	) =              SUCCESS: '0'[00110000]

A more complicated call could be when calling the "getEntityMetadata"-method:

	getEntityMetadata 1234 {parent=>1} [".system.entity.name",".Creator",".Description"] 

## dbquery.pl

Execute SQL queries to the AURORA database and received the response in a formatted way.

The syntax of the script is as follows:

	dbquery.pl [OPT] [OPTVALUE]

where OPT is the option and OPTVALUE is the value set on the option. Even the SQL-query itself is given as an option. 

Valid options are:

  - -c  Dump the result from the query in a CSV-format to screen. Must evaluate to true or false
  - -cs Separator to use when dumping with -c. Default is ";"
  - -ch Print header or not when dumping with -c. Default is false. Value must evaluate to true or false.
  - -d  Dump the result from the query using Data::Dumper.
  - -f  Read SQL queries/operations from a file.
  - -r  Query replacement variable definition(s). The option-value is defined as: "1=ABC,2=CBA,3=DEF..N=XYZ".
  - -rd Query replacement dry run or not. Default is false. Value must evaluate to true or false. The replaced query(ies) are displayed on screen.
  - -s  Query to execute.

Example of a dbquery-command is:

	./dbquery.pl -c 1 -ch 1 -s "SELECT * from METADATA where entity=1"

one can also choose to perform SQL inserts, deletes etc with the utility. The output is the result from 
the SQL-server, if any. One can choose to have this formatted in various ways. The supported formats are:

  - CSV-format with a selectable separator (see the -cs option).
  - Perl Data::Dumper format (see the -d option).

One can also choose to have the first row in the output be the name of the fields of the row. This might be of 
interest when dumping to a CSV-file. Writing the header or not is chosen by the "-ch"-option. If both CSV-format and 
others are selected at the same time, if will do both. This might not be practical when wanting a CSV-file.

An example of a complete CSV-dump is as follows:

	./dbquery.pl -c 1 -ch 1 -s "SELECT * from METADATA natural left join METADATAKEY where entity=1" > /tmp/myfile.csv

The chosen field separator character is always quoted in the response from the database in order to avoid confusion.

One can also define that the SQL statements are to be read from a text-file with the "-f" options. This allows for multiple statements and can be 
handy if one wants to do eg. multiple INSERTS or DELETES. The contents of the text-file is one statement per line:

	SELECT * from METADATA where entity=1
	SELECT * from METADATA natural left join METADATAKEY where entity=1

This can then be run by doing the following:

	./dbquery.pl -c 1 -ch 1 -f MYFILE.SQL 

One can also do variable replacement inside the SQL statement(s), both with the "-s" and "-f" options. This is done by specifying the "-r" 
option and defining some variables. The variable format is as follows:

	1=VALUE1,2=VALUE2,10=VALUE10..N=VALUEN

If you need spaces in the replacement value(s), enclose the whole option definition in quotes. Then in the statement ("-s"-option) or in the 
SQL-file ("-f"-option) write where the variable replacements are to be done by using the notation:

	{N}

where N is the variable number (see the replacement definition above). So with the statement examples above, you could write the following in 
the file:

	SELECT * from METADATA where entity={1}
	SELECT * from METADATA natural left join METADATAKEY where entity={1}

And then run the file with the following options:

	./dbquery.pl -c 1 -ch 1 -f MYFILE.SQL -r "1=1"

and then the "{1}"-variables in the text-file will be replaced with the value 1 in all relevant places. In this way, you can basically 
construct macros.

If you want to check the result of your replacements statements before actually running them, you can perform at replacement dry-run by using 
the "-rd" option and setting it to true. It will then do the replacements and print them to the screen without actually executing them.

## getentitytemplate.pl

Get aggregated dataset template for an entity.

The script takes the following parameters: entity id. The entity ID to get the dataset template of.

The script will return a dump of the aggregated template of the various defined metadata keys for the given entity.

## gettemplate.pl

Get a specific, defined template.

The script takes one parameter: template ID. The entity ID of the template to get.

The script will then get the template in question if it exists and dump its contents to the screen.

## mkcrypt.pl

Creates a new, random crypt.

Accepts no parameters.

Upon success returns the random-generated crypt.

## mksalt.pl

Creates a new, random salt.

Accepts no parameters.

Upon success returns the random-generated salt.

## modperm.pl

Modify permissions in the entity tree.

Modify parmissions for a subject/object pair.

Synopsis: modperm.pl subject object perm [ perm ...]

- subject - id of the subject, either numeric, Aurora username (email) or NTNU username.
- object - numeric if of the object
- perm - permission name

perm may include the following flags:

- "/" - add the permission bit to the deny mask instead of grant mask
- "-" - clear the bit instead of setting it

The first occurence of the flags will be recognized and removed from the permission name.

A perm parameter may contain a comma separated list for convenience.
A perm parameter of ADMIN,COMPUTERUSER,GROUPADM,GROUPMEMBER,GROUPGUEST,CREATE,COMPTER or DATASETALL will be expanded to the relevant set. 

A report of whats done is printed on STDOUT.

## permtree.pl

List permissions in the entity tree.

Synopsis: permtree.pl [subject [object [depth]]]

- subject - show only perms relevant for subject
- object  - show only perms relevant for and descendants
- depth   - limit dept of descendants so show

All parameters is numeric, 0 acting as undefined.

### Output format:

For each displayed object the path is displayed tab separated. Any permissions is displayed on the subsequent lines.

If subject i given, a list of the subjects roles if shown at the top. For each object in the listing the relevant permissions is shown like this:

- >[<inherited permission bits>]
- -[<deny bits>](<due to role>) = [<permission after deny bits is applied>]
- +[<grant bits>](<due to role>) = [<permission after grant bits is applied>]
- =[<resultant permission bits>]

If subjet is not given, any permissions on the object is listed:

- * <role>: -[<denybits>] +[<grant bits>]


## restcall.pl

Execute and test AURORA REST-server methods.

This script does not accept any parameters and will ask for input after being started. It requires a valid set of 
authentication credentials into AURORA in order to work.

When started it will ask for the connection details as follows:

- Authentication Type. The AURORA authentication type, defaults to AuroraID.
- Email-address. The email-address or username of the user.
- Authentication-string. The Authentication string/password of the user (it will not be visible).

The script will use the certificates that are located in the certs-subfolder of the utility-folder.

When the script has been started and the authentication details given, it will enter a loop where 
you can continue to write REST-calls as many times as you will. All rest-calls are given with name of 
the call followed by any potential parameters in JSON-notation. You can find an overview of REST-methods 
by checking out the REST-server documentation in the technical-part of the documentation.

So, in order to execute the REST-call "getName" and get the name of the root-entity, one would write 
the following:

	getName {"id":1}

And the script will then dump the response from the REST-server.

## restcmd.pl

Execute and test AURORA REST-server methods on the command-line.

The restcmd.pl script is self-contained and are not dependent upon any other libraries.

The script takes the following parameters in this order: [OPT] [OPTVALUE] [REST-CALL] [PARAMETERS].

The valid options are:

- -t Sets the authtype to use (AuroraID, OAuthAccessToken etc.). Defaults to AuroraID.
- -s Sets the authstr to use.
- -h Sets the hostname of the REST-server.
- -o Sets the port number of the REST-server. Defaults to 9393.
- -k Sets the path and name of the private key that the script uses.
- -p Sets the path and name of the public key that the script uses.
- -c Sets the path and name of the CA that the script uses.
- -v Sets verbose mode on the utility. Value that evaluates to true or false. Both JSON and Dumper-output of input and output data.

The REST-CALL is the name of the REST-server method in question, such as "getName". PARAMETERS are any potential parameters to the 
REST-server method. They are to be given in JSON-notation.

So, an example of a command-line execution of the getName-method would be:

	./restcmd.pl -t AuroraID -s "MY_PASSWORD" -h localhost -k ./certs/private.key -p ./certs/public.key -c ./certs/DigiCertCA.crt getName {"id":1}

And then the script will dump the reponse from the server. Please also note that if the script experiences any errors, either with 
the input parameters or in the response from the REST-server it will exit with an error code of 1. If everything went OK it will 
exit with an exit code of 0.

## saveaccessmatrix.pl

List who have access to DATASET and COMPUTER-resources/entities. The result is written to CSV-files using semi-colon as the 
separator.

The script takes only one parameter: PREFIX. The prefix sets the textual prefix to put on the two filesnames that the 
script generates when dumping the DATASET- and COMPUTER permissions. The data is written to the following two files:

	PREFIX-computers.csv
	PREFIX-datasets.csv

The column names are listed on the first line of each CSV.

The result shows who have access to read the data of various datasets and also which users have the permissions to 
access the various computers listed.

The intention is to create datasets that can be analyzed to pick out candidates that must be updated or changed.

## setperm.pl

Modify permissions in the entity tree.

It accepts the following parameters in this order: [[+|-|=]subject] [object] [grant|deny] [permnames-comma-separated]

The +/-/=-signs have the following meaning:

- &#43; means add these bits to exising bitmask
- &#45; means clear these bits from exiting bitmask
- = means replace bitmask with these bits (default)

Subject is the entity of which one is setting/changing the permissions of. Object is the entity that one wishes to set the 
permissions on. Grant or deny signifies if the change to permissions is to be a grant or deny setting. The last parameter 
"permnames-comma-separated] is a comma-seperated list of the permissions one can set.

Some grouped permissions are possible to specify by using their group-alias:

- ADMIN (all permissions possible).
- COMPUTERUSER = COMPUTER_READ.
- GROUPADM = DATASET_CHANGE,DATASET_CREATE,DATASET_DELETE,DATASET_LIST,DATASET_LOG_READ,DATASET_CLOSE,DATASET_METADATA_READ,
  DATASET_MOVE,DATASET_PERM_SET,DATASET_PUBLISH,DATASET_READ,DATASET_RERUN.
- GROUPMEMBER = DATASET_LIST,DATASET_LOG_READ,DATASET_METADATA_READ,DATASET_READ,DATASET_CREATE,DATASET_CLOSE.
- GROUPGUEST = DATASET_CREATE.
- CREATE = DATASET_CREATE.

## settemplate.pl

Modify/create a template.

The settemplate-script accepts parameters in two variants, either to create a template or to modify an existing template.

The parameters for these two variants are:

- Create: [0] [template-name] parent=value
- Modify: [tmpl] [keyname] [regex=value] [flags=value] [min=value] [max=value] [comment=value] [default=value]

In the create-variant, you start by specifying what would have been the template entity ID as 0. Since this is an invalid 
entity ID, it signifies that you want to create an entity instead of modifying it. The next parameter is the template name and 
the last is giving the parent entity ID by setting the parent-value (parent=N). The entity ID of the newly created template is 
written to the screen.

After you create a template, you can use the modify-variant of settemplate.pl to set the template for the newly created template. 

In order to modify a template, you start by specifying the templates entity ID (tmpl). After that you need to specify the key-name 
in the metadata space that you wish to set the template definition for. After this you have a series of attributes/constraints on the 
template key in question. These are:

- regex (the regex-expression to check the value of this key with)
- flags (the textual flags to set on the key)
- min (the minimum number of values allowed on this key)
- max (the maximum number of values allowed on this key)
- comment (textual comment that explains how the given key is to be answered/user and its constraints)
- default (default value(s) for the given key. Multiple defaults are given by using the comma-separator)

Please remember that when specifying the value part of a constraint/attribute, be careful about using space without quotes. Consider 
this:

	default=John Doe
	default="John Doe"

You have to invoke the script several times to set/modify several keys in the metadata name space.

Please see the documentation of the AuroraDB-library and/or user documentation for more information on how to use the 
attributes of the template and the metadata namespace.

## undelete.pl

Restore a dataset that is removed, ie moved out of sight, but not actually deleted. 

The FileInterfaceDataset->remove method move the dataset out of sight to be deleted later by maintaiance. Undelete reverses this process. 

Input parameters is a list of dataset id's to undelete. It seach the stores for the given datasets. The deleted datasets is restored if found. No action is done if it is not deleted, or multiple instances is found. A message is given on STDERR for each specified id.

If multiple instances is found the set in question should be manually inspected and cleaned up. This should not happen, but may possybly be result of errors in rare situations during creation/moving of datasets. Take care not to trash valid data.

