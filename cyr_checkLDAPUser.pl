#!/usr/bin/perl  
#
# by Paolo Cravero, 20131009

# Usage:
#  -u <user> 	get mailhost for user, if exists. Error otherwise.
#

require "/usr/local/cyr_scripts/core.pl";

# Config setting#
use Config::Simple;
my $cfg = new Config::Simple();
$cfg->read('/usr/local/cyr_scripts/cyr_scripts.ini');
# LDAP
my $ldapconf = $cfg->get_block('ldap');
my $ldaphost    = $ldapconf->{server};
my $ldapPort    = $ldapconf->{port};
my $ldapBase    = $ldapconf->{baseDN};  # Base dn containing whole domains
my $ldapBindUid = $ldapconf->{user};
my $ldapBindPwd = $ldapconf->{pass};


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
