#!/usr/bin/perl  -w

# Move INBOX to another folder at user level authorization.
# If you want to move a non INBOX folder to another folder
# you can use cyr_moveMailboxPart instead. It reuses the same connection
# when it runs on multiple users.

use Getopt::Long::Descriptive;
use Unicode::IMAPUtf7;
use Encode;
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

my $desc = "moves INBOX of <user> into <folder> with the new optional partition <part>, if allowed.\n";
$desc .= "Provide the following parameters:\n";

my @user = undef;
my $fdr = undef;
my @folder = undef;
my @part= undef;
my $i = 0;
my $c = 0;
my $v = 1; #verbosity
my $logproc = 'renameINBOX';
## Parameter used to check if an account is logged in
my $procdir = $cfg->val('logintest','procdir');
# Interval time to check if account is logged
my $Tw =  $cfg->val('logintest','Tw');
# Set 1 to check if account is logged in before move folders
my $useAccountCheck =  $cfg->val('logintest','active');

my $code=$cfg->val('code','code');
my $imaputf7 = Unicode::IMAPUtf7->new();

# Parameter handler
my ($opt, $usage) = describe_options(
  '%c %o '.$desc,
  [ 'h=s', 'the server to connect to', { required => 1} ],
  [ "mode" =>
        hidden => {
                one_of => [
                        [ 'user=s', 'the username' ],
                        [ 'file|f=s', "read a file with lines in the form <user>;<folder>;<part>\n\t\t\t\tThe optional utf7 flag allows to write folders already utf7-imap encoded.\n\t\t\t\t<part> can be the empty or null char if you don't want to change the partition.\n\t\t\t\tie\n\t\t\t\tuser1;folder1;" ]
                ],
        },
  ],
  [],
  [ 'folder=s', 'destination folder of INBOX content (in combination with --user)' ],
  [ 'part=s', 'the new partition (in combination with --user)'],
  [],
  [ 'utf7', 'this optional flag let you to write folders already utf7-imap encoded (in combination with --file)' ],
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
if ($opt->mode eq 'user') {
        if ($opt->user  =~ /\Q$sep/) {
                die("\nYou must specify a root mailbox in '--user'\n");
        }
        $user[0] = $opt->user;
	$folder[0] = $imaputf7->encode(encode($code,$opt->folder));
        $part[0] = $opt->part;
	defined($part[0])
		or $part[0]='';
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
                        ($user[$i],$fdr,$part[$i])=@PARAM;
                        $part[$i]=~ s/\s+$//;  # Remove trailing spaces
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

#
# assuming all necessary variables have been declared and filled accordingly:
#

use Cyrus::IMAP::Admin;
my $cyrus;

for ($c=0;$c<$i;$c++) {

	$auth = {
		-mechanism => 'PLAIN',
		-service => 'imap',
		-authz => $user[$c],
		-user => $cyrus_user,
		-minssf => 0,
		-maxssf => 10000,
		-password => $cyrus_pass,
	};
	if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $v)) == 0) {
			$exit++;
		        next;
	}

	if ( $useAccountCheck ) {
		# wait forever if the account is logged!
		accountIsLogged($logproc, $user[$c], $procdir, $Tw, $v);
	}
	renameFolder($logproc, $cyrus, 'INBOX', $folder[$c], $part[$c], $sep, $v)
		or $exit++;
	$cyrus->send(undef, undef, 'LOGOUT');
}
exit($exit);
