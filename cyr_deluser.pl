#!/usr/bin/perl -w
# Usage:
#  -u <user> 		         	   delete <user> 
#  -f <file>                               use a file in the form <user> 


# Config setting#



my $desc  = "removes permanently all mailboxes of a user. Provide the following parameters:\n";

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
use Cyrus::IMAP::Admin;
use Net::LDAP;

#
# CONFIGURATION PARAMS
#

my $verbose = 1;
my $auth = {
    -mechanism => 'login',
    -service => 'imap',
    -authz => $cyrus_user,
    -user => $cyrus_user,
    -minssf => 0,
    -maxssf => 10000,
    -password => $cyrus_pass,
};


#
# EOC
#


######################################################
#####			MAIN			######
######################################################

my $i = 0;
my $c = 0;
my @user = undef;
my $logproc='deluser';
my $cyrus;

my $ldap;       # LDAP connection handler
my $ldaphost    = $cfg->val('ldap','server');
my $ldapPort    = $cfg->val('ldap','port');
my $ldapBase    = $cfg->val('ldap','baseDN');  # Base dn containing whole domains
my $ldapBindUid = $cfg->val('ldap','user');
my $ldapBindPwd = $cfg->val('ldap','pass');

# Parameter handler
my ($opt, $usage) = describe_options(
  '%c %o '.$desc,
  [ 'h=s', 'the server to connect to', { required => 1} ],
  [ "mode" =>
        hidden => {
                one_of => [
                        [ 'u=s', 'the username where to delete' ],
                        [ 'file|f=s', 'read a file with lines in the form <user>' ]
                ],
        },
  ],
  [],
  [ 'help',       "print usage message and exit", { shortcircuit => 1 } ],
  [],
);

print($usage->text), exit 0 if $opt->help;
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
        $user[0] = $opt->u;
        $i = 1;
}
if ($opt->mode eq 'file') {
        $data_file = $opt->file;
        open(DAT, $data_file) || die("Could not open $data_file!");
        @raw_data=<DAT>;
        close(DAT);
        foreach $line (@raw_data) {
                wchomp($line);
		$user[$i]=$line;
                $i++;
        }
        print "\nFound $i accounts\n";
}
## End of parameter handler

if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $verbose)) == 0) {
	exit(255);
}

if ( !($ldap=ldapconnect($logproc, $ldaphost, $ldapPort, $v)) ) {
        exit(255);
}

if ( (ldapbind($logproc, $ldap, $ldaphost, $ldapPort, $ldapBindUid, $ldapBindPwd, $v)) == 0 ) {
        $ldap->disconnect ($ldaphost, port => $ldapPort);
        exit(255);
}


for ($c=0;$c<$i;$c++) {
	setACL($logproc, $cyrus, $user[$c],'INBOX', $cyrus_user,'all',$sep,$verbose)
		or $exit++;
        deleteMailbox($logproc, $cyrus, $user[$c], 'INBOX', $sep, $verbose)
		or $exit++;
	ldapDeluser($logproc,$ldap,$ldapBase,$user[$c],$cyrus_server,'removed',$verbose)
		or $exit++;
}
exit($exit);
