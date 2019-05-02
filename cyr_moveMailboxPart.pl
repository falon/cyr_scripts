#!/usr/bin/perl  -w

use Config::IniFiles;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
my $cyrus_server = $cfg->val('imap','server');
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');
my $exit = 0;
require "/usr/local/cyr_scripts/core.pl";

# Config setting#


## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -mboxold <user_now> -folderold <foldernow> -mboxnew <user_new> -foldernew <foldernew> [-p part] [-autopart] [-oldpart]\n";
$usage .= "\tmove <foldernow> of <user_now> in <foldernew> of <user_new>\n";
$usage .= "\tinto new partition <part>\n";
$usage .="\t* or into partition of <mboxnew> domain defined by Partition Manager if -autopart\n";
$usage .="\t* or into partition of <foldernow> if -oldpart\n";
$usage .="\t  use either oldpart or autopart, or none. Both are not allowed.\n\n";
$usage .= "\t $0 -file <file> [-utf7]\n";
$usage .= "\tread a file with lines in the form <user_now>;<foldernow>;<user_new>;<foldernew>;<part>\n";
$usage .= "\tthe optional utf7 flag let you to write folders already utf7-imap encoded.\n";
$usage .= "\t<part> can be the empty or null char if you don't want to specify the partition.\n";
$usage .= "\tie\n\t\tmbox1;folder1;mbox2;folder2;\n\n";

my $auth = {
    -mechanism => 'login',
    -service => 'imap',
    -authz => $cyrus_user,
    -user => $cyrus_user,
    -minssf => 0,
    -maxssf => 10000,
    -password => $cyrus_pass,
};

my @mboxold = undef;
my @mboxnew = undef;
my $fdrold = undef;
my $fdrnew = undef;
my @folderold = undef;
my @foldernew = undef;
my @part= undef;
my $autopart = 0;
my $oldpart = 0;
my $i = 0;
my $c = 0;
my $v = 1; #verbosity
my $logproc = 'renameMailbox';
## Parameter used to check if an account is logged in
my $procdir = $cfg->val('logintest','procdir');
# Interval time to check if account is logged
my $Tw =  $cfg->val('logintest','Tw');
# Set 1 to check if account is logged in before move folders
my $useAccountCheck =  $cfg->val('logintest','active');


use Getopt::Long;
use Unicode::IMAPUtf7;
use Encode;
my $code=$cfg->val('code','code');
my $imaputf7 = Unicode::IMAPUtf7->new();
my $utf7 = 0;

if (! defined($ARGV[0]) ) {
	        die($usage);
}

for ( $ARGV[0] ) {
	if (/^-(-|)mboxold/)  {
		GetOptions(     'mboxold=s'	=> \$mboxold[0],
				'folderold:s'	=> \$fdrold,
				'mboxnew=s'	=> \$mboxnew[0],
				'foldernew:s'	=> \$fdrnew,
				'part:s'	=> \$part[0],
				'autopart'	=> \$autopart,
				'oldpart'	=> \$oldpart	
		) or die($usage);
		@ARGV == 0
			or die("\nToo many arguments.\n$usage");
                if (defined($fdrold)) {
			if ($fdrold =~ /\$sep/) {
				die(\"nYou must specify a root mailbox in '-u'.\n$usage");
			}
			$folderold[0] = $imaputf7->encode(encode($code,$fdrold));
		}
		else { $folderold[0] = 'INBOX'; }
		if (defined($fdrnew)) {
			if ($fdrnew =~ /\$sep/) {
				die(\"nYou must specify a root mailbox in '-u'.\n$usage");
			}
			$foldernew[0] = $imaputf7->encode(encode($code,$fdrnew));
		}
		else { $foldernew[0] = 'INBOX'; }
		defined($mboxnew[0])
			or die("\nParameter mboxnew required.\n$usage");
		defined($part[0])
			or $part[0]='';
		$i=1;
	}
	elsif (/^-(-|)file/)  {
		GetOptions(     'file=s'   => \$data_file,
				'utf7'   => \$utf7
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
			@PARAM=split(/\;/,$line,5);
			if ($#PARAM != 4) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
			else {
				($mboxold[$i],$fdrold,$mboxnew[$i],$fdrnew,$part[$i])=@PARAM;
				 $part[$i]=~ s/\s+$//;  # Remove trailing spaces
				 if ($utf7 == 0) {
				 	$folderold[$i] = $imaputf7->encode(encode($code,$fdrold));
				 	$foldernew[$i] = $imaputf7->encode(encode($code,$fdrnew));
				}
				else {
					$folderold[$i] = $fdrold;
					$foldernew[$i] = $fdrnew;
				}
			 }
			 $i++;
		}
		print "\nFound $i mailboxes\n";
	}
	else { die($usage); }
}


#
# assuming all necessary variables have been declared and filled accordingly:
#

use Cyrus::IMAP::Admin;
my $cyrus;

if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $v)) == 0) {
        exit(255);
}

use Sys::Syslog;
openlog("$logproc/master", "pid", LOG_MAIL);

for ($c=0;$c<$i;$c++) {

	if ( $useAccountCheck ) {
		if ($mboxold[$c] eq $mboxnew[$c]) {
			accountIsLogged($logproc, $mboxold[$c], $procdir, $Tw, $v);		# wait forever if the account is logged!
		}
		else {
			accountIsLogged($logproc, $mboxold[$c], $procdir, $Tw, $v);
			accountIsLogged($logproc, $mboxnew[$c], $procdir, $Tw, $v);
		}
	}
	if ($part[$c] eq '') {
		if ($oldpart) {
			# Set partition of moving mailbox in new mailbox
			$part[$c] = getPart($logproc, $cyrus, $mboxold[$c], $folderold[$c], $sep, $v);
		}
        	if ($autopart) {
			# CSI Partition Manager choice
			if ($oldpart) {
				printLog('LOG_ERR', "action=renmailbox status=fail mailbox=${mboxold[$c]} folder=\"${folderold[$c]}\" newmailbox=${mboxnew[$c]} newfolder=\"${foldernew[$c]}\" partition=${part[$c]} error=\"You define both oldpart and autopart. Not allowed. Exiting without any changes.\"",$v);
				exit(255);
			}
			$part[$c] = getDomainPart($logproc, $cyrus, $mboxnew[$c], $v);
		}
	}
	else {
		if ($oldpart or $autopart) {
			printLog('LOG_WARNING', "action=renmailbox status=notice mailbox=${mboxold[$c]} folder=\"${folderold[$c]}\" newmailbox=${mboxnew[$c]} newfolder=\"${foldernew[$c]}\" partition=${part[$c]} detail=\"You define explicit partition name, but some partitions flag too. Explicit declaration takes precedence.\"", $v);
		}
	}
	if ($part[$c] eq 'NIL') {
		printLog('LOG_ERR', "action=renmailbox status=fail mailbox=${mboxold[$c]} folder=\"${folderold[$c]}\" newmailbox=${mboxnew[$c]} newfolder=\"${foldernew[$c]}\" partition=${part[$c]} error=\"An error occurred defining partition by oldpart or autopart flag. Skipping.\"", $v);
		$exit++;
		next;
	}

	# Oh, finally we can proceed!
	renameMailbox($logproc, $cyrus ,$mboxold[$c], $folderold[$c], $mboxnew[$c], $foldernew[$c], $part[$c], $sep, $v)
		or $exit++;
}
closelog();
exit($exit);
