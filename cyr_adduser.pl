#!/usr/bin/perl -w
#
# This will create a new mailbox and set a quota on the new user. Just be 
# sure that you installed the Cyrus::IMAP perl module.
#


# Config setting#



my $desc  = "\nCreate new mailbox account with system folders and specialuse if supported. Provide the following parameters:\n";

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
use Net::LDAP;

#
# CONFIGURATION PARAMS
#


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


#
# EOC
#


######################################################
#####			MAIN			######
######################################################

my $i = 0;
my $c = 0;
my @newuser = undef;
my @partition = undef;
my @quota_size = undef;
my $autopart = undef;
my @password = undef;
my $logproc='adduser';
my $exit = 0;
my $cyrus;

my $ldap;	# LDAP connection handler
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
                        [ 'u=s', 'the username' ],
                        [ 'file|f=s', 'read a file with lines in the form <user>;<partition>;<quota>;<spamexp>;<trashexp>;<name>;<surname>;<mail>;<password>' ]
                ],
        },
  ],
  [],
  [ 'gn=s', 'Name of the user (in combination with -u)' ],
  [ 'sn=s', 'Surname of the user (in combination with -u)' ],
  [ 'mail=s', 'Email address of the user (in combination with -u)' ],
  [ 'password=s', 'Password of the user (in combination with -u)' ],
  [ 'p=s', 'partition name (in combination with -u)' ],
  [ 'q=s', 'quota root (in combination with -u)'],
  [ 'spamexp=s', 'Spam folder expiration in days (in combination with -u)'],
  [ 'trashexp=s', 'Trash folder expiration in days (in combination with -u)'],
  [ 'autopart', 'Let CSI Partition Manager to choose the partition'],
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
	if ( defined($opt->p) ) {
		$partition[0] = $opt->p;
	}
	else {
		$partition[0]='';
	}
        $quota_size[0] = $opt->q;
	$expSpam[0] = $opt->spamexp;
	$expTrash[0] = $opt->trashexp;
	if ( defined($opt->gn) ) {
		$name[0] = $opt->gn;
	} else {
		die("\nInsufficient arguments.\n\n".$usage->text);
	}
	if ( defined($opt->sn) ){
		$surname[0] = $opt->sn;
	} else {
		die("\nInsufficient arguments.\n\n".$usage->text);
	}
	if ( defined($opt->mail) ) {
		$mail[0] = $opt->mail;
	} else {
		die("\nInsufficient arguments.\n\n".$usage->text);
	}
	if ( defined($opt->password) ) {
		$password[0] = $opt->password;
	} else {
		die("\nInsufficient arguments.\n\n".$usage->text);
	}
	if ( defined($opt->autopart) ) {
		$autopart = $opt->autopart;
	}
        $i = 1;
}



if ($opt->mode eq 'file') {
        $data_file = $opt->file;
        open(DAT, $data_file) || die("Could not open $data_file!");
        @raw_data=<DAT>;
        close(DAT);
        foreach $line (@raw_data) {
                wchomp($line);
                @PARAM=split(/\;/,$line,9);
                if ($#PARAM != 8) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
                else {
                        ($newuser[$i],$partition[$i],$quota_size[$i],$expSpam[$i],$expTrash[$i],$name[$i],$surname[$i],$mail[$i],$password[$i])=@PARAM;
			$password[$i]=~ s/\s+$//;  # Remove trailing spaces
                }
                $i++;
        }
        print "\nFound $i accounts\n";
}
## End of parameter handler


if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $verbose)) == 0) {
        exit(255);
}

if ( !($ldap=ldapconnect($logproc, $ldaphost, $ldapPort, $verbose)) ) {
	exit(255);
}

if ( (ldapbind($logproc, $ldap, $ldaphost, $ldapPort, $ldapBindUid, $ldapBindPwd, $verbose)) == 0 ) {
	$ldap->disconnect ($ldaphost, port => $ldapPort);
	exit(255);
}

openlog("$logproc/master", "pid", LOG_MAIL);
LOOP: for ($c=0;$c<$i;$c++) {
	print "\n\tAdding User: $newuser[$c]...\n";
        if ($partition[$c] eq '') {
                if ($autopart) {
                        # CSI Partition Manager choice
                        $partition[$c] = getDomainPart($logproc, $cyrus, $newuser[$c], $verbose);
			if ($partition[$c] eq 'NIL') {
				printLog('LOG_ERR', "action=checkpart mailbox=${newuser[$c]} status=fail error=\"An error occurred reading the  partition using autopart flag. Skipping.\"", $verbose);
				$exit++;
				next LOOP;
			}
				
                }
        }
        else {
                if ($autopart) {
                        printLog('LOG_WARNING', "action=checkpart status=notice mailbox=${newuser[$c]} partition=${partition[$c]} detail=\"You define explicit partition name, but the autopartition flag too. Explicit declaration takes precedence.\"", $verbose);
                }
        }

	createMailbox($logproc, $cyrus, $newuser[$c],'INBOX',$partition[$c], $sep, $verbose)
		or $exit++;
        setQuota($logproc, $cyrus, $newuser[$c], 'INBOX', $quota_size[$c], $sep, $verbose)
		or $exit++;
	createMailbox($logproc, $cyrus, $newuser[$c],'Spam', $partition[$c], $sep, $verbose, 'Junk')
		or $exit++;
	setMetadataMailbox($logproc, $cyrus, $newuser[$c],'Spam', 'expire', $expSpam[$c], $sep, $verbose)
		or $exit++;
	setACL($logproc, $cyrus, $newuser[$c],'Spam','anyone','p', $sep, $verbose)
		or $exit++;
	setACL($logproc, $cyrus, $newuser[$c],'Spam',$newuser[$c],'lrswipted', $sep, $verbose)
		or $exit++;
	createMailbox($logproc, $cyrus, $newuser[$c], 'Trash', $partition[$c], $sep, $verbose, 'Trash')
		or $exit++;
	setMetadataMailbox($logproc, $cyrus, $newuser[$c], 'Trash', 'expire', $expTrash[$c], $sep, $verbose)
		or $exit++;
	createMailbox($logproc, $cyrus, $newuser[$c], 'Sent', $partition[$c], $sep, $verbose, 'Sent')
		or $exit++;
	createMailbox($logproc, $cyrus, $newuser[$c], 'Drafts', $partition[$c], $sep, $verbose, 'Drafts')
		or $exit++;
	ldapAdduser($logproc,$ldap,$ldapBase,$newuser[$c],$cyrus_server,$name[$c],$surname[$c],$mail[$c],$password[$c],$verbose)
		or $exit++;
##	setACL($logproc, $cyrus, $newuser[$c], 'Trash', $newuser[$c], 'lrswipktecd', $sep, $verbose);
}
$ldap->disconnect ($ldaphost, port => $ldapPort);
closelog();
exit($exit);
