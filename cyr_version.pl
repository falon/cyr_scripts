#!/usr/bin/perl

use strict;
use vars qw($build);
use Config::Simple;
my $verbose = 0;
my $logproc = 'cyrVersion';
my $cfg = new Config::Simple();
$cfg->read('cyr_scripts.ini');
my $imapconf = $cfg->get_block('imap');
my $cyrus_server = $imapconf->{server};
my $sep = $imapconf->{sep};
my $cyrus_user = $imapconf->{user};
my $cyrus_pass = $imapconf->{pass};
my $client;
require "/usr/local/cyr_scripts/core.pl";

my $auth = {
	    -mechanism => 'login',
	    -service => 'imap',
	    -authz => $cyrus_user,
	    -user => $cyrus_user,
	    -minssf => 0,
	    -maxssf => 10000,
	    -password => $cyrus_pass,
};

if ( ($client = cyrusconnect($logproc, $auth, $cyrus_server, $verbose)) == 0) {
	        exit(255);
	}
my $version = cyrusVersion($client);

print "\n\n Script version \e[33m$build\e[39m for host \e[33m$cyrus_server\e[39m\n";
print " \e[33m$cyrus_server\e[39m is running a Cyrus IMAP version: \e[33m$version\e[39m\n\n";

exit(0);
