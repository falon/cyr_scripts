#!/usr/bin/perl  
#
# by Paolo Cravero, 20131009

# Usage:
#  -u <user> 	get mailhost for user, if exists. Error otherwise.
#

require "/usr/local/cyr_scripts/core.pl";

# Config setting#
use Config::IniFiles;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
# LDAP
my $ldaphost    = $cfg->val('ldap','server');
my $ldapPort    = $cfg->val('ldap','port');
my $ldapBase    = $cfg->val('ldap','baseDN');  # Base dn containing whole domains
my $ldapBindUid = $cfg->val('ldap','user');
my $ldapBindPwd = $cfg->val('ldap','pass');


## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -u <email.address@example.com>\n";
$usage .= "Verify the existance of a mailrecipient object on LDAP.\n\n";

my @old = undef;
my @new = undef;
my @part= undef;
my $i = 0;
my $c = 0;
my $verbose=1;
my $logproc='checkLDAPUser';


if (($#ARGV < 1) || ($#ARGV > 1)) {
	print $usage;
	exit;
}

     for ( $ARGV[0] ) {
	 if    (/^-u/)  {
		if ($#ARGV <1) { print $usage; die("\nI need <email.address@example.com>>\n"); }
		$user[0]=$ARGV[1];
		$i=1;
	 }
     
     }



#
# assuming all necessary variables have been declared and filled accordingly:
#

my $exit = 0;
for ($c=0;$c<$i;$c++) {
		ldapCheckUserExists($logproc,$ldaphost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$user[$c],$verbose)
			or $exit++;
}
exit( $exit );
