#!/usr/bin/perl -w
# Copyright (C) 2019-2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
#
# This file is part of AURORA, a system to store and manage science data.
#
# AURORA is free software: you can redistribute it and/or modify it under 
# the terms of the GNU General Public License as published by the Free 
# Software Foundation, either version 3 of the License, or (at your option) 
# any later version.
#
# AURORA is distributed in the hope that it will be useful, but WITHOUT ANY 
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with 
# AURORA. If not, see <https://www.gnu.org/licenses/>. 
#
use strict;
use lib qw(/usr/local/lib/aurora);
use AuroraVersion;
use Time::HiRes qw(time);
use Schema;
use SysSchema;
use SystemLogger;
use Settings;
use ErrorAlias;
use Log;
use Not;
use Notification;
use sectools;
use Socket qw( getaddrinfo getnameinfo SOCK_RAW NI_NUMERICHOST NIx_NOSERV AF_INET AF_INET6);
use HTTPSServer;
use Authenticator;
use Authenticator::AuroraID;
use Authenticator::OAuthAccessToken;
use Authenticator::Crumbs;
use AuroraDB;
use restserver::MethodsReuse;
use restserver::MethodsGeneral;
use restserver::MethodsAuth;
use restserver::MethodsInterface;
use restserver::MethodsComputer;
use restserver::MethodsDataset;
use restserver::MethodsGroup;
use restserver::MethodsNotice;
use restserver::MethodsStore;
use restserver::MethodsTemplate;
use restserver::MethodsUser;
use restserver::MethodsTask;
use restserver::MethodsScript;
use HTTP::Daemon;
use DBD::SQLite::Constants ':dbd_sqlite_string_mode';

# version constant
my $VERSION=$AuroraVersion::VERSION;

$SIG{HUP}=\&signalHandler;

# set base name
my $BASENAME="$0 AURORA REST-Server";
# set parent name
$0=$BASENAME." Daemon";
# set short name
our $SHORTNAME="RESTSRVC";

# set debug level
my $DEBUG="WARNING";

# get command line options (key=>value)
my %OPT=@ARGV;
%OPT=map {uc($_) => $OPT{$_}} keys %OPT;
# see if user has overridden debug setting
if (exists $OPT{"-D"}) { 
   my $d=$OPT{"-D"} || "WARNING";
   $DEBUG=$d;
}

# instantiate syslog logger
my $L=SystemLogger->new(ident=>"$BASENAME",priority=>$DEBUG);
if (!$L->open()) { die "Unable to open SystemLogger: ".$L->error(); }

$L->log("Using system loglevel $DEBUG for this process.","WARNING");

# load all system settings
my $CFG=Settings->new();
$CFG->load();

# create log instace
my $log=Log->new(location=>$CFG->value("system.log.location"),name=>$CFG->value("system.log.tablename"),
                 user=>$CFG->value("system.log.username"),pw=>$CFG->value("system.log.password"),
                 sqlite_string_mode=>DBD_SQLITE_STRING_MODE_UNICODE_FALLBACK);

if (!defined $log) {
   $L->log ("Failed to create Log instance...aborting","CRIT");
   exit(1);
}

# get ipv6 setting
my $ipv6=$CFG->value("system.rest.enableipv6") || 0;
my $family=($ipv6 == 1 ? AF_INET6 : AF_INET);
# create server-instance
our $srv=HTTPSServer->new(LocalHost=>$CFG->value("system.rest.host"),LocalPort=>$CFG->value("system.rest.port"),Listen=>$CFG->value("system.rest.listen"),
                         SSL_key_file=>$CFG->value("system.rest.privatekey"),
                         SSL_cert_file=>$CFG->value("system.rest.publickey"),
                         servername=>"Aurora REST-server",
                         Family=>$family,
                         settings=>$CFG,
                         log=>$log,
                         syslog=>$L,
                        );

# add all methods to server-instance by calling entity packages
# registermethod.
MethodsGeneral::registermethods($srv);
MethodsAuth::registermethods($srv);
MethodsUser::registermethods($srv);
MethodsGroup::registermethods($srv);
MethodsDataset::registermethods($srv);
MethodsComputer::registermethods($srv);
MethodsNotice::registermethods($srv);
MethodsTemplate::registermethods($srv);
MethodsTask::registermethods($srv);
MethodsInterface::registermethods($srv);
MethodsStore::registermethods($srv);
MethodsScript::registermethods($srv);

