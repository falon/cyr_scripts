#!/usr/bin/perl -w
#
#
# Usage:
#  -u <user> <folder> <anno> <value>         	   set annotation <anno> on <folder> of <user>
#                                          with <value>
#  -f <file>                               use a file in the form <user> <folder> <anno> <value>


# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -u <user> <folder> <anno> <value>\n";
$usage .= "\t $0 -f <file>\n";
$usage .= "\t read a file with lines in the form <user> <folder> <anno> <value>\n\n";

if (($#ARGV < 1) || ($#ARGV > 4)) {
        print $usage;
        exit;
}

require "/usr/local/cyr_scripts/core.pl";
use vars qw($cyrus_server $cyrus_user $cyrus_pass);
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

my $i = 0;
my $c = 0;
my @newuser = undef;
my @partition = undef;
my @quota_size = undef;
my $cyrus;

     for ( $ARGV[0] ) {
         if    (/^-u/)  {
                if ($#ARGV <4) { print $usage; die("\nI need  <user> <folder> <anno> <value>\n"); }
		$newuser[0] = "$ARGV[1]";
		$folder[0] = "$ARGV[2]";
		$anno[0] = "$ARGV[3]";
		$value[0] = "$ARGV[4]";
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
                        @PARAM=split(/\s+/,$line,4);
                        if ($#PARAM != 3) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
                        else {
                                ($newuser[$i],$folder[$i],$anno[$i],$value[$i])=@PARAM;
                        }
                        $i++;
                }
                print "\nFound $i accounts\n";
         }
	else { die($usage); }
   }


if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $verbose)) == 0) {
        return 0;
}


for ($c=0;$c<$i;$c++) {
	print "\tSet annotation for User: $newuser[$c]...\n";
	setAnnotationMailbox($logproc, $cyrus, $newuser[$c],$folder[$c], $anno[$c], $value[$c], $verbose);
}
