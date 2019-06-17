#!/usr/bin/perl -w
#


my $usage  = "\nUsage:\t$0 \n\n";
my $exit = 0;

if ($#ARGV != -1) {
        print $usage;
        exit(255);
}


require "/usr/local/cyr_scripts/core.pl";
use Config::IniFiles;
use Sys::Syslog;
my $cfg = new Config::IniFiles(
	-file => '/usr/local/cyr_scripts/cyr_scripts.ini',
	-nomultiline => 1,
	-handle_trailing_comment => 1);

my $logproc='showconf';
my $verbose=0;


######################################################
#####			MAIN			######
######################################################

my $status;
my $error;
my $sev;

openlog("$logproc/master",'pid','LOG_MAIL');
if ( $cfg->OutputConfigToFileHandle(STDOUT) ) {
	$status = 'success';
	$error = '';
	$exit = 0;
}
else {
	$status = 'fail';
	$error = ' error="can\'t read config file"';
	$exit = 255;
}

my $rdlog = rdlog();
printLog('LOG_INFO', "action=showconf status=${status}${error}${rdlog}",$verbose);
exit($exit);
