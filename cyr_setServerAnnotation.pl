#!/usr/bin/perl -w
#
#
# Usage:
#  <path> <anno> <value type> <value>
# 		set annotation <anno>
#               for path <path> with <value> into <value type>


# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 <path> <anno> <value type> <value>\n";

if (! defined($ARGV[0]) ) {
	die($usage);
}
if ($#ARGV != 3) {
        print $usage;
        exit(255);
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
my $logproc='setServAnn';
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
my $IMAP;

use Switch;

if ($#ARGV != 3) {
	die ($usage);
}
		$path = "$ARGV[0]";
		$anno = "$ARGV[1]";
		$valuetype = "$ARGV[2]";
		$value = "$ARGV[3]";


use Sys::Syslog;
openlog("$logproc/cyrusconnect",'pid',$logfac);
$IMAP = Mail::IMAPTalk->new(
      Server   => $cyrus_server,
      Username => $cyrus_user,
      Password => $cyrus_pass,
      Uid      => 0 );
$error=$@;
my $rdlog = rdlog();

if ( !$IMAP ) {
	printLog('LOG_ALERT','action=cyrusconnect status=fail error="' . $error . "\" server=$cyrus_server mailHost=${cyrus_server}${rdlog}",$verbose);
	$exit = 255;
}
else {
	printLog('LOG_DEBUG',"action=cyrusconnect status=success server=$cyrus_server mailHost=$cyrus_server user=". $cyrus_user .' authz='.$cyrus_user . $rdlog, $verbose);
	setAnnotationServer($logproc, $IMAP, $path, $anno, $valuetype, $value, TRUE, $verbose)
		or $exit = 1;
	$IMAP->close();
}
exit($exit);
