#!/usr/bin/perl -wT
# Copyright (C) 2019-2024 Bård Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway
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

use Settings;
use AuroraDB;
use Digest::SHA;
use YAML::XS qw();
use Time::HiRes qw(time);
use ISO8601;
use Net::LDAP;
use Sys::Syslog;

# test environment on login.*.ntnu.no:
#    perl -e 'use lib "."; use FileInterface2; use FileInterface2_testADB; use Data::Dumper; $fi=FileInterface->new(TestADB->adb); my $d=$fi->dataset($ARGV[0]); print Dumper({created=>$d->create||undef, result=>$d->perm});' 5551


my $CFG = Settings->new(); $CFG->load();

my $BASE        = $CFG->value('fileinterface.base')        || '/aurora'; $BASE =~ /^(.*)$/; $BASE = $1;
my $OAUTHDOMAIN = $CFG->value('fileinterface.oauthdomain') || "ntnu.no";
my $HTTP        = $CFG->value('system.www.base')           || 'https://www.aurora.it.ntnu.no/';
my $ACTION_HREF = $CFG->value('fileinterface.action')      || 'https://www.aurora.it.ntnu.no/id-verb.cgi?%2$d-%1$s';


#my $BASE = "/home/ahomed/b/bt/public_html/auroratest/Aurora";
#my $HTTP = "DUMMY";

package FileInterface; #<
use File::Path qw(make_path remove_tree);
use Time::HiRes qw(time);
use Encode;

my $ALGORITM = "SHA-256";
my $SecretTTL = 1; # Cache liftime for secret file;

my @CookieCHARS = ('a'..'z','A'..'Z');
my $CookieLENGTH = 32;

sub new {                                      #< Constructor
    my $class = shift;                         #
    my $AuroraDB = shift;                      #< AuroraDB object(opt), default Auroradb->new()
    my $base = shift || $BASE;                 #< Aurora file tree location (opt)
    my $http = shift || $HTTP;                 #< Aurora web interface location (opt)
    #
    my $self = bless({}, $class);
    bless($self, $class);
    $self->{adb} = $AuroraDB;
    $self->{Settings} = $CFG;
    $self->{config}{base} = $base;
    $self->{config}{http} = $http;
    $self->{config}{cache_ttl} = 10;
    $self->{config}{cookie_life} = 600;
    $self->{yell} = [];
    $self->{cache} = {};
    $self->{FI} = $self;
    return $self;
}

sub FI { return shift->{FI}; }                 #< Get the FileInterface object
sub Settings {return shift->FI->{Settings}; }
sub adb {                                      #< Get the AuroraDB object
    my $self = shift->FI;
    $self->{adb} = shift if @_;
    unless ($self->{adb}) {
        my $CFG = $self->Settings;
        $self->{adb} = AuroraDB->new(
            data_source=>$CFG->value("system.database.datasource"),
            user=>$CFG->value("system.database.user"),
            pw=>$CFG->value("system.database.pw")
            );
    }
    return $self->{adb};
}
sub dbi { shift->adb->getDBI; }

sub base { return shift->FI->{config}{base}; }        #< Get the configured base directory
sub absolute { return join("/", shift->base, @_); }   #< Join base() and arguuments with "/"

sub flush {
    my $self = shift->FI;
    $self->{cache} = {};
}

sub dataset {                                 #< Return an dataset object for the first argument
    my $self = shift->FI;
    my $dataset = shift;
    if (my $isa = ref($dataset)) {
        if ($isa eq "HASH") {
            return FileInterfaceDataset->new($self, $dataset);
        }
        else {
            return $dataset
        }
    }
    else {
        return FileInterfaceDataset->get($self, $dataset);
    }
}



#          --- General utillity functions ---


sub yell { #< Warning stacker
    # yell('Mayday') and return;    
    # yell() - yelled?
    # yell(undef, expr) - return undef if yelled, else expr
    # yell(message[,message...]) - yell! - stack message(s).
    # yell('!',...) - Yell unless already yelling. Short for "yell() or yell(...)".
    # yell('?',...) - Join the choir if already yelling. Short for "yell() and yell(...)". Overides '!'.
    # yell('>',...) - Clear after yelling. "warn yell('>', ...);" is short for "warn yell(...); yell('<');"
    # yell('<') - Cancel any yell.
    # yell('<',message[,message,...]) - Clear before yelling, ie replace messages.
    # yell('?<>', messages) - If yelling, return this messages (true) and clear the yell. 
    # $value = may_return_undef_or_false() or yell() and return; - return if sub is yelling.
    #
    my $self = shift->FI;
    my $method=(caller(1))[3];

    if (@_ == 2 and !defined($_[0])) { return $self->yell ? undef : $_[1]; } 
    my $flags = (@_ and $_[0] =~ /^[?!<>]*$/) ? shift : '';
    if ($flags =~ /\?/) { # yell('?', $message) short for yell() and yell($message)
	return unless @{$self->{yell}};
    }
    elsif ($flags =~ /\!/) { # yell('!', $message) short for yell() or yell($message)
	return if @{$self->{yell}};
	shift;
    }
    my $clearatend = 0;
    if ($flags =~ /\>/) {
	$clearatend = 1;
	shift;
    }
    if ($flags =~ /\</) { # Clear yell;
	$self->{yell} = [];
	shift;
    }
    foreach (@_) {
	my $message = ref($_) ? $_ : "$method: $_";
	push(@{$self->{yell}}, $message);
    }

    my @yell = ();
    @yell = @{$self->{yell}} if exists $self->{yell};
    $self->{yell} = [] if $clearatend;
    return @yell;
}

sub ensurepath {
    my $self = shift;
    my $path = shift;
    my $mode = shift || 0711;
    #
    my $err;
    File::Path::make_path( $path,
               { error => \$err,
                 chmod => $mode,
                 verbose => 0,
               }
        );
    if (@$err) {
        $self->yell(map { values(%$_);  } @$err);
        return;
    }
    return $path;
}
sub newcookie { return join('', map { $CookieCHARS[int rand(@CookieCHARS)]; } 1..$CookieLENGTH); }

