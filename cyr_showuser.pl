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
my $i = 0;
my $c = 0;

use Getopt::Std;
my %opt=();
getopts("hu:d:q:p:", \%opt) or die ($usage);

if ($opt{h}) { die ($usage); } 
if ($opt{u}) { 
                $user[0]=$opt{u};
                $i = 1;
         }
if ($opt{d}) {
                $user[0]='%@'.$opt{d};
                $i = 1;
         }
if ($opt{q}) {
		if ($opt{q} !~ /^\d+$/) { die ("\n\nPlease, check quota threshold syntax, Remember to omit \%!\n\n") };
                $thq = $opt{q};
         }
if ($opt{p}) {
		$thispart = $opt{p};
         }




use Cyrus::IMAP::Admin;
use POSIX;

$totocc = 0;
$totq = 0;
$nmbox=0;
$warnq = 0;
my $client;
my $logproc = 'showmb';
my $verbose = 0;

require "/usr/local/cyr_scripts/core.pl";
use vars qw($cyrus_server $cyrus_user $cyrus_pass);

#
# assuming all necessary variables have been declared and filled accordingly:
#

my %anno =();

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
        return 0;
}


printf "\n\n".'%-30.30s  %-9s %-9s %-8s %-27s %-27s %-12s'."\n", 'Mailbox','Used','Quota','Used(%)','LastIMAPupdate','Lastpop','Partition';
for ($c=0;$c<$i;$c++) {

		@mailboxes=$client->listmailbox('user/'.$user[$c]);
		$nmbox+=$#mailboxes+1;
		for ($m=0;$m<=$#mailboxes;$m++) {
                        @info = $client->info($mailboxes[$m][0]);
                        for ($j=0;$j<$#info;$j+=2) {
                        	$anno{$info[$j]} = $info[$j+1];
                        }
			if ((defined $thispart) and ( $anno{'/mailbox/{'.$mailboxes[$m][0].'}/vendor/cmu/cyrus-imapd/partition'} !~ /^$thispart/)) {next;}
			($root,%quota) = $client->quotaroot($mailboxes[$m][0]);
			$root = $mailboxes[$m][0];
			$root =~ s/user\///;
			$root =~ s/@.*$//;
                        $totocc+=$quota{'STORAGE'}[0];
                        $totq+=$quota{'STORAGE'}[1];
			if (!(defined($quota{'STORAGE'}[1])) or ($quota{'STORAGE'}[1] eq '')) {$perc = 0;$warnq = 1;$quota{'STORAGE'}[1]='NO';}
			else {$perc = ceil(100*$quota{'STORAGE'}[0]/$quota{'STORAGE'}[1]);}
			if ((!(defined $thq)) or ($perc > $thq)) {
				printf '%-30.30s  %-9u %-9s %-7u  ',$root,$quota{'STORAGE'}[0],$quota{'STORAGE'}[1],$perc;
				$anno{'/mailbox/{'.$mailboxes[$m][0].'}/vendor/cmu/cyrus-imapd/lastupdate'} =~ /^\s*\S+/ ? printf '%-27s ',$anno{'/mailbox/{'.$mailboxes[$m][0].'}/vendor/cmu/cyrus-imapd/lastupdate'} : print '--------------------------  ';
				$anno{'/mailbox/{'.$mailboxes[$m][0].'}/vendor/cmu/cyrus-imapd/lastpop'} =~ /^\s*\S+/ ? printf '%-27s ',$anno{'/mailbox/{'.$mailboxes[$m][0].'}/vendor/cmu/cyrus-imapd/lastpop'} : print '--------------------------  ';
				printf "%-12s\n",$anno{'/mailbox/{'.$mailboxes[$m][0].'}/vendor/cmu/cyrus-imapd/partition'};
			}
		}
}

print "\n---------------------------------------------------------------------------------------------------------------------------------------------\n";
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
