#!/usr/bin/perl -w
#
#
# Usage:
#  -a <path> <anno> <value type> <value>
# 		set annotation <anno>
#               for path <path> with <value> into <value type>


# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -a <path> <anno> <value type> <value>\n";

if ($#ARGV != 4) {
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
use Mail::IMAPTalk;
use Sys::Syslog;


#
# CONFIGURATION PARAMS
#
my $logtag = 'setServerAnnotation';
my $logfac = 'LOG_MAIL';
my $verbose = 1;

#
# EOC
#


######################################################
#####			MAIN			######
######################################################

my $path = undef;
my $anno = undef;
my $value_type = undef;
my $value = undef;
my $logproc='setServerAnno';
my $IMAP;

use Switch;

     for ( $ARGV[0] ) {
         if    (/^-a/)  {
		$path = "$ARGV[1]";
		$anno = "$ARGV[2]";
		$valuetype = "$ARGV[3]";
		$value = "$ARGV[4]";
	}
	else { die($usage); }
   }


use Sys::Syslog;
openlog("$logproc/imapconnect",'pid',$logfac);
$IMAP = Mail::IMAPTalk->new(
      Server   => $cyrus_server,
      Username => $cyrus_user,
      Password => $cyrus_pass,
      Uid      => 0 );
$error=$@;
if (!$IMAP) {
    printLog('LOG_ERR',"action=imapconnect status=fail error=\"$error\" server=$Server mailHost=$Server",$verbose);
    $exit = 255;
}

setAnnotationServer($logproc, $IMAP, $path, $anno, $valuetype, $value, TRUE, $verbose)
	or $exit = 1;
$IMAP->close();
exit($exit);
