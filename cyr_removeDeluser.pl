#!/usr/bin/perl -w
#
# This will remove all mailboxes with LDAP mailUserStatus=deleted and change this to
# removed. Just be 
# sure that you installed the Cyrus::IMAP perl module.  If you did 
# don't have to do anything at all.
#
# Change the params below to match your mailserver settins, and
# your good to go!
#
# Author: Marco Fav
#
#
# Usage:
#  filename itself. Crontab or systemd timer suggested!

my $logproc = 'removedeluser';
my $desc = "permanently remove mailboxes flagged as 'deleted' over LDAP. Provide the following parameters:\n";

#
# CONFIGURATION PARAMS
#
use Getopt::Long::Descriptive;
use Config::IniFiles;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');

my $ldapHost    = $cfg->val('ldap','server');
my $ldapPort    = $cfg->val('ldap','port');
my $ldapBase    = $cfg->val('ldap','baseDN');  # Base dn containing whole domains
my $ldapBindUid = $cfg->val('ldap','user');
my $ldapBindPwd = $cfg->val('ldap','pass');

# Why the following test? Because if you specify in Config
# grace =
# then $cfg->val('orphan','grace') become a null array!
if ( ref($cfg->val('orphan','grace')) eq 'ARRAY') {
	die("The default grace parameter in your config file is wrong. Check it!\n");
}
my $grace = $cfg->val('orphan','grace');
my $verbose = 1;

#
# EOC
#

# Parameter handler
my ($opt, $usage) = describe_options(
	'%c %o '.$desc,
	[ 'd=s', 'the domain where to run', { required => 1} ],
	[ 'g=i', 'optional grace days other than default' ],
	[],
	[ 'help',       "print usage message and exit", { shortcircuit => 1 } ],
	[],
);

print($usage->text), exit 0 if $opt->help;
@ARGV == 0
	or die("\nToo many arguments.\n\n".$usage->text);
my $domain = $opt->d;
if ( defined($opt->g) ) {
	$grace = $opt->g;
}
$ldapBase = "o=$domain,ou=People,".$ldapBase;

require "/usr/local/cyr_scripts/core.pl";


######################################################
#####			MAIN			######
######################################################

my $ok = removeDelUser ( $logproc, $ldapHost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$cyrus_user,$cyrus_pass,$grace, $sep, $verbose );
if (!$ok) {
	print "\n\n\e[33mSome errors occur. Please, see urgently the logs.\e[39m\n\n";
	exit(255);
}
exit(0);
