#!/usr/bin/perl -w
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

use lib qw(/local/lib);
use lib qw(/usr/local/lib/aurora);
use HTTPSClient::Aurora;
use Schema;
use SysSchema;
use Data::Dumper;
use Settings;
use JSON::XS;

use CGI;
use BTsession;
use BTsession;
use paramHash;

# set UTF-8 encoding on STDIN/STDOUT
binmode(STDIN, ':encoding(UTF-8)');
binmode(STDOUT, ':encoding(UTF-8)');

package AuroraWebTools;

use Data::Dumper;
our $AUTOLOAD;

sub new {
    my $this = shift;
    my $self = bless({}, ref($this) || $this);
    if    (@_)        { $self->{head} = shift; } # Explicit head
    elsif (ref $this) { $self->{head} = $this; } # Implicit head
    unless (defined $self->{head}) {             # Create new session on undefined head
	$self->{head} = $self;
	$self->_setup_session;
    }
    return $self;
}

sub _setup_session {
    my $self = shift;
    #
    # get settings
    my $cfg;
    my $cfgpath=$ENV{"AURORAWEB_PATH"} || "..";
    $cfg=Settings->new(path=>"$cfgpath/settings");
    $cfg->load();
    #
    # instantiate session object
    my %data = ();
    my $session;
    $session = new BTsession(
	payload=>\%data,
	cookieName=>$cfg->value("www.cookiename"),
	secret=>$cfg->value("www.session.secret"),
	) or die "BTsession failed: $!";
    #
    # instantiate connection to REST-server
    my $aurora = HTTPSClient::Aurora->new(
	Host=>$data{cfg}{"aurora.rest.server"},
	%{$data{cfg}{"aurora.rest.sslparams"}},
	);
    $self->{cfg} = $cfg;
    $self->{cgi} = $session;
    $self->{server} = $aurora;
    $self->{data} = \%data;
    $self->{data}->{var} = {};
    return $self;
}


sub head   { return shift->{head}; }
sub cfg    { return shift->head->{cfg}; }
sub cgi    { return shift->head->{cgi}; }
sub data   { return shift->head->{data}; }
sub var    { return shift->head->data->{var}; }
sub server { return shift->head->{server}; }

sub loggedOn { return shift->data->{loggedon}; }
sub logonPopupLink {
    my $self = shift;
    return CGI->a({-href=>'/', -target=>'_blank'}, @_);
}
sub logonPage {
    my $self = shift;
    my @page = (
	CGI->header(),
	CGI->start_html(),
	"Woops, seem you need to ",
	AuroraWebTools->logonPopupLink("Logon Aurora"),
	". Reload this page when done.",
	CGI->end_html(),
	);
    return @page;
}
sub CheckLoggedIn {
    my $self = shift;
    return 1 if $self->loggedOn;
    print $self->logonPage;
    return;
}

sub call {
    my $self = shift;
    my $method = shift;
    #
    my $result = {};
    eval {
	$self->server->$method(
	    $result,
	    authtype=>$self->data->{authtype},
	    authstr=>$self->data->{authstr},
	    @_
	    );
    };
    return $result;
}
sub AUTOLOAD {
    my $self = shift;
    (my $method = $AUTOLOAD) =~ s/^.*://;
    warn "AUTOLOAD=$AUTOLOAD\n";
    return $self->{params}{$method} if exists $self->{params}{$method};
    return $self->call($method, @_);
}

sub serialize {
    my $self = shift;
    return JSON::XS->new->pretty(1)->encode(shift);
}

sub serializeLine {
    my $self = shift;
    return map { JSON::XS->new->encode($_); } @_;
}

sub unserialize {
    my $self = shift;
    return @{JSON::XS->new->decode('['.shift.']')};
}

sub html {
    my $self = shift;
    $self->head->{html} = [] unless exists $self->head->{html};
    my $html = $self->head->{html};
    push(@$html, @_) if @_;
    return @$html;
}
sub render {
    my $self = shift;
    my $c = $self->cgi;
    my @source = @_;
    my @render = ();
    foreach my $element (@source) {
	if (my $ref = ref($element)) {
	    if ($ref =~ /^[A-Z]+$/) { $element = $self->serialize($element); }
	    else                    { $element = Dumper($element); }
	    $element = $c->pre($element);
	}
	push(@render, $element);
    }
    return $render[0] if @render == 1;
    return @render;
}
sub show {
    my $self = shift;
    $self->html($self->render(@_));
    return @_;
}
sub params {
    my $self = shift->head;
    $self->{params} = {} unless exists $self->{params};
    return $self->{params};
}
sub set {
    my $self = shift;
    my $c = $self->cgi;
    #
    my $got = $self->params;
    while (@_) {
	my $param = shift;
	my $value = shift;
	if (defined $value) {
	    $c->param($param, $value);
	    $$got{$param} = $value;
	}
	else {
	    $c->delete($param);
	    delete($$got{$param});
	}
    }
}

