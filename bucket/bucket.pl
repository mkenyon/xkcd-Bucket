#!/usr/bin/perl -w
#  Copyright (C) 2011  Dan Boger - zigdon+bot@gmail.com
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software Foundation,
#  Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# $Id: bucket.pl 685 2009-08-04 19:15:15Z dan $

use strict;
use POE;
use POE::Component::IRC;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::NickServID;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::SimpleDBI;
use Lingua::EN::Conjugate qw/past gerund/;
use Lingua::EN::Inflect qw/A PL_N/;
use Lingua::EN::Syllable qw//;    # don't import anything
use YAML qw/LoadFile DumpFile/;
use Data::Dumper;
use Fcntl qw/:seek/;
use HTML::Entities;
use URI::Escape;
use DBI;
$Data::Dumper::Indent = 1;

# try to load Math::BigFloat if possible
my $math = "";
eval { require Math::BigFloat; };
unless ($@) {
    $math = "Math::BigFloat";
    &Log("$math loaded");
}

$SIG{CHLD} = 'IGNORE';

$|++;

### IRC portion
my $configfile = shift || "bucket.yml";
my $config     = LoadFile($configfile);
my $nick       = &config("nick") || "Bucket";
my $pass       = &config("password") || "somethingsecret";
$config->{nick} = $nick =
  &DEBUG ? ( &config("debug_nick") || "bucketgoat" ) : $nick;

my $channel =
  &DEBUG
  ? ( &config("debug_channel") || "#bucket" )
  : ( &config("control_channel") || "#billygoat" );
our ($irc) = POE::Component::IRC::State->spawn();
my %channels = ( $channel => 1 );
my $mainchannel = &config("main_channel") || "#xkcd";
my %_talking;
my %fcache;
my %stats;
my %undo;
my %last_activity;
my @inventory;
my @random_items;
my %replacables;
my %handles;
my %plugin_signals;
my @registered_commands;

my %config_keys = (
    autoload_plugins         => [ s => '' ],
    band_name                => [ p => 5 ],
    band_var                 => [ s => 'band' ],
    ex_to_sex                => [ p => 1 ],
    file_input               => [ f => "" ],
    idle_source              => [ s => 'factoid' ],
    increase_mute            => [ i => 60 ],
    inventory_preload        => [ i => 0 ],
    inventory_size           => [ i => 20 ],
    item_drop_rate           => [ i => 3 ],
    lookup_tla               => [ i => 10 ],
    max_sub_length           => [ i => 80 ],
    minimum_length           => [ i => 6 ],
    random_exclude_verbs     => [ s => '<reply>,<action>' ],
    random_item_cache_size   => [ i => 20 ],
    random_wait              => [ i => 3 ],
    repeated_queries         => [ i => 5 ],
    timeout                  => [ i => 60 ],
    the_fucking              => [ p => 100 ],
    tumblr_name              => [ p => 50 ],
    uses_reply               => [ i => 5 ],
    user_activity_timeout    => [ i => 360 ],
    value_cache_limit        => [ i => 1000 ],
    var_limit                => [ i => 3 ],
    your_mom_is              => [ p => 5 ],
);

$stats{startup_time} = time;
&open_log;

if ( &config("autoload_plugins") ) {
    foreach my $plugin ( split ' ', &config("autoload_plugins") ) {
        &load_plugin($plugin);
    }
}

my %gender_vars = (
    subjective => {
        male        => "he",
        female      => "she",
        androgynous => "they",
        inanimate   => "it",
        "full name" => "%N",
        aliases     => [qw/he she they it heshe shehe/]
    },
    objective => {
        male        => "him",
        female      => "her",
        androgynous => "them",
        inanimate   => "it",
        "full name" => "%N",
        aliases     => [qw/him her them himher herhim/]
    },
    reflexive => {
        male        => "himself",
        female      => "herself",
        androgynous => "themself",
        inanimate   => "itself",
        "full name" => "%N",
        aliases =>
          [qw/himself herself themself itself himselfherself herselfhimself/]
    },
    possessive => {
        male        => "his",
        female      => "hers",
        androgynous => "theirs",
        inanimate   => "its",
        "full name" => "%N's",
        aliases     => [qw/hers theirs hishers hershis/]
    },
    determiner => {
        male        => "his",
        female      => "her",
        androgynous => "their",
        inanimate   => "its",
        "full name" => "%N's",
        aliases     => [qw/their hisher herhis/]
    },
);

# make sure the file_input file is empty, if it is defined
# (so that we don't delete anything important by mistake)
if ( &config("file_input") and -f &config("file_input") ) {
    &Log(   "Ignoring the file_input directive since that file already exists "
          . "at startup" );
    delete $config->{file_input};
}

# set up gender aliases
foreach my $type ( keys %gender_vars ) {
    foreach my $alias ( @{$gender_vars{$type}{aliases}} ) {
        $gender_vars{$alias} = $gender_vars{$type};
        &Log("Setting gender alias: $alias => $type");
    }
}

$irc->plugin_add( 'NickServID',
    POE::Component::IRC::Plugin::NickServID->new( Password => $pass ) );

POE::Component::SimpleDBI->new('db') or die "Can't create DBI session";

POE::Session->create(
    inline_states => {
        _start           => \&irc_start,
        irc_001          => \&irc_on_connect,
        irc_kick         => \&irc_on_kick,
        irc_public       => \&irc_on_public,
        irc_ctcp_action  => \&irc_on_public,
        irc_msg          => \&irc_on_public,
        irc_notice       => \&irc_on_notice,
        irc_disconnected => \&irc_on_disconnect,
        irc_topic        => \&irc_on_topic,
        irc_join         => \&irc_on_join,
        irc_332          => \&irc_on_jointopic,
        irc_331          => \&irc_on_jointopic,
        irc_nick         => \&irc_on_nick,
        irc_chan_sync    => \&irc_on_chan_sync,
        db_success       => \&db_success,
        delayed_post     => \&delayed_post,
        heartbeat        => \&heartbeat,
    },
);

POE::Kernel->run;
print "POE::Kernel has left the building.\n";

# vim: set sw=4
