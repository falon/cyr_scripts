#!/usr/bin/perl -w
#
#
# Usage:
#  -a <path> <anno> 


# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -a <path> <anno> \n";

if ($#ARGV != 2) {
        print $usage;
        exit;
}

use Mail::IMAPTalk;
use Config::Simple;
my $cfg = new Config::Simple();
$cfg->read('cyr_scripts.ini');
my $imapconf = $cfg->get_block('imap');
my $sep = $imapconf->{sep};
my $cyrus_server = $imapconf->{server};
my $cyrus_user = $imapconf->{user};
my $cyrus_pass = $imapconf->{pass};
require "/usr/local/cyr_scripts/core.pl";

#
# CONFIGURATION PARAMS
#

#
# EOC
#


######################################################
#####			MAIN			######
######################################################

my $path = undef;
my $anno = undef;
my $IMAP;
my $verbose = 1;
my $logproc='showServerAnno';
my $logfac = 'LOG_MAIL';
my $error;
my $read;

     for ( $ARGV[0] ) {
         if    (/^-a/)  {
		$path = "$ARGV[1]";
		$anno = "$ARGV[2]";
	}
	else { die($usage); }
   }


openlog("$logproc/imapconnect",'pid',$logfac);
$IMAP = Mail::IMAPTalk->new(
      Server   => $cyrus_server,
      Username => $cyrus_user,
      Password => $cyrus_pass,
      Uid      => 0 );
$error=$@;
if (!$IMAP) {
    printLog('LOG_ERR',"action=imapconnect status=fail error=\"$error\" server=$Server mailHost=$Server",$verbose);
}

$read=$IMAP->getannotation($path,$anno,"*");
$error=$@;
if (!$read) {
	printLog('LOG_ERR',"action=imapread status=fail error=\"$error\" server=$Server mailHost=$Server",$verbose);
	$IMAP->close();
	closelog();
}

use Data::Dumper;
$Data::Dumper::Terse = 1;
print Dumper $read;
$IMAP->close();
closelog();
