#!/usr/bin/perl  -w

# Usage:
#  -u <user_now> <user_new> [part]         move <user_now> in <user_new> (use form [userSEPuid])
#					   into new partition <part>
#  -f <file>				   use a file in the form <user_now> <user_new> [<part>]


require "/usr/local/cyr_scripts/core.pl";
use vars qw($cyrus_server $cyrus_user $cyrus_pass);

# Config setting#


## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -mboxold <user_now> -folderold <foldernow> -mboxnew <user_new> -foldernew <foldernew> [-p part]\n";
$usage .= "\tmove <foldernow> of <user_now> in <foldernew> of <user_new>\n";
$usage .= "\tinto new partition <part>\n\n";
$usage .= "\t $0 -f <file>\n";
$usage .= "\tread a file with lines in the form <user_now>,<foldernow>,<user_new>,<foldernew>,[<part>]\n\n";

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
my $i = 0;
my $c = 0;
my $v = 1; #verbosity
my $logproc = 'renameMailbox';
## Parameter used to check if an account is logged in
my $procdir = '/run/cyrus/proc';
# Interval time to check if account is logged
my $Tw = 60;
# Set 1 to check if account is logged in before move folders
my $useAccountCheck = 1;


use Getopt::Long;
use Unicode::IMAPUtf7;
use Encode;
my $code='ISO-8859-1';
my $imaputf7 = Unicode::IMAPUtf7->new();

if (! defined($ARGV[0]) ) {
	        die($usage);
}

for ( $ARGV[0] ) {
	if (/^-(-|)mboxold/)  {
		GetOptions(     'mboxold=s'   => \$mboxold[0],
				'folderold:s' => \$fdrold,
				'mboxnew=s'   => \$mboxnew[0],
				'foldernew:s' => \$fdrnew,
				'part:s'       => \$part[0]
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
		GetOptions(     'file=s'   => \$data_file
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
			chomp($line);
			@PARAM=split(/\,/,$line,5);
			if ($#PARAM != 4) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
			else {
				($mboxold[$i],$fdrold,$mboxnew[$i],$fdrnew,$part[$i])=@PARAM;
				 $part[$i]=~ s/\s+$//;  # Remove trailing spaces
				 $folderold[$i] = $imaputf7->encode(encode($code,$fdrold));
				 $foldernew[$i] = $imaputf7->encode(encode($code,$fdrnew));
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
        return 0;
}

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
	renameMailbox($logproc, $cyrus ,$mboxold[$c], $folderold[$c], $mboxnew[$c], $foldernew[$c], $part[$c], $v);
}
