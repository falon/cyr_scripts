#!/usr/bin/perl 
#
# All this code written by Marco Fav, so you must use better code. You are advised!

#  -u1 <user1> -u2 <user2> -q <quota> -fw <mail>               migrate <user> with <quota> KB
#  -f <file>                               use a file in the form <user1>,<user2>,<quota> KB,<mail>

# Config setting#

use Getopt::Long;
use Mail::IMAPTalk;
use Sys::Syslog;
use Switch;

require '/usr/local/cyr_scripts/core.pl';
#
# CONFIGURATION PARAMS
#
my $dest_server = "msg.example.com";
my $dest_user = "imapadmin";
my $dest_pass = "password";
my $dest_port = 143;
my $orig_server = 'localhost';
my $orig_user = 'imapadm';
my $orig_pass = 'password';
my $orig_port = 143;
my $mainproc = 'imapxfer';
my $logfac = 'LOG_MAIL';
my $debug =1;
my $imapsync = `which imapsync`;
# Following opt line works with imapsync 1.404.
my $imapsynopt = '--authmech1 PLAIN --authmech2 PLAIN --expunge --subscribed --subscribe --syncacls --fastio1 --fastio2 --noreleasecheck --nofoldersizes --proxyauth1 --usecache';
# Set forward to new mailbox into original LDAP accounts?
my $forward = 1;
if ($forward) {
	$nolocalcopy =1;	# if set to 1 prevent local copy
	$origUidNotDom = 1;	# use only local part of uid when look for username in LDAP to set forward.
	$ldaphost    = 'testldap.example.com';
	$ldapPort    = 389;
	$ldapBase    = 'cn=en';       # Base dn containing whole domains
	$ldapBindUid = 'uid=admin,cn=en';
	$ldapBindPwd = 'password';
	$smtpdest	= 'smtprelay.example.com'; 
}
# Only for -d option:
my $quota_def = undef;
#
# EOC
#


######################################################
#####                   MAIN                    ######
######################################################

my $usage  = "\nUsage:\t$0 -u1 <user1> -u2 <user2> -q <newquota> (KB) -fw <email>\n";
$usage .= "\t$0 -f <file>\n";
$usage .= "\t read a file with lines in the form <user1>,<user2>,[<newquota> (KB),<email>]\n";
$usage .= "\t $0 -d <domain>\n";
$usage .= "\tprepare a file named IMAPxfer_<domain> with lines in the form <user>,<user>,<quota>,<mail_fw> for you. No changes to systems.\n";
$usage .= "IMAP transfer based on imapsync by Gilles LAMIRAL\n";
$usage .= "Start always with -u1 or -f or -d, please.\n\n";

chop($imapsync);
if ($imapsync !~ /imapsync$/) {die("\n\nimapsync program not found with \'which\'. Please install it.\n\n");}

