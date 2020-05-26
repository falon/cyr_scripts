#!/usr/bin/perl -w
#
#
# Usage:
#  -h <imap server> --path <path> --anno <anno> --type <value type> --value <value>
# 		set annotation <anno>
#               for path <path> with <value> into <value type>


# Config setting#



my $desc = "set a generic metadata. Provide the following parameters:\n";

use Config::IniFiles;
use Getopt::Long::Descriptive;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
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

# Parameter handler
my ($opt, $usage) = describe_options(
   '%c %o '.$desc,
   [ 'h=s', 'the server to connect to', { required => 1} ],
   [ 'path=s', 'the metadata path', ],
   [ 'anno=s', 'the metadata name', { required => 1} ],
   [ 'type=s', 'the metadata type (private/shared)', { required => 1} ],
   [ 'value=s', 'the metadata value', { required => 1} ],
   [],
   [ 'help',       "print usage message and exit", { shortcircuit => 1 } ],
   [],
);

print($usage->text), exit 255 if $opt->help;
@ARGV == 0
         or die("\nToo many arguments.\n\n".$usage->text);


$cyrus_server = $opt->h;
$path = $opt->path;
defined ($path)
	or $path = '';
$anno = $opt->anno;
$valuetype = $opt->type;
$value = $opt->value;


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
        my $cVer = cyrusVersion_byIMAPTalk($IMAP);
	if ( $cVer =~ /^3/ ) {
		setMetadataServer($logproc, $IMAP, $path, $anno, $valuetype, $value, TRUE, $verbose)
			or $exit = 1;
	}
	else {
		setAnnotationServer($logproc, $IMAP, $path, $anno, $valuetype, $value, TRUE, $verbose)
			or $exit = 1;
	}
	$IMAP->close();
}
exit($exit);
