#!/usr/bin/perl -w
#
# This will set right on mailbox for specific user.
#


my $desc = "writes ACL <right> for user <user> in <folder> of <mailbox>.";
$desc .= "\n\tIf <folder> = '*' then we set ACL on INBOX and all mailbox subfolders.";
$desc .= "\n\t<folder> defaults to INBOX, if not set.";
$desc .= "\n\tProvide following parameters:\n";

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
use Cyrus::IMAP::Admin;
use Getopt::Long::Descriptive;
use Unicode::IMAPUtf7;
use Encode;

#
# CONFIGURATION PARAMS
#


my $v=1;
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
my @mailbox = undef;
my @folder = undef;
my $fdr = undef;
my @who = undef;
my @right = undef;
my $logproc='setACL';
my $cyrus;

my $code= $cfg->val('code','code');
my $imaputf7 = Unicode::IMAPUtf7->new();

my ($opt, $usage) = describe_options(
  '%c %o '.$desc,
  [ 'h=s', 'the server to connect to', { required => 1} ],
  [ "mode" =>
        hidden => {
                one_of => [
                        [ 'u=s', 'the root mailbox where to define the ACL' ],
                        [ 'file|f=s', 'read a file with lines in the form <mailbox>;<folder>;<user>;<right>' ]
                ],
        },
  ],
  [],
  [ 'folder=s', 'the folder where to define the ACL (in combination with -u)' ],
  [ 'uid=s', 'the username receiving the ACL (in combination with -u)' ],
  [ 'right=s', 'the righit as expected by RFC4314 or by Cyrus IMAP ACL macros (in combination with -u)' ],
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
	if ($opt->u  =~ /\Q$sep/) {
		die("\nYou must specify a root mailbox in '-u'\n");
	}
	$mailbox[0] = $opt->u;
	if ( defined($opt->folder) ) {
		$folder[0] = $imaputf7->encode(encode($code,$opt->folder));
	}
	else { $folder[0] = 'INBOX'; }
	defined($opt->uid)
		or die("\nuid required.\n");
	$who[0] = $opt->uid;
	defined($opt->right)
		or die("\nright required.\n");
	$right[0] = $opt->right;
	$i=1;
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
                        ($mailbox[$i],$fdr,$who[$i],$right[$i])=@PARAM;
                        $right[$i]=~ s/\s+$//;  # Remove trailing spaces
                        if (not defined $opt->utf7) {
                                $folder[$i] = $imaputf7->encode(encode($code,$fdr));
                        }
                        else {
                                $folder[$i] = $fdr;
                        }
                }
                $i++;
        }
        print "\nFound $i folders\n";
}
## End of parameter handler


if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $v)) == 0) {
        exit(255);
}


for ($c=0;$c<$i;$c++) {
	my @mboxfolders = undef;
	my @mboxfoldersname = undef;
	if ($folder[$c] eq '*') {
		my ($uidm,$dom) = split('@',$mailbox[$c]);
		@mboxfolders = $cyrus->listmailbox('user'.$sep.$uidm.$sep.'*@'.$dom);
		for ($g=0;$g<=$#mboxfolders;$g++) {
			($uid,$dom) = split('@',$mboxfolders[$g][0]);
			substr $uid, 0, 5+length($uidm) +1, ''; # Remove 'user/<name>'
			$mboxfoldersname[$g] = $uid;
		}
		$mboxfoldersname[$g] = 'INBOX';
	}
	else {
		$mboxfoldersname[0] = $folder[$c];
	}
	LOOP: for ($f=0;$f<=$#mboxfoldersname;$f++) {
		$oldright = listACL($logproc, $cyrus, $mailbox[$c], $mboxfoldersname[$f], $who[$c], $sep, $v);
		if ($oldright eq $right[$c]) {
			$status='success';
	                $sev='LOG_WARNING';
	                $detail='value unchanged';
	                $error='';
			openlog("$logproc", "pid", LOG_MAIL);
			$fdr=decodefoldername($mboxfoldersname[$f],$imaputf7, $code);
			printLog($sev, "action=setimapacl status=$status error=\"$error\" uid=${who[$c]} mailbox=\"${mailbox[$c]}\" folder=\"$fdr\" right=${right[$c]} detail=\"$detail\"", $v);
			next LOOP;
		}
		if ($oldright eq 0) {
			# Something was wrong reading ACL
			next LOOP;
		}

		setACL($logproc, $cyrus, $mailbox[$c], $mboxfoldersname[$f], $who[$c], $right[$c], $sep, $v)
			or $exit++;
	}
}
exit($exit);
