#!/usr/bin/perl 

# Usage:
#  -u <user> <quota>		set <quota> for <user> (use form [userSEPuid])
#  -f <file>			use a file in the form <user> <quota>


# Config setting#
my $logproc = 'setquota';
my $logfac = 'LOG_MAIL';
my $verbose = 1;


## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -u <user> <folder> <quota> MB\n";
$usage .= "\n\n";
$usage .= "\t $0 -f <file>\n";
$usage .= "\tread a file with lines in the form <user>;<folder>;<quota> MB\n\n";
$usage .= "The folder MUST be a quotaroot, otherwise it become a new quotaroot!\n\n";

my @user = undef;
my @quota = undef;
my $i = 0;
my $c = 0;
my $cyrus;

if (($#ARGV < 1) || ($#ARGV > 3)) {
	print $usage;
	exit;
}


     for ( $ARGV[0] ) {
         if    (/^-u/)  {
		if ($#ARGV != 3) { print $usage; die("\nI need at least <user>, <folder> and <quota> MB\n"); }
		$user[0]=$ARGV[1];
		$folder[0]=$ARGV[2];
		$quota[0]=$ARGV[3];
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
			@PARAM=split(/\;/,$line,2);
			if ($#PARAM != 2) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
			else {
				($user[$i],$folder[$i],$quota[$i])=@PARAM; 
			}
			$i++;
		}
		print "\nFound $i accounts\n";  
	 }     
         else           { print $usage; exit("Make sense in what you write, stupid user!\n"); }     # default
     }


use Cyrus::IMAP::Admin;

#
# assuming all necessary variables have been declared and filled accordingly:
#

require "/usr/local/cyr_scripts/core.pl";
use vars qw($cyrus_server $cyrus_user $cyrus_pass);

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
        return 0;
}

for ($c=0;$c<$i;$c++) {
		setQuota($logproc, $cyrus, $user[$c], $folder[$c], $quota[$c], $verbose);
}
