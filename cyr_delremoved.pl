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

use Config::Simple;
my $cfg = new Config::Simple();
$cfg->read('/usr/local/cyr_scripts/cyr_scripts.ini');
my $imapconf = $cfg->get_block('imap');
my $sep = $imapconf->{sep};
my $cyrus_server = $imapconf->{server};
my $cyrus_user = $imapconf->{user};
my $cyrus_pass = $imapconf->{pass};

my $ldapconf = $cfg->get_block('ldap');
my $ldapHost    = $ldapconf->{server};
my $ldapPort    = $ldapconf->{port};
my $ldapBase    = $ldapconf->{baseDN};  # Base dn containing whole domains
my $ldapBindUid = $ldapconf->{user};
my $ldapBindPwd = $ldapconf->{pass};
require "/usr/local/cyr_scripts/core.pl";

my $verbose = 1;


#
# EOC
#


######################################################
#####			MAIN			######
######################################################

my $logproc = 'delremoved';
my $status=delRemovedUser ( $logproc, $ldapHost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$cyrus_user,$cyrus_pass, $sep, $verbose );

if ($status) {
	print 'Process successfully completed';
}
else {
	print 'Process exited abnormally due to errors';
}
print "\n";
