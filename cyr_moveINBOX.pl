#!/usr/bin/perl  -w

# Move INBOX to another folder at user level authorization.
# If you want to move a non INBOX folder to another folder
# you can use cyr_moveMailboxPart instead. It reuses the same connection
# when it runs on multiple users.

use Getopt::Long;
use Unicode::IMAPUtf7;
use Encode;
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

my $usage  = "\nUsage:\t$0 -user <user> -folder <folder> [-p part]\n";
$usage .= "\tmove INBOX of <user> into <folder>\n";
$usage .= "\twith new optional partition <part>, if allowed\n\n";
$usage .= "\t $0 -file <file> [-utf7]\n";
$usage .= "\tread a file with lines in the form <user>;<folder>;<part>\n";
$usage .= "\tthe optional utf7 flag let you to write folders already utf7-imap encoded.\n";
$usage .= "\t<part> can be the empty or null char if you don't want to change the partition.\n";
$usage .= "\tie\n\t\tuser1;folder1;\n\n";

my $auth = { };
my @user = undef;
my $fdr = undef;
my @folder = undef;
my @part= undef;
my $i = 0;
my $c = 0;
my $v = 1; #verbosity
my $logproc = 'renameINBOX';
## Parameter used to check if an account is logged in
my $procdir = $cfg->val('logintest','procdir');
# Interval time to check if account is logged
my $Tw =  $cfg->val('logintest','Tw');
# Set 1 to check if account is logged in before move folders
my $useAccountCheck =  $cfg->val('logintest','active');

my $code=$cfg->val('code','code');
my $imaputf7 = Unicode::IMAPUtf7->new();
my $utf7 = 0;

if (! defined($ARGV[0]) ) {
	        die($usage);
}

for ( $ARGV[0] ) {
	if (/^-(-|)user/)  {
		GetOptions(     'user=s'   => \$user[0],
				'folder:s' => \$fdr,
				'part:s'       => \$part[0]
		) or die($usage);
		@ARGV == 0
			or die("\nToo many arguments.\n$usage");
		if ($user[0] =~ /\$sep/) {
				die(\"nYou must specify a root mailbox in '-user'.\n$usage");
		}
		$folder[0] = $imaputf7->encode(encode($code,$fdr));
		defined($part[0])
			or $part[0]='';
		$i=1;
	}
	elsif (/^-(-|)h(|elp)$/) {
		print $usage;
		exit(0);
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
			@PARAM=split(/\;/,$line,3);
			if ($#PARAM != 2) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
			else {
				($user[$i],$fdr,$part[$i])=@PARAM;
				 $part[$i]=~ s/\s+$//;  # Remove trailing spaces
				 if ($utf7 == 0) {
				 	$folder[$i] = $imaputf7->encode(encode($code,$fdr));
				}
				else {
					$folder[$i] = $fdr;
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

for ($c=0;$c<$i;$c++) {

	$auth = {
		-mechanism => 'PLAIN',
		-service => 'imap',
		-authz => $user[$c],
		-user => $cyrus_user,
		-minssf => 0,
		-maxssf => 10000,
		-password => $cyrus_pass,
	};
	if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $v)) == 0) {
			$exit++;
		        next;
	}

	if ( $useAccountCheck ) {
		# wait forever if the account is logged!
		accountIsLogged($logproc, $user[$c], $procdir, $Tw, $v);
	}
	renameFolder($logproc, $cyrus, 'INBOX', $folder[$c], $part[$c], $sep, $v)
		or $exit++;
	$cyrus->send(undef, undef, 'LOGOUT');
}
exit($exit);
