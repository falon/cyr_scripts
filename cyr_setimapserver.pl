#!/usr/bin/perl -w
#
# Usage:
#  <hostname>         	   set <hostname> in 'server' setting, imap block of cyr_scripts.ini file.


my $usage  = "\nUsage:\t$0 <hostname>\n\n";
my $exit = 0;

if ($#ARGV != 0) {
        print $usage;
        exit(255);
}

require "/usr/local/cyr_scripts/core.pl";
use Cyrus::IMAP::Admin;
use Config::IniFiles;
use Sys::Syslog;
use feature "switch";
my $cfg = new Config::IniFiles(
	-file => '/usr/local/cyr_scripts/cyr_scripts.ini',
	-nomultiline => 1,
	-handle_trailing_comment => 1);
my $old_server = $cfg->val('imap','server');
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $logproc='setimaphost';
my $verbose=1;
my $auth = {
    -mechanism => 'login',
    -service => 'imap',
    -authz => $cyrus_user,
    -user => $cyrus_user,
    -minssf => 0,
    -maxssf => 10000,
    -password => $cyrus_pass,
};


######################################################
#####			MAIN			######
######################################################

for ( $ARGV[0] ) {
	$new_server = "$ARGV[0]";
}

my $cyrus;
my $status;
my $error;
my $sev;

openlog("$logproc/master",'pid','LOG_MAIL');
given ( $new_server ) {
	when ( $new_server eq $old_server ) {
		$exit = 0;
		$status = 'fail';
		$error = ' error="new server is the same already configured"';
		$sev = 'LOG_ERR';
	}
	when (($cyrus = cyrusconnect($logproc, $auth, $new_server, $verbose)) == 0) {
		$exit = 255;
		$status = 'fail';
		$error = ' error="new server doesn\'t authenticate. So I refuse to set it."';
		$sev = 'LOG_ALERT';
	}	
	default {
		my $result = 0;
		my $thistime = localtime();
		$cfg->SetParameterTrailingComment('imap', 'server', ("Modified on $thistime by $0"));
		$cfg->setval('imap', 'server', $new_server);
		$result = $cfg->RewriteConfig;
		if ($result == 1) {
			$exit = 0;
			$status = 'success';
			$error = '';
			$sev = 'LOG_INFO';
		}
		else {
			$exit = 1;
			$status = 'fail';
			$error = ' error="can\'t write config file"';
			$sev = 'LOG_ERR';
		}
	}
}
printLog($sev, "action=setimaphost status=${status}${error} oldserver=$old_server newserver=$new_server",$verbose);
exit($exit);
