#!/usr/bin/perl -w
#
# This will create a new mailbox and set a quota on the new user. Just be 
# sure that you installed the Cyrus::IMAP perl module.  If you did 
# 'make all && make install' or installed Cyrus using the FreeBSD ports you
# don't have to do anything at all.
#
# Change the params below to match your mailserver settins, and
# your good to go!
#
# Author: amram@manhattanprojects.com
#
# modified by Marco Fav
#
# Usage:
#  -u <user> <part> <quota>         	   create <user> with <quota>
#                                          into partition <part> with <spamexp> days of spamfolder
#  -f <file>                               use a file in the form <user> <part> <quota> <spamexp>


# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -u <user> -p <partition> -q <quota> -spamexp <spamexp> -trashexp <trashexp>\n";
$usage .= "\t $0 -file <file>\n";
$usage .= "\t read a file with lines in the form <user>;<partition>;<quota>;<spamexp>;<trashexp>.\n";
$usage .= "Please, add the LDAP entry before.\n\n";

if (! defined($ARGV[0]) ) {
	die($usage);
}

use Config::IniFiles;
use Getopt::Long;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
my $cyrus_server = $cfg->val('imap','server');
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');
require "/usr/local/cyr_scripts/core.pl";
use Cyrus::IMAP::Admin;

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
my $logproc='adduser';
my $exit = 0;
my $cyrus;

for ( $ARGV[0] ) {
	if (/^-(-|)u/)  {
		GetOptions(     'u=s'	=> \$newuser[0],
				'p=s'	=> \$partition[0],
				'q=s'	=> \$quota_size[0],
				'spamexp=s'	=> \$expSpam[0],
				'trashexp=s'	=> \$expTrash[0]
		) or die ($usage);
		@ARGV == 0
			or die("\nToo many arguments.\n$usage");

		if ($newuser[0] =~ /\Q$sep/) {
			die("\nYou must specify a root mailbox in '-u'.\n$usage");
		}
		$i=1;
	}
	elsif (/^-(-|)file/)  {
		GetOptions(     'file=s'   => \$data_file,
		) or die($usage);
		@ARGV == 0
			or die("\nToo many arguments.\n$usage");
		defined($data_file)
			or die("\nfile required.\n$usage");

	        open(DAT, $data_file) || die("Could not open $data_file!");
        	@raw_data=<DAT>;
        	close(DAT);
        	foreach $line (@raw_data)
        	{
                        wchomp($line);
                        @PARAM=split(/\;/,$line,5);
                        if ($#PARAM != 4) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
                        else {
                                ($newuser[$i],$partition[$i],$quota_size[$i],$expSpam[$i],$expTrash[$i])=@PARAM;
				$expTrash[$i]=~ s/\s+$//;  # Remove trailing spaces
                        }
                        $i++;
         	}
         	print "\nFound $i accounts\n";
	}
	elsif (/^-(-|)h(elp|)$/) {
		print $usage;
		exit 0;
	}
	else { die($usage); }
}


if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $verbose)) == 0) {
        exit(255);
}


for ($c=0;$c<$i;$c++) {
	print "\n\tAdding User: $newuser[$c]...\n";
	createMailbox($logproc, $cyrus, $newuser[$c],'INBOX',$partition[$c], $sep, $verbose)
		or $exit++;
        setQuota($logproc, $cyrus, $newuser[$c], 'INBOX', $quota_size[$c], $sep, $verbose)
		or $exit++;
	createMailbox($logproc, $cyrus, $newuser[$c],'Spam', $partition[$c], $sep, $verbose)
		or $exit++;
	setAnnotationMailbox($logproc, $cyrus, $newuser[$c],'Spam', 'expire', $expSpam[$c], $sep, $verbose)
		or $exit++;
	setACL($logproc, $cyrus, $newuser[$c],'Spam','anyone','p', $sep, $verbose)
		or $exit++;
	setACL($logproc, $cyrus, $newuser[$c],'Spam',$newuser[$c],'lrswipted', $sep, $verbose)
		or $exit++;
	createMailbox($logproc, $cyrus, $newuser[$c], 'Trash', $partition[$c], $sep, $verbose)
		or $exit++;
	setAnnotationMailbox($logproc, $cyrus, $newuser[$c], 'Trash', 'expire', $expTrash[$c], $sep, $verbose)
		or $exit++;
##	setACL($logproc, $cyrus, $newuser[$c], 'Trash', $newuser[$c], 'lrswipktecd', $sep, $verbose);
}
exit($exit);