# set authentication handler
$srv->setAuthHandler(\&auroraAuthHandler);

# set database handler
$srv->setDBHandler(\&auroraDBHandler);

# show header
header();

# attempt to bind to interface
if (!$srv->bind()) {
   $L->log ("Unable to start server: ".$srv->error(),"CRIT");
   exit(0);
}

#print Dumper($srv);

# the loop method times out by default every 5 minutes.
# this can be adjusted by the HTTPSServer parameter Timeout set to the number of
# seconds for the desired timeout. A timeout of 0 does not disable timeout, so
# we continue to have an eternal loop as long as we are bound to the interface.
$L->log ("Aurora started at: ".time(),"INFO");
while ($srv->bound()) {
   if (!$srv->loop()) {
      $L->log ("Error! ".$srv->error(),"ERR");
   }
}

##### Aurora Authentication handling 

sub auroraAuthHandler {
   my $mess=shift;
   my $data=shift;
   my $db=shift;
   my $cfg=shift;
   my $log=shift;

   if ((defined $data) &&
       (defined $data->{authtype}) &&
       (defined $data->{authstr})) {
      # get auth type and string
      my $type=$data->{authtype} || "";
      $type=$SysSchema::CLEAN{authtype}->($type);
      my $str=$data->{authstr} || "";
      # go through each allowed auth methods and see if we have a match
      my @authmethods=@{($cfg->value("system.auth.methods"))[0]};
      my $userid=0;
      my $uid=0;
      my $username="N/A";
      my $found=0;
      my $auth;
      foreach (@authmethods) {
         my $m=$_;

         # match is case-sensitive in order to invoke actual Authenticator sub-class
         if ($type eq $m) {
            # match found - try to instantiate class
            my $atype="Authenticator::$type";
            my $err="";
            local $@;
            eval { $auth=$atype->new(db=>$db,cfg=>$cfg,query=>$data) || undef; };
            $@ =~ /nefarious/;
            $err = $@;            

            if (defined $auth) {
               $found=1;
               # attempt validation and input the authstr
               $userid=$auth->validate($str);
               # uid differs from userid in that it can be retrieved often even when
               # validate() fails.
               $uid=($userid > 0 ? $userid : $auth->id($str));
               # attempt to get email/username of user
               $username=$auth->email($str);
               $username=(defined $username && $uid > 0 ? $username : "N/A");
               # we are finished with the foreach-loop in any case
               last;
            } else {
               # something failed
               $err=(defined $err ? ": $err" : "");
               $mess->value("errstr","Unable to instantiate Authenticator-class $atype$err");
               $mess->value("err",$ErrorAlias::ERR{restinstfailed});
               return 0;
            }
         }
      }
      # set correct error message
      my $error;
      my $errcode=1;
      if (!$found) {
         $error="Invalid authentication type ($type) attempted";
         $errcode=$ErrorAlias::ERR{restinvalidtype};
      } elsif (!$userid) {
         $error="Validation of type $type failed: ".$auth->error();
         $errcode=$auth->errorcode();
      }

      # get modules allowed to use proxies
      my %pmods=map { $_ => 1; } @{($cfg->value("system.auth.proxy.modules"))[0]};

      # get proxy hosts
      my @proxies=@{($cfg->value("system.auth.proxy.hosts"))[0]};
      @proxies=(defined $proxies[0] ? @proxies : ());
      # set intial IP and Host
      my $ip = $data->{"SYSTEM_REMOTE_ADDR"};
      my $port = $data->{"SYSTEM_REMOTE_PORT"};
      my $realip = $Schema::CLEAN_GLOBAL{ip}->($data->{ip});
      my $realport = $SysSchema::CLEAN{port}->($data->{port})||0;
      my %proxies_map;

      # check if we are using an Authenticator module that
      # are allowed to use proxy
      if (exists $pmods{$type}) {
         # module is allowed....go through proxies and attempt to do dns resolving
         foreach (@proxies) {
            my $proxy = $_;
            # ipv4
            my @ipv4adr=getaddrinfo($proxy,"", {socktype => SOCK_RAW, family=>AF_INET});
            my @ipv4ni=(@ipv4adr == 1 ? () : getnameinfo($ipv4adr[1]->{addr},NI_NUMERICHOST, NIx_NOSERV));
            my $ipv4=(@ipv4ni == 1 ? "" : $ipv4ni[1]);
            # ipv6 
            my @ipv6adr=getaddrinfo($proxy,"", {socktype => SOCK_RAW, family=>AF_INET6});
            my @ipv6ni=(@ipv6adr == 1 ? () : getnameinfo($ipv6adr[1]->{addr},NI_NUMERICHOST, NIx_NOSERV));
            my $ipv6=(@ipv6ni == 1 ? "" : $ipv6ni[1]);
            # add combine ipv4 and ipv6 addresses
            my @adr;
            if ($ipv4 ne "") { push @adr,$ipv4; }
            if ($ipv6 ne "") { push @adr,$ipv6; }
            # add all addresses found to proxies map
            foreach (@adr) {
               $proxies_map{$_}=1;
            }
         }
         # if ip used is a proxy ip (web-server), if so use real IP-address if supplied
         if (exists $proxies_map{$ip}) {
            # check if real ip is supplied from trusted proxy-host
            if ($realip) {
               # set ip to the real ip and host being used.
               $ip=$realip;
               $port=$realport;
            }
         }
      }

      if ((!$userid) || (!$found)) {
         # log failure to login
         # first store in USERLOG - no checking of failure here...
         $db->doSQL("INSERT INTO USERLOG (timedate,entity,tag,message) VALUES (".time().",0,\"LOGIN FAILURE\",\"Login failure from $ip:$port using $type for user $uid ($username) : $error ($errcode)\")");
         # notify caller of failure
         $mess->value("errstr","$error");
         $mess->value("err",$errcode);

         return 0;
      }

      # get which auth types that are to be logged upon success
      # all types are logged upon failure (see above)
      my @authlog=@{($cfg->value("system.auth.log.success"))[0]};
      @authlog=(defined $authlog[0] ? @authlog : ());
      my %alog=map { $_ => 1; } @authlog;

      # check that authtype is set to a type that exists in the 
      # success-log setting
      if (exists $alog{$type}) {
         # log to USERLOG success in authenticating, no checking for success
         $db->doSQL("INSERT INTO USERLOG (timedate,entity,tag,message) VALUES (".time().",$userid,\"LOGIN SUCCESS\",\"Login success from $ip:$port using $type for user $userid ($username)\")");
      }

      # return the resulting userid
      return $userid;
   } else {
      # missing input data
      $mess->value("errstr","Unable to authenticate login because of missing parameter input: authtype and authstr needed.");
      $mess->value("err",$ErrorAlias::ERR{restmissingpar});
      return 0;
   }
}

