#!/usr/bin/perl 

# Usage:
#  -u <user> 		
# -d <domain fqdn> (list all user of fqdn)
# [-q <%>] (list only if percent quota busy is greater than <%>)

# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 [-u <user>][-d <fqdn>][[-q \% quota th (omit \%)]]\n";
$usage .= "\n\n";

my @user = undef;
my $thq = undef;
my $i = 1;
my $c = 0;

use Getopt::Std;
my %opt=();
getopts("hu:d:q:p:", \%opt) or die ($usage);

if ($opt{h}) { die ($usage); } 
if ($opt{u}) { 
                $user[0]=$opt{u};
         }
if ($opt{d}) {
                $user[0]='%@'.$opt{d};
         }
if ($opt{q}) {
		if ($opt{q} !~ /^\d+$/) { die ("\n\nPlease, check quota threshold syntax, Remember to omit \%!\n\n") };
                $thq = $opt{q};
         }
if ($opt{p}) {
		$thispart = $opt{p};
         }

if (not defined ($user[0])) { die ($usage); }


use Cyrus::IMAP::Admin;
use POSIX;

my $totocc = 0;
my $totq = 0;
my $nmbox=0;
my $warnq = 0;
my $client;
my $logproc = 'showmb';
my $verbose = 0;

use Config::IniFiles;
my $cfg = new Config::IniFiles(
        -file => '/usr/local/cyr_scripts/cyr_scripts.ini',
        -nomultiline => 1,
        -handle_trailing_comment => 1);
my $cyrus_server = $cfg->val('imap','server');
my $cyrus_user = $cfg->val('imap','user');
my $cyrus_pass = $cfg->val('imap','pass');
my $sep = $cfg->val('imap','sep');
require "/usr/local/cyr_scripts/core.pl";

#
# assuming all necessary variables have been declared and filled accordingly:
#

my %anno =();
my %anno_var = ();

my $auth = {
    -mechanism => 'login',
    -service => 'imap',
    -authz => $cyrus_user,
    -user => $cyrus_user,
    -minssf => 0,
    -maxssf => 10000,
    -password => $cyrus_pass,
};

if ( ($client = cyrusconnect($logproc, $auth, $cyrus_server, $verbose)) == 0) {
	exit(255);
}

printf "\n\n\e[33m" . '%-30.30s  %-9s %-9s %-8s %-27s %-27s %-12s %-3s' . "\e[39m\n",
	'Mailbox',
	'Used',
	'Quota',
	'Used(%)',
	'LastIMAPupdate',
	'Lastpop',
	'Partition',
	'Expire';

my $cVer = cyrusVersion($client);

for ($c=0;$c<$i;$c++) {
		@mailboxes=$client->listmailbox('user'.$sep.$user[$c]);
		for ($m=0;$m<=$#mailboxes;$m++) {
                        @info = $client->getinfo($mailboxes[$m][0]);
			for ($j=0;$j<$#info;$j+=2) {
				$anno_var{$info[$j]} = $info[$j+1];
			}
			if ( $cVer =~ /^3/ ) {
				%anno = %{$anno_var{$mailboxes[$m][0]}{'shared'}};
				$anno_prefix = '/mailbox//vendor/cmu/cyrus-imapd';
			}
			if ( $cVer =~ /^(v|)2/ ) {
				%anno = %anno_var;
				$anno_prefix = '/mailbox/{'.$mailboxes[$m][0].'}/vendor/cmu/cyrus-imapd';
			}
			#use Data::Dump qw(dump);
			#dump (\@info);
			if ((defined $thispart) and ( $anno{$anno_prefix.'/partition'} !~ /^$thispart$/)) {next;}
			$nmbox++;
			($root,%quota) = $client->quotaroot($mailboxes[$m][0]);
			$root = $mailboxes[$m][0];
			$root =~ s/user\///;
			$root =~ s/@.*$//;
                        $totocc+=$quota{'STORAGE'}[0];
                        $totq+=$quota{'STORAGE'}[1];
			if (!(defined($quota{'STORAGE'}[1])) or ($quota{'STORAGE'}[1] eq '')) {
				$perc = 0;$warnq = 1;$quota{'STORAGE'}[1]='NO';
			}
			elsif ($quota{'STORAGE'}[1] == 0) {
				$perc = 0;
			}
			else {$perc = ceil(100*$quota{'STORAGE'}[0]/$quota{'STORAGE'}[1]);}
			if ((!(defined $thq)) or ($perc > $thq)) {
				printf '%-30.30s  %-9u %-9s %-7u  ',$root,$quota{'STORAGE'}[0],$quota{'STORAGE'}[1],$perc;
				$anno{$anno_prefix.'/lastupdate'} =~ /^\s*\S+/ ?
					printf '%-27s ',$anno{$anno_prefix.'/lastupdate'} : print '--------------------------  ';
				$anno{$anno_prefix.'/lastpop'} =~ /^\s*\S+/ ?
					printf '%-27s ',$anno{$anno_prefix.'/lastpop'} : print '--------------------------  ';
				printf "%-12s ",$anno{$anno_prefix.'/partition'};
				printf "%-3d\n",$anno{$anno_prefix.'/expire'};
			}
		}
}

print "\n\e[33m----------------------------------------------------------------------------------------------------------------------------------------\e[39m\n";
if ($nmbox == 0) { print ("No mailboxes found!\n\n"); }
else {
	if ($totq == 0) {
		printf '# mailboxes: %-18s %-9u %-9u'."\n",$nmbox,$totocc,$totq;
	}
	else {
		printf '# mailboxes: %-18s %-9u %-9u %-6u  '."\n",$nmbox,$totocc,$totq,ceil(100*$totocc/$totq);
	}
	print "\nQuota and Used are in KB\n\n";
}

if ($warnq) { print "\n\n".'Pay attention, some account(s) have no quota!'."\n\n";}
exit (0);
