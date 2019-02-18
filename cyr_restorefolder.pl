#!/usr/bin/perl -w 
#
# This program tries to restore a deleted folder into mailbox
# at the original location
#
# Author: Marco Fav
#
#
# Usage:
#  -u <user>	         	   tries to restore <user>
#  -f <file>                       use a file in the form <user>


# Config setting#

## Change nothing below, if you are a stupid user! ##

require 5.8.8;

my $usage  = "\nUsage:\n\t$0 -u <user> [--folder <folder>] [--delay <n><udm>]\n\n";
$usage .= "\t$0 -f <file>\n";
$usage .= "\t read a file with lines in the mandatory form <user> <TAB><folder> <TAB><n><udm>\n";
$usage .= "\t\t <n> = unit, such as 1 2 3... (not active for deleted folders)\n";
$usage .= "\t\t <udm> = m: minutes, h: hours, d: days, w: weeks (not active for deleted folders)\n";
$usage .= "\t\t type INBOX for <folder> root.\n";
$usage .= "\t\t type NOTIME for no time limits in place of <n><udm>\n\n";


require "/usr/local/cyr_scripts/core.pl";
use vars qw($cyrus_server $cyrus_user $cyrus_pass);
use Cyrus::IMAP::Admin;
use Sys::Syslog;
use Getopt::Long;


#
# CONFIGURATION PARAMS
#
$logtag = 'cyrRestore';
$logfac = 'LOG_MAIL';
my $localtimecountry = 'it_IT';
$rootRestore = 'RIPRISTINATI';
if (defined($rootRestore)) { $nof = "($rootRestore)";}
else { $nof = ''; }


$verbose=1;
my $unexpunge = `which unexpunge`;


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
my @user = undef;
my @folders = undef;
my @fdr = undef;
my @PARAM = undef;

use Unicode::IMAPUtf7;
use Encode;

# Import locale-handling tool set from POSIX module.
# This example uses: setlocale -- the function call
# LC_CTYPE -- explained below

use POSIX qw(locale_h);
use POSIX qw(strftime);
use Env;


sub restoreUnexp {
# Restore mails from already existing folders
                my $restore = '';
		my @unexpFolders = @{$_[0]};
		my $timelimit = $_[1];
		my $excludeFolder = $_[2];
		my $folderToExcludeRegex = $_[3];
		my $imaputf7 = $_[4];
                for (my $f=0;$f<=$#unexpFolders;$f++) {
                        if ($excludeFolder) {
				if ($unexpFolders[$f][0] =~ /$folderToExcludeRegex/i) {
					printLog('LOG_INFO','action=unexpunge status=notice folder="'.
					decodefoldername($unexpFolders[$f][0], $imaputf7,'ISO-8859-1').
                                	"\" timerange=$timelimit detail=\"folder excluded\"",1);
					next;
				}
			}
                        if ($timelimit =~ /^\d+/) {
                                $restore = $restore.$unexpunge. " -t $timelimit -v -d \"$unexpFolders[$f][0]\"; ";
                        }
                        else {
                                $restore = $restore.$unexpunge. " -a -v -d \"$unexpFolders[$f][0]\"; ";
                        }
			printLog('LOG_INFO','action=unexpunge status=notice folder="'.decodefoldername($unexpFolders[$f][0], $imaputf7, 'ISO-8859-1').
				"\" timerange=$timelimit",1);
                }
                system ($restore);

}

