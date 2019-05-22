#!/usr/bin/perl -w
#
# Usage:
#  <section> <parameter> <value>	set <parameter>=<value> in [<section>] of cyr_scripts.ini file.


my $usage  = "\nUsage:\t$0 <section> <parameter> <value>\n\n";
my $exit = 0;

if ($#ARGV != 2) {
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

my $logproc='setconf';
my $verbose=1;


######################################################
#####			MAIN			######
######################################################

my $section = $ARGV[0];
my $par = $ARGV[1];
my $new_value = $ARGV[2];
my $old_value = $cfg->val($section,$par);

my $status;
my $error;
my $pre_error = undef;
my $sev;
my $rdlog = '';
if (defined $ENV{'RD_JOB_USERNAME'}) {
	$rdlog = ' orig_user="'.$ENV{'RD_JOB_USERNAME'}.'"';
}
if (defined $ENV{'RD_JOB_EXECID'}) {
	$rdlog .= ' rd_execid="'.$ENV{'RD_JOB_EXECID'}.'"';
}
if (defined $ENV{'RD_JOB_EXECUTIONTYPE'}) {
	$rdlog .= ' rd_exectype="'.$ENV{'RD_JOB_EXECUTIONTYPE'}.'"';
}
if (defined $ENV{'RD_JOB_ID'}) {
	$rdlog .= ' rd_id="'.$ENV{'RD_JOB_ID'}.'"';
}
if (defined $ENV{'RD_JOB_NAME'}) {
	$rdlog .= ' rd_name="'.$ENV{'RD_JOB_NAME'}.'"';
}

given ( $section ) {
	when ( 'imap' ) {
		my %imap = ();
		@params = $cfg->Parameters($section);
		foreach $thispar ( @params ) {
			if ($thispar eq $par) {
				$imap{$thispar} = $new_value;
			} else {
				$imap{$thispar} = $cfg->val($section,$thispar);
			}
		}
		my $auth = {
			-mechanism => 'login',
			-service => 'imap',
			-authz => $imap{'user'},
		        -user => $imap{'user'},
			-minssf => 0,
			-maxssf => 10000,
			-password => $imap{'pass'},
		};
		if ( cyrusconnect($logproc, $auth, $imap{'server'}, $verbose) == 0 ) {
			$pre_error = 'With this change I can\'t authenticate. I refuse to proceed.';
		}
	}
}



openlog("$logproc/master",'pid','LOG_MAIL');
given ( $new_value ) {
	when ( $old_value ) {
		$exit = 0;
		$status = 'fail';
		$error = ' error="This value is already configured"';
		$sev = 'LOG_ERR';
	}
	when ( defined $pre_error ) {
		$exit = 255;
		$status = 'fail';
		$error = " error=\"$pre_error\"";
		$sev = 'LOG_ERR';
	}
	default {
		my $result = 0;
		my $addinfo = '';
		my $thistime = localtime();
		if (defined $ENV{'RD_JOB_USERNAME'}) {
			$addinfo= $ENV{'RD_JOB_USERNAME'} . ' using';
		}
		$cfg->SetParameterTrailingComment($section, $par, ("Modified on $thistime by $addinfo $0"));
		$cfg->setval($section, $par, $new_value);
		$result = $cfg->RewriteConfig;
		defined $result
			or $result = 0;
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
printLog($sev, "action=writeconf status=${status}${error}${rdlog} section=\"$section\" param=$par old_value=\"$old_value\" new_value=\"$new_value\"",$verbose);
exit($exit);
