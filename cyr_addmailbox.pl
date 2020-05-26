#!/usr/bin/perl -w
#
# This will create a new mailbox and set a quota on the new user. Just be 
# sure that you installed the Cyrus::IMAP perl module.
#
# Usage:
#  -h <server> -u <user> <part> <quota>    create <user> with <quota>
#                                          into partition <part>
#  -f <file>                               use a file in the form <server> <user> <part> <quota>


# Config setting#



my $desc  = "creates a new INBOX mailbox and quotaroot.\nThis is like cyr_adduser.pl, but it create the INBOX only folder.\n";
$desc .= "Please, add the LDAP entry before.\nProvide the following parameter:\n";

use Config::IniFiles;
use Getopt::Long::Descriptive;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');
require "/usr/local/cyr_scripts/core.pl";
use Cyrus::IMAP::Admin;

#
# CONFIGURATION PARAMS
#


my $auth = {
    -mechanism => 'login',
    -service => 'imap',
    -authz => $cyrus_user,
    -user => $cyrus_user,
    -minssf => 0,
    -maxssf => 10000,
    -password => $cyrus_pass,
};
my $verbose=1;

#
# EOC
#


######################################################
#####			MAIN			######
######################################################

my $i = 0;
my $c = 0;
my $cyrus_server = undef;
my @newuser = undef;
my @partition = undef;
my @quota_size = undef;
my $logproc='addquotaroot';
my $exit = 0;
my $cyrus;

# Parameter handler
my ($opt, $usage) = describe_options(
  '%c %o '.$desc,
  [ 'h=s', 'the server to connect to', { required => 1} ],
  [ "mode" =>
	hidden => {
		one_of => [
  			[ 'u=s', 'the username' ],
			[ 'file|f=s', 'read a file with lines in the form <server>;<user>;<partition>;<quota>' ]
		], 
	},
  ],
  [],
  [ 'p=s', 'partition name (in combination with -u)' ],
  [ 'q=s', 'quota root (in combination with -u)'],
  [],
  [ 'help',       "print usage message and exit", { shortcircuit => 1 } ],
  [],
);
 
print($usage->text), exit 255 if $opt->help;
@ARGV == 0
	or die("\nToo many arguments.\n\n".$usage->text);

if (not defined($opt->mode)) {
	die("\nInsufficient arguments.\n\n".$usage->text);
}
my $cyrus_server = $opt->h;
if ($opt->mode eq 'u') {
	if ($opt->u  =~ /\Q$sep/) {
		die("\nYou must specify a root mailbox in '-u'\n");
	}
	$newuser[0] = $opt->u;
	$partition[0] = $opt->p;
	$quota_size[0] = $opt->q;
	$i = 1;
}
if ($opt->mode eq 'file') {
	$data_file = $opt->file;
	open(DAT, $data_file) || die("Could not open $data_file!");
	@raw_data=<DAT>;
	close(DAT);
	foreach $line (@raw_data) {
		wchomp($line);
		@PARAM=split(/\;/,$line,3);
		if ($#PARAM != 2) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
		else {
			($newuser[$i],$partition[$i],$quota_size[$i])=@PARAM;
		}
		$i++;
	}
	print "\nFound $i accounts\n";
}
## End of parameter handler

if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $verbose)) == 0) {
        exit(255);
}

for ($c=0;$c<$i;$c++) {
	createMailbox($logproc, $cyrus, $newuser[$c],'INBOX', $partition[$c], $sep, $verbose)
		or $exit++;
	setQuota($logproc, $cyrus, $newuser[$c], 'INBOX', $quota_size[$c], $sep, $verbose)
		or $exit++;
}
exit($exit);
