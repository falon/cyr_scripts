#!/usr/bin/perl -w
#
#
# Usage:
#  -u <user> <folder> <anno> <value>         	   set annotation <anno> on <folder> of <user>
#                                          with <value>
#  -f <file>                               use a file in the form <user> <folder> <anno> <value>


# Config setting#


my $desc = "writes metadata <anno> with value <value> on <folder> of <user>.\n";

use Config::IniFiles;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');
my $code=$cfg->val('code','code');

require "/usr/local/cyr_scripts/core.pl";
use Cyrus::IMAP::Admin;

#
# CONFIGURATION PARAMS
#

my $logproc = 'setanno';
my $logfac = 'LOG_MAIL';
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

use Getopt::Long::Descriptive;
use Unicode::IMAPUtf7;
use Encode;
my $imaputf7 = Unicode::IMAPUtf7->new();
my $utf7 = 0;
my $i = 0;
my $c = 0;
my @newuser = undef;
my $fdr = undef;
my @partition = undef;
my @quota_size = undef;
my $data_file = undef;
my $cyrus;
my $exit = 0;

# Parameter handler
my ($opt, $usage) = describe_options(
  '%c %o '.$desc,
  [ 'h=s', 'the server to connect to', { required => 1} ],
  [ "mode" =>
        hidden => {
                one_of => [
                        [ 'user=s', 'the root mailbox name' ],
                        [ 'file|f=s', "read a file with lines in the form <user>;<folder>;<anno>;<value>\n\t\t\t\tThe optional utf7 flag allows to write folders already utf7-imap encoded." ]
                ],
        },
  ],
  [],
  [ 'folder=s', 'the folder name (in combination with --user)' ],
  [ 'anno=s', 'the metadata name (in combination with --user)' ],
  [ 'value=s', 'the metadata value (in combination with --user)' ],
  [],
  [ 'utf7', 'this optional flag let you to write folders already utf7-imap encoded (in combination with --file)' ],
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
if ($opt->mode eq 'user') {
        if ($opt->user  =~ /\Q$sep/) {
                die("\nYou must specify a root mailbox in '--user'\n");
        }
        $newuser[0] = $opt->user;
	if ( defined($opt->folder) ) {
		if ($opt->folder =~ /^\Q$sep/) {
			 die("\nYou must specify a folder path without the initial $sep in '--folder'.\n");
		}
        	$folder[0] = $imaputf7->encode(encode($code,$opt->folder));
	}
	else { $folder[0] = 'INBOX'; }
	if ( defined($opt->anno) ) {
		$anno[0] = $opt->anno;
	}
	else { die("\n--anno required.\n"); }
        if ( defined($opt->value) ) {
		$value[0] = $opt->value;
	}
	else { die("\n--value required.\n"); }
        $i = 1;
}
if ($opt->mode eq 'file') {
        $data_file = $opt->file;
        open(DAT, $data_file) || die("Could not open $data_file!");
        @raw_data=<DAT>;
        close(DAT);
        foreach $line (@raw_data) {
                wchomp($line);
                @PARAM=split(/\;/,$line,4);
                if ($#PARAM != 3) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
                else {
                        ($newuser[$i],$fdr,$anno[$i],$value[$i])=@PARAM;
                        if (not defined $opt->utf7) {
                                $folder[$i] = $imaputf7->encode(encode($code,$fdr));
                        }
                        else {
                                $folder[$i] = $fdr;
                        }
                }
                $i++;
        }
        print "\nFound $i mailboxes\n";
}
## End of parameter handler


if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $verbose)) == 0) {
        exit(255);
}


for ($c=0;$c<$i;$c++) {
	print "\tSet annotation for User: $newuser[$c]...\n";
	setMetadataMailbox($logproc, $cyrus, $newuser[$c],$folder[$c], $anno[$c], $value[$c], $sep, $verbose)
		or $exit++;
}
exit($exit);
