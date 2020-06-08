#!/usr/bin/perl 

# Usage:
#  -u <user> <quota>		set <quota> for <user> (use form [userSEPuid])
#  -f <file>			use a file in the form <user> <quota>


# Config setting#
my $logproc = 'setquota';
my $logfac = 'LOG_MAIL';
my $verbose = 1;
my $exit = 0;



my $desc = " writes the quota size <quota> MiB on <folder> of <user>.";
$desc .= "\n\t<quota> is an integer in MiB or 'none'";
$desc .= "\n\tThe folder MUST be a quotaroot, otherwise it becomes a new quotaroot!";
$desc .= "\n\tProvide the following parameters:\n";

my @user = undef;
my @quota = undef;
my @folder = undef;
my $fdr = undef;
my $i = 0;
my $c = 0;
my $cyrus;
use Getopt::Long::Descriptive;
use Unicode::IMAPUtf7;
use Encode;
my $imaputf7 = Unicode::IMAPUtf7->new();

use Config::IniFiles;
my $cfg = new Config::IniFiles(
	-file => '/usr/local/cyr_scripts/cyr_scripts.ini',
	-nomultiline => 1,
	-handle_trailing_comment => 1);
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');
my $code= $cfg->val('code','code');

require "/usr/local/cyr_scripts/core.pl";

# Parameters handler
my ($opt, $usage) = describe_options(
  '%c %o '.$desc,
  [ 'h=s', 'the server to connect to', { required => 1} ],
  [ "mode" =>
        hidden => {
                one_of => [
                        [ 'u=s', 'the root mailbox where to define the quota' ],
                        [ 'file|f=s', 'read a file with lines in the form <user>;<folder>;<quota>' ]
                ],
        },
  ],
  [],
  [ 'folder=s', 'the folder where to define the quota size (in combination with -u)' ],
  [ 'quota=i', 'the quota size in MiB (in combination with -u)' ],
  [],
  [ 'utf7', 'this optional flag let you to write folders utf7-imap encoded (in combination with --file)' ],
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
        $user[0] = $opt->u;
        if ( defined($opt->folder) ) {
		if ($opt->folder =~ /^\Q$sep/) {
			die("\nYou must specify a folder path without the initial $sep in '--folder'.\n");
		}
                $folder[0] = $imaputf7->encode(encode($code,$opt->folder));
        }
        else { $folder[0] = 'INBOX'; }
	if ( defined($opt->quota) ){
		$quota[0] = $opt->quota;
	}
	else {
		die("\nYou must specify a quota value!\n");
	}
        $i=1;
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
                        ($user[$i],$fdr,$quota[$i])=@PARAM;
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

use Cyrus::IMAP::Admin;

#
# assuming all necessary variables have been declared and filled accordingly:
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

if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $verbose)) == 0) {
        exit(255);
}

for ($c=0;$c<$i;$c++) {
		setQuota($logproc, $cyrus, $user[$c], $folder[$c], $quota[$c], $sep, $verbose)
			or $exit++;
}
exit($exit);
