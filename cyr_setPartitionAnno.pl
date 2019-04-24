#!/usr/bin/perl 
#
#
# Usage:
# Prerequisite: partition path returned by 'df' or 'cyr_df' MUST be in the form '/maildata/<fqdn>/*'
#               metapartition NOT checked. Assume they have always space.

# Config setting#

## Change nothing below, if you are a stupid user! ##

my $usage  = "\nUsage:\t$0 [-d]\nSet partition for each domain.\nPartition path returned by \'df\' or \'cyr_df\' MUST be in the form \'/maildata/<fqdn>/*\'.\nMetapartition NOT checked.\nThis program MUST be run on the Cyrus IMAP server as daemon.\n-d: run in daemon mode.\n\n";

if ($#ARGV > 0) {
        print $usage;
        exit;
}

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
# CONFIGURATION PARAMS
#
my $mainproc = 'setPartAn';
my $debug = $cfg->val('partition','debug');
my $th = $cfg->val('partition','threshold');
my $Tc = $cfg->val('partition','tc');
my $algo = $cfg->val('partition','algo');
my $df= `which cyr_df`;

my %optDom = (
	domain_private_tld => {
		'invalid'   =>      1,
	}
);
#
# EOC
#

use Mail::IMAPTalk;
use Sys::Syslog;
use Data::Validate::Domain qw(is_domain);
use Switch; # Note: upgrade this from Perl 5.10 with 'given/when'
use Getopt::Std;

our $opt_d = 0;
my $continue = 1;
getopts('d');
%argdaemon = (
	work_dir     =>  $cfg->val('partition','run_dir'),
	pid_file     =>  $cfg->val('partition','pid_file')
);
%procpidfile = (
        dir     =>  $cfg->val('partition','pid_dir'),
        name     => $cfg->val('partition','pid_file')
);

if ($debug) { use POSIX qw/strftime/; use Term::ANSIColor; }
if (($algo eq 'free') and ($Tc < 7200)) { $Tc = 7200; }

# Algorithms for assigning partitions

sub roundrobin {
# Round robin on available partitions for each domain.
	my $mainproc = shift,
	my $p = shift;
	my $domain = shift;
	my $spaceavail = shift;
	my $perc = shift;
	my $partname = shift;
	my $thwarn = shift;
 
                if ($perc < $thwarn){
                        $p->{$domain}->{$partname}->{'avail'}=$spaceavail;
                        $p->{$domain}->{$partname}->{'perc'}=$perc;
                }
                else {
			openlog("$mainproc",'pid','LOG_MAIL');
                        printLog('LOG_EMERG',"action=$mainproc status=fail meta_value=$partname domain=$domain error=\"no space left\" detail=\"THIS IS A SEVERE WARNING!\nPartition <$partname> for domain <$domain> excluded because is $perc% full. Please, add more space on  <$partname>, immediately!\"",1);
			closelog();
                }
}


sub  morespace {
# Set partition with more ABSOLUTE free space on each domain
        my $p = shift;
        my $domain = shift;
        my $spaceavail = shift;
        my $perc = shift;
        my $partname = shift;

        if ( (!defined($p->{$domain}->{'avail'}))or($spaceavail > $p->{$domain}->{'avail'}) ) {
                $p->{$domain}->{'avail'}=$spaceavail;
                $p->{$domain}->{'part'}=$partname;
		$p->{$domain}->{'perc'}=$perc;
        }
}
############################

sub Running {
# Check if process is already running
	my $file = shift;

        if (-e $file) { return 1; }
	return 0;
}

	
openlog($mainproc,'pid','LOG_MAIL');

######################################################
#####                DAEMON                      #####
######################################################

if ($opt_d) {
        $debug = 0;
        use Proc::Daemon;

        # If already running, then exit
	if (Running($argdaemon{work_dir}.'/'.$argdaemon{pid_file})) {
		printLog('LOG_EMERG',"action=start algo=$algo status=fail error=\"can't start\" detail=\"Can't start process. A process is already running or stalled with pid file ".$argdaemon{pid_file}.'"',$debug);
		exit(-1);
	}



	#Start new daemon
        Proc::Daemon::Init( { %argdaemon } );


        $SIG{TERM} = sub {
                $continue = 0;
		openlog($mainproc,'pid','LOG_MAIL');	
                printLog('LOG_INFO',"action=stop algo=$algo status=notice detail=\"Stopping process\"",$debug);
		Proc::Daemon::Kill_Daemon($argdaemon{work_dir}.'/'.$argdaemon{pid_file} );
                unlink $argdaemon{work_dir}.'/'.$argdaemon{pid_file} or
			printLog('LOG_EMERG',"action=stop algo=$algo status=fail error=\"can't stop\" detail=\"Can't remove ".$argdaemon{pid_file}.'"',$debug);
        };

        $SIG{HUP}  = sub {
		openlog($mainproc,'pid','LOG_MAIL');
                $continue = 1;
                $notdone= 1;
                while (($endcycle)&&($notdone)) {
                        if ($notdone)  {
                                $notdone = 0;
                                my $change = undef;
                                my $partition = {};
                                my $j = {};
                                printLog('LOG_INFO',"action=reload algo=$algo status=success detail=\"Caught SIGHUP:  reloading\"",$debug);
                        }
                }
        };
        printLog('LOG_INFO',"action=start algo=$algo status=success detail=\"Starting process\"",$debug);
}




