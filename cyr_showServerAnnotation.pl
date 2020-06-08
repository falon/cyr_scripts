#!/usr/bin/perl -w
#
#
# Usage:
#   -h <IMAP server> --path <path> --anno <anno> --type <type>


# Config setting#
# Options:
# <path> is the annotation path
# <anno> is the annotation name
# 	(must be downcase in Cyrus METADATA implementation)
# <type> is the type of <anno> to return. Some instances:
#  With old ANNOTATEMORE:
# 	"*" (all)
# 	"value.*" (all values, as ("value.priv" "value.shared")
# 	"value.priv" (only value.priv)
# With METADATA standard:
# 	"shared" or "private"


my $desc  = "shows the <path> metadata named <anno> and of type <type>. Provides the following parameters:\n";
use Mail::IMAPTalk;
use Getopt::Long::Descriptive;
use Config::IniFiles;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
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

# Parameter handler
my ($opt, $usage) = describe_options(
   '%c %o '.$desc,
   [ 'h=s', 'the server to connect to', { required => 1} ],
   [ 'path=s', 'the metadata path', ],
   [ 'anno=s', 'the metadata name', { required => 1} ],
   [ 'type=s', 'the metadata type (private/shared)', { required => 1} ],
   [],
   [ 'help',       "print usage message and exit", { shortcircuit => 1 } ],
   [],
);

print($usage->text), exit 0 if $opt->help;
@ARGV == 0
         or die("\nToo many arguments.\n\n".$usage->text);

$cyrus_server = $opt->h;
$path = $opt->path;
defined ($path)
	or $path='';
$anno = $opt->anno;
$type = $opt->type;

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
		$read=$IMAP->getmetadata($path, {depth => 'infinity'}, "/$type$anno");
	}
	else {
		$read=$IMAP->getannotation($path,$anno,$type);
	}
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