##### Aurora DB Handler

sub auroraDBHandler {
   my $mess = shift;
   my $db = shift;
   my $cfg = shift;
   my $log = shift;

   if (!defined $db) {
      # no database instance - create one
      $db=AuroraDB->new(data_source=>$cfg->value("system.database.datasource"),user=>$cfg->value("system.database.user"),
                        pw=>$cfg->value("system.database.pw"));
   }

   # connect if not connected
   my $dbi=$db->getDBI();

   if (!defined $dbi) {
      $mess->value("errstr","REST-server is unable to get DBI handler: ".$db->error());
      $mess->value("err",1);
      return undef;
   } elsif (!$db->connected()) {
      $mess->value("errstr","REST-server is not connected to database. Unable to proceed.");
      $mess->value("err",1);
      return undef;   
   }

   # return db instance
   return $db;
}

##### Aurora div

# use a placeholder for methods not implemented yet
sub not_implemented_yet {
   my ($content,$query,$db,$userid,$cfg,$log)=@_;

   # set return values
   $content->value("errstr","Method has not been implemented yet. Please try again later.");
   $content->value("err",1);

   return 1;
}

sub header {
   print "$BASENAME, version $VERSION, (C) 2019 NTNU, Trondheim, Norway\n";
   print "\n";

   return 1;
}

