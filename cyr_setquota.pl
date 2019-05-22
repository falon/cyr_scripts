#!/usr/bin/perl 

# Usage:
#  -u <user> <quota>		set <quota> for <user> (use form [userSEPuid])
#  -f <file>			use a file in the form <user> <quota>


# Config setting#
my $logproc = 'setquota';
my $logfac = 'LOG_MAIL';
my $verbose = 1;
my $exit = 0;


## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -u <user> -folder <folder> -quota <quota>\n\t<quota> is an integer in MiB or 'none'";
$usage .= "\n\n";
$usage .= "\t $0 -f <file> [-utf7]\n";
$usage .= "\tread a file with lines in the form <user>;<folder>;<quota>\n";
$usage .= "\tthe optional utf7 flag let you to write folders already utf7-imap encoded.\n";
$usage .= "\n\tThe folder MUST be a quotaroot, otherwise it becomes a new quotaroot!\n\n";

my @user = undef;
my @quota = undef;
my @folder = undef;
my $fdr = undef;
my $i = 0;
my $c = 0;
my $cyrus;
use Getopt::Long;
use Unicode::IMAPUtf7;
use Encode;
my $imaputf7 = Unicode::IMAPUtf7->new();
my $utf7 = 0;

use Config::IniFiles;
my $cfg = new Config::IniFiles(
	-file => '/usr/local/cyr_scripts/cyr_scripts.ini',
	-nomultiline => 1,
	-handle_trailing_comment => 1);
my $cyrus_server = $cfg->val('imap','server');
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');
my $code= $cfg->val('code','code');

if (! defined($ARGV[0]) ) {
	die($usage);
}

require "/usr/local/cyr_scripts/core.pl";
for ( $ARGV[0] ) {
         if    (/^-u/)  {
		GetOptions(
			'u=s'		=> \$user[0],
			'folder:s'	=> \$fdr,
			'quota=s'	=> \$quota[0]
		) or die($usage);
		@ARGV == 0
			or die("\nToo many arguments.\n$usage");
		if (defined($fdr)) {
			if ($fdr =~ /^\Q$sep/) {
				die("\nYou must specify a folder path without the initial $sep in '-folder'.\n$usage");
			}
			$folder[0] = $imaputf7->encode(encode($code,$fdr));
		}
		else { $folder[0] = 'INBOX'; }
		if (!defined($quota[0])) {
			die("\nYou must specify a quota value!\n$usage");
		}
		$i=1;
	}
	elsif (/^-(-|)h(|elp)$/) {
	   print $usage;
   	   exit(0);
   	}	   
        elsif (/^-(-|)file/)  {
		GetOptions(
			'file=s'   => \$data_file,
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
				($user[$i],$fdr,$quota[$i])=@PARAM;
				if ($utf7 == 0) {
					$folder[$i] = $imaputf7->encode(encode($code,$fdr));
				}
				else {
					$folder[$i] = $fdr;
				}
			}
			$i++;
		}
		print "\nFound $i accounts\n";  
	}     
        else           {
		 print $usage;
		 print "Make sense in what you write, stupid user!\n";
		 exit(255);
 	}
}


use Cyrus::IMAP::Admin;

#
# assuming all necessary variables have been declared and filled accordingly:
#


my $auth = {
    -mechanism => 'login',
    -service => 'imap',
    -authz => $cyrus_user,
    -user => $cyrus_user,
    -minssf => 0,
    -maxssf => 10000,
    -password => $cyrus_pass,
};

if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $verbose)) == 0) {
        exit(255);
}

for ($c=0;$c<$i;$c++) {
		setQuota($logproc, $cyrus, $user[$c], $folder[$c], $quota[$c], $sep, $verbose)
			or $exit++;
}
exit($exit);