sub rellink {
    my $self = shift;
    my $file = shift;
    my $link = shift;
    my $mode = shift || 0711;
    #
    my @file = split(/\//, $file);
    my @link = split(/\//, $link);
    while (@file and @link and $file[0] eq $link[0]) {
        shift(@file);
        shift(@link);
    }
    $self->yell("rellink into it self: $link -> $file") and return unless @link; 
    for (my $up=1; $up<@link; $up++) { unshift(@file, ".."); }
    my $rfile = join("/", @file);
    unlink($link) or $self->yell("unlink($link): $!") and return if lstat($link);
    (my $linkdir = $link) =~ s|/[^/]*$||;
    my $err;
    $self->ensurepath($linkdir);
    symlink($rfile, $link) or $self->yell("symlink($rfile, $link): $!") and return;
    return $rfile;
}

sub selectstore { #< Select a online storage baset on supplied leafe nodes. 
    my $self = shift;
    my @hints = @_;
    #
    # expand candidate list with path and roles if numeric
    my @candidates = (1);
    foreach (reverse @hints) {
        if (/^\d+$/) {
            push( @candidates,
                  $self->adb->getEntityPath($_),
                  $self->adb->getEntityRoles($_),
                );
        }
    }
    #
    # Remove duplicates starting from from head
    my %seen = ();
    @candidates = grep { my $seen = $seen{$_}; $seen{$_} = 1; !$seen; } @candidates;
    #
    # Search for first system.fileinterface.store among candidates from tail
    my $found;
    while (not $found and my $entity = pop(@candidates)) {
        my $metadata = $self->adb->getEntityMetadata($entity);
        if ( $metadata and exists $metadata->{'system.fileinterface.store'}) {
            $found = $metadata->{'system.fileinterface.store'};
        }
    }
    $self->yell("No storage candidate found")        and return unless $found;
    $self->yell("Storage $found not available")      and return unless $self->storewcheck($found);
    return $found;
}

sub storewcheck { #< Check if a store is online and have rw folder.
    my $self = shift;
    my $store = shift;
    #
    my $FSre = '[0-9a-zA-Z_-]+';
    #
    $self->yell("Invalid storage name: $store")       and return unless $store and $store =~ /^($FSre)$/;
    my $probe = $self->absolute("fi-$1/rw/.storewcheck");
    $self->yell("Storage $store ($probe) is not writable: $!") and return unless open(RW, '>>', $probe); # No rw: possibly offline
    close(RW);
    unlink($probe) or $self->yell("unlink($probe): $!");
    return 1;
}

sub storeprobe {
    my $self = shift;
    #
    my $dbi = $self->dbi;
    my $known = $dbi->selectall_arrayref("select distinct store,mode from FI_DATASET join FI_MODE using (perm)");
    $self->yell($dbi->errstr) and return if $dbi->err;
    my %stat = ();
    foreach my $row (@$known) {
        my ($store, $mode) = @$row;
        my $name = "$mode-$store";
        my @stat = stat($self->absolute($name, '.'));
        if (@stat) {
            $stat{$name} = \@stat;
        }
        else {
            $self->yell("stat($name): $!");
            $stat{$name} = undef;
        }
    }
    return \%stat;
}

sub storescan {
    my $self = shift;
    my @stores = @_;
    #
    my $base = $self->absolute;
    unless (@stores) {
        $self->storeprobe;
        if (opendir STORES, $base) {
            my %seen = ();
            push(@stores, "view");
            foreach (readdir(STORES)) {
                next unless /^(rw|ro)-\w+$/; # Only scan ro-/rw- storage
                my @stat = stat("$base/$_/.");
                $self->yell("stat($base/$_/.):$!") and next unless @stat;
                my $inode = join(":", @stat[0,1]);
                warn "$inode $_";
                next if $seen{$inode}++;
                push(@stores, $_);
            }
        }
        else { $self->yell("opendir($base): $!") and return; }
    }
    #
    my $found;
    foreach my $store (@stores) {
        if (opendir STORE, "$base/$store") {
            foreach my $L1 (readdir STORE) {
                next unless $L1 =~ /^\d+$/;
                if (opendir L1, "$base/$store/$L1") {
                    foreach my $L2 (readdir L1) {
                        next unless $L2 =~ /^\d+$/;
                        if (opendir L2, "$base/$store/$L1/$L2") {
                            foreach my $id (readdir L2) {
                                next unless $id =~ /^\d+$/;
                                if (int($id/1000) == $L1 * 1000 + $L2) {
                                    push(@{$found->{$id}}, $store);
                                }
                                else {
                                    $self->yell("Misplaced: base/$store/$L1/$L2/$id");
                                }
                            }
                        }
                        else { $self->yell("opendir($base/$store/$L1/$L2): $!"); }
                    }
                }
                else { $self->yell("opendir($base/$store/$L1): $!"); }
            }
        }
        else { $self->yell("opendir($base/$store/): $!"); }
    }
    return $found;
}

sub storelint {
    my $self = shift;
    #
    my %log;
    my $scan = $self->storescan or return;
    foreach my $id (keys %$scan) {
        if (my $dataset = $self->dataset($id)) {
            my @found = grep(!/^view$/, @{$scan->{$id}});
            if (@found == @{$scan->{$id}}) { # No view
                if (@found == 1) {           # and no duplicates
                    my $found = $found[0];
                    #
                    # Build cache..
                    my ($mode, $store) = $found =~ /^(\w+)-(\w+)$/; 
                    $dataset->save($store, $mode, "dummy");
                    # ... and view
                    $self->rellink(
                        $self->absolute($dataset->linkpath),
                        $self->absolute($dataset->datasetpath),
                        );
                    # ... get cookie with lint()
                    $log{$id} = $dataset->lint;
                    push(@{$log{$id}{done}}, "$id linked to $found");
                }
                else {
                    # No view and multiple candidates - resolve manually
                    push(@{$log{$id}{error}}, "Ambiguous $id found at: @found");
                }
            }
            else {  # View exists
                my $store = $dataset->store;
                unless ($store) { # Seem to be missing in cache - use lint()
                    warn $id;
                    $log{$id} = $dataset->lint;
                    $store = $dataset->store || '';
                }
                my $mode = $dataset->mode || '';
                my @excess = grep(!/^$mode-$store$/, @found);
                if (@excess) {
                    push(@{$log{$id}{warning}}, "Excess data for $id found at @excess");
                }
                else {
                    # Operation normal
                    # $log{$id} = undef unless exists $log{$id};
                }
            } 
            $self->flush; # Flush cache to conserve memory
        }
        else {
            my @found = @{$scan->{$id}};
            push(@{$log{$id}{error}}, "Unknown $id found at: @found");
        }
    }
    return \%log;
}

sub grantpath {
    my $self = shift;
    my $subject = shift;
    my $keycode = shift;
    my $dataset = shift;
    unless (defined $keycode) {
        if (exists $self->{cache}{keycode}{$subject}) {
            $keycode = $self->{cache}{keycode}{$subject};
        }
        else {
            $keycode = $self->newcookie;
            my $dbi = $self->dbi;
            my $keycode_q = $dbi->quote($keycode);
            $dbi->do("insert into FI_SUBJECT values($subject,$keycode_q,NULL,0)")
                or $self->yell($dbi->errstr) and return;
            my $view = $self->grantpathview($subject,$keycode);
            $self->ensurepath($self->absolute($view)) or return;
            chmod(0755, $self->absolute($view));
            $self->{cache}{keycode}{$subject} = $keycode;
        }
    }
    return join("/", $self->grantpathview($subject,$keycode), $dataset);
}
sub grantpathview {
    my $self = shift;
    my $subject = shift;
    my $keycode = shift;
    return sprintf( "view/%03d/%03d/%d-%s",
                    ($subject / 1000000) % 1000,
                    ($subject / 1000) % 1000,
                    $subject,
                    $keycode,
        );
}

sub purge {
    my $self = shift;
    #
    my $soucetime = $self->adb->getMtime("PERM_EFFECTIVE_PERMS");
    my $start = time();
    #
    $self->purge_deny;
    $self->purge_grant;
    $self->adb->setMtime("FI_GRANTED", $soucetime);
    $self->purge_user(@_);
}

sub purge_needed {
    my $self = shift;
    my $adb = $self->adb;
    return $adb->getMtime("FI_GRANTED") ne $adb->getMtime("PERM_EFFECTIVE_PERMS") ? 1 : 0;
}

sub purge_deny {
    my $self = shift;
    my $dbi = $self->dbi;
    #
    my $query = $dbi->prepare("select subject,keycode,dataset from FI_DENY")
        or             $self->yell($dbi->errstr) and return;
    $query->execute or $self->yell($dbi->errstr) and return;
    my $changes = 0;
    while (my @row = $query->fetchrow_array) {
        my ($subject,$keycode,$dataset) = @row;
        $changes += 1;
        unlink($self->absolute($self->grantpath($subject,$keycode,$dataset)))
            or $self->yell("unlink(@row): $!") and return;
        $dbi->do("delete from FI_GRANTED where subject=$subject and dataset=$dataset")
            or $self->yell($dbi->errstr) and return;
    }
    return $changes;
}

sub purge_grant {
    my $self = shift;
    my $dbi = $self->dbi;
    #
    my $query = $dbi->prepare("select privatepath,perm,subject,keycode,dataset from FI_GRANT")
        or             $self->yell($dbi->errstr) and return;
    $query->execute or $self->yell($dbi->errstr) and return;
    my $changes = 0;
    while (my @row = $query->fetchrow_array) {
        my ($target,$perm,$subject,$keycode,$dataset) = @row;
        $changes += 1;
        $self->rellink(
            $self->absolute($target),
            $self->absolute($self->grantpath($subject,$keycode,$dataset)),
            ) or return;
        $dbi->do("insert into FI_GRANTED(subject,dataset,perm) values($subject,$dataset,$perm)")
            or $self->yell($dbi->errstr) and return;
    }
    return $changes;
}

sub purge_user {
    my $self = shift;
    my $retryage = shift                  || 10;                                           ###
    my $metadatakey = shift               || "system.authenticator.oauthaccesstoken.user"; ###
    return unless $metadatakey;
    #
    my $dbi = $self->dbi;
    my $metadatakey_q = $dbi->quote($metadatakey);
    #
    my $tmo = time() - $retryage;
    my $query = $dbi->prepare( "
                               select subject,keycode,username,uid,metadataval 
                               from FI_SUBJECT S
                               join METADATA M
                                   on  M.entity=S.subject
                                   and metadataidx=1
                               join METADATAKEY K
                                   on  K.metadatakey=M.metadatakey
                                   and K.metadatakeyname=$metadatakey_q
                               where username is NULL and uid < $tmo
                               ") or $self->yell($dbi->errstr) and return;
    $query->execute or $self->yell($dbi->errstr) and return;
    while (my @row = $query->fetchrow_array) {
        my ($subject, $keycode, $username, $uid, $userstring) = @row;
        #
        # Postpone next check for this subject if the rest is failing.
        my $now = int(time());
        $dbi->do( "
                  update FI_SUBJECT set uid=$now 
                  where subject=$subject
                  ") or warn $dbi->errstr;
        #
        # Map the userstring to username and uid
        my $pw;
        ($username, $pw, $uid) = $self->mapuserstring($userstring, @_);
        next unless $uid;
        #
        # Create the userpath
        my $userpath = "view/user/$username";
        $self->ensurepath($self->absolute($userpath), 0711) or next;
        $userpath = $self->absolute($userpath);
        $self->rellink(
            $self->absolute("view/user/.ACTIONS"),
            "$userpath/ACTIONS",
            );
        #
        # Link ALL to grantpathview
        my $grantpathview = $self->absolute($self->grantpathview($subject, $keycode));
        $self->rellink(
            $grantpathview,
            "$userpath/ALL",
            ) or next;
        #
        chown($uid, 0, $userpath) or $self->yell("chown($userpath): $!");
        chmod(0500,    $userpath) or $self->yell("chmod($userpath): $!");
        #
        # Update FI_SUBJECT on succes
        my $username_q = $dbi->quote($username);
        $dbi->do( "
                  update FI_SUBJECT
                  set username=$username_q,
                      uid=$uid
                  where subject=$subject
                  ") or warn $dbi->errstr;
    }
    my $yell = $self->FI->{yell};
    return if @$yell;
    return 1;
}

sub hrconfig {
    my $self = shift;
    #
    my $dbi = $self->dbi;
    #
    # get rellevant entities
    my $entities = $dbi->selectall_hashref(
        'select * from FI_SUBJECT where username is not null',
        'subject',
        ) or return;
    #
    # Get key for system.fileinterface.hrconfig;
    my $configkey = $self->adb->getMetadataKey('system.fileinterface.hrconfig') or return;
    #
    # Read tree from bottom up (may consider only USERS and GROUPS ...)
    my $q = $dbi->prepare("
                          select E.entity,E.entityparent,M.metadataval,S.sequence
                          from ENTITY E
                          join ENTITY_SEQUENCE S on S.entity=E.entity
                          left join METADATA M on M.entity=E.entity and metadatakey=? and metadataidx=1
                          order by S.sequence desc;
                          ") or return;
    $q->execute($configkey) or return;
    #
    # Extract config for revevant entities.
    my %sequenced = ();                                               # Sequenced pointers into $entities.
    while (my @row = $q->fetchrow_array) {
        my ($entity,$parent,$config,$sequence) = @row;
        next if not $entities->{$entity};                             # Skip irelevant entries
        unless (exists $entities->{$parent}) {                        # Make sure parent is relevant
            $entities->{$parent} = { childs => [] };
        }
        my $self = $entities->{$entity};
        my $dad = $entities->{$parent};
        $self->{parent} = $dad;                                       # Link parent to child
        push(@{$dad->{childs}}, $self);                               # Link child to parent
        $self->{config} = $config;
        $sequenced{$sequence} = $self;
    }
    #
    # Parse config top down;
    use JSON::XS;
    foreach my $this (sort { $a <=> $b } keys %sequenced) {
        my $self = $sequenced{$this};
        my $parent = $self->{parent};
        if (defined $self->{config}) {
            eval { $self->{config} = JSON::XS->new->decode($self->{config}); };
        }
        $self->{config} = {} if ref($self->{config}) ne 'HASH';
        if ($parent ne $self and ref($parent->{config}) eq 'HASH') {
            foreach my $key (keys %{$parent->{config}}) {
                $self->{config}{$key} = $parent->{config}{$key} unless exists $self->{config}{$key};
            }
        }
    }
    return $entities;
}

sub purge_hrlinks {
    my $self = shift;
    #
    my $SET_RE = '\@[a-zA-Z0-9_]+';
    my %map = (
        id => 'system.entity.id',
        size => 'system.dataset.size',
        status => 'system.dataset.status',
        );
    #
    my $dbi = $self->dbi;
    #
    my $config = $self->hrconfig;
    #
    # Iterate over subjects in config
    foreach my $subject (keys %$config) {
        my $user = $config->{$subject}{username} or next; # Not a users
        my $spec = $config->{$subject}{config}   or next; # No config for user
        #
        # Get my sets from config
        my %sets = ('.' => { spec => $spec } );
        foreach (keys %$spec) {
            next unless /^($SET_RE)$/;
            next unless ref($spec->{$1}) eq 'HASH';
            $sets{$1}{spec} = $spec->{$1};
        }
        # ... and from existsing structure
        my $udir = $self->absolute("view/user/$user");
        my $ALLtime = (stat "$udir/ALL/.")[9] or $self->yell("stat($udir/ALL/.): $!") and  return;
        opendir(DIR, $udir)                   or $self->yell("opendir($udir): $!") and return;
        $sets{'.'}{old} = {};
        foreach (readdir DIR) {
            next if /^\./;
            next if /^[A-Z]+$/;
            if (/^$SET_RE$/) { $sets{$_}{old} = undef; } # a set
            else             { $sets{'.'}{old}{$_} = 1; } # assume link to avoid lstat()
        }
        close(DIR);
        #
        # Iterate over my sets
        foreach my $setname (sort keys %sets) {
            my $dir = "$udir/$setname";
            my $set = $sets{$setname};
            #
            # Check presence
            if ($set->{spec}) {
                my $dirtime = (stat "$dir/.")[9] || 0;
                $dirtime or mkdir($dir) or $self->yell("mkdir($dir): $!") and next;
            }
            # Read the directory (if not allready done, ie '.');
            unless (defined $set->{old}) {
                $set->{old} = {};
                if (opendir DIR, $dir) {
                    foreach (readdir DIR) {
                        next if /^\.\.?$/;
                        $set->{old}{$_} = 1;
                    }
                }
                close(DIR);
            }
            #
            # get wanted links if spec.
            my $want = {};
            my ($match, $show, $separator);
            if ($set->{spec}) {
                #
                # What we want
                $match     = $set->{spec}{match}     || $spec->{match};
                $show      = $set->{spec}{show}      || $spec->{show};
                $separator = $set->{spec}{separator} || $spec->{separator};
                $show = [$show] unless ref($show);
                $show = ['id'] unless ref($show) eq 'ARRAY';
                push(@$show, 'id') unless grep(/^id$/, @$show);
                #
                # What we find
                my @where = ("entity in (select dataset from FI_GRANTED where subject=$subject)");
                if (ref($match) eq 'HASH') {
                    foreach my $key (keys %$match) {
                        my $vals = $$match{$key};
                        $vals = [$vals] unless ref($vals);
                        if (ref($vals) eq 'ARRAY') {
                            foreach my $val (@$vals) {
                                push(@where, matchpair($key, $val));
                            }
                        }
                    }
                }
                my $sql = "select * from METADATA natural join METADATAKEY where " . join(" and ", @where);
                my $query = $dbi->prepare($sql);
                $query->execute;
                my $data = {};
                while (my $row = $query->fetchrow_hashref) {
                    $$data{$$row{entity}}{$$row{metadatakeyname}} = $$row{metadataval};
                }
                #
                # Generate link names
                foreach my $dataset (keys %$data) {
                    my @fields = ();
                    foreach (@$show) {
                        my $field = $_;
                        my $mapped = 0;
                        my $type;
                        if (my $class = ref($field)) {
                            if    ($class eq 'HASH')  { ($field, $type) = (%$field)[0,1]; }
                            elsif ($class eq 'ARRAY') { ($field, $type) = (@$field)[0,1]; }
                            else                      { next; }
                            next unless defined $field;
                        }
                        if (exists $map{$field}) { $field = $map{$field}; }
                        else                     { $field = ".$field" unless $field =~ /^\./; }
                        $field = $$data{$dataset}{$field};
                        $field = '' unless defined $field;
                        $field = formatit($field, $type) if defined $type;
                        push(@fields, $field);
                    }
                    my $name = join($separator, @fields);
                    $name =~ s/[\000-\037\177\"\'\*\/\:\<\>\?\\\|]//g;                                        # untaint filename
                    if (length($name) > 250) {                                                                # link name to long...
                        $name = substr($name, 0, 186)."+".Digest::SHA->new($ALGORITM)->add($name)->hexdigest; #     use a substring and SHA-sum.
                    }
                    $name = encode('UTF-8', $name);
                    $$want{$name} = $dataset;
                }
                #
                # Update links where needed
                #
                my $old = $set->{old};
                # Remove unwanted sets
                foreach my $name (keys %$old) {
                    next if $want->{$name};
                    unlink("$dir/$name");
                    delete($old->{$name});
                }
                # Create missing sets
                my $rALL = 'ALL';
                $rALL = "../$rALL" unless $setname eq '.';
                foreach my $name (keys %$want) {
                    my $id = $want->{$name};
                    next if $old->{$name};
                    symlink("$rALL/$id", "$dir/$name") or warn "symlink($rALL/$id, $dir/$name): $!";
                }
                #
                # Remove unspecified set folders
                rmdir($dir) or warn("rmdir($dir): $!") unless $setname eq '.' or $set->{spec};
            }
        }
    }
}


sub mapuserstring {
    my $self = shift;
    my $userstring = shift;
    my $helper = shift; 
    #
    if ($helper) { # executable taking userstring as param and emitting passwd style line 
        open(HELPER, '-|', $helper, $userstring) or return;
        my $line = <HELPER>;
        close(HELPER);
        return split(/:/, $line); # expect passwd style line
    }
    else { # use native getpwnam() unless external helper.
        return unless $userstring =~ /^(\w+)\@ntnu.no$/;
        return getpwnam($1);
    }
}

sub mode2perm {
    my $self = shift->FI;
    my $mode = shift;
    #
    my $dbi = $self->dbi;
    unless (exists $self->{cache}{mode}) {
        $self->{cache}{mode} = $dbi->selectall_hashref("select * from FI_MODE","mode");
        $self->yell($dbi->errstr) and return if $dbi->err;
    }
    my $perm = $self->{cache}{mode}{$mode}{perm};
    $self->yell("Unknown mode $mode") and return unless $perm;
    return $perm;
}


################################################################################################################################


package FileInterfaceDataset;
our @ISA = qw(FileInterface);
use Time::HiRes qw(time);
use File::Path;

sub new {
    my $class = shift; $class = ref($class) || $class;
    my $FI = shift;
    my $info = shift;
    my $id = $$info{entity} or self->yell("Invalid HASH stucture") and return;
    my $self = {
        id => $id,
        FI => $FI,
        info => $info,
    };
    bless($self, $class);
    $FI->{cache}{dataset}{$id} = $self;
    return $self;
}
        
sub get {
    my $class = shift; $class = ref($class) || $class;
    my $FI = shift;
    my $id = shift;
    #
    return $FI->{cache}{dataset}{$id} if exists $FI->{cache}{dataset}{$id};
    my $self = {
        id   => $id,
        FI   => $FI,
    };
    bless($self, $class);
    $self->dbi->do("insert ignore into FI_DATASET(entity) values($id)");
    $self->info or return;
    $FI->{cache}{dataset}{$id} = $self;
    return $self;
}

sub info {
    my $self = shift;
    #
    my $id = $self->id;
    my $FI = $self->FI;
    my $info = $FI->dbi->selectrow_hashref("select * from FI_INFO where entity=$id");
    $FI->yell($FI->dbi->errstr) and return if $FI->dbi->err;
    $FI->yell("No info found for $id") and return unless $info;
    $self->{info} = $info;
    return $info;
}

sub save {
    my $self = shift;
    my $store =  shift || $self->store;
    my $mode =   shift || $self->mode;
    my $cookie = shift || $self->cookie;
    #
    my $dbi = $self->dbi;
    my $perm = $self->mode2perm($mode) or return;
    $dbi->do(sprintf( "replace into FI_DATASET(entity,store,perm,cookie,timestamp) values(%d,%s,%d,%s,%0.6f)",
                      $self->id,
                      $dbi->quote($store),
                      $perm,
                      $dbi->quote($cookie),
                      time(),
             ),
        );
    $self->yell($dbi->errstr) and return if $dbi->err;
    $self->adb->setMtime("FI_DATASET");
    return $self->info;
}

sub id          { return shift->{id};                   } 
sub entity      { return shift->{info}{entity};         }
sub scale       { return shift->{info}{scale};          }
sub store       { return shift->{info}{store};          }
sub perm        { return shift->{info}{perm};           }
sub mode        { return shift->{info}{mode};           }
sub cookie      { return shift->{info}{cookie};         }
sub timestamp   { return shift->{info}{timestamp};      }
sub datasetpath { return shift->{info}{datasetpath};    }
sub viewscale   { return shift->{info}{viewscale};      }
sub rwscale     { return shift->{info}{rwscale};        }
sub roscale     { return shift->{info}{roscale};        }
sub rmscale     { return shift->{info}{rmscale};        }
sub fipath      { return shift->{info}{fipath};         }
sub fiprivate   { return shift->{info}{fiprivate};      }
sub rwpath      { return shift->{info}{rwpath};         }
sub ropath      { return shift->{info}{ropath};         }
sub rmpath      { return shift->{info}{rmpath};         }
sub linkpath    { return shift->{info}{linkpath};       }
sub privatepath { return shift->{info}{privatepath};    }
sub datapath    { return shift->{info}{datapath};       }

sub check { #< Return datapath if dataset is loaded and online
    my $self = shift;
    #
    return $self->datapath if ($self->datapath and -d $self->absolute($self->datapath));
    return;
}

sub find { #< return datapath if exists, 
    my $self = shift;
    return $self->datapath if $self->check;
    my $link = $self->absolute($self->datasetpath);
    my $target = readlink($link) or return;
    return '' unless -d $link;
    $self->yell("Unknown dataset view target in link $link") and return unless $target =~ /^[\/.]*(\w+)-(\w+)/;
    my ($mode, $store) = ($1, $2);
    opendir(DSET, $link) or $self->yell("opendir($link): $!") and return;
    my @cookie = grep /^(\w+)$/, readdir(DSET);
    close DSET;
    $self->yell("Found ".int(@cookie)." cookies") and return unless @cookie == 1;
    $self->save($store, $mode, $cookie[0]) or return; 
    $self->yell("Offline dataset ".$self->id) and return unless $self->check;
    return $self->datapath;
}

sub create {
    my $self = shift;
    my @hints = @_;
    #
    my $id = $self->id;
    my $found = $self->find;
    $self->yell("Dataset $id allready exists") and return $found if $found;
    $self->yell("Dataset $id is offline")      and return if defined($found);
    #
    my $store = $self->selectstore(@hints) or $self->yell("No suitable store for dataset $id with hints (@hints)") and return;
    my $mode = 'rw';
    my $cookie = $self->newcookie;
    $self->save($store, $mode, $cookie) or return;
    #
    $self->ensurepath($self->absolute($self->fipath),                  0711) or return;
    $self->ensurepath($self->absolute($self->viewscale),               0711) or return;
    $self->rellink(
        $self->absolute($self->rwpath),
        $self->absolute($self->datasetpath),
        )                                                                    or return;
    $self->ensurepath($self->absolute($self->privatepath),             0755) or return;
    $self->ensurepath($self->absolute($self->datapath),                0777) or return;
    $self->lint; # Create html methods
    #
    return $self->datapath;
}

sub close {
    my $self = shift;
    #
    my $id = $self->id;
    #
    $self->yell("Dataset missing for $id") and return unless defined $self->mode;
    return $self->datapath if $self->mode eq "ro";
    #
    # Set new cookie
    my $oldpriv = $self->absolute($self->fiprivate);
    $self->save(undef, undef, $self->newcookie) or return;
    my $newpriv = $self->absolute($self->fiprivate);
    unless (rename($oldpriv, $newpriv)) {
        $self->yell("rename($oldpriv,$newpriv): $!");
        $self->lint; # Clean up any mess
        return;
    }
    #
    # Move to ro storage
    my $oldpath = $self->absolute($self->fipath);
    $self->save(undef, 'ro', undef) or return;    
    my $newpath = $self->absolute($self->fipath);
    $self->ensurepath($self->absolute($self->roscale), 0711) or return;
    unless (rename($oldpath, $newpath)) {
        $self->yell("rename($oldpath,$newpath): $!");
        $self->lint; # Clean up any mess
        return;
    }
    #
    # Update view
    $self->rellink(
        $self->absolute($self->ropath),
        $self->absolute($self->datasetpath),
        ) or return;
    $self->lint; # Removes Close html method.
    #
    return $self->datapath;
}

sub remove { #< Remove a dataset, ie currently make it unavailable.
    my $self = shift;
    #
    my $id = $self->id;
    return $id unless $self->mode; # Return success if the set is nonexistsing.
    my $rprivate = $self->fiprivate              or $self->yell("No privatepath for $id") and return;
    my $private = $self->absolute($rprivate);
    my $view = $self->absolute($self->datasetpath);
    chmod(0000, $private)                        or $self->yell("chmod($id) failed")  and return;
    rename($private, "$private-deleted-".time()) or $self->yell("rename($id) failed") and return;
    unlink($view)                                or $self->yell("unlink($id) failed") and return;
    $self->dbi->do("delete from FI_DATASET where entity=$id");
    $self->yell($self->dbi->errstr) and return if $self->dbi->err;
    return $id;
}

sub recook { ... }

sub lint {
    my $self = shift;
    #
    my $id = $self->id;
    my $scale = $self->scale;
    my $survey = {};
    my @warning = ();
    my @error = ();
    my @done = (),
    #
    my $view = $self->absolute($self->datasetpath);
    if (lstat $view) {
        if (-l _) {
            #
            # Survey the storage
            my $linkpath = readlink($view);
            if ($linkpath =~ m|^(../)*([a-z]+)-(\w+)/$scale/$id$|) {
                $survey->{mode} = $2;
                $survey->{store} = $3;
                if (opendir STORAGE, $view) {
                    my @storage = readdir(STORAGE);
                    CORE::close(STORAGE);
                    my @valid = ();
                    my @links = ();
                    my @empty = ();
                    my @noise = ();
                    my $sequence = 0;
                    foreach (@storage) {
                        next if /^\./;
                        if (/^\w+$/) {
                            my $this = "$view/$_";
                            my $now = time();
                            my $age = $now - (lstat $this)[9];
                            if    (-l _) {
                                # Leaked link from rehas?
                                push(@links, $_) if $age > 86400;
                            }
                            elsif (-d _) { 
                                if (-d "$this/data") {
                                    # Seem ti be a valid folder
                                    push(@valid, $_);
                                }
                                else {
                                    if ($age < 8) {
                                        # If fresh it may be under construction
                                        push(@empty, $_);
                                    }
                                    else {
                                        # try to remove it (empty) or reduce it to noicse
                                        if (rmdir($this)) {
                                            push(@done, "Removed empty '$_'");
                                        }
                                        else {
                                            my $why = $!;
                                            my $noise = "$this-NOISE-$now-$$-".++$sequence;
                                            if (rename($this, $noise)) {
                                                push(@done, "Reduced empty '$_' to noice: $why");
                                                push(@noise, $_);
                                            }
                                            else {
                                                push(@error, "Failed reducing '$_' to noise: $!");
                                            }
                                        }
                                    }
                                }
                            }
                            else {
                                rename($this, "$this-NOISE-$now-$$-".++$sequence);
                                push(@done, "Reduced non directory '$_' to noice");
                                push(@noise, $_);
                            }
                        }
                        else {
                            push(@noise, $_);
                        }
                    }
                    # 
                    if (@valid == 0) { push(@error, "Missing data folder") unless @empty == 1; }
                    if (@valid == 1) { $survey->{cookie} = $valid[0]; } # Operation normal
                    if (@valid >  1) { push(@error, "Multiple data folders: ".int(@valid)); }
                    #
                    if (@empty == 1) { push(@error, "Empties: 1") unless @valid == 0; }
                    if (@empty >  1) { push(@error, "Empties: ".int(@empty)); }
                    #
                    if (@noise > 0)  { push(@warning, "Noise level: ".int(@noise)); }
                }
                else { push(@error, "Offline: $linkpath"); }
            }
            else { push(@error, "Invalid view target: $view -> $linkpath"); }
            #
            # compare survey and info
            my $info = $self->info;
            if ($survey->{cookie}) {
                unless ( $info->{cookie}
                         and $info->{store}  eq $survey->{store}
                         and $info->{mode}   eq $survey->{mode}
                         and $info->{cookie} eq $survey->{cookie}
                    ) {
                    $self->save( $survey->{store},
                                 $survey->{mode},
                                 $survey->{cookie},
                        );
                    push(@done, "Saved actual info for $id");
                }
            }
            #
            # Action files
            my $ACTION_HTML = '<HEAD><META http-equiv="refresh" content="0; %2$s"  /></HEAD><BODY><A href="%2$s">%1$s</A></BODY>';
            my %ACTION = (
                rw => {
                    'Close.html'       => [$ACTION_HTML, $ACTION_HREF, 'Close'],
                        'Metadata.html'    => [$ACTION_HTML, $ACTION_HREF, 'Metadata'],
                        'Permissions.html' => [$ACTION_HTML, $ACTION_HREF, 'Permissions'],
                },
                ro => {
                    'Close.html'       => undef,
                        'Metadata.html'    => [$ACTION_HTML, $ACTION_HREF, 'Metadata'],
                        'Permissions.html' => [$ACTION_HTML, $ACTION_HREF, 'Permissions'],
                },
                );
            my $actions = $ACTION{$self->mode};
            foreach my $action (keys %$actions) {
                my $path = $self->absolute($self->fiprivate)."/$action";
                if (defined $actions->{$action}) {
                    my ($html, $href, $verb) = @{$actions->{$action}};
                    unless (-e $path) {
                        if (open ACTION, '>', $path) {
                            printf( ACTION $html,
                                    $verb,
                                    sprintf($href, $verb, $id),
                                );
                            push(@done, "Added verb $verb to $id");
                            CORE::close(ACTION);
                        }
                    }
                }
                else {
                    if (-e $path) {
                        unlink($path);
                        push(@done, "Removed $action from $id");
                    }
                }
            }
        }
        else { push(@error, "Not a symlink: $view"); }
        #
        my $log = {};
        $log->{warning} = \@warning if @warning;
        $log->{error}   = \@error   if @error;
        $log->{done}    = \@done    if @done;
        return $log;
    }
    else { return; }            # No dataset exists
}


#=============================================================================================

package FileInterface;

sub server {
    my $self = shift;
    my %restrict = ();
    $restrict{$_} = 1 foreach (@_);
    my $fi = $self->FI;
    $| = 1;
    while (<>) {
	chomp;
        my $start = time();
	my $result = undef;
	if (/^([a-zA-Z0-9_]+(\s+[a-zA-Z0-9\/_\s-]*)?)/) {
	    my ($method, @params) = split(/\s+/, $1);
	    if (!%restrict or $restrict{$method}) {
		eval { $result = $fi->$method(@params); };
		if (my $class = ref($result)) {
		    unless ($class =~ /^(SCALAR|HASH|ARRAY)$/) { 
			$result = $result->id;
		    }
		}
		$self->yell($@) unless $@ eq "";
	    }
	    else {
		$self->yell("Restricted method: $method");
	    }
	}
	else {
	    $self->yell("Invalid call: $_");
	}
        
	print YAML::XS::Dump({ result => $result, yell => $self->{yell}}), "...\n";
        if (open LOG, ">>", "/var/log/aurora/FileInterface.log") {
            print(LOG YAML::XS::Dump(
                      {
                          time => $start." + ".(time()-$start),
                          request => $_,
                          result => $result,
                          yell => $self->{yell},
                      }
                  ), "...\n"
                );
            close(LOG);
        }
	$self->yell('<');
    }
}

# Public dataset methods

sub create   { return shift->dataset(shift)->create(@_); }
sub close    { return shift->dataset(shift)->close(@_); }
sub mode     { return shift->dataset(shift)->mode(@_); }
sub lint     { return shift->dataset(shift)->lint(@_); }
sub remove   { return shift->dataset(shift)->remove(@_); }
sub datapath {
    my $self = shift;
    my $entity = shift // return;
    my $dataset = $self->dataset($entity);
    return unless $dataset->mode;
    my $path = $dataset->datapath;
    $path = $self->absolute($path) if defined $path;
    return $path;
}



package FileInterfaceClient;

use IPC::Open2;
use FileHandle;
# use parent qw(FileInterface);
our @ISA = qw(FileInterface);
our @SERVER = ('/local/app/aurora/dist/fileinterface/AuroraFileInterface');

sub new {
    my $class = shift; $class = ref($class) || $class;
    my @connect = @_;
    # @connect = qw(ssh -T root@archive.it.ntnu.no) unless @connect;
    @connect = qw(sudo) unless @connect;
    my $self = bless({}, $class);
    $self->{FI} = FileInterface->new();
    $self->{connect} = \@connect;
    return $self;
}

sub _connect {
    my $self = shift;
    $ENV{PATH} = '/usr/bin/';
    unless ($self->{pid}) {
	$self->{pid} = undef;
	$self->{error} = undef;
	$self->{request} = FileHandle->new;
	$self->{responce} = FileHandle->new;
	eval {
	    $self->{pid} = open2(
		$self->{responce},
		$self->{request},
		@{$self->{connect}},
		@SERVER,
		);
	};
	$self->{error} = $@ unless $self->{pid};
    }
    return $self->{pid};
}

sub _request {
    my $self = shift;
    die unless $self->_connect;
    my $request = $self->{request};
    my $responce = $self->{responce};
    my $current = select($request);
    $| = 1;
    select($current);
    print($request "@_\n");
    my $yaml = '';
    while (<$responce>) {
	last if /^\.{3}/;
	$yaml .= $_;
    }
    my $result = YAML::XS::Load($yaml);
    $self->FI->{yell} = $result->{yell};
    return $result->{result};
}

sub _generic {
    my $self = shift;
    my $method = (caller(1))[3];
    $method =~ s/.*://;
    return $self->_request($method, @_);
}

# Public methods
#
# Dataset
sub storewcheck { return shift->_generic(@_); }
sub create      { return shift->_generic(@_); }
sub close       { return shift->_generic(@_); }
sub datapath    { return shift->_generic(@_); }
sub mode        { return shift->_generic(@_); }
sub lint        { return shift->_generic(@_); }
sub remove      { return shift->_generic(@_); }
#
# Purge is now a noop trough the client
sub purge      { return 1; }

1;
=encoding utf-8


=head1 FileInterface


FileInterface (FI) is managing the file storage for Aurora. This is intended for direct access trough NFS, SMB/CIFS, HTTP etc. To simplify access control across different platforms the access control is implemented with unix execure only-mode and hard to guess "cookie" directory names. Knowledge of a cookie gives access to the relevant object.

In FI, an Aurora entity may be "dataset", a "subject", both or none of them. The entity type is not consulted. A dataset is simply an entity FI has created a dataset storage for. A subject is a entity with DATASET_CREATE or DATASET_READ right on a dataset. 

The FI is split into two disinct parts:


=head3 Storage


This is where the actual data is stored, and may cmprise of different file systems for scalability ao. The different file systems should be available to the FI under a common base directory ($base), here called "/Aurora". Each file system has a name ($store) and contain two directorys "rw" and "ro"; The store should be available to the FI as tree entries under the base:


=over


=item *

fi-$store - the root of store

=item *

rw-$store - the rw directory

=item *

ro-$store - the ro directory


=back

This is typically implementetd by NFS like in the example below, but may also be symlinks or loopback mounts if local. 

     mount -o rw fileserver:/export/aurora_storage01    /Aurora/fi-storage01
     mount -o rw fileserver:/export/aurora_storage01/rw /Aurora/rw-storage01
     mount -o rw fileserver:/export/aurora_storage01/ro /Aurora/ro-storage01

The "fi-" mount must be exported as no_root_squash since FI has to do priveleged operations on it.


=head3 View


All access is implemented as symlinks under $base/view. This tree has two functions: Keep track of where the datasets is currently stored, and who may access it.


=head2 Dataset structure


When a dataset is created, a storage is selected based on hints to the create method, and a cookie is generated. The resulting storage path to the dataset is like $base/rw-$storage/$scale/$entity/$cookie/. $scale is a scaling to avoid unlimited nmber of elements in one directory. The dataset consists of a data directory with the actual data, alongside other files and folders for metadata etc. The $scale part is derived from the $entity like '$scale = sprintf("%03d/%03d, int($entity/1000000) % 1000, int($entity/1000) % 1000)'. The data of the dataset should thus reside in a path like "/Aurora/fi-storage01/rw/000/034/34625/FtHugftvcRcrfdfdRD/data/". Unpriveleged access should be done trough the "rw" path "/Aurora/rw-storage01/000/034/34625/FtHugftvcRcrfdfdRD/data/".

On close, the dataset is moved from rhe "rw" to the "ro" storage directory, and unpriveleged access is thus done trough the read only ro-$store mount.

To keep track of the eksact location at any time, FI maintain a symbolic links under "$base/view". This is similary scaled so, "/$base/view/$scale/$entity" will allways be a relative symink to "/$base/$mode-$store/$scale/$entity", like 

    /Aurora/view/000/034/34625 -> ../../../rw-storage01/000/034/34625


=head2 Access structure


Any entity with DATASET_CREATE or DATASET_READ is considered a "subject". The subject is assigned an $keycode and represented by a directory in the view tree as $base/view/$scale/$entity-$keycode. This contain relative symlinks to the dataset folders of all datasets the subject is entitled to. So if entity 450 has keykode lkjKLjLJoihjlIj and access to 34625 there is a symlink like this:

    /Aurora/view/000/000/450-lkjKLjLJoihjlIj/34625 -> ../../034/34625/FtHugftvcRcrfdfdRD

So knowlege to 450's keycode will give access to the dataset 34625.


=head3 Local user access


If a subject maps to a local user ($username), a directory with exclusive access for the user is created as "$base/view/user/$username". In this ther wil be a relatin\ve symlink "ALL" pointing to the subjets access directory like

    /Aurora/view/user/bt/ALL -> ../../000/000/450-lkjKLjLJoihjlIj

The local user "bt" (entity 450) may this way access the dataset as /Aurora/view/user/bt/ALL/34625/ without knowledge to its keycode or the cookie of the dataset.


=head2 FI roles



=head3 Aurora server


This is the controlling service for dataset management. This is normally running without privileges, so FI is accesed trough a simple server/client interface. This is based om sudo for escalation, but may easily be adapted to ssh if running on a separat host.


=head3 Aurora client


A aurora client is an host that provide user access to the data, like login services, http or samba server etc. The clients need to mount the view directroy tree read only and any "$mode-" exports with relevant mode, all prefferably with root squash.

Note tath FI is not responsibel of data transport. Populating the datsets data-directory is done trough a Aurora server or client.


=head3 FI purger


This is an asynchrounus privileged process mainatining the access structure troug the purgepoll() and purge() methods.  


=head3 FI sets (unimplemented)


This is a process that populate the users access directory with sets of relative symlinks to datasets ALL/ based on users wish.


=head2 Synopsis


Client usage

    use FileInterface;
    $client = FileInterfaceClient->new;
    $datapath = $client->create($entity, $user, $parent);
    $datapath = $client->close($id);
    $datapath = $clinet->datapath($id);
    $mode = $client->mode;
    $result = $client->lint($id);
    $client->remove($id);

Mainainace processes (priveleged)

    use FileInterface;
    my $fi = FileInterface->new;
    $elapsed = $fi->purgepoll;
    $elapsed = $fi->purge;
    $result = $fi->lint(id);
    $results = $fi->storelint;


=head2 Methods



=head3 yell([string, ...]))


Most methods return undefined on errors. Any error messages is returned as a list from the yell() method. Any parameters to the yell is added to the list, except for the first parameter which I<may> have special meaning, the most important is "E<lt>" which clears the list and adds any subsequent parametes. Other codes can be found in the source.
Yell prepend messages with the name of the calling method.


=head3 new(AuroraDB, base, http)


Return a new FileInterface object. The three parameters i optional and primarely for testing. In production any undefined parameter will default to reasonable values.


=head3 server()


Read method and parameters from STDIN and return result and yells on STDOUT as YAML. Primarely used to execute the following dataset methods with privileges. 


=over


=item *

create(id, [hint, ...])

=item *

close(id)

=item *

mode(id)

=item *

remove(id)

=item *

datapath(id)

=item *

lint(id)


=back

All is pure wrappers for similar FileInterfaceDataset methods described below, except for create, close and datapath which return absolute paths (prepend with "$base/").


=head3 FI() 


Return the FileInterface object itself, also for child FileInterfaceDataset objects. The following methods use FI() where relevant allowing inheritanse to child objects for methods conserning the parent FI object. 


=head3 Settings()


Return the Aurora Settings object used for configuration.


=head3 adb()


Return the AuroraDB object.


=head3 dbi()


Return the DBI object of the AuroraDB


=head3 base()


Return the configiured base path.


=head3 absolute(path, [path, ...])


Join paths with "/" and prepend with $base.


=head3 flush()


Clear all data and objects cached in the FI object.


=head3 dataset(id)


Return the a FileInterfaceDataset object for the entity id. The object is new unless found in cache.


=head3 ensurepath(path, mode)


Make sure the path exists. Set mode on any newly created directory


=head3 newcookie()


Return an newly created cookie string for dataset cookie or subject keycard


=head3 rellink(target, link)


Create a relative link to target using the shorthest relative path.


=head3 selectstore([hint, ...]);


Find the prefferred store according to the hints. The hints is entity id's, and these will be followed along their entity path for the first hit. The hints are typically the user requesting the creation and the parent of the dataset to be created. A hit is when a store with the entity number or "system.fileinterface.store" metadata as the store name is found. 


=head3 storewcheck(store)


Check that a store is online and writable.

Takes a store name as parameter.
Return 1 if online and rw/ is writable 

May find new (empty) stores storeprobe() do not know about.


=head3 storeprobe()


Bring all known stores online.

Return all known stores as an hash. Key in the hash is "$mode-$store", value is stat() of the directory.


=head3 storescan([store, ...])


Scann the list of stores for datasets, and return a complete list. Store is here the $mode-$store mount. 

If no list is given, all rw- and -ro trees present as well as view is scanned. storeprobe() is called prior to the scan to bring all known stores online. Note that any unknown stores (ie with only unknown datasets) has to be brought online in some other way to detect the unknown datasets, unless a "browse" automount option is in effect.

Return a hash with dataset id as key and "$mode-$store" as value;


=head3 storelint([store, ...])


Run lint() on all datasets found by storescan([store, ...]). Any parameters is pased unaltered to storescan();

Return a hash with dataset id as key, The values is the return hash from lint() on the dataset, possibly augmented by storelint();


=head3 grantpathview(subject, keycode)


Return the subject view path according to the parameters.


=head3 grantpath(subject, keycode, dataset)


Return the path for a grant. Unless already exixsting, the grantpathview() is crated and subject is registered. 


=head3 purge()


Evaluate the actual permissions against registered grants, and do the neccecary adjustments. This is split into tree phases:


=over


=item *

purge_deny() - remove any permission symlinks that should not be there

=item *

purge_grant() - create any permission symlinks

=item *

purge_user() - create any missing view/user directories for subjects with local user.


=back

Return the elapsed time.


=head3 purgepoll()


Run purge() if any changes in the source.

Return the elapsed time from purge() or 0 if purge() is not run.


=head3 mapuserstring(userstring [,helper])


Maps a userstring to a local user for purge_user().
Optional helper parameter is the name of an external program that is passed the userstring, and is expected to return a normal passwd string which is plitted and returned.
Without a helper, it expect the userstring to be of the form /^(\w+)\@ntnu.no$/, and return getpwnam($1);  


=head1 FileInterfaceDataset;


Dataset methods is separated into a subclass. FileInterfaceDataset objects doe allways know its own own entity id and the FileInterface object it is created from. 


=head3 new(FI, info)


Create a new dataset object from an info hash, typically from an SQL query. 


=over


=item *

FI is the creating FileInterface object.

=item *

info is a hash where the "entity" is a required key containing the dataset id.


=back

Returns the newly created object.


=head3 get(FI, id)


Create and retuurn new dataset object.


=head3 save(store, mode, cookie)


Save or update a dataset database entry. Only defined parameters is updated.


=head3 id()


Return the id of an dataset


=head3 info()


return the info hash of the dataset. The fields is 


=over


=item *

entity - Aurora entity id

=item *

scale

=item *

store

=item *

mode

=item *

perm - The numeric permission assosiated with the mode

=item *

cookie

=item *

timestamp - Update timestamp

=item *

datasetpath - view/$scale/$dataset

=item *

privatepath - view/$scale/$dataset/$cookie

=item *

datapath - view/$scale/$dataset/$cookie/data

=item *

viewscale - view/$scale

=item *

rwscale - rw-$store/$scale

=item *

roscale - ro-$store/$scale

=item *

rmscale - rm-$store/$scale (unused)

=item *

rwpath - rw-$store/$scale/$id

=item *

ropath - ro-$store/$scale/$id

=item *

rmpath - rm-$store/$scale/$id (unused)

=item *

linkpath - $mode-$store/$scale/$id

=item *

fipath - fi-$store/$mode/$scale/$id

=item *

fiprivate - fi-$store/$mode/$scale/$id/$cookie


=back

The values is undefined for missing/unset fields, like fiprivate if no cookie is set.

All of theese may also be obtained as methods with the same name, like entity() etc.


=head3 check()


Return $self-E<gt>datapath if defined and the path exists.


=head3 find

Return $self-E<gt>datapath if check() or a meaningful view link is found. 


=head3 mode2perm(mode)


Return the numeric permission assosiated with the mode.


=head3 create()


Create the a dataset for an entity.

Return datapath if created and online on exit, but yell if it did exists.


=head3 close()


Move a dataset from rw to ro mode and return the new dataset path. Creates a new cookie in the process.


=head3 remove()


Remove a dataset and return the id. Currently just renames it out of view.


=head3 recook() (unimplemented)


Set a new cookie and update all relevant links.


=head3 lint()


Clean up any discrepancys. Does also some auxilary tasks like maintaining html shortcuts etc.

Return a hash of the following lists:


=over


=item *

errors - list of uncorrectable errors

=item *

warnings - list of discrepancys of less importance 

=item *

done - list of corrections taken


=back


=head1 FileInterfaceClient;



=head3 new([connect, ...])


Return a FileInterfaceClient object for privilege escalation. The optional connect parameters is passed to open2 if another connection escalation method than the default "sudo" is required. Should be transparent to FileInterface for the following methods:


=over


=item *

create(id, [hint, ...])

=item *

close(id)

=item *

datapath(id)

=item *

mode(id)

=item *

lint(id)

=item *

remove(id)


=back

This method is made noop in the client, since it is function now should be handled by an asynchrounous process:


=over


=item *

purge()


=back

The following methods is internal to the client:


=over


=item *

_connect() - make the connection when required (lazy connect)

=item *

_request(method, [arg, ...] - build an request

=item *

_generic([arg, ...]) - generic wrapper for request

=back