sub signalHandler {
   my $sig=shift;

   if ($sig eq "HUP") {
      # handle HUP by reloading config-file
      if ($CFG->load("system.yaml")) {
         $L->log("Successfully reloaded configuration file.","WARNING");
      } else {
         $L->log("Unable to load configuration file: ".$CFG->error().". Keeping existing settings.","ERR");
      }
   }
}

__END__

=encoding UTF-8

=head1 AURORA REST-Server Overview and Methods

=head2 General overview

This is the AURORA REST-server which serves requests and responses to and from the AURORA database and system.

For more information and in order to understand the entity tree of AURORA and how the various parts interact, 
please read the "AURORA Systems Overview"-document.

The AURORA REST-server is as the name suggests based upon the REST principles. However, it does not use various 
HTTP-methods based on what is being asked (such as "GET", "DELETE", "MOVE" etc.). Instead the method is 
implemented as a name directly under the server root, such as eg.:

  /getTree

All HTTP-requests to the server must be sent as HTTP POST-requests. All requests are only served over HTTPS/SSL.

All method names starts with a verb describing what one wishes to do, eg.: get, delete, move, list, check and so on 
and so forth. Then that is followed by the entity type, such as eg.: Computer, Group, Dataset and so on and so 
forth (the subject). A few methods will not be associated with any entity types and as such will not have this as 
the second part of the method name (such as I<getTree>). The last part of the method name will be the object of the 
verb (ie. what to get, delete, move and so on). Sometimes this will be the entity type as well, such as with the 
method-name: I<moveComputer>.

The naming scheme of the methods also starts with a lower case letter and all subsequent words have an uppercase 
letter, eg: I<moveComputer>, I<checkTemplateCompliance>, I<listComputerFolder> and so on and so forth.

In the same manner the AURORA REST-server has standardized its input and output parameters and return data based 
upon the method-name and some selected names. In most cases a parameter like "id" means the "id" of the subject/
object of the method when used as input. Eg. I<moveComputer> takes "id" as parameter of the computer that one 
wants to move, I<checkTemplateCompliance> takes "id" as the entity to check the template compliance for and
I<getComputerMetadata> takes "id" as the computer to get the metadata of (and so on and so forth). Another input 
parameter that is common in many instances is "parent" and is usually used to signify the group entity that is 
the parent of the entity in question. This is eg. used with I<moveComputer>, I<moveGroup> etc.

When it comes to output/result from the various methods, the result always comes in the structure named after 
the object of the request. So for example, I<getComputerMetadata> will return the metadata in a sub-hash that 
is called "metadata". In the method I<enumTemplates> the templates will be returned in a sub-hash called 
"templates".

All method requests to the AURORA REST-server uses JSON as encoding and HTTP POST as the HTTP-method.

All requests to the REST-server needs to contain authentication information, since all calls needs to be authenticated. 
Even so, the server optimizes its mode of operation and one can choose to connect to it by setting the keepalive-flag, so 
that each subsequent call uses the same established connection. However, no session data is kept and it is still 
required to authenticate for each call. 

The authentication parameters are: authtype and authstr. The first B<authtype> sets the authentication type to use. AURORA 
supports plugin classes for authentication and are also supplied with its own native AuroraID authentication type as well 
as OAuth-based authentication (SSO) called OAuthAccessToken. So if one wants to authenticate with the native AuroraID 
authentication, one sets authtype to "AuroraID" (the name is case sensitive, so be careful to get it right). The other 
parameter B<authstr> sets the corresponding authentication string that matches the chosen authtype. Usually all authstr 
parameters will contain an email and then some sort of cookie/string or password. In the case of AuroraID the format of 
the authstr is as follows:

  email,password

or eg.:

  myname@mydomain.org,ThisIsMySecretPassword1234

In addition to the authstr and authtype parameters, each REST-server method has its own requirements which can be perused 
in this very document.

So, eg. for the call moveComputer, one would send a json string which looks like this:

  { "authtype":"AuroraID","authstr":"myname@mydomain.org,ThisIsMySecretPassword1234","id":314,"parent":413 }

In addition to these parameter requirements for REST-server methods, it might also be some permission requirements that 
the user has to fulfill in order to be allowed to successfully run it. These requirements will also be outlined the 
documentation of the method.

