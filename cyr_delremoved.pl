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

require "/usr/local/cyr_scripts/core.pl";
use vars qw($cyrus_server $cyrus_user $cyrus_pass);

#
# CONFIGURATION PARAMS
#
my $ldapHost = 'ldap.example.com';
my $ldapPort = 489;
my $ldapBase = 'o=servizirete,cn=en';
my $ldapBindUid = 'uid=admin,cn=en';
my $ldapBindPwd = 'ldapassword';
my $verbose = 1;


#
# EOC
#


######################################################
#####			MAIN			######
######################################################

my $logproc = 'delremoved';
delRemovedUser ( $logproc, $ldapHost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$cyrus_user,$cyrus_pass, $verbose );
