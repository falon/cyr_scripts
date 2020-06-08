#!/usr/bin/perl

use strict;
use vars qw($build);
my $verbose = 0;
my $logproc = 'cyrVersion';
my $desc = " show the Cyrus version running on host provided in -h switch:\n";
use Getopt::Long::Descriptive;
use Config::IniFiles;
# Parameters handler
(my $opt, my $usage) = describe_options(
   '%c %o '.$desc,
     [ 'h=s', 'the server to connect to', { required => 1} ],
     [],
     [ 'help',       "print usage message and exit", { shortcircuit => 1 } ],
     [],
);

print($usage->text), exit 0 if $opt->help;
@ARGV == 0
	or die("\nToo many arguments.\n\n".$usage->text);
my $cyrus_server = $opt->h;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');
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
