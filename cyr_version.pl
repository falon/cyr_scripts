#!/usr/bin/perl

use strict;
use vars qw($build);
use Config::Simple;
my $cfg = new Config::Simple();
$cfg->read('cyr_scripts.ini');
my $imapconf = $cfg->get_block('imap');
my $cyrus_server = $imapconf->{server};
require "/usr/local/cyr_scripts/core.pl";

print "\n\n Script version <$build> for host <$cyrus_server>\n\n\n";
