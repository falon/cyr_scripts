#!/usr/bin/perl -w
#
# This will remove all mailboxes with LDAP mailUserStatus=deleted and change this to
# removed. Just be 
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
#  filename itself. Crontab or systemd timer suggested!



## Change nothing below, if you are a stupid user! ##

my $logproc = 'removedeluser';
my $usage  = "\nUsage:\t$0 [-d domain] [-g day of grace]\n\n";

if ($#ARGV >= 4) {
        print $usage;
        exit;
}

if (($#ARGV == 0)||($#ARGV == 2)) { print $usage; die("Specify all parameters you want!\n"); }

#
# CONFIGURATION PARAMS
#
my $ldapHost = 'ldap.example.com';
my $ldapPort = 489;
my $ldapBase = 'o=servizirete,cn=en';
my $ldapBindUid = 'uid=admin,cn=en';
my $ldapBindPwd = 'ldapassword';
my $grace = '';
my $verbose = 1;

#
# EOC
#

if ($#ARGV >= 1) {
     for ( $ARGV[0] ) {
        if    (/^-d/)  {
		$ldapBase = "o=$ARGV[1],ou=People,".$ldapBase;
	}
	
	elsif (/^-g/) {
                $grace = $ARGV[1];	
        }
	else           { print $usage; die("Make sense in what you write, stupid user!\n"); }     # default
     }
}

if ($#ARGV >= 3) {
     for ( $ARGV[2] ) {
        if    (/^-d/)  {
                if ($ARGV[0] ne '-d') {$ldapBase = "o=$ARGV[3],ou=People,".$ldapBase;}
		else {die ("$usage\nDon't specify -d twice!\n");}
        }

        elsif (/^-g/) {
                if ($ARGV[0] ne '-g') {$grace = $ARGV[3];}
		else {die ($usage."Don't specify -g twice!\n");}
        }
        else           { print $usage; die("Make sense in what you write, stupid user!\n"); }     # default
     }
}

require "/usr/local/cyr_scripts/core.pl";
use vars qw($cyrus_server $cyrus_user $cyrus_pass);


######################################################
#####			MAIN			######
######################################################

my $ok = removeDelUser ( $logproc, $ldapHost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$cyrus_server,$cyrus_user,$cyrus_pass,$grace, $verbose );
if (!$ok) {
	print "\n\n\e[33mSome errors occur. Please, see urgently the logs.\e[39m\n\n";
}
