#!/usr/bin/perl -w
#
#
# Usage:
#  -u <user> <folder> <anno> <value>         	   set annotation <anno> on <folder> of <user>
#                                          with <value>
#  -f <file>                               use a file in the form <user> <folder> <anno> <value>


# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -user <user> -folder <folder> -anno <anno> -value <value>\n";
$usage .= "\t $0 -file <file> [-utf7]\n";
$usage .= "\t read a file with lines in the form <user>;<folder>;<anno>;<value>\n";
$usage .= "\tthe optional utf7 flag let you to write folders already utf7-imap encoded.\n\n";

if (! defined($ARGV[0]) ) {
	die($usage);
}

use Config::IniFiles;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
my $cyrus_server = $cfg->val('imap','server');
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');
my $code=$cfg->val('code','code');

require "/usr/local/cyr_scripts/core.pl";
use Cyrus::IMAP::Admin;

#
# CONFIGURATION PARAMS
#

my $logproc = 'setanno';
my $logfac = 'LOG_MAIL';
my $verbose = 1;

my $auth = {
    -mechanism => 'login',
    -service => 'imap',
    -authz => $cyrus_user,
    -user => $cyrus_user,
    -minssf => 0,
    -maxssf => 10000,
    -password => $cyrus_pass,
};


#
# EOC
#


######################################################
#####			MAIN			######
######################################################

use Getopt::Long;
use Unicode::IMAPUtf7;
use Encode;
my $imaputf7 = Unicode::IMAPUtf7->new();
my $utf7 = 0;
my $i = 0;
my $c = 0;
my @newuser = undef;
my $fdr = undef;
my @partition = undef;
my @quota_size = undef;
my $data_file = undef;
my $cyrus;
my $exit = 0;

     for ( $ARGV[0] ) {
         if    (/^-u/)  {
		GetOptions(     'user=s'	=> \$newuser[0],
				'folder:s'	=> \$fdr,
				'anno=s'	=> \$anno[0],
				'value=s'	=> \$value[0]
		) or die($usage);
		@ARGV == 0
			or die("\nToo many arguments.\n$usage");
		if (defined($fdr)) {
			if ($fdr =~ /^\Q$sep/) {
				die("\nYou must specify a folder path without the initial $sep in '-folderold'.\n$usage");
			}
			$folder[0] = $imaputf7->encode(encode($code,$fdr));
		}
		else { $folder[0] = 'INBOX'; }
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
                        @PARAM=split(/\;/,$line,4);
                        if ($#PARAM != 3) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
                        else {
                                ($newuser[$i],$fdr,$anno[$i],$value[$i])=@PARAM;
                        }
			if ($utf7 == 0) {
				$folder[$i] = $imaputf7->encode(encode($code,$fdr));
			} else {
				$folder[$i] = $fdr;
			}
                        $i++;
                }
                print "\nFound $i accounts\n";
         }
	else { die($usage); }
   }


if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $verbose)) == 0) {
        exit(255);
}


for ($c=0;$c<$i;$c++) {
	print "\tSet annotation for User: $newuser[$c]...\n";
	setAnnotationMailbox($logproc, $cyrus, $newuser[$c],$folder[$c], $anno[$c], $value[$c], $sep, $verbose)
		or $exit++;
}
exit($exit);
