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

use Config::Simple;
my $cfg = new Config::Simple();
$cfg->read('/usr/local/cyr_scripts/cyr_scripts.ini');
my $imapconf = $cfg->get_block('imap');
my $sep = $imapconf->{sep};
my $cyrus_server = $imapconf->{server};
my $cyrus_user = $imapconf->{user};
my $cyrus_pass = $imapconf->{pass};
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
}

setAnnotationServer($logproc, $IMAP, $path, $anno, $valuetype, $value, TRUE, $verbose);
$IMAP->close();