######################################################
#####			MAIN			######
######################################################


# Initialize
my $change = undef;
my $partition = {};
my $j = {};


## $_[0] = partition name
## $_[3] = space available
## $_[4] = space occupied in %
## $_[5] = FQDN

while ($continue) {
	my $pfree = {};
	$endcycle = 0;

	$partition = {};
		

	# Read all partition
##	if (-x $df) {
        	@part = `$df`;
##	} else {
##        	die (printLog($logtag,$logfac,'LOG_EMERG','EXIT: No Cyrus df executable file found.',$debug));
##	}

	for ($i=1;$i<=$#part;$i++) {
		@_=split(/\s+/,$part[$i]);
		if ($_[0] eq '') {next;}
		if ($_[5] !~ /^\/maildata\//) {next;}	# Skip archive partitions
		$_[5] =~ s/^\/maildata\///;
		$_[5] =~ s/\/.*$//;
		$_[4] =~ s/\%$//;
		if (!defined(is_domain($_[5], \%optDom))) {
			die (printLog('LOG_EMERG',"action=check algo=$algo domain=$_[5] partition=$_[0] status=fail error=\"invalid domain\" detail=\"EXIT: <$_[5]> domain of partition <$_[0]> is invalid. Please check this path\"",$debug));
		}

		switch ( $algo ) {
			case ( 'rr' )   { &roundrobin($mainproc, $partition,$_[5],$_[3],$_[4],$_[0],$th); }
			case ( 'free' ) { &morespace($pfree,$_[5],$_[3],$_[4],$_[0]); }
			else {
				die (printLog('LOG_EMERG',"action=check algo=$algo status=fail error=\"invalid algo\" detail=\"EXIT: Select an existent algorithm, not <$algo>!\"",$debug));
			}
		}
	
	}

	closelog();
	if ( $algo eq 'free' ) {
		while (  ($dom, $ppt) = each(%$pfree) ) {
			$partition->{$dom}->{$pfree->{$dom}->{'part'}}->{'avail'} = $pfree->{$dom}->{'avail'};
			$partition->{$dom}->{$pfree->{$dom}->{'part'}}->{'perc'} = $pfree->{$dom}->{'perc'};
		}
	}


	$IMAP = Mail::IMAPTalk->new(
	      Server   => $cyrus_server,
	      Username => $cyrus_user,
	      Password => $cyrus_pass,
	      Uid      => 0 );
	$error=$@;
	if (not $IMAP) {
		openlog("$mainproc/imapconnect",'pid','LOG_MAIL');
		printLog('LOG_ERR',"action=imapconnect status=fail error=\"$error\" server=$cyrus_server mailHost=$cyrus_server",$debug);
		closelog();
		exit(255);
	}

	if ($debug) {
		print "\033[2J";    #clear the screen
		print "\033[0;0H"; #jump to 0,0
		print "CYRUS PARTITION MANAGER: REAL TIME DEBUG MODE";
		print strftime("           %Y-%m-%d %H:%M:%S (run every $Tc seconds)\n\n", localtime(time));
		printf ("%-40s %-30s %-3s\n",'Domain','Partition','% used');
	}

	# Set Partitions
	while (  ($dom, $pt) = each(%$partition) ) {
		$anno="/vendor/CSI/partition/$dom";
		if (!($j->{$dom})) { $j->{$dom} = 0; } #First time initialization
		@partlist       = keys %{ $partition->{$dom} };
		$j->{$dom} = ($j->{$dom}+1)%($#partlist+1);  # A Galois field
		$part = $partlist[$j->{$dom}];
		if ($debug) {
			printf ("%-50.50s %-40.40s %-3s\n",colored($dom,green),colored($part,yellow), colored($partition->{$dom}->{$part}->{'perc'},magenta));
		}
		if ($opt_d) { setAnnotationServer($mainproc, $IMAP,'', $anno,'value.priv',$part,0); }

	}

	if ($debug) {
		print "\n\nMetric: $algo\nThis is only a demo, no changes made on annotations.$change\n  Hit ^C to Exit.\n\n";
		$change = undef;
	}
	$IMAP->close();
	$endcycle = 1;
	sleep $Tc;
}
