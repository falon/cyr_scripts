#!/usr/bin/perl  

# Usage:
#  -h <imap server> -u <user> <destServer> [part]	transfer <user> in <destServer> 
#							into new partition <part>. User will be removed from
#							origin server.
#  -h <imap server> -f <file>		use a file in the form <user> <destServer> [<part>]
#  -d <domain> <destServer> [part]	Prepare a file xfer_<domain> for you! No change to systems.
#
# Prerequisite: admin uid and password for the two imap servers are the same.
#

use Config::IniFiles;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
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
use Getopt::Long::Descriptive;

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



my $desc = "transfer with XFER <user> to <destServer> into new optional partition <part>.\n";
$desc .= "\tProvide the following parameters:\n";

my @old = undef;
my @new = undef;
my @part= undef;
my @destServer = undef;
my $i = 0;
my $c = 0;
my $mainproc = 'CyrXfer';

my ($opt, $usage) = describe_options(
  '%c %o '.$desc,
  [ 'h=s', 'the server to connect to' ],
  [ "mode" =>
        hidden => {
                one_of => [
                        [ 'user=s', 'the root mailbox to transfer' ],
                        [ 'file|f=s', 'read a file with lines in the form  <user>;<destServer>[;<part>]' ],
			[ 'd=s', 'prepare a file named xfer_<domain> with lines in the form <user>;<destServer>;[<part>] for you. No changes applied.' ],
                ],
        },
  ],
  [],
  [ 'dest=s', 'the destination server (in combination with --user or -d)' ],
  [ 'part=s', 'the destination partition (in combination with --user or -d)' ],
  [],
  [],
  [ 'help',       "print usage message and exit", { shortcircuit => 1 } ],
  [],
);

print($usage->text), exit 255 if $opt->help;
@ARGV == 0
        or die("\nToo many arguments.\n\n".$usage->text);

if (not defined($opt->mode)) {
        die("\nInsufficient arguments.\n\n".$usage->text);
}
if ($opt->mode eq 'user') {
	defined($opt->h)
		or die("\nParameter -h required.\n");
	my $cyrus_server = $opt->h;
        if ($opt->u  =~ /\Q$sep/) {
                die("\nYou must specify a root mailbox in '--user'.\n");
        }
        $user[0] = $opt->user;
        if ( defined($opt->dest) ) {
                $destServer[0] = $opt->dest;
        }
        else { die("\nParameter --dest required.\n"); }
	defined($opt->part)
		or $part[0]='';
        $i=1;
}

if ($opt->mode eq 'd') {
	defined($opt->dest)
		or die("\nParameter --dest required.\n");
	if ( defined($opt->part) ){
		$partition = $opt->part;
	}
	else {
		$partition = '';
	}
	if ( prepareXferDomain($mainproc,$ldaphost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$opt->d,$origServer,$opt->dest,$partition,$v) == 0 ) {
		print "\n\nThe file xfer_" . $opt->d . " has created for your convenience. No changes made to systems.\n\n";
		exit (0);
	}
	else {
		exit(255);
	}
}

if ($opt->mode eq 'file') {
        $data_file = $opt->file;
        open(DAT, $data_file) || die("Could not open $data_file!");
        @raw_data=<DAT>;
        close(DAT);
        foreach $line (@raw_data) {
                wchomp($line);
                @PARAM=split(/\;/,$line,3);
                if (($#PARAM <1) || ($#PARAM >2)) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
                else {  if ($#PARAM == 2) {
				($user[$i],$destServer[$i],$part[$i])=@PARAM;
			}
			else {($user[$i],$destServer[$i])=@PARAM; $part[$i]=''; }
                $i++;
        	}
	}	
        print "\nFound $i accounts\n";
}
## End of parameter handler

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