The REST-server will after B<all> method calls issue a response. This response is also in JSON and is a HASH-structure 
which looks like this:

  "received": STRING # unix datetime (UTC) with hires microseconds for when the request was received by the REST-server
  "delivered": STRING # unix datetime (UTC) with hires microseconds for when the request reponse was sent by the REST-server
  "err": INTEGER # 0 for no error, 1 for error.
  "errstr": STRING # the failure reason upon an error, blank if no error.

The key-values will always be there in all method responses. In addition to these "global" response values, the various 
REST-methods will add additional key->values and sub-keys or hashes. These additional responses are documented in the 
REST-server method description itself.

The time format that are mentioned in the "received" and "delivered" response-values are unix datetime in high resolution 
format. The time is in UTC without any locales. This means that they come out like (string of float):

  12345678.54321

where the hires part is after the dot "." in microseconds.

Some methods will even return sub-hashes. Eg. the getAggregatedTemplate-method will give you the mentioned global values 
and in addition a sub-hash called "template" (after the object of the method, the subject being the system or entity tree):

  {"delivered":1593585453.44301,"received":1593585453.39645,"errstr":"","err":0,"template":{"system.user.username":{"comment":"This is the users email address","max":"1","flags":["MANDATORY","NONOVERRIDE"],"min":"1","regex":"[a-zA-Z]{1}[a-zA-Z0-9\\.\\!\\#$\\%\\%\\&\\'\\*\\+\\-\\/\\=\\?\\^\\_\\`\\{\\|\\}\\~\\@]+","default":null},"system.user.fullname":{"default":null,"regex":"[^\\000-\\037\\177]+","min":"1","max":"1","flags":["MANDATORY","NONOVERRIDE"],"comment":"This is the users full name. Accepts all non-special characters"}}}

=cut

=head2 Calling the REST-server

One can use many different libraries or software to connect to the AURORA REST-server as long as they support REST-type servers 
(basically HTTP). It is also possible to do REST-server calls by using the curl-command in linux like so:

  curl -v -k -d '{"authtype":"AuroraID","authstr":"myname@mydomain.org,ThisIsMySecretPassword1234","id":314,"type":"COMPUTER"}' -H "Content-Type: application/json; charset=utf-8" https://localhost:1000/getAggregatedTemplate

Alternately if you are not comfortable with saving your AURORA authentication details in the history through the 
the command line, you can put the JSON structure inside a file instead:

  curl -v -k -d @myjsonfilename -H "Content-Type: application/json; charset=utf-8" https://localhost:1000/getAggregatedTemplate

=cut

=head2 Permissions

The AURORA system has a rich system of permissions and all the various permissions can be set in the entire tree, but only 
on GROUP-, DATASET- and TEMPLATE entities. All permissions set will be inherited down the tree if not denied on the way 
down, which in essence means that only GROUP-permissions are inherited since the other entity types always resides at 
branch ends of the tree.

AURORA enforces a permissions scheme where the right to perform a method depends on the users permissions on the entity 
being manipulated. The permission must either reside on the entity itself or come down through inheritance. Note, however, 
that in most cases the system will allow the operation if the user in question has the correct permission on the parent of 
the entity being manipulated (also through inheritance on the parent). The reason for this is to avoid a scenario where 
denied permissions will lock users from manipulating or seeing entities.

Furthermore, the AURORA-system enforces the following rule when it comes to setting permissions: the user is only allowed 
to set/give away permissions that he himself has on the entity in question. This is to avoid security defects where 
having the right to set permissions gives you the option to elevate your own set of permissions, thereby achieving 
godhood (well, at least in that small part of the hood).

All permissions to and from the AURORA REST-server is specified in textual/string format. All permissions start with the 
entity type name, such as DATASET, TEMPLATE, GROUP and so on. Examples of permission names are:

  DATASET_CREATE
  DATASET_MOVE
  GROUP_CREATE
  GROUP_CHANGE

and so and so forth. All permission names are also uppercase, but the methods are case-insensitive when it comes to 
specifying the permission name. The permission name might not have a uniform meaning between methods as some methods 
might sometimes use the permission to signify certain permission variants relevant to that method. This is not the 
default use and meaning of the permissions, but if such cases exist, they will be documented in the method in question.

