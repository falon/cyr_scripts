#!/usr/bin/perl -w
#
#
# Usage:
#   <path> <anno> 


# Config setting#
# Options:
# <path> is the annotation path
# <anno> is the annotation name
# <field> is the type of <anno> to return. Some instances:
# 	"*" (all)
# 	"value.*" (all values, as ("value.priv" "value.shared")
# 	"value.priv" (only value.priv)

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 <path> <anno> <field>\n";

if (! defined($ARGV[0]) ) {
	die($usage);
}
if ($#ARGV != 2) {
        print $usage;
        exit(255);
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
my $type = undef;
my $IMAP;
my $verbose = 1;
my $logproc='showServAnn';
my $logfac = 'LOG_MAIL';
my $error;
my $read;

		$path = "$ARGV[0]";
		$anno = "$ARGV[1]";
		$type = "$ARGV[2]";


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
	$read=$IMAP->getannotation($path,$anno,$type);
	$error=$@;
	if (!$read) {
                printLog('LOG_ERR',"action=showimapmetadata status=fail error=\"$error\" server=$cyrus_server mailHost=$cyrus_server meta_name=\"$anno\" path=\"$path\" type=$type",$verbose);
                $exit = 1;
        }
        else {
                use Data::Dumper;
                $Data::Dumper::Terse = 1;
                #print Dumper($read->{''}->{'/vendor/domain'});
                print Dumper($read);
                printLog('LOG_DEBUG',"action=showimapmetadata status=success server=$cyrus_server mailHost=$cyrus_server meta_name=\"$anno\" path=\"$path\" type=$type", 0);
	}
}
$IMAP->close();
closelog();
exit($exit);