sub ask {
    my $self = shift;
    my $c = $self->cgi;
    #
    my $got = $self->params;
    my @html = ();
    my $missing = 0;
    #
    # Check for missing params
    while (@_) {
	my $param = shift;
	my $field = shift || $c->textfield(-name => $param);
	if ($c->param("_delete_$param")) {
	    $c->delete("_delete_$param");
	    $c->delete($param);
	    delete($got->{param});
	}
	if (my $value = $c->url_param($param) || $c->param($param)) {
	    $got->{$param} = $value;
	    push(@html, $c->Tr({}, $c->td({}, [$param, $value, $c->submit(-name=>"_delete_$param", value=>"X", -tabindex => 9999)])));
	}
	else {
	    $field = [$field] unless ref($field) eq 'ARRAY';
	    push(@html, $c->Tr({}, $c->td({}, [$param, @$field])));
	    $missing += 1;
	}
    }
    if (@html) {
	unshift(@html, $c->start_table({}));
	push(@html, $c->end_table);
    }
    $self->html(@html);
    return not $missing;
}
sub yesno {
    my $self = shift;
    my $c = $self->cgi;
    #
    my $got = $self->params;
    #
    my @html = ();
    my $missing = 0;
    #
    # Check for missing params
    my $table = @_ > 1;
    my @rows;
    while (@_) {
	my $param = shift;
	my $lead = shift || $param;
	if ($c->param("_delete_$param")) {
	    $c->delete("_delete_$param");
	    $c->delete($param);
	    delete($got->{param});
	}
	my @row = ();
	push(@row, $lead) if $table;
	if (my $value = $c->url_param($param) || $c->param($param)) {
	    $got->{$param} = $value;
	    push(@row, $value, $c->submit(-name=>"_delete_$param", value=>"X", -tabindex => 9999));
	}
	else {
	    push(@row, $c->radio_group(-name=>$param, -values=>['Yes','No'], -linebreak=>0));
	    $missing += 1;
	}
	push(@rows, \@row);
    }
    #
    # Make table if more than one parameter
    if ($table) {
	push(@html,
	     $c->start_table({}),
	     map { $c->Tr({}, $c->td($_)); } @rows,
	     push(@html, $c->end_table),
	    );
    }
    else {
	push(@html, @{$rows[0]});
    }
    #
    $self->html(@html);
    return not $missing;
}

sub done {
    my $self = shift;
    my $done = $self->{done} || 0;
    $self->{done} = 1;
    return $done;
}

sub page {
    my $self = shift;
    #
    # Set HTTP header
    my $http = (@_ > 1 and ref($_[0]) and ref($_[1]))
	? shift
	: {}
	;
    # Set HTML header
    @_ = $0 =~ m:([^\/]*)$: unless @_; # Default to process name
    #
    my $c = $self->cgi;
    #
    my $got = $self->params;
    my @hidden = ();
    foreach my $param (keys %$got) {
	push(@hidden, $c->hidden(-name=>$param, -value=>$$got{$param}));
    }
    my $submit = $self->done ? '' : $c->submit(-tabindex => 1); 
    my @html = (
	$c->header(),
	$c->start_html(@_),
	$c->start_form,
	$submit,
	@hidden,
	$self->html,
	$c->end_form,
	$c->end_html(),
	);
    return @html;
}
sub clearPage {
    my $self = shift;
    $self->head->{html} = [];
    return;
}

sub testPage {
    my $self = shift;
    return $self->logonPage unless $self->loggedOn;
    my $s = $self->cgi;
    my @want = (
	method => $s->textfield( -name => 'method', -size => 40 ),
	args => $s->textarea( -name => 'args' ),
	);
    #
    my %got = ();
    my @html = ();
    #
    # Check for missing params
    while (@want) {
	my $param = shift(@want);
	my $field = shift(@want);
	if (my $value = $s->url_param($param) || $s->param($param)) {
	    $got{$param} = $value;
	}
	else {
	    push(@html, $s->Tr({}, $s->td({}, [$param, $field])));
	}
    }
    #
    # if any missing params, ask for them
    if (@html) {
	@html = (
	    $s->start_form({ -action => $s->self_url}),
	    $s->start_table({}),
	    @html,
	    $s->end_table,
	    $s->submit(),
	    $s->end_form,
	    );
    }
    #
    # ... otherwise do the call and present results
    else {
	my @restparams = $self->unserialize($got{args});
	my ($result, $error) = $self->call($got{method}, @restparams);
	push(@html, $s->pre($self->serialize($result)));
        push(@html,
             $s->hr,
             $s->pre(Dumper(\@restparams)),
            );
             
    }
    #
    # return a page
    @html = (
	$s->header(),
	$s->start_html("Aurora restcall"),
	@html,
	$s->end_html,
	);

    return @html;
}

1;
