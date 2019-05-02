#!/usr/bin/perl -w
# Usage:
#  -u <user> 		         	   delete <user> 
#  -f <file>                               use a file in the form <user> 


# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -u <user>\n";
$usage .= "\t $0 -f <file>\n";
$usage .= "\t read a file with lines in the form <user> \n\n";

if ($#ARGV != 1) {
        print $usage;
        exit;
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
my $exit = 0;

require "/usr/local/cyr_scripts/core.pl";
use Cyrus::IMAP::Admin;

#
# CONFIGURATION PARAMS
#

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

my $i = 0;
my $c = 0;
my @user = undef;
my $logproc='deluser';
my $cyrus;

use Switch;

     for ( $ARGV[0] ) {
         if    (/^-u/)  {
                if ($#ARGV != 1) { print $usage; die("\nI need  <user>\n"); }
		$user[0] = "$ARGV[1]";
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
                        wchomp($line);
                        $user[$i]=$line;
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
	setACL($logproc, $cyrus, $user[$c],'INBOX', $cyrus_user,'all',$sep,$verbose)
		or $exit++;
        deleteMailbox($logproc, $cyrus, $user[$c], 'INBOX', $sep, $verbose)
		or $exit++;
}
exit($exit);