So, eg. the permission DATASET_CREATE obviously means that one has the permission to create a dataset on whatever 
group that one has this permission on. However, this permission is also used by the getTree() REST-method to signify that 
the user is not allowed to list or view (see that it exists) that dataset if he B<only> has this permission on it. This 
touches upon the implicit permissions one has through having certain other permissions. In this example, one has the 
permission to view or list a dataset (not read its data or metadata) when one has any other DATASET-permission, except 
DATASET_CREATE.

Also, upon creating a dataset, the AURORA-system will assign all dataset permissions to the creating user on the dataset 
being created, with the exception of DATASET_DELETE, DATASET_MOVE and DATASET_EXTEND_UNLIMITED. This mechanism is to underline the 
fact that it is the parental group that owns the dataset and therefore manages both its location (move) as well as its state 
(delete). The DATASET_EXTEND_UNLIMITED is an admin-type permission that allows the holder to extend the expire-date unlimited 
beyond any expire-policy in the entity tree.

=cut

=head2 SQLStruct

When doing more sophisticated database operations in the AURORA REST-server it utilizes a structure called SQLStruct (for more technical 
details see the documentation of the SQLStruct-module). This structure makes it possible to define more refined SQL 
search parameters without actually writing SQL and are used by eg. the getDatasets()-method. The SQLStruct structure can 
either be a HASH or an ARRAY, while some methods might enforce one or the other (getDatasets()-method requires the main 
structure to be an ARRAY as in the example below).

The SQLStruct might look like this:

  SQLStruct = ( 'OR', # First ARRAY element is ALWAYS the logical operator (LOP) of the ARRAY.
              { 'Creator' => 'Bård', # second ARRAY element is a HASH with key "Creator"
                'Created' => { '>' => '1990', '<' => '2000' }  # next HASH key is "Created" pointing to a sub-hash comparing years with LOP "AND".
              },        
              { 'Creator' => 'Jan Frode*', # third ARRAY element is a HASH with key "Creator" equals a name and then a wildcard
              },
              { 'Religion' => { '!' => "NULL", '-' => "NULL" } # fourth ARRAY element  is a HASH with a key "Religion" pointing to a sub-hash with a nonsensical comparison, of which nonsense religion sometimes mimicks.
              },
              '1', # fifth ARRAY element is just the value 1 (which will evaluate to true)
              [ 'not',   # the sixth ARRAY element is last and contains an sub-ARRAY, which again has a sub-HASH and so on.
                { 'Group' => 'Whatever',
                },
               '11'
              ],
              )

As you can see, both ARRAYS, HASHES and STRINGS are allowed within the structure itself. In the example above Perl 
notation has been used. "()" is an ARRAY, "{}" is a HASH, "[]" is a ARRAY-reference. "=>" is a value assignment for a 
key in a HASH.

SQLStruct has the following rule about the difference between an ARRAY and a HASH:

=over

=item

B<ARRAYS> makes it possible to define the logical operator (LOP) between its elements. The first element is ALWAYS to be 
the LOP (valid LOPs are: OR,AND,NOT,ALL,ANY,BETWEEN,EXISTS,IN,LIKE and SOME). The LOP is case-insensitive. Please be aware 
that not all logical operators that are supported by SQLStruct in this list might be supported by the underlying SQL-engine.

=cut

=item

B<HASHES> cannot define any LOP between its keys and all keys in the HASH are processed together using the logical 
operator "AND".

=cut

=back

HASHES are used with various comparative operators (COP). The key or sub-key can be used to define the following 
valid COPs:  

  ">"    # greater than
  "<"    # lesser than
  "<>"   # not equal to
  "="    # equal to
  ">="   # greater than or equal
  "<="   # lesser than or equal
  "!"    # is not
  "-"    # not
  "&"    # bitwise and
  "|"    # bitwise or
  "^"    # bitwise xor

If the key is not a COP it must be a key-name that one wants to compare to a value in the following hash assignment:

  KEYNAME => VALUE  # the value can contain wildcards

Values that the COPs are used with can contain wildcards in the form of "*". If one wishes to use "*" as a value in and 
of itself, the value must be escaped.

=cut

The rest (no pun intended) of this document will deal with the various methods of the AURORA REST-server and their use and 
requirements.
