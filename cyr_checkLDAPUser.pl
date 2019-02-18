#!/usr/bin/perl  
#
# by Paolo Cravero, 20131009

# Usage:
#  -u <user> 	get mailhost for user, if exists. Error otherwise.
#

require "/usr/local/cyr_scripts/core.pl";

# Config setting#


# LDAP
my $ldaphost	= 'ldap.example.com';
my $ldapPort	= 489;
my $ldapBase	= 'cn=en';	# Base dn containing whole domains
my $ldapBindUid	= 'uid=admin,cn=en';
my $ldapBindPwd	= 'ldapassword';


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

$return = 0;
for ($c=0;$c<$i;$c++) {
		$return += ldapCheckUserExists($logproc,$ldaphost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$user[$c],$verbose);
}

exit( $return );