sub restoreDEL {
	my ($cyrus, $user, $folder, $folderToExcludeRegex, $tlimit, $imaputf7, $code, $verbose) = @_;

	my ($uid, $dom) = split('@',$user);
	my $k=0;
	my @folderToUnexp;

      @folders=$cyrus->listmailbox('DELETED/user/'.$uid.'*@'.$dom);
      printLog('LOG_INFO',"action=restoreDEL status=notice mailbox=$user startfolder=\"".decodefoldername($folder, $imaputf7, $code).
		'" nfolder='.($#folders+1),$verbose);
##      if ($#folders == -1) { print  '    User: '.$user[$c].": are you sure to exist?\n"; }

      for ($f=0;$f<=$#folders;$f++) {
	      my $n=0;
	      my $ruid = undef;
              if ($folders[$f][0] =~ /$folderToExcludeRegex/i) {
                        printLog('LOG_DEBUG','action=restoreDEL status=skipping folder="'.
                                decodefoldername($folders[$f][0], $imaputf7, 'ISO-8859-1').
                                '" startfolder="'.decodefoldername($folder, $imaputf7, $code)."\" timerange=NOTIME detail=\"skipping folder in exclusion list\"",$verbose);
                        next;
              }
              if ($folder ne '') {
         	     if ($folders[$f][0] !~ /$folder/i) {
                     	printLog('LOG_INFO','action=restoreDEL status=skipping folder="'.
                        	decodefoldername($folders[$f][0], $imaputf7, 'ISO-8859-1').
                        	'" startfolder="'.decodefoldername($folder, $imaputf7, $code)."\" timerange=NOTIME detail=\"skipping folder\"",$verbose);
			next;}
              }
              @_=split('/',$folders[$f][0]);
              $n=$#_;
              ($hexfolder,$dom) = split('@',$_[$n]);
              $deltimestamp = scalar(localtime(hex($hexfolder)));
              $transfolder = $imaputf7->encode(encode('utf8', strftime "%A%d%B%Y-%Hh%M", localtime(hex($hexfolder))));
              for ($j=1;$j<=$n;$j++) {
           	   if ($j==$n) {$ruid .= $transfolder.'@'.$dom;}
##		   else {
##				if ($j>2) {$ruid .= $_[$j].'-';}
##                   		else        {$ruid .= $_[$j].'/';}
##		   }
		   else {$ruid .= $_[$j].'/';}
                   if (($j==2)&&($rootRestore ne '')) {$ruid .= $rootRestore.'/';}
              }
              $cyrus->rename($folders[$f][0], $ruid);
              if ($cyrus->error) {
		$error=$cyrus->error;
		$sev='LOG_ERR';
		$status='fail';
              }
              else {
		$error='';
		$sev='LOG_INFO';
		$status='success';
	      }
		printLog($sev, "action=restoreDEL status=$status mailbox=$user folder=\"".decodefoldername($folders[$f][0], $imaputf7, 'ISO-8859-1').
                        '" newfolder="'.decodefoldername($ruid, $imaputf7, $code)."\" deldate=\"$deltimestamp\" timerange=NOTIME detail=\"Will try to unexpunge mail in newfolder\"", $verbose);
		$k=$k+$n;
	     $folderToUnexp[0][0] = $ruid;
	     # Finally, unexpunge mails from restored folders.
	     restoreUnexp(\@folderToUnexp,$tlimit,0,$folderToExcludeRegex,$imaputf7);
     }
     return $k;

}



# query and save the old locale

$old_locale = setlocale(LC_CTYPE);
setlocale(LC_TIME, $localtimecountry);
my ($syscountry, $code) = split(/\./,$old_locale);
$code='ISO-8859-1';
if ($syscountry ne $localtimecountry) {
	printLog('LOG_DEBUG', "action=check status=notice detail=\"You have configured a time country <$localtimecountry> which differs from system country <$syscountry>\"", $verbose);
}

$imaputf7 = Unicode::IMAPUtf7->new();

if (! defined($ARGV[0]) ) {
	die($usage);
}
     for ( $ARGV[0] ) {
         if    (/^-u/)  {
		if ($#ARGV >6) {die($usage);}
		##$user[0] = "$ARGV[1]";
		GetOptions( 	'u=s'	=> \$user[0],
				'folder:s' => \$folder,
                                'delay:s' => \$timelimit[0],
				'mutf7'    => \$mutf7
                ) or die($usage);
		if (defined($folder)) {
			if ($mutf7) {
				$fdr[0] = encode($code,$folder);
			}
			else {
				$fdr[0] = $imaputf7->encode(encode('ISO-8859-1',$folder));
			}
		}
		else { $fdr[0] = ''; }
		if ($folder eq 'INBOX') { $fdr[0] = ''; }
		if (!defined($timelimit[0])) { $timelimit[0] = 'NOTIME'; }
		$i=1;
	}
        elsif (/^-f/)  {
                if ($#ARGV != 1) { print $usage; die ("\nI need the file name!\n"); }
                $data_file=$ARGV[1];
                open(DAT, $data_file) || die("Could not open $data_file!");
                @raw_data=<DAT>;
                close(DAT);
                foreach $line (@raw_data)
                {
                        chomp($line);
                        @PARAM=split(/\t+/,$line,4);
                        if ($#PARAM != 2) { die ("\nInconsistency in line\n<$line>\n Recheck <$data_file>\n"); }
                        else {
                                $user[$i] = $PARAM[0];
				if ($PARAM[1] eq 'INBOX') {
								$fdr[$i]='';
							}
				else {
							$fdr[$i]= $imaputf7->encode(encode('ISO-8859-1',$PARAM[1]));
							}
				$timelimit[$i] = $PARAM[2];
				## PARAM[2] is 'NOTIME' if no time specified
                        }
                        $i++;
                }
                print "\nFound $i accounts\n";
         }
	else { die($usage); }
   }


  
  if ($unexpunge eq '') {die ("unexpunge NOT found!\n\n")};
  chop ($unexpunge);

if ( ($cyrus = cyrusconnect($logtag, $auth, $cyrus_server, $verbose)) == 0) {
        return 0;
}


openlog("$logtag/master", "pid", $logfac);
for ($c=0;$c<$i;$c++) {
	($uid,$dom) = split('@',$user[$c]);
	#### Look for specific folder if specified ####
	if ($fdr[$c] ne '') {
		printLog('LOG_INFO','action=unexpunge status=notice mailbox="'.$user[$c].
		'" startfolder="'.decodefoldername($fdr[$c], $imaputf7, $code).'" detail="trying to restore starting from <'.
		decodefoldername($fdr[$c], $imaputf7, $code).'>..."',$verbose);
		@folders=$cyrus->listmailbox('user/'.$uid.'/'.$fdr[$c].'*@'.$dom);
	        if ($#folders >= 0) {
        	        # Folders still exist
			# Try to restore excluding folders to skip
                	restoreUnexp(\@folders,$timelimit[$c],1,$nof,$imaputf7);
        	}
		
			## Folders that doesn't exist, try to restore folder by hand... pray please.
                        $inf = 'action=restoreDEL mailbox='.$user[$c].' status=notice startfolder="'.decodefoldername($fdr[$c], $imaputf7, $code).'" detail=" startfolder does not exist, I try to pray and restore it by hand ignoring time limits..."';
                        printLog('LOG_ERR',$inf,$verbose);
			$n = restoreDEL($cyrus,$user[$c], $fdr[$c], $nof, $timelimit[$c], $imaputf7, $code, $verbose);
        }
	#### Else look for all folder ####
        else {
		printLog('LOG_INFO','action=unexpunge status=notice mailbox="'.$user[$c].
                '" folder="'.$user[$c].'" detail="trying to restore starting from INBOX level of <'.$user[$c].'>..."',$verbose);
                @folders=$cyrus->listmailbox('user/'.$uid.'*@'.$dom);
		if ($#folders >= 0) {
                	restoreUnexp(\@folders,$timelimit[$c],1,$nof,$imaputf7);
        	}
		# Also restore all deleted folders
		$n = restoreDEL($cyrus, $user[$c], $fdr[$c], $nof, $timelimit[$c], $imaputf7, $code, $verbose);
	}

        if ( $n>2 )  {
                # I have restored folders
                if ($rootRestore ne '') {
		        print 'Remember to notice the user MUST check <'.$rootRestore.'> folder';
			printLog('LOG_INFO','action=restoreDEL status=notice mailbox='.$user[$c].' startfolder="'.decodefoldername($fdr[$c], $imaputf7, $code).'" detail="Some folder restored"',0);
		}
        }
        # No deleted folders to restore for this user
        if ( $n==0 ) {
		printLog('LOG_INFO','action=restoreDEL status=fail mailbox='.$user[$c].' startfolder="'.decodefoldername($fdr[$c], $imaputf7, $code).'" detail="no folder found"',$verbose);
	}
        print "\n";
	
}
	##########################################
	##########################################
	
## Just for vanity
# LC_TIME now reset to default defined by LC_ALL/LC_CTYPE/LANG
# environment variables. See perldoc for documentation.
# Remember that 42 will save you!
# restore the old locale
setlocale(LC_TIME, $old_locale);