if (($#ARGV < 1) || ($#ARGV > 7)) {
        print $usage;
        exit;
}

openlog("$mainProc",'pid','LOG_MAIL');


     for ( $ARGV[0] ) {
         if    (/^-u1/)  {
                if ($#ARGV <2) { print $usage; die("\nI need  <user1> <user2> [<newquota> <mail2>]\n"); }
                GetOptions(	'u1=s' => \$user1[0],
                		'u2=s' => \$user2[0],
            			'q:s' => \$quota_size[0],
				'fw:s' => \$mail2[0]
		);
                $i=1;
        }
        elsif (/^-f/)  {
                if ($#ARGV != 1) { print $usage; die ("\nI need the file name!\n"); }
                $data_file=$ARGV[1];
                open(DAT, $data_file) || die("Could not open $data_file!");
                @raw_data=<DAT>;
                close(DAT);
                foreach $line (@raw_data)
                {
                        chomp($line);
                        @PARAM=split(',',$line,4);
                        if ($#PARAM < 3) { die printLog('LOG_WARNING',"EXIT. \nInconsistency in line\n<$line>\n Recheck <$data_file>\n",$debug); }
                        else {
                                ($user1[$i],$user2[$i],$quota_size[$i],$mail2[$i])=@PARAM;
                                $mail2[$i]=~ s/\s+$//;  # Remove trailing spaces at EOL
                        }
                        $i++;
                }
                print "\nFound $i accounts\n";
         }
         elsif    (/^-d/)  {
                if ($#ARGV <1) { print $usage; die("\nI need <domain> parameter.\n"); }
		if ($forward == 0) { print $usage; die("\nYou must set forward in config.\n"); }
                $domain = $ARGV[1];
                prepareIMAPXferDomain($mainproc, $ldaphost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$domain,$origUidNotDom,$orig_server,$quota_def,$smtpdest,$debug);
                die ("The file IMAPxfer_$domain has created for your convenience. No changes made to systems.\n\n");
         }

        else { die($usage); }
   }

my %arrayimapt = (
      Server   => $dest_server,
      Username => $dest_user,
      Password => $dest_pass,
      Port     => $dest_port,
      Uid      => 1
); 
$IMAP = Mail::IMAPTalk->new( %arrayimapt )
    || die (printLog('LOG_WARNING',"EXIT. Failed to connect/login to IMAP server <$dest_server> on port <$dest_port>. Reason: $@",$debug));


for ($c=0;$c<$i;$c++) {

        printLog('LOG_INFO',"\n".'INFO. Starting work on <'.$user1[$c].'>...',$debug);

	#### Set forward on original LDAP server ####
	if ( ($forward) && ($mail2[$c] ne '') ) {
		my $attr = {
        		mailDeliveryOption => 'forward',
        		mailForwardingAddress => '@'."$smtpdest:".$mail2[$c]
		};
		if ( $origUidNotDom ) {
			($username,$dm) = split('@',$user1[$c]);
		}
		else {
			$username = $user1[$c];
		}
		printLog('LOG_INFO','INFO. Setting forward for uid <'.$user1[$c].'> to mail <'.$mail2[$c].'> on <'.$smtpdest.'>...',$debug);
		ldapModAttr($mainproc, $ldaphost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$username,$attr,'add',$debug);
		if ($nolocalcopy) {
			my $attr = {
				mailDeliveryOption => 'mailbox'
			};
			printLog('LOG_INFO','INFO. Setting forward for uid <'.$user1[$c].'> with no local copy...',$debug);
			ldapModAttr($mainproc, $ldaphost,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$username,$attr,'delete',$debug);
		}
	}	

	#### Get current quotaroot threshold ####
	my $Result = $IMAP->getquotaroot('user'.sep().$user2[$c]) || die (printLog('LOG_WARNING',"EXIT. Failed to get quota for ".$user2[$c].".Reason: $@", $debug));
	my $quota = $Result->{'user'.sep().$user2[$c]}[2];
	printLog('LOG_INFO','INFO. Quota for <'.$user2[$c]."> is $quota KB.",$debug);


	#### Set NIL quotaroot ####
	$IMAP->setquota('user'.sep().$user2[$c], '()') || die (printLog($logtag,$logfac,'LOG_WARNING',"EXIT. Failed to remove quota for ".$user2[$c].".Reason: $@",$debug));
	printLog('LOG_INFO','INFO. Quota for <'.$user2[$c].'> has removed.',$debug);

	#### IMAPSYNC ####
	printLog('LOG_INFO','INFO. Starting IMAP migration of '.$user1[$c]." to $dest_server...",$debug);
	@sync = `$imapsync --host1 $orig_server --port1 $orig_port --user1 $user1[$c] --authuser1 $orig_user --password1 $orig_pass --host2 $dest_server --port2 $dest_port --user2 $user2[$c] --authuser2 $dest_user --password2 $dest_pass $imapsynopt`;
	foreach $line (@sync) {
		chop($line);
		printLog('LOG_INFO','INFO. '.$line,$debug);
	}
	if ($? != 0) {
		printLog('LOG_ALERT','SEVERE ERROR. Errors in IMAP transfer of <'.$user1[$c].'>. Check previous log\'s lines for more details.', $debug);
	}
	else {
		        printLog('LOG_INFO','INFO. User <'.$user1[$c].'> has migrated successfully into <'.$user2[$c]."> from $orig_server to $dest_server.",$debug);
	}
 
			
	#### Restore quota root ####
        if (!($IMAP->is_open())) {
                printLog('LOG_WARNING',"INFO. Reconnecting to IMAP server <$dest_server> on port <$dest_port> due to timeout exceeded.",$debug);
                $IMAP = Mail::IMAPTalk->new( %arrayimapt )
                || die (printLog('LOG_WARNING',"EXIT. Failed to reconnect/login to IMAP server <$dest_server> on port <$dest_port>. Reason: $@",$debug));
        }
	if ($quota_size[$c]!='') {
		$IMAP->setquota('user'.sep().$user2[$c], "(STORAGE ".$quota_size[$c].')') || die (printLog($logtag,$logfac,'LOG_ALERT',"EXIT. Failed to set quota for ".$user2[$c].' at '.$quota_size[$c]." KB. Reason: $@",$debug));
                printLog($logtag,$logfac,'LOG_INFO','INFO. As your choice quota for <'.$user2[$c].'> has set to '.$quota_size[$c]." KB in place of previously value $quota KB.",$debug);
	}
	else {
		$IMAP->setquota('user'.sep().$user2[$c], "(STORAGE $quota)") || die (printLog($logtag,$logfac,'LOG_ALERT',"EXIT. Failed to restore quota for ".$user2[$c]." at $quota KB. Reason: $@",$debug));
		printLog('LOG_INFO','INFO. Quota for <'.$user2[$c]."> has restored to $quota KB.",$debug);
	}

	#### Successful end ####
	printLog('LOG_INFO','INFO. Work on <'.$user1[$c].'> terminated.'."\n",$debug);
}


$IMAP->logout();

