#!/usr/bin/perl -w
#
# This will create a new mailbox and set a quota on the new user. Just be 
# sure that you installed the Cyrus::IMAP perl module.  If you did 
# 'make all && make install' or installed Cyrus using the FreeBSD ports you
# don't have to do anything at all.
#
# Change the params below to match your mailserver settins, and
# your good to go!
#
# Author: amram@manhattanprojects.com
#
# modified by Marco Fav
# modified by Paolo Cravero 20150612
#
# Usage:
#  -u <user> <part> <quota>         	   create <user> with <quota>
#                                          into partition <part>
#  -f <file>                               use a file in the form <user> <part> <quota>


# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -u <user> <partition> <quota>\n";
$usage .= "\t $0 -f <file>\n";
$usage .= "\t read a file with lines in the form <user> <partition> <quota>.\n";

if (($#ARGV < 1) || ($#ARGV > 3)) {
        print $usage;
        exit;
}

require "/usr/local/cyr_scripts/core.pl";
use vars qw($cyrus_server $cyrus_user $cyrus_pass );

#
# CONFIGURATION PARAMS
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

my $print=1; #Print stdout too
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

use Cyrus::IMAP::Admin;

     for ( $ARGV[0] ) {
         if    (/^-u/)  {
                if ($#ARGV <3) { print $usage; die("\nI need  <user> <part> <quota>\n"); }
		$newuser[0] = "$ARGV[1]";
		$partition[0] = "$ARGV[2]";
		$quota_size[0] = "$ARGV[3]";
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
                        @PARAM=split(/\s+/,$line,3);
                        if ($#PARAM != 2) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
                        else {
                                ($newuser[$i],$partition[$i],$quota_size[$i])=@PARAM;
                        }
                        $i++;
                }
                print "\nFound $i accounts\n";
         }
	else { die($usage); }
   }


  $logproc='addArchivio';
  my $cyrus;
  if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $print)) == 0) {
	return 0;
  }

for ($c=0;$c<$i;$c++) {
	createMailbox($logproc, $cyrus, $newuser[$c],'Archivio', $partition[$c], $print);
	setQuota($logproc, $cyrus, $newuser[$c], 'Archivio', $quota_size[$c], $print);
}
