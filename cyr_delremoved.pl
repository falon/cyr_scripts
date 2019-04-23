#!/usr/bin/perl -w
#
# This will remove all mailboxes with LDAP mailUserStatus=removed. Just be 
# sure that you installed the Cyrus::IMAP perl module.  If you did 
# 'make all && make install' or installed Cyrus using the FreeBSD ports you
# don't have to do anything at all.
#
# Change the params below to match your mailserver settins, and
# your good to go!
#
# Author: Marco Fav
#
#
# Usage:
#  filename itself. Crontab suggested!


# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0\n\n";

if ($#ARGV >= 0) {
        print $usage;
        exit;
}

use Config::IniFiles;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
my $cyrus_server = $cfg->val('imap','server');
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');

my $ldapHost    = $cfg->val('ldap','server');
my $ldapPort    = $cfg->val('ldap','port');
my $ldapBase    = $cfg->val('ldap','baseDN');  # Base dn containing whole domains
my $ldapBindUid = $cfg->val('ldap','user');
my $ldapBindPwd = $cfg->val('ldap','pass');

require "/usr/local/cyr_scripts/core.pl";

my $verbose = 1;


#
# EOC
#


######################################################
#####			MAIN			######
######################################################

my $logproc = 'delremoved';
my $exit = 0;
my $status=delRemovedUser ( $logproc, $ldapHost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$cyrus_user,$cyrus_pass, $sep, $verbose );

if ($status) {
	print 'Process successfully completed';
}
else {
	print 'Process exited abnormally due to errors';
	$exit = 1;
}
print "\n";
exit($exit);
