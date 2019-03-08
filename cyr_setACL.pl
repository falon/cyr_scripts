#!/usr/bin/perl -w
#
# This will set right on mailbox for specific user. Just be 
# sure that you installed the Cyrus::IMAP perl module.  If you did 
# 'make all && make install' or installed Cyrus using the FreeBSD ports you
# don't have to do anything at all.
#
# Change the params below to match your mailserver settins, and
# your good to go!
#
# Usage:
#  -u <mailbox> <user> <right>         	   set ACL on <mailbox> with <right> for <user>
#  -f <file>                               use a file in the form <mailbox> <user> <right>


# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 -u <mailbox> -folder <folder> -uid <user> -right <right>\n";
$usage .= "\t $0 -file <file>\n";
$usage .= "\t read a file with lines in the form <mailbox>;<folder>;<user>;<right>.\n\n";

use Config::Simple;
my $cfg = new Config::Simple();
$cfg->read('cyr_scripts.ini');
my $imapconf = $cfg->get_block('imap');
my $sep = $imapconf->{sep};
my $cyrus_server = $imapconf->{server};
my $cyrus_user = $imapconf->{user};
my $cyrus_pass = $imapconf->{pass};
require "/usr/local/cyr_scripts/core.pl";
use Cyrus::IMAP::Admin;
use Getopt::Long;
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

my $code= $cfg->param('code.code');
my $imaputf7 = Unicode::IMAPUtf7->new();

if (! defined($ARGV[0]) ) {
        die($usage);
}
     for ( $ARGV[0] ) {
         if (/^-(-|)u/)  {
		GetOptions(     'u=s'   => \$mailbox[0],
                                'folder:s' => \$fdr,
                                'uid=s' => \$who[0],
				'right=s' => \$right[0]
		) or die($usage);
		@ARGV == 0
			or die("\nToo many arguments.\n$usage");
                if (defined($fdr)) {
	                if ($fdr =~ /\$sep/) {
                        	die(\"nYou must specify a root mailbox in '-u'.\n$usage");
			}
			$folder[0] = $imaputf7->encode(encode($code,$fdr));
                }
                else { $folder[0] = 'INBOX'; }
		defined($who[0])
			or die("\nuid required.\n$usage");
		defined($right[0])
			or die("\nright required.\n$usage");
		$i=1;
	}
        elsif (/^-(-|)file/)  {
                GetOptions(     'file=s'   => \$data_file
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
                        chomp($line);
                        @PARAM=split(/\;/,$line,4);
                        if ($#PARAM != 3) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
                        else {
                                ($mailbox[$i],$fdr,$who[$i],$right[$i])=@PARAM;
				$right[$i]=~ s/\s+$//;  # Remove trailing spaces
				$folder[$i] = $imaputf7->encode(encode($code,$fdr));
                        }
                        $i++;
                }
                print "\nFound $i folders\n";
        }
	else { die($usage); }
   }


if ( ($cyrus = cyrusconnect($logproc, $auth, $cyrus_server, $v)) == 0) {
        exit(255);
}


LOOP: for ($c=0;$c<$i;$c++) {
	$oldright = listACL($logproc, $cyrus, $mailbox[$c], $folder[$c], $who[$c], $sep, $v);
	if ($oldright eq $right[$c]) {
		$status='success';
                $sev='LOG_WARNING';
                $detail='value unchanged';
                $error='';
		openlog("$logproc", "pid", LOG_MAIL);
		$fdr=decodefoldername($folder[$c],$imaputf7, $code);
		printLog($sev, "action=setimapacl status=$status error=\"$error\" uid=${who[$c]} mailbox=\"${mailbox[$c]}\" folder=\"$fdr\" right=${right[$c]} detail=\"$detail\"", $v);
		next LOOP;
	}
	if ($oldright eq 0) {
		# Something was wrong reading ACL
		next LOOP;
	}

	setACL($logproc, $cyrus, $mailbox[$c], $folder[$c], $who[$c], $right[$c], $sep, $v);
}
