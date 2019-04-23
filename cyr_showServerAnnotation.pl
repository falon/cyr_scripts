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
    printLog('LOG_ERR',"action=imapconnect status=fail error=\"$error\" server=$cyrus_server mailHost=$cyrus_server",$verbose);
    $exit = 255;
}

$read=$IMAP->getannotation($path,$anno,"*");
$error=$@;
if (!$read) {
	printLog('LOG_ERR',"action=imapread status=fail error=\"$error\" server=$cyrus_server mailHost=$cyrus_server",$verbose);
	$IMAP->close();
	closelog();
	$exit = 1;
}

use Data::Dumper;
$Data::Dumper::Terse = 1;
print Dumper $read;
$IMAP->close();
closelog();
exit($exit);
