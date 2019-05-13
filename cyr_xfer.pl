#!/usr/bin/perl  

# Usage:
#  -u <user> <destServer> [part]           transfer <user> in <destServer> 
#					   into new partition <part>. User will be removed from
#					   origin server.
#  -f <file>				   use a file in the form <user> <destServer> [<part>]
#  -d <domain> <destServer> [part]	   Prepare a file xfer_<domain> for you! No change to systems.
#
# Prerequisite: admin uid and password for the two imap servers are the same.
#

use Config::IniFiles;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
my $cyrus_server = $cfg->val('imap','server');
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');

my $ldaphost    = $cfg->val('ldap','server');
my $ldapPort    = $cfg->val('ldap','port');
my $ldapBase    = $cfg->val('ldap','baseDN');  # Base dn containing whole domains
my $ldapBindUid = $cfg->val('ldap','user');
my $ldapBindPwd = $cfg->val('ldap','pass');
my $exit = 0;
require "/usr/local/cyr_scripts/core.pl";
use URI;
use Getopt::Long;

# Config setting#

my $v = 1;	# verbosity to STDOUT
# Orig Cyrus Server
my $origServer	= $cfg->val('xfer','origserver'); 			# Cyrus server where relocating from
# OPEN-XCHANGE
my $noproxy = $cfg->val('xfer','noproxy');
my $netloc = $cfg->val('xfer','netloc');
my $realm = $cfg->val('xfer','realm');
my $apiuser = $cfg->val('xfer','apiuser');
my $apipwd = $cfg->val('xfer','apipwd');
my $url = URI->new( $cfg->val('xfer','url') );




## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -user <user> -dest <destServer> [-part part]\n";
$usage .= "\ttransfer <user> in <destServer>\n";
$usage .= "\tinto new partition <part>. User will be removed from origin server.\n\n";
$usage .= "\t $0 -file <file>\n";
$usage .= "\tread a file with lines in the form <user>;<destServer>[;<part>]\n\n";
$usage .= "\t $0 -d <domain> -dest <destServer> [-part part]\n";
$usage .= "\tprepare a file named xfer_<domain> with lines in the form <user>;<destServer>;[<part>] for you. No changes applied.\n\n";

my @old = undef;
my @new = undef;
my @part= undef;
my @destServer = undef;
my $i = 0;
my $c = 0;
my $mainproc = 'CyrXfer';


if (! defined($ARGV[0]) ) {
	die($usage);
}

for ( $ARGV[0] ) {
	 if    (/^-(-|)user/)  {
		GetOptions(
			'user=s'	=> \$user[0],
			'dest=s'	=> \$destServer[0],
			'part=s'	=> \$part[0]
		) or die($usage);
		@ARGV == 0
			or die("\nToo many arguments.\n$usage");
		defined($destServer[0])
			or die("\nParameter -dest required.\n$usage");
		if (defined($user[0])) {
			if ($user[0] =~ /\Q$sep/) {
				die("\nYou must specify a root mailbox in '-user'.\n$usage");
			}
		}
		defined($part[0])
			or $part[0]='';
		$i=1;
	 }
     
	 elsif (/^-(-|)file/)  {
		GetOptions(
			'file=s'   => \$data_file
		) or die($usage);
		@ARGV == 0
			or die("\nToo many arguments.\n$usage");
		defined($data_file)
			or die("\nfile required.\n$usage");
		open(DAT, $data_file) || die("Could not open $data_file!");
		@raw_data=<DAT>;
		close(DAT);
		foreach $line (@raw_data)
		{
			wchomp($line);
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

	 elsif    (/^-(-|)d/)  {
		my $partition = undef;
		GetOptions(
			'd=s'	=> \$domain,
			'dest=s'=> \$destServer,
			'part=s'=> \$partition
		) or die($usage);
		@ARGV == 0
			or die("\nToo many arguments.\n$usage");
		defined($destServer)
			or die("\n-dest required.\n$usage");
		defined($partition)
			or $partition='';
		prepareXferDomain($mainproc,$ldaphost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$domain,$origServer,$destServer,$partition,$v);
		print "\n\nThe file xfer_$domain has created for your convenience. No changes made to systems.\n\n";
		exit (0);
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
					$exit++;
				} 
			}
			else {
				print "FAIL replacing mailHost over LDAP. See at logs for details.\n";
				$exit++;
			}
		}
		else {
			print "FAIL in Cyrus XFER operation.\n";
			$exit++;
		}
}
exit($exit);
