#!/usr/bin/perl  

# Usage:
#  -u <user> <destServer> [part]           transfer <user> in <destServer> 
#					   into new partition <part>. User will be removed from
#					   origin server.
#  -f <file>				   use a file in the form <user> <destServer> [<part>]
#  -d <domain> <destServer> [part]	   Prepare a file xfer_<domain> for you! No change to systems.
#
# NOTE: this program MUST be run locally with open-xchange.
# Prerequisite: admin uid and password for the two imap server are the same.
#

use Config::Simple;
my $cfg = new Config::Simple();
$cfg->read('cyr_scripts.ini');
my $imapconf = $cfg->get_block('imap');
my $sep = $imapconf->{sep};
my $cyrus_user = $imapconf->{user};
my $cyrus_pass = $imapconf->{pass};
my $ldapconf = $cfg->get_block('ldap');
my $xferconf = $cfg->get_block('xfer');
require "/usr/local/cyr_scripts/core.pl";
use URI;

# Config setting#

my $v = 1;	# verbosity to STDOUT
# LDAP
my $ldaphost	= $ldapconf->{server};
my $ldapPort	= $ldapconf->{port};
my $ldapBase	= $ldapconf->{baseDN};	# Base dn containing whole domains
my $ldapBindUid	= $ldapconf->{user};
my $ldapBindPwd	= $ldapconf->{pass};
# Orig Cyrus Server
my $origServer	= $xferconf->{origserver}; 			# Cyrus server where relocating from
# OPEN-XCHANGE
my $noproxy = $xferconf->{noproxy};
my $netloc = $xferconf->{netloc};
my $realm = $xferconf->{realm};
my $apiuser = $xferconf->{apiuser};
my $apipwd = $xferconf->{apipwd};
my $url = URI->new( $xferconf->{url} );




## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -u <user> <destServer> [part]\n";
$usage .= "\ttransfer <user> in <destServer>\n";
$usage .= "\tinto new partition <part>. User will be removed from origin server.\n\n";
$usage .= "\t $0 -f <file>\n";
$usage .= "\tread a file with lines in the form <user>;<destServer>[;<part>]\n\n";
$usage .= "\t $0 -d <domain> <destServer> [part]\n";
$usage .= "\tprepare a file named xfer_<domain> with lines in the form <user>;<destServer>;[<part>] for you. No change to systems.\n\n";

my @old = undef;
my @new = undef;
my @part= undef;
my @destServer = undef;
my $i = 0;
my $c = 0;
my $mainproc = 'CyrXfer';


if (($#ARGV < 1) || ($#ARGV > 3)) {
	print $usage;
	exit;
}


     for ( $ARGV[0] ) {
	 if    (/^-u/)  {
		if ($#ARGV <2) { print $usage; die("\nI need at least <user> and <destServer>\n"); }
		$user[0]=$ARGV[1];
                if ($user[0] =~ /$sep/) {
                        die("\nYou must specify a root mailbox in -u.\n$usage");
                }
		$destServer[0]=$ARGV[2];
		if ($#ARGV == 3) {$part[0]=$ARGV[3];}
		else {$part[0]='';}
		$i=1;
	 }
     
	 elsif (/^-(-|)f/)  {
		if ($#ARGV != 1) { print $usage; die ("\nI need the file name!\n"); }
		$data_file=$ARGV[1];
		open(DAT, $data_file) || die("Could not open $data_file!");
		@raw_data=<DAT>;
		close(DAT);
		foreach $line (@raw_data)
		{
			chomp($line);
			@PARAM=split(/\;/,$line,3);
			if (($#PARAM <1) || ($#PARAM >2)) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
			else { if ($#PARAM == 2) {
				($user[$i],$destServer[$i],$part[$i])=@PARAM; }
				else {($user[$i],$destServer[$i])=@PARAM; $part[$i]=''; }
			}
			$i++;
		}
		print "\nFound $i accounts\n";  
	 }

	 elsif    (/^-d/)  {
		if ($#ARGV <2) { print $usage; die("\nI need at least <domain> <destServer>\n"); }
		$domain = $ARGV[1];
		$destServer=$ARGV[2];
		if ($#ARGV == 3) {$part=$ARGV[3];}
		else {$part='';}
		prepareXferDomain($mainproc,$ldaphost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$domain,$origServer,$destServer,$part,$v);
		die ("The file xfer_$domain has created for your convenience. No changes made to systems.\n\n");
	 }
     

	 else           { print $usage; die("Make sense in what you write, stupid user!\n"); }     # default
     }



#
# assuming all necessary variables have been declared and filled accordingly:
#

use Sys::Syslog;
use Cyrus::IMAP::Admin;
my $cyrus;


my $auth = {
    -mechanism => 'login',
    -service => 'imap',
    -authz => $cyrus_user,
    -user => $cyrus_user,
    -minssf => 0,
    -maxssf => 10000,
    -password => $cyrus_pass,
};

if ( ($cyrus = cyrusconnect($mainproc, $auth, $origServer, $v)) == 0) {
        exit(255);
}


LOOP: for ($c=0;$c<$i;$c++) {
		if ( $origServer eq $destServer[$c] ) {
			openlog("$mainproc", "pid", LOG_MAIL);
			printLog('LOG_ERR',"action=cyrxfer status=fail mailbox=\"".$user[$c].
				"\" mailHost=${destServer[$c]} detail=\"Orig Server and Destination server are the same.\"", $v);
			closelog();
			next LOOP;
		}

		$url->query_form(
		  'uid'         => $user[$c],
		  'archiveOnly' => 'false',
		  'asynch'      => 'false'
		);

		print 'Start transferring <'.$user[$c].'> on <'.$destServer[$c].'>... ';
		if ( transferMailbox($mainproc, $cyrus,$user[$c],$destServer[$c],$part[$c],$sep,0) ) {
			if ( ldapReplaceMailhost($mainproc, $ldaphost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$user[$c],$origServer,$destServer[$c],0) ) {
				if ( changeOXIMAPServer($mainproc, $apiuser, $apipwd, $netloc, $realm, $url, $noproxy,0) ) {
					print 'OK. Job terminated with success.'."\n";
				}
				else {
					print "FAIL in change OX server. See at logs for details.\n";
				} 
			}
			else {
				print "FAIL replacing mailHost over LDAP. See at logs for details.\n";
			}
		}
		else {
			print "FAIL in Cyrus XFER operation.\n";
		}
}
