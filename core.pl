#!/usr/bin/perl -w
#
# All this code written by Marco Fav, so you must use better code. You are advised!

#########  Build release  #########
our $build = '0.2.3 - 11 Jun 2020';
###################################


no if $] >= 5.017011, warnings => 'experimental::smartmatch';

sub printLog {
  my ($sev,$mes,$verbose) = @_;
   syslog($sev,$mes);
   if ($verbose && $sev ne 'LOG_DEBUG') {
		  # when perl5.10 we can use var name in matching group
		  no warnings 'uninitialized';
		  $mes =~ s/(?:(\s*\w+\=)"([^"\r\n]+)"|(\s*\w+\=)([^\s]+))/$1$3\e[33m$2$4\e[39m/g;
		  #$mes =~ s/(\w+\=)("|)([^"]+)("|)/$1\e[33m$3\e[39m/g;
		  print " $mes\n";
		  if ($sev =~ /(LOG_ERR|LOG_CRIT|LOG_ALERT|LOG_EMERG)/) { print "\a"; }
		  use warnings 'uninitialized';
   }
}

sub checkascii {
 my ($str) = @_;
 if ( $str =~ /[[:^ascii:]]/) {
  return 0;
 } else {
  return 1;
 }
}

sub wchomp {
# We redefine chomp to work with CRLF too.
# It works by references.
	foreach (@_) {
		$_ =~ s/[\r\n]*//gm;
	}
}

sub rdlog {
# Return structured log with Rundeck ENV
        my $rdlog='';
        if (defined $ENV{'RD_JOB_USERNAME'}) {
                $rdlog = ' orig_user="'.$ENV{'RD_JOB_USERNAME'}.'"';
        }
        if (defined $ENV{'RD_JOB_EXECID'}) {
                $rdlog .= ' rd_execid="'.$ENV{'RD_JOB_EXECID'}.'"';
        }
        if (defined $ENV{'RD_JOB_EXECUTIONTYPE'}) {
                $rdlog .= ' rd_exectype="'.$ENV{'RD_JOB_EXECUTIONTYPE'}.'"';
        }
        if (defined $ENV{'RD_JOB_ID'}) {
                $rdlog .= ' rd_id="'.$ENV{'RD_JOB_ID'}.'"';
        }
        if (defined $ENV{'RD_JOB_NAME'}) {
                $rdlog .= ' rd_name="'.$ENV{'RD_JOB_NAME'}.'"';
        }
	return $rdlog;
}


sub composembx {
# rootmbx is the account name
#	(alice@example.com)
# folder is the folder part
#	(Trash)
# sep is separator
#	(/)
# nsp is the root part namespace
#	(user)

	my ($rootmbx,$folder,$sep,$nsp) = @_;	
	if ($folder eq "INBOX") {
    		return "$nsp$sep$rootmbx";
 	} else {
		my ($uid,$dom) = split('@',$rootmbx);
		defined ( $dom )
			or return "$nsp$sep$uid$sep$folder";
		return "$nsp$sep$uid$sep$folder\@$dom";
	}
}

sub decodefoldername {
# Decoder string $folder from
# modified imap utf7 to the
# new code $code.
# Usage:
#  decodefoldername($folder,$imaputf7,$code)
# where $impautf7 is the resource of module
# Unicode::IMAPUtf7
# Also remember to call "Encode" module.

        my $folder= $_[0];
        my $imaputf7 = $_[1];
        my $code;
        if ($_[2]) {
                $code = $_[2];
        } else {
                $code = 'utf8';
        }
        return decode ($code,$imaputf7->decode($folder));
}


## Routine to use with Net::LDAP ##
sub ldapconnect {
	my ($mainproc, $Server, $Port, $v) = @_;
        $ldap = Net::LDAP->new( $Server, port => $Port );
        $error=$@;
        if (!$ldap) {
                printLog('LOG_ALERT',"action=ldapconnect status=fail error=\"$error\" server=$Server port=$Port",$v);
        }
	return $ldap;
}

sub ldapbind {
	my ($mainproc, $resource, $Server, $Port, $BindUid, $BindPwd, $v) = @_;
        $mesg = $resource->bind($BindUid, password => $BindPwd);
        if ( $mesg->code ) {
                $error=$mesg->error;
                $code=$mesg->code;
                printLog('LOG_ERR',"action=ldapbind status=fail error=\"$error\" code=$code server=$Server port=$Port bind=\"$BindUid\"",$v);
                return 0;
        }
	return $mesg;
}
### -------- ###

sub accountIsLogged {
## Check if an account is logged every $wait seconds.
## It checks forever until the account logouts.

	my ($mainproc, $account, $dir, $wait, $v) = @_;

	use Sys::Syslog;
	openlog("$mainproc/isLogged",'pid','LOG_MAIL');
	# Read files
	if(!opendir( PROCDIR, $dir )) {
		printLog('LOG_WARNING',"action=iscyruslogged mailbox=\"$account\" status=fail error=\"EXIT - Could not open folder <$dir>: $!\"",$v);
		exit;
	}
	my @files = grep { $_ ne '.' && $_ ne '..' } readdir PROCDIR;
	closedir PROCDIR;

	foreach $file (@files) {
		if (!(open( FILEPROC, "<", $dir.'/'.$file))) {
				printLog('LOG_WARNING',"action=iscyruslogged mailbox=\"$account\" status=fail error=\"EXIT - Could not open <$file>: $!\"",$v);
				exit;
		}
		while (<FILEPROC>) {
			if ($_ =~ /$account/) {
				chop($_);
				printLog('LOG_WARNING',"action=iscyruslogged mailbox=\"$account\" status=pending detail=\"<$account> is logged in: <$_>\"",$v);
				close FILEPROC;
				sleep $wait;
				accountIsLogged($mainproc, $account, $dir, $wait, $v);
				return 0;
			}
    		}
		close FILEPROC;
	}
	printLog('LOG_INFO',"action=iscyruslogged mailbox=\"$account\" status=success detail=\"<$account> is not logged in\"",$v);
	closelog();
	return 0;
}

sub cyrusconnect {
## Connect to cyrus server via Cyradm
## Facility to log Rundeck remote user, if set in ENV
	#https://docs.rundeck.com/2.11.3/manual/jobs.html#context-variable-usage

	my ($mainproc, $auth, $Server, $v) = @_;
	my $rdlog=rdlog();

	use Sys::Syslog;
	openlog("$mainproc/cyrusconn",'pid','LOG_MAIL');
	my $cyrus = Cyrus::IMAP::Admin->new($Server);
	if ( !defined $cyrus ) {
		printLog('LOG_ALERT','action=cyrusconnect status=fail error="Connection error"' . " server=$Server mailHost=${Server}${rdlog}",$v);
		$cyrus = 0;
	}
	elsif ( !$cyrus->authenticate(%$auth) ) {
        	printLog('LOG_ALERT','action=cyrusconnect status=fail error="'. $cyrus->error . "\" server=$Server mailHost=${Server}${rdlog}",$v);
                $cyrus = 0;
	}
	else {
		printLog('LOG_DEBUG',"action=cyrusconnect status=success server=$Server mailHost=$Server user=".$auth->{-user}.' authz='.$auth->{-authz} . $rdlog, $v);
	}
	closelog();
	return $cyrus;
}

sub cyrusVersion {
# Query the Cyrus IMAP version
	my ($client) = @_;
	my $info;
	$client->addcallback({-trigger => 'ID',
        	-callback => sub {
                	my %d = @_;
                	$info = $d{-text};
	}});
	my ($rc, $msg) = $client->send('', '', 'ID NIL');
	$client->addcallback({-trigger => 'ID'});
	if ($rc ne 'OK') {
		return 'ERROR';
	}
	while ($info =~ s/\"([^\"]+)\"\s+(\"[^\"]+\"|NIL)\s*//) {
		my $field = $1;
		my $value = $2;
		$value =~ s/\"//g;
		if ($field eq 'version') {
                	return $value;
		}
	}
	return 'NIL';
}

sub cyrusVersion_byIMAPTalk {
# Query the Cyrus IMAP version
        my ($client) = @_;
        my $info;
        $client->_require_capability('id') || return 'NIL';
        $info = $client->_imap_cmd("id", 0, "id", ("NIL"));
        while ($info =~ s/\"([^\"]+)\"\s+(\"[^\"]+\"|NIL)\s*//) {
                my $field = $1;
                my $value = $2;
                $value =~ s/\"//g;
                if ($field eq 'version') {
                        return $value;
                }
        }
        return 'NIL';
}


sub createMailbox {

  use Sys::Syslog;
  use Unicode::IMAPUtf7;
  use Encode;
  my ($mainproc, $cyrus, $user, $subfolder, $partition, $sep, $v, $specialuse) = @_;

  my $code = 'ISO-8859-1';
  my $status;
  my $error;
  my $return;
  my $severity;
  my $imaputf7 = Unicode::IMAPUtf7->new();
  my $mailbox=composembx($user,$subfolder,$sep,'user');
  if ($specialuse) {
	  # RFC 6154 section 2
	  my %special = map { $_ => 1 } ('Archive', 'Drafts', 'Flagged', 'Junk', 'Sent', 'Trash');
	  if(exists($special{$specialuse})) {
		my %ops = ('-specialuse', "\\$specialuse");
	  	$cyrus->create($mailbox,$partition,\%ops);
	  }
	  else {
		$cyrus->{error} = "<$specialuse> is not on standard RFC6154";
	  }
  }
  else {
	$specialuse = 'none';
  	$cyrus->create($mailbox,$partition);
  }
  openlog("$mainproc/addMbox", "pid", LOG_MAIL);
  $folder = decodefoldername($subfolder, $imaputf7, $code);
  if ($cyrus->error) {
	$status = 'fail';
	$severity = 'LOG_WARNING';
	$return = 0;
	$error = ' error="'.$cyrus->error . '"';
  } else {
	$status = 'success';
	$severity = 'LOG_INFO';
	$return = 1;
	$error = '';
  }
  if (!defined($partition)) {$partition='root partition of mailbox or autoselected by Cyrus';}
  printLog($severity, "action=addmailbox status=$status mailbox=\"$user\" folder=\"$folder\" part=\"$partition\" special=$specialuse${error}", $v);
  closelog();
  return $return;
}

sub deleteMailbox {

  use Sys::Syslog;
  use Unicode::IMAPUtf7;
  use Encode;
  my $status;
  my $error;
  my $return;
  my $severity;
  my $code = 'ISO-8859-1';
  my $imaputf7 = Unicode::IMAPUtf7->new();
  my ($mainproc, $cyrus, $user, $subfolder, $sep, $v) = @_;
  my $mailbox=composembx($user,$subfolder,$sep,'user');
  openlog("$mainproc/delMbox", "pid", LOG_MAIL);
  $cyrus->delete('user'. $sep . $user);
  $folder = decodefoldername($subfolder, $imaputf7, $code);
  if ($cyrus->error) {
	  $status = 'fail';
	  $severity = 'LOG_WARNING';
	  $return = 0;
	  $error = ' error="'.$cyrus->error . '"';
  } else {
	  $status = 'success';
	  $severity = 'LOG_INFO';
	  $return = 1;
	  $error = '';
  }
  printLog($severity,"action=delmailbox status=$status mailbox=\"$user\" folder=\"$folder\"${error}", $v);
  closelog();
  return $return;
}


sub renameMailbox {

  use Sys::Syslog;
  my ($mainproc, $cyrus, $user_old, $folder_old, $user_new, $folder_new, $partition, $sep, $v) = @_;
  use Unicode::IMAPUtf7;
  use Encode;
  my $code = 'ISO-8859-1';
  my $imaputf7 = Unicode::IMAPUtf7->new();
  my $plog = '';
  my $status;
  my $error;
  my $return;
  my $severity;
  openlog("$mainproc/renMbox", "pid", LOG_MAIL);

  if ($partition eq '') {
	  undef $partition;
  }
  else {
	  $plog = "part=$partition ";
  }

  $mailbox_old = composembx($user_old, $folder_old, $sep, 'user');
  $mailbox_new = composembx($user_new, $folder_new, $sep, 'user');

  if (defined $partition) { $cyrus->rename($mailbox_old, $mailbox_new, $partition); }
  else { $cyrus->rename($mailbox_old, $mailbox_new); }
  if ($cyrus->error) {
          $status = 'fail';
          $severity = 'LOG_WARNING';
          $return = 0;
          $error = ' error="'.$cyrus->error . '"';
  } else {
          $status = 'success';
          $severity = 'LOG_INFO';
          $return = 1;
          $error = '';
  }
  $folder_old = decodefoldername($folder_old, $imaputf7, $code);
  $folder_new = decodefoldername($folder_new, $imaputf7, $code);
  printLog($severity,"action=renmailbox status=$status mailbox=\"$user_old\" folder=\"$folder_old\" newmailbox=\"$user_new\" newfolder=\"$folder_new\" ${plog}${error}", $v);
  closelog();
  return $return;
}


sub renameFolder {
# Rename folder at normal user level authorization.
# If folder_old is INBOX, rename INBOX and all folders
# at INBOX level hierarchy.

	use Sys::Syslog;
	my ($mainproc, $cyrus, $folder_old, $folder_new, $partition, $sep, $v) = @_;
		# folder_old = folder name excluding 'INBOX/', or INBOX
		# folder_new = folder name excluding 'INBOX/'

	use Unicode::IMAPUtf7;
	use Encode;
	my $code = 'ISO-8859-1';
	my $plog = '';
	my $imaputf7 = Unicode::IMAPUtf7->new();
	my $return = 1;
        if ($partition eq '') {
		undef $partition;
	}
	else {
		$plog = "part=$partition ";
	}
	openlog("$mainproc/renFold", "pid", LOG_MAIL);
	if ( $folder_new eq 'INBOX' ) {
		printLog('LOG_WARNING',"action=renfolder status=fail folder=\"$folder_old\" newfolder=\"$folder_new\" ${plog}error=\"Can't rename <$folder_old> in destination folder <INBOX>. Choose a destination folder different than INBOX.\"", $v);
		closelog();
		return 0;
	}
	## Non INBOX folder ##
	if ($folder_old ne 'INBOX') {
		if (defined $partition) { $cyrus->rename('INBOX'.$sep.$folder_old, 'INBOX'.$sep.$folder_new, $partition); }
		else { $cyrus->rename('INBOX'.$sep.$folder_old, 'INBOX'.$sep.$folder_new); }
		$folder_old = decodefoldername($folder_old, $imaputf7, $code);
		$folder_new = decodefoldername($folder_new, $imaputf7, $code);
		if ($cyrus->error) {
			printLog('LOG_WARNING',"action=renfolder status=fail folder=\"$folder_old\" newfolder=\"$folder_new\" ${plog}error=\"" . $cyrus->error . '"', $v);
			closelog();
			return 0;
		} else {
			printLog('LOG_INFO',"action=renfolder status=success folder=\"$folder_old\" newfolder=\"$folder_new\" $plog", $v);
			closelog();
			return 1;
		}
	}
	else {
		## Rename of INBOX folder ##
		# Discover all root mailboxes of user
		# Excluding destination root folder
		my @folders = $cyrus->listmailbox('INBOX'.$sep.'%');
		my @comp = split (/$sep/,$folder_new);
		my $filt = 'INBOX'.$sep.$comp[0];
		my $cVer = cyrusVersion($cyrus);
		for ($f=0;$f<=$#folders;$f++) {
			if ( $folders[$f][0] =~ /^$filt/ ) {
				next;
			}
                        my @path = split (/$sep/,$folders[$f][0]);
			my $leaf = $path[$#path];
                        $folder_oldL = decodefoldername($folders[$f][0], $imaputf7, $code);
			$folder_oldL =~ s/^INBOX\///;
			$folder_newL = decodefoldername($folder_new.$sep.$leaf, $imaputf7, $code);

			# Deletion of specialuse flags, if any #
			if ( $cVer =~ /^3/ ) {
				# We delete all specialuse flags which deny the RENAME or DELETE command.
				# The metadata is /private/specialuse, it applies NIL to unset (rfc6154).
				$cyrus->setmetadata($folders[$f][0], 'specialuse', 'none', 1);
				if ($cyrus->error) {
					$return = 0;
					printLog('LOG_WARNING',"action=set_specialuse folder=\"$folder_oldL\" value=NIL error=\"" . $cyrus->error . '"', $v);
				}
			}

			if (defined $partition) { $cyrus->rename($folders[$f][0], 'INBOX'.$sep.$folder_new.$sep.$leaf, $partition); }
			else { $cyrus->rename($folders[$f][0], 'INBOX'.$sep.$folder_new.$sep.$leaf); }
			## Log
			if ($cyrus->error) {
				$return = 0;
                        	printLog('LOG_WARNING',"action=renfolder status=fail folder=\"$folder_oldL\" newfolder=\"$folder_newL\" ${plog}error=\"" . $cyrus->error . '"', $v);
                	} else {
				printLog('LOG_INFO',"action=renfolder status=success folder=\"$folder_oldL\" newfolder=\"$folder_newL\" ${plog}", $v);
                	}
		}
		# Oh yes, INBOX too
		if ( $cVer =~ /^3/ ) {
			$cyrus->setmetadata('INBOX', 'specialuse', 'none', 1);
			if ($cyrus->error) {
				$return = 0;
				printLog('LOG_WARNING','action=set_specialuse folder=INBOX value=NIL error="' . $cyrus->error . '"', $v);
			}
		}
		if (defined $partition) { $cyrus->rename($folder_old, 'INBOX'.$sep.$folder_new, $partition); }
		else { $cyrus->rename($folder_old, 'INBOX'.$sep.$folder_new); }
		## Log
                $folder_new = decodefoldername($folder_new, $imaputf7, $code);
                if ($cyrus->error) {
			$return = 0;
                        printLog('LOG_WARNING',"action=renfolder status=fail folder=\"$folder_old\" newfolder=\"$folder_new\" ${plog}error=\"" . $cyrus->error . '"', $v);
                } else {
                        printLog('LOG_INFO',"action=renfolder status=success folder=\"$folder_old\" newfolder=\"$folder_new\" $plog", $v);
                }
	}
	closelog();
	return $return;
}


sub transferMailbox {

  use Sys::Syslog;
  my ($mainproc, $cyrus, $user, $destServer, $partition, $sep, $v) = @_;
  my $plog;
  my $status;
  my $severity;
  my $return;
  my $error;

  openlog("$mainproc/xferMbox", "pid", LOG_MAIL);
  if ($partition eq '') { undef $partition; }

  $mailbox = "user". $sep . $user;

  if (defined $partition) {
	$cyrus->xfermailbox($mailbox, $destServer, $partition);
	$plog = "part=$partition ";
  }
  else {
	$cyrus->xfermailbox($mailbox, $destServer);
	$plog = '';
  }
  if ($cyrus->error) {
          $status = 'fail';
          $severity = 'LOG_WARNING';
          $return = 0;
          $error = 'error="'.$cyrus->error . '"';
  } else {
          $status = 'success';
          $severity = 'LOG_INFO';
          $return = 1;
          $error = '';
  }
  syslog($severity,"action=cyrxfer status=$status mailbox=\"$user\" ${plog}${error}", $v);
  closelog();
  return $return;
}


sub changeOXIMAPServer {
# $user:        username to Digest Auth on url
# $pwd:         password for $user
# $netloc:      see at LWP::UserAgent doc, it is the <host>:<port> site where to send the above credentials.
# $realm:       the "site says" popup message. You must know it!
# $url:         an URI object for the GET request.
# $noproxy:     an optional array of FQDN domains where to escape proxy.

	use Sys::Syslog;
        use LWP::UserAgent ();
        my ($mainproc, $user, $pwd, $netloc, $realm, $url, $noproxy, $v) = @_;

        my $ua = LWP::UserAgent->new;
        $ua->timeout(10);
        $ua->no_proxy($noproxy);

        $ua->credentials($netloc, $realm, $user, $pwd);
        my $response = $ua->get($url);

	openlog("$mainproc/changeOX", "pid", LOG_MAIL);
	if ($response->is_success) {
		$status='success';
		$sev='LOG_INFO';
	}
	else {
		$status='fail';
		$sev='LOG_ERR';
	}
        printLog($sev,
	  "action=oxapi oxbatch=\"$url\" status=$status code=".$response->code.' detail="Powered by : '. $response->header('X-Powered-By').'"', $v);
	closelog();
        return $response->is_success;
}



sub setMetadataMailbox {

  my ($mainproc, $cyrus, $user, $subfolder, $attr, $value, $sep, $v) = @_;
  use Sys::Syslog;
  use Unicode::IMAPUtf7;
  use Encode;
  my $folder;
  my $status;
  my $sev;
  my $return;
  my $error;
  my $code = 'ISO-8859-1';
  my $imaputf7 = Unicode::IMAPUtf7->new();
  openlog("$mainproc/setMetaMbox", "pid", LOG_MAIL);

  return 0 if (not defined $attr or not defined $value);
  $mailbox=composembx($user,$subfolder,$sep,'user');
  $folder = decodefoldername($subfolder, $imaputf7, $code);
  $cyrus->mboxconfig($mailbox,$attr,$value);
  if ($cyrus->error) {
	$status='fail';
	$error=' error="' . $cyrus->error .'"';
	$sev='LOG_ERR';
	$return=0;
  }
  else {
	$status='success';
	$sev='LOG_WARNING';
	$return=1;
	$error='';
  } 
  printLog($sev,"action=setimapmetadata status=$status mailbox=\"$user\" folder=\"$folder\" meta_name=\"$attr\" meta_value=\"$value\"${error}", $v);
  closelog();
  return $return;
}



sub setAnnotationServer {

  my ($mainproc, $imap, $path, $anno, $valuetype, $value, $v) = @_;
  openlog("$mainproc/setAnServer", "pid", LOG_MAIL);

  my $return=1;
  my $error='';
  my $detail=$error;
  my $sev='LOG_INFO';
  # Check for ascii value, else exit
  if (!checkascii($value)) {
	$error='values is not ASCII';
	$status='fail';
	$sev='LOG_ERR';
	$return=0;
  }
  if ($return == 1) {
	# Read current value, if it exists
	$read=$imap->getannotation($path,$anno,$valuetype);
	$oldvalue=$read->{$path}->{$anno}->{$valuetype};
	if (!defined($oldvalue)) {$oldvalue = 'NIL';}
  
	# Check if value has to be changed, else exit
	if ($oldvalue eq $value) {
		$status='success';
		$sev='LOG_WARNING';
		$detail='value unchanged';
		$error='';
		$return=0;
	}
  }

  if ($return == 0) {
	printLog($sev, "action=setimapmetadata status=$status error=\"$error\" detail=\"$detail\" meta_name=\"$anno\" meta_oldvalue=\"$oldvalue\" meta_value=\"$value\" path=\"$path\"", $v);
	closelog();
	return $return;
  }

  # Set annotation value
  $result=$imap->setannotation($path, $anno, [$valuetype, $value]);
  if (!$result)
  {
	$sev='LOG_ALERT';
	$status='fail';
	$error=$@;
	$detail='';
	$return=0;
  }
  else {
	$status='success';
	$detail='value changed';
  }

  printLog($sev, "action=setimapmetadata status=$status error=\"$error\" detail=\"$detail\" meta_name=\"$anno\" meta_oldvalue=\"$oldvalue\" meta_value=\"$value\" path=\"$path\"", $v);
  closelog();
  return $return;
}

sub setMetadataServer {

  my ($mainproc, $imap, $path, $anno, $valuetype, $value, $v) = @_;
  openlog("$mainproc/setMdServer", "pid", LOG_MAIL);

  my $return=1;
  my $error='';
  my $detail=$error;
  my $sev='LOG_INFO';
  # Check for ascii value, else exit
  if (!checkascii($value)) {
        $error='values is not ASCII';
        $status='fail';
        $sev='LOG_ERR';
        $return=0;
  }
  if ($return == 1) {
        # Read current value, if it exists
	$read=$imap->getmetadata($path, {depth => 'infinity'}, "/$valuetype$anno");
	$oldvalue=$read->{$path}->{lc "/$valuetype$anno"};
        if (!defined($oldvalue)) {$oldvalue = 'NIL';}

        # Check if value has to be changed, else exit
        if ($oldvalue eq $value) {
                $status='success';
                $sev='LOG_WARNING';
                $detail='value unchanged';
                $error='';
                $return=0;
        }
  }

  if ($return == 0) {
        printLog($sev, "action=setimapmetadata status=$status error=\"$error\" detail=\"$detail\" meta_name=\"$anno\" meta_oldvalue=\"$oldvalue\" meta_value=\"$value\" path=\"$path\"", $v);
        closelog();
        return $return;
  }

  # Set annotation value
  $result=$imap->setmetadata($path,"/$valuetype$anno", $value);
  if (!$result)
  {
        $sev='LOG_ALERT';
        $status='fail';
        $error=$@;
        $detail='';
        $return=0;
  }
  else {
        $status='success';
        $detail='value changed';
  }

  printLog($sev, "action=setimapmetadata status=$status error=\"$error\" detail=\"$detail\" meta_name=\"$anno\" meta_oldvalue=\"$oldvalue\" meta_value=\"$value\" path=\"$path\"", $v);
  closelog();
  return $return;
}


sub getPart {
	my ($mainproc, $cyrus, $user, $subfolder, $sep, $v) = @_;
	use Sys::Syslog;

	openlog("$mainproc/getPart", "pid", LOG_MAIL);
	my $part = 'NIL';
	my $mailbox=composembx($user,$subfolder,$sep,'user');
	# Return the partition of $mailbox INBOX
	my $cVer = cyrusVersion($cyrus);
	if ( $cVer =~ /^3/ ) {
		my @info = $cyrus->getinfo($mailbox);
		if ($cyrus->error) {
         		$status='fail';
	         	$error=' error="'.$cyrus->error .'"';
		        $sev='LOG_ERR';
		}
		else {
			$status='success';
			$sev='LOG_INFO';
			$error='';
			for ($j=0;$j<$#info;$j+=2) {
				$anno{$info[$j]} = $info[$j+1];
			}
			if ( $cVer !~ /^3.0/ ) {
				$part = $anno{$mailbox}{'shared'}{'/mailbox//shared/vendor/cmu/cyrus-imapd/partition'};
			}
			else {
				$part = $anno{$mailbox}{'shared'}{'/mailbox//vendor/cmu/cyrus-imapd/partition'};
			}
		}
	}
	if ( $cVer =~ /^(v|)2/ ) {
		my @info = $cyrus->info($mailbox);
                if ($cyrus->error or !@info) {
       			$status='fail';
			if ( $cyrus->error ) {
                        	$error=' error="'.$cyrus->error . '"';
			}
			else {
				$error=' error="can\'t determine partition."';
			}
                        $sev='LOG_ERR';
		}
                else {
                        $status='success';
                        $sev='LOG_INFO';
                        $error='';
			for ($j=0;$j<$#info;$j+=2) {
				$anno{$info[$j]} = $info[$j+1];
			}
			$part = $anno{'/mailbox/{'.$mailbox.'}/vendor/cmu/cyrus-imapd/partition'};

		}
	}
	printLog($sev,"action=getinfo status=$status mailbox=\"$user\" folder=\"$subfolder\" part=${part}${error}", $v);
	closelog();
	return $part;
}

sub getDomainPart {
	my ($mainproc, $cyrus, $user, $v) = @_;
	use Sys::Syslog;
	openlog("$mainproc/getDomPart", "pid", LOG_MAIL);
	my $cVer = cyrusVersion($cyrus);
	my $part = 'NIL';

	# Read partition domain from Partition Manager metadata
	my ($uid,$dom) = split('@',$user);
	my $part_path = "/vendor/csi/partition/$dom";
	if ( $cVer =~ /^3/ ) {
		my @info = $cyrus->getinfo('',$part_path);
		if ( $info[1]{private}{"/server//private$part_path"} ne 'NIL' ) {
			$part = $info[1]{private}{"/server//private$part_path"};
		}
	}
	if ( $cVer =~ /^(v|)2/ ) {
		# There is a BUG in getinfo when reading server annotations. So...
		$cyrus->addcallback({-trigger => 'ANNOTATION',
                        -callback => sub {
                                my %d = @_;
                                my $text = $d{-text};
                                if ($text =~ /\"\Q$part_path\E\"\s+\(\"value\.priv\"\s+\"(\w+)\"\)/) {
                                        ${$d{-rock}} = $1;
                                }
                        },
                        -rock => \$part});

        	my ($rc, $msg) = $cyrus->send('', '', 'GETANNOTATION %s %q "value.priv"',
                                                '', $part_path);
        	$cyrus->addcallback({-trigger => 'ANNOTATION'});
        	if ($rc eq 'OK') {
                	$cyrus->{error} = undef;
        	} else {
                	$cyrus->{error} = $msg;
        	}
	}
        if ($cyrus->error) {
                $status='fail';
                $error=' error="'.$cyrus->error . '"';
                $sev='LOG_ERR';
        }
        else {
                $status='success';
                $sev='LOG_INFO';
                $error='';
	}
	printLog($sev,"action=getinfo status=$status mailbox=\"$user\" domain=$dom part=${part}${error}", $v);
	closelog();
	return $part;
}

sub setQuota {

  use Sys::Syslog;
  use Unicode::IMAPUtf7;
  use Encode;
  use feature "switch";
  no if $] >= 5.018, warnings => qw( experimental::smartmatch );
  my ($mainproc, $cyrus, $user, $subfolder, $quota_size, $sep, $v) = @_;
  my $code = 'ISO-8859-1';
  my @argv;
  my $imaputf7 = Unicode::IMAPUtf7->new();
  openlog("$mainproc/setQuota", "pid", LOG_MAIL);

  $mailbox=composembx($user,$subfolder,$sep,'user');
  $folder = decodefoldername($subfolder, $imaputf7, $code);
  defined $quota_size
	  or $quota_size = 'none';
  if ( $quota_size =~ /^[\s\r\n\t]*$/ ) {
	  $quota_size = 'none';
  }
  given ( $quota_size ) {
	when( 'none' ) {
		  @argv=($mailbox);
	}
	when( /^\d+$/ ) {
	  	# quota provided in MB, but cyradm want KB:
	  	$quota_size = $quota_size * 1024;
	  	@argv=($mailbox, "STORAGE", $quota_size);
	}
	default {
		printLog('LOG_ERR', "action=setimapquota status=fail error=\"You must provide a quota in MiB, or none\" mailbox=\"$user\" folder=\"$folder\" detail=\"Error reading the new quota value\"", $v);
		closelog();
		return 0;
	}
  }
  my @before=$cyrus->listquotaroot($mailbox);
  if ($cyrus->error) {
        $sev='LOG_ERR';
        $error=$cyrus->error;
        $status='fail';
        $return=0;
	printLog($sev, "action=setimapquota status=$status error=\"$error\" mailbox=\"$user\" folder=\"$folder\" detail=\"Error reading the old quota value\"", $v);
  }
  if (! defined $before[2][1]) {
	$before[2][1] = 'none';
  }
  if (! defined $before[2][0]) {
	 $before[2][0] = 0;
  }

  $cyrus->setquota(@argv);
  if ($cyrus->error) {
	$sev='LOG_ERR';
	$error=$cyrus->error;
	$status='fail';
	$return=0;
  } else {
        $sev='LOG_WARNING';
	if ($before[0] ne $mailbox) {
		$error = "$folder is now a new Quota Root!";
	} else {
        	$error='';
	}
        $status='success';
        $return=1;
  }
  printLog($sev, "action=setimapquota status=$status mailbox=\"$user\" folder=\"$folder\" error=\"$error\" oldvalue=".
	$before[2][1]." value=$quota_size used=".$before[2][0], $v);
  closelog();
  return $return;
}


sub setACL {
  my ($mainproc, $cyrus, $user,$subfolder,$who,$right, $sep, $v) = @_;
  use Sys::Syslog;
  use Unicode::IMAPUtf7;
  use Encode;
  my $folder;
  my $code = 'ISO-8859-1';
  my $imaputf7 = Unicode::IMAPUtf7->new();
  openlog("$mainproc/setACL", "pid", LOG_MAIL);


  $mailbox=composembx($user,$subfolder,$sep,'user');
  $cyrus->setaclmailbox($mailbox,$who,$right);
  if ($cyrus->error) {
	$status='fail';
	$sev='LOG_ERR';
	$error= ' error="' . $cyrus->error . '"';
	$return=0;
  }
  else {
	$status='success';
	$sev='LOG_WARNING';
	$error='';
	$return=1;
  }
  $folder = decodefoldername($subfolder, $imaputf7, $code);
  printLog($sev,"action=setimapacl status=${status}${error} mailbox=\"$user\" folder=\"$folder\" uid=$who right=$right", $v);
  closelog();
  return $return;
}


sub listACL {
  my ($mainproc, $cyrus, $user,$subfolder,$who, $sep, $v) = @_;
  use Sys::Syslog;
  use Unicode::IMAPUtf7;
  use Encode;
  my $folder;
  my $code = 'ISO-8859-1';
  my $imaputf7 = Unicode::IMAPUtf7->new();
  openlog("$mainproc/listACL", "pid", LOG_MAIL);

  $mailbox=composembx($user,$subfolder,$sep,'user');
  %$acl= $cyrus->listaclmailbox($mailbox);
  if ($cyrus->error) {
        $status='fail';
        $sev='LOG_ERR';
        $error=$cyrus->error;
        $right=0;
  }
  else {
        $status='success';
        $sev='LOG_INFO';
        $error='';
        # Read current value, if it exists
        $right=$acl->{$who};
        if (!defined($right)) {
		$right = 'NIL';
		$error='No right found';
	}

  }

#  use Data::Dumper;
#  print Dumper(\%$acl);
  $folder = decodefoldername($subfolder, $imaputf7, $code);
  printLog($sev,"action=listimapacl status=$status error=\"$error\" mailbox=\"$user\" folder=\"$folder\" uid=$who right=$right", $v);
  closelog();
  return $right;
}

sub parseuid {
	my ($mainproc,$uid,$v) = @_;
	my ($user,$dom) = split('@',$uid);
	if (not defined($dom)) {
		my $error="<$uid> is not in the form user\@domain";
		openlog("$mainproc/parseuid", "pid", LOG_MAIL);
		printLog('LOG_ERR',"action=parseuid status=fail error=\"$error\" uid=$uid", $v);
		closelog();
		return 0;
	}
	return 1;
}

sub ldapAdduser {
	use Net::LDAP;
	use Sys::Syslog;
	my $error= undef;
	my $code = NULL;
	my $dn = NULL;
	my $origStatus = NULL;
	my ($mainproc,$ldap,$ldapBase,$uid,$mailhost,$name,$surname,$mail,$pwd,$v) = @_;
	openlog("$mainproc/ldapAddUser", "pid", LOG_MAIL);

        $mesg = $ldap->search( # perform a search
                base   => $ldapBase,
                filter => "(&(objectClass=mailRecipient)(uid=$uid))",
                attrs  => ['uid', 'mailUserStatus']
        );
        if ($mesg->code) {
                $error=$mesg->error;
                $code=$mesg->code;
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code",$v);
                closelog();
                return 0;
        }

        $nret = $mesg->count;
        if ($nret > 0) {
		# The LDAP entry already exists. But if the mailUserStatus is "removed", we can change it to
		# "active" and let another task to add the IMAP mailbox.
		# givenName, sn and mail are not checked against the values provided. We consider uid unique.
		$error="The LDAP entry of <$uid> already exists. We won\'t create the entry.";
		printLog('LOG_INFO',"action=ldapsearch status=success detail=\"$error\" uid=$uid code=$code",$v);
		my $entry = $mesg->entry ( 0 );
        	$origStatus = $entry->get_value( 'mailUserStatus' );
        	if ( $origStatus eq 'removed' ) {
			$dn= $mesg->entry->dn();
            		$mesg = $ldap->modify( $dn,
				replace => { 'mailUserStatus' => 'active' } );
            		if ($mesg->code) {
                		$error=$mesg->error;
                		$code=$mesg->code;
                		printLog('LOG_ALERT',"action=ldapmod status=fail error=\"$error\" uid=$uid code=$code origMailUserStatus=$origStatus mailUserStatus=active",$v);
				closelog();
				return 0;
        		}
        		else {
                		printLog('LOG_INFO',"action=ldapmod status=success uid=$uid origMailUserStatus=$origStatus mailUserStatus=active",$v);
                		closelog();
                		return 1;
        		}
		}
		printLog('LOG_ALERT',"action=ldapmod status=fail error=\"The entry already exists and its mailUserStatus does not allow a new mailbox account\" uid=$uid origMailUserStatus=$origStatus",$v);
		closelog();
		return 0;
	}
	else {
		# Add the LDAP entry
		my ($user,$dom) = split('@',$uid);
		if (not defined($dom)) {
			$error="<$uid> is not in the form user\@domain";
			printLog('LOG_ERR',"action=parseuid status=fail error=\"$error\" uid=$uid", $v);
			closelog();
			return 0;
		}
		$dn="uid=$uid,o=$dom,$ldapBase";
		$mesg = $ldap->add( $dn,
				attrs => [
					cn			=> [ "$name $surname" ],
					sn			=> $surname,
					givenName		=> $name,
					mail			=> $mail,
					objectClass		=> ['top', 'person', 'organizationalPerson', 'inetOrgPerson', 'inetMailUser', 'mailRecipient' ],
					uid			=> $uid,
					userPassword		=> $pwd,
					mailHost		=> $mailhost,
					mailPostfixTransport	=> "lmtp:[$mailhost]",
					mailUserStatus		=> 'active',
					mailDeliveryOption	=> 'mailbox'
				]
			);
		if ($mesg->code) {
			$error=$mesg->error;
			$code=$mesg->code;
			printLog('LOG_ERR',"action=ldapadd status=fail error=\"$error\" uid=$uid code=$code",$v);
			closelog();
			return 0;
		}
		else {
			printLog('LOG_INFO',"action=ldapadd status=success uid=$uid mail=$mail mailhost=$mailhost", $v);
		        closelog();
			return 1;
		}
	}
}

sub ldapDeluser {
        use Net::LDAP;
        use Sys::Syslog;
	my $error= undef;
	my $code = NULL;
        my ($mainproc,$ldap,$ldapBase,$uid,$mailhost,$typeDel,$v) = @_;
        openlog("$mainproc/ldapDelUser", "pid", LOG_MAIL);

	my @allowed = ('deleted', 'removed');
	if ( not ( $typeDel ~~ @allowed ) ) {
		printLog('LOG_ERR',"action=parsearg status=fail error=\"$typeDel is not allowed as mailUserStatus\" uid=$uid",$v);
		closelog();
		return 0;
	}

        $mesg = $ldap->search( # perform a search
                base   => $ldapBase,
                filter => "(&(objectClass=mailRecipient)(uid=$uid))",
                attrs  => ['uid', 'mailHost' ]
        );

        if ($mesg->code) {
                $error=$mesg->error;
                $code=$mesg->code;
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code",$v);
                closelog();
                return 0;
        }

        $nret = $mesg->count;
        if ($nret > 1) {
                $error="Multiple instance found for <$uid>";
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code",$v);
                closelog();
                return 0;
        }
        if ($nret < 1) {
                $error="No instance found for <$uid>";
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" action=search uid=$uid code=$code",$v);
                closelog();
                return 0;
        }
	my ($user,$dom) = split('@',$uid);
	if (not defined($dom)) {
		$error="<$uid> is not in the form 'user\@domain'";
		printLog('LOG_ERR',"action=parseuid status=fail error=\"$error\" uid=$uid", $v);
		closelog();
		return 0;
	}
	my $dn="uid=$uid,o=$dom,$ldapBase";
	$mesg = $ldap->modify( $dn,
			replace => { mailUserStatus	=> $typeDel }
		);
	if ($mesg->code) {
                $error=$mesg->error;
                $code=$mesg->code;
                printLog('LOG_ALERT',"action=ldapmod status=fail error=\"$error\" uid=$uid code=$code mailHost=$mailhost mailUserStatus=$typeDel",$v);
		closelog();
		return 0;
	}
	else {
		printLog('LOG_INFO',"action=ldapmod status=success uid=$uid mailHost=$mailhost mailUserStatus=$typeDel",$v);
		closelog();
		return 1;
	}
}
	



sub ldapReplaceMailhost {
	use Net::LDAP;
	use Sys::Syslog;

	my ($mainproc,$ldapServer,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$uid,$origServer,$destServer,$v) = @_;
	openlog("$mainproc/ldapRepMHost", "pid", LOG_MAIL);
	if ( !($ldap=ldapconnect($mainproc, $ldapServer, $ldapPort, $v)) ) {
		closelog();
		return 0;
	}
	if ( ($mesg=ldapbind($mainproc, $ldap, $ldapServer, $ldapPort, $ldapBindUid, $ldapBindPwd, $v)) == 0 ) {
		closelog();
		return 0;
	}

	$mesg = $ldap->search( # perform a search
        	base   => $ldapBase,
        	filter => "(&(objectClass=mailRecipient)(mailHost=$origServer)(uid=$uid))",
        	attrs  => ['mailHost', 'mailPostfixTransport', 'uid']
        );
	if ($mesg->code) {
		$error=$mesg->error;
		$code=$mesg->code;
		printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$v);
		closelog();
		return 0;
	}

	$nret = $mesg->count;
	if ($nret > 1) {
		$error="Multiple instance found for <$uid> with <$origServer>";
		printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$v);
		closelog();
		return 0;
	}
	if ($nret < 1) {
		$error="No instance found for <$uid> with <$origServer>";
		printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" action=search uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$v);
		closelog();
		return 0;
	}

	my $entry = $mesg->entry ( 0 );
	$origMailHost = $entry->get_value( 'mailHost' );
	$origMailPostfixTransport = $entry->get_value( 'mailPostfixTransport' );
	printLog('LOG_INFO', "action=ldapsearch status=success uid=$uid origMailHost=$origMailHost origMailPostfixTransport=$origMailPostfixTransport",$v);
	$dn= $mesg->entry->dn();
	if ( ($entry->get_value( 'mailHost' ) eq $origServer ) && ($entry->get_value( 'mailPostfixTransport' ) eq 'lmtp:['.$origServer.']' ) ) {
            $mesg = $ldap->modify( $dn, replace => { 'mailHost' => $destServer } );
            if ($mesg->code) {
		$error=$mesg->error;
		$code=$mesg->code;
		printLog('LOG_ALERT',"action=ldapmod status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" origMailHost=$origMailHost mailHost=$destServer",$v);
		closelog();
		return 0;
	    }
            $mesg = $ldap->modify( $dn, replace => { 'mailPostfixTransport' => 'lmtp:['.$destServer.']' } );
            if ($mesg->code) {
		$error=$mesg->error;
		$code=$mesg->code;
		printLog('LOG_ALERT',"action=ldapmod status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" origMailPostfixTransport=$origMailPostfixTransport mailPostfixTransport=lmtp:[$destServer]",$v);
                closelog();
                return 0;
            }            
	    printLog('LOG_INFO',"action=ldapmod status=success uid=$uid server=$ldapServer port=$ldapPort origMailPostfixTransport=$origMailPostfixTransport mailPostfixTransport=lmtp:[$destServer] origMailHost=$origMailHost mailHost=$destServer",$v);
	}
	else {
		$error="mailHost is <".$entry->get_value( 'mailHost' )."> and should be <$origServer>; mailPostfixTransport is <".$entry->get_value( 'mailPostfixTransport' )."> and should be <lmtp:[$origServer]>";
		printLog('LOG_ALERT',"action=ldapmod status=fail error=\"$error\" uid=$uid code=$code origMailPostfixTransport=$origMailPostfixTransport mailPostfixTransport=$destServer origMailHost=$origMailHost mailHost=$destServer",$v);
		closelog();
		return 0;
	}

	$mesg = $ldap->unbind;   # take down session
	$ldap->disconnect ($ldapServer, port => $ldapPort);
	closelog();
	return 1;
}


sub prepareXferDomain {
	use Net::LDAP;
	use Sys::Syslog;
        my ($mainproc, $ldapServer,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$domain,$origServer,$destServer,$part,$v) = @_;
	openlog("$mainproc/prepXferDom", "pid", LOG_MAIL);
        if ( !($ldap=ldapconnect($mainproc, $ldapServer, $ldapPort, $v)) ) {
                closelog();
                return 255;
        }
        if ( ($mesg=ldapbind($mainproc, $ldap, $ldapServer, $ldapPort, $ldapBindUid, $ldapBindPwd, $v)) == 0 ) {
                closelog();
                return 255;
        }

        $mesg = $ldap->search( # perform a search
                base   => "o=$domain,".$ldapBase,
                filter => "(&(objectClass=mailRecipient)(mailHost=$origServer)(mailPostfixTransport=lmtp:[$origServer])(uid=*@$domain))",
                attrs  => ['uid']
        );
        if ($mesg->code) {
                $error=$mesg->error;
                $code=$mesg->code;
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$v);
                closelog();
                return 255;
        }
        $nret = $mesg->count;
	print "\n$nret mailboxes found!\n\n";
        printLog('LOG_INFO', "action=ldapsearch status=success domain=$domain origMailHost=$origServer mailHost=$destServer part=$part nMailbox=$nret",$v);
	open (FILE, ">xfer_$domain");
        for ( $i = 0 ; $i < $nret ; $i++ ) {
		my $entry = $mesg->entry ( $i );
		if ($part ne '') {print FILE $entry->get_value( 'uid' ).";$destServer;$part\n";}
		else {print FILE $entry->get_value( 'uid' ).";$destServer\n";}
	}
	close (FILE);
	printLog('LOG_INFO', "action=writefile status=success origMailHost=$origServer mailHost=$destServer part=$part detail=\"File xfer_$domain saved\"",$v);
        $mesg = $ldap->unbind;   # take down session
        $ldap->disconnect ($ldapServer, port => $ldapPort);
	closelog();
	return 0;
}


sub delRemovedUser {
        use Net::LDAP;
	use Cyrus::IMAP::Admin;
        use Sys::Syslog;
        my ($mainproc,$ldapServer,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$cyrus_user,$cyrus_pass,$sep,$v) = @_;

	openlog("$mainproc/delRemUser", "pid", LOG_MAIL);
	my $auth = {
	    -mechanism => 'login',
	    -service => 'imap',
	    -authz => $cyrus_user,
	    -user => $cyrus_user,
	    -minssf => 0,
	    -maxssf => 10000,
	    -password => $cyrus_pass,
	};

        if ( !($ldap=ldapconnect($mainproc, $ldapServer, $ldapPort, $v)) ) {
                closelog();
                return 0;
        }
        if ( ($mesg=ldapbind($mainproc, $ldap, $ldapServer, $ldapPort, $ldapBindUid, $ldapBindPwd, $v)) == 0 ) {
                closelog();
                return 0;
        }

        $mesg = $ldap->search( # perform a search
                base   => $ldapBase,
                filter => '(&(objectClass=mailRecipient)(mailUserStatus=removed))',
                attrs  => ['uid','mailHost']
        );
        if ($mesg->code) {
                $error=$mesg->error;
                $code=$mesg->code;
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$v);
                closelog();
                return 0;
        }

        $nret = $mesg->count;

        if ($nret < 1) {
                $error="No removable mailboxes found";
                printLog('LOG_ERR',"action=ldapsearch status=success detail=\"$error\" server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$v);
                closelog();
                return 1;
        }

	foreach $entry ( $mesg->entries ) {
		$cyrus_server = $entry->get_value( 'mailHost' );
		$uid = $entry->get_value( 'uid' );
		$dn= $entry->dn();
 
		print "Entry to remove: uid= <$uid>\tmailHost= <$cyrus_server>\n";

		## Remove from LDAP ##
                $mesg = $ldap->delete( $dn );
                if ($mesg->code) {
                	$error=$mesg->error;
                	$code=$mesg->code;
                	printLog('LOG_ALERT',"action=ldapdel status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" mailHost=$cyrus_server",$v);
                	closelog();
                	return 0;
            	}

		##print "Success - <$uid> removed from LDAP\n";
		printLog('LOG_INFO',,"action=ldapdel status=success uid=$uid server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" mailHost=$cyrus_server",$v);

		## Remove from Cyrus PopServer ##
  		my $cyrus = Cyrus::IMAP::Admin->new($cyrus_server);
  		$cyrus->authenticate(%$auth);
		if ($cyrus->{error}) {
			printLog('LOG_ALERT',"action=cyrusconnect status=fail error=\"$error\" server=$cyrus_server mailHost=$cyrus_server",$v);
			closelog();
                        return 0;
		}
		setACL($mainproc, $cyrus, $uid,'INBOX', $cyrus_user,'all', $sep, $v);
	        if (! deleteMailbox ( $mainproc,$cyrus,$uid, 'INBOX' ,$sep, $v ) ) {
			closelog();
			return 0;
		}
	}

	$mesg = $ldap->unbind;   # take down LDAP session
        $ldap->disconnect ($ldapServer, port => $ldapPort);
	closelog();
	return 1;
}



sub removeDelUser {

	use Sys::Syslog;
	use Date::Calc qw(Delta_Days Add_Delta_Days Today Date_to_Text_Long Decode_Language);
	use String::Scanf;

        my ($mainproc,$ldapServer,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$cyrus_user,$cyrus_pass,$gracedays,$sep,$v) = @_;

	my $return = 1;
        my $auth = {
            -mechanism => 'login',
            -service => 'imap',
            -authz => $cyrus_user,
            -user => $cyrus_user,
            -minssf => 0,
            -maxssf => 10000,
            -password => $cyrus_pass,
        };

	if ( $gracedays !~ /\d+/ ) {
		printLog('LOG_ERR',"action=cyrpurge status=fail error=\"grace specified in configuration is not a number!\"");
		closelog();
		return 0;
	}
	if ($ldapBase eq '')  {
		printLog('LOG_ERR',"action=ldapsearch status=fail error=\"no BASEDN defined in conf.\" server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$v);
		closelog();
		return 0;
	}


	@now = Today(1);
	@pday = Add_Delta_Days(@now,-$gracedays);
	openlog("$mainproc/msuserpurge", "pid", LOG_MAIL);
	#syslog('LOG_WARNING',"Grace period is $gracedays days.");
	#syslog('LOG_WARNING',"LDAP Search Base set to: $ldapBase");
	print "\nGrace period: $gracedays\n";
	print "Purge users deleted since: ". Date_to_Text_Long(@pday,Decode_Language("US")).".\n";
	print "============================================================================\n";
	print "LDAP Search Base: $ldapBase\n\n";

        if ( !($ldap=ldapconnect($mainproc, $ldapServer, $ldapPort, $v)) ) {
                closelog();
                return 0;
        }
        if ( ($mesg=ldapbind($mainproc, $ldap, $ldapServer, $ldapPort, $ldapBindUid, $ldapBindPwd, $v)) == 0 ) {
                closelog();
                return 0;
        }

        $mesg = $ldap->search( # perform a search
                base   => $ldapBase,
                filter => '(&(objectClass=mailRecipient)(mailUserStatus=deleted))',
                attrs  => ['uid','mailHost','modifyTimestamp']
        );
        if ($mesg->code) {
                $error=$mesg->error;
                $code=$mesg->code;
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",0);
        }
        $nret = $mesg->count;

        if ($nret < 1) {
		$error='REGULAR EXIT - No removable mailboxes found';
                printLog('LOG_INFO',"action=ldapsearch status=success detail=\"$error\" server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",0);
                closelog();
                return 1;
        }
	else {
		$error="$nret deleted mailboxes found";
		printLog('LOG_INFO',"action=ldapsearch status=success detail=\"$error\" server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" nmailbox=$nret",0);
		print "$nret deleted mailboxes found.\n\n";
	}

	print "\n------------------------------------------------------------------------------------------------------------------------------";
	print "\nUID\t\t\t\tMAILHOST\t\tModify Date\t\t\t\tAction\t\t\tStatus\n";
	print "------------------------------------------------- ----------------------------------------- ------------------------ ---------\n";
	foreach $entry ( $mesg->entries ) {
                $cyrus_server = $entry->get_value( 'mailHost' );
                $uid = $entry->get_value( 'uid' );
                $dn= $entry->dn();
		$lastmod = $entry->get_value( 'modifyTimestamp' );
		@datemod = sscanf('%4s%2s%2s%2s%2s%2sZ', $lastmod);
		$mod = $gracedays - Delta_Days($datemod[0],$datemod[1],$datemod[2], @now);
        	if ($mod > 0) { 
				printLog('LOG_INFO',"action=cyrpurge status=notice uid=$uid mailHost=$cyrus_server lastMod=\"".Date_to_Text_Long($datemod[0],$datemod[1],$datemod[2],Decode_Language("US")).", $datemod[3]h$datemod[4]'UTC\" detail=\"Pending for $mod days\"", 0);
				print "\n$uid\t$cyrus_server\t".Date_to_Text_Long($datemod[0],$datemod[1],$datemod[2],Decode_Language("US")).", $datemod[3]h$datemod[4]'UTC\tPending for $mod days\tpending..."; next;
		}

                print "\n$uid\t$cyrus_server\t".Date_to_Text_Long($datemod[0],$datemod[1],$datemod[2],Decode_Language("US")).", $datemod[3]h$datemod[4]'UTC\tTO BE REMOVED NOW";
		printLog('LOG_WARNING',"action=cyrpurge status=notice uid=$uid mailHost=$cyrus_server lastMod=\"".Date_to_Text_Long($datemod[0],$datemod[1],$datemod[2],Decode_Language("US")).", $datemod[3]h$datemod[4]'UTC\" detail=\"TO BE REMOVED NOW\"",0);
		
		$status = "success";
                ## Removed into mailUserStatus ##
                $mesg = $ldap->modify( $dn,
    			replace => {
      				mailUserStatus => 'removed'
			}
  		);
                if ($mesg->code) {
                        $error=$mesg->error;
                        $code=$mesg->code;
                        printLog('LOG_ALERT',"action=ldapmod status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" mailHost=$cyrus_server",0);
                        $status='fail';
                }

		$error="<$uid> set as REMOVED over LDAP";
		syslog('LOG_WARNING',"action=ldapmod status=success detail=\"$error\" uid=$uid server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" mailHost=$cyrus_server",0);

                ## Remove from Cyrus PopServer ##
                my $cyrus = Cyrus::IMAP::Admin->new($cyrus_server);
                $cyrus->authenticate(%$auth);
                if ($cyrus->{error}) {
			$status='fail';
			$error=$cyrus->{error};
                        printLog('LOG_ALERT',"action=cyrusconnect status=$status error=\"$error\" server=$cyrus_server mailHost=$cyrus_server",0);
                }
		else {
                	if (!(setACL($mainproc, $cyrus, $uid,'INBOX', $cyrus_user,'all',$sep,0))) { $status = "fail"; }
			printLog('LOG_INFO',"action=cyrusdel status=notice server=$cyrus_server mailHost=$cyrus_server detail=\"Removing mailbox $uid from store\" ",0);
                	if (!( deleteMailbox ( $mainproc,$cyrus,$uid,'INBOX',$sep,0 ) )) { $status = "fail"; };
		}

		print "\t$status";
		if ($status eq 'fail') {
			$return = 0;
		}
        }

	print "\n------------------------------------------------------------------------------------------------------------------------------";
	print "\n\n Done! See your log for more details...\n\n";
        $mesg = $ldap->unbind;   # take down LDAP session
        $ldap->disconnect ($ldapServer, port => $ldapPort);
	closelog();
	return $return;
}


sub ldapModAttr {
###
# Use an hash ref in the form
# {
#	attr 	  => 'value',
#	attrmulti => [ 'value1', 'value2']
# }
###
        use Net::LDAP;

        my ($mainproc,$ldapServer,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$uid,$attr,$OP,$debug) = @_;
	openlog("$mainproc/ldapModAttr",'pid','LOG_MAIL');
        if ( !($ldap=ldapconnect($mainproc, $ldapServer, $ldapPort, $debug)) ) {
                closelog();
                return 0;
        }
        if ( ($mesg=ldapbind($mainproc, $ldap, $ldapServer, $ldapPort, $ldapBindUid, $ldapBindPwd, $debug)) == 0 ) {
                closelog();
                return 0;
        }

        $mesg = $ldap->search( # perform a search
                base   => $ldapBase,
                filter => "(&(objectClass=mailRecipient)(uid=$uid))",
                attrs  => [ keys %$attr ]
        );
        if ($mesg->code) {
                $error=$mesg->error;
                $code=$mesg->code;
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$debug);
                closelog();
                return 0;
        }

        $nret = $mesg->count;
        if ($nret > 1) {
                $error="Multiple instance found for <$uid> with <$origServer>";
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$debug);
                closelog();
                return 0;
        }
        if ($nret < 1) {
                $error="No instance found for <$uid> with <$origServer>";
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$debug);
                closelog();
                return 0;
        }
        my $entry = $mesg->entry ( 0 );
	$dn= $mesg->entry->dn();
       	$mesg = $ldap->modify( $dn, $OP => $attr );
        if ($mesg->code) {
                $error=$mesg->error;
                $code=$mesg->code;
                printLog('LOG_ALERT',"action=ldapmod status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" attr=$OP value=\"". $OP => $attr .'"',$debug);
                closelog();
                return 0;
        }
	printLog('LOG_INFO',"action=ldapmod status=success uid=$uid server=$ldapServer port=$ldapPort attr=$OP value=\"". $OP => $attr .'"',$debug);
        $mesg = $ldap->unbind;   # take down session
        $ldap->disconnect ($ldapServer, port => $ldapPort);
        closelog();
	return 1;
}


sub prepareIMAPXferDomain {

        use Net::LDAP;
        my ($mainproc,$ldapServer,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$domain,$conc,$origServer,$quota,$smtpFW,$v) = @_;
	openlog("$mainproc/prepIMAPxfer",'pid','LOG_MAIL');
        if ( !($ldap=ldapconnect($mailproc, $ldapServer, $ldapPort, $v)) ) {
                closelog();
                return 0;
        }
        if ( ($mesg=ldapbind($mailproc, $ldap, $ldapServer, $ldapPort, $ldapBindUid, $ldapBindPwd, $v)) == 0 ) {
                closelog();
                return 0;
        }

        $mesg = $ldap->search( # perform a search
                base   => "o=$domain,".$ldapBase,
                filter => "(&(objectClass=mailRecipient)(mailHost=$origServer)(uid=*))",
                attrs  => ['uid','mail']
        );
        if ($mesg->code) {
                $error=$mesg->error;
                $code=$mesg->code;
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" detail=\"ERROR looking for mailbox of $domain\"",$v);
                closelog();
                return 0;
	}

        $nret = $mesg->count;
        if ($nret < 1) {
                $error="No mailboxes found for <$domain>";
                printLog('LOG_ERR',"action=ldapsearch status=success detail=\"$error\" server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$v);
                closelog();
                return 0;
        }

        $error="$nret mailboxes found";
        printLog('LOG_INFO',"action=ldapsearch status=success detail=\"$error\" server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" nmailbox=$nret",$v);
        open (FILE, ">IMAPxfer_$domain");
        for ( $i = 0 ; $i < $nret ; $i++ ) {
                my $entry = $mesg->entry ( $i );
		$uid = $entry->get_value( 'uid' );
                if ($conc) { print FILE "$uid\@$domain,$uid\@$domain,$quota,".'@'."$smtpFW:".$entry->get_value( 'mail' )."\n"; }
		else       { print FILE "$uid,$uid,$quota,".'@'."$smtpFW:".$entry->get_value( 'mail' )."\n"; }
        }
        close (FILE);
	printLog('LOG_INFO',"action=writefile status=success detail=\"File <IMAPxfer_$domain> successfully saved\"", $v);
        $mesg = $ldap->unbind;   # take down session
        $ldap->disconnect ($ldapServer, port => $ldapPort);
        closelog();
	return 1;
}

# by Paolo Cravero 20131009
# si richiama con questi parametri:
# ($ldapServer,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$uid)

sub ldapCheckUserExists {

	use Net::LDAP;
	use Sys::Syslog;

	my ($mainproc,$ldapServer,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$uid,$v) = @_;
	openlog("$mainproc/ldapCheckUser", "pid", LOG_MAIL);
        if ( !($ldap=ldapconnect($mainproc, $ldapServer, $ldapPort, $v)) ) {
                closelog();
                return 0;
        }
        if ( ($mesg=ldapbind($mainproc, $ldap, $ldapServer, $ldapPort, $ldapBindUid, $ldapBindPwd, $v)) == 0 ) {
                closelog();
                return 0;
        }

	$mesg = $ldap->search( # perform a search
        	base   => $ldapBase,
        	filter => "(&(objectClass=mailRecipient)(uid=$uid))",
        	attrs  => ['mailHost', 'mailPostfixTransport', 'uid']
        );
	$code = $code=$mesg->code;
        if ($code) {
                $error=$mesg->error;
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" detail=\"ERROR looking for <$uid>\"",$v);
                closelog();
                return 0;
	}

	$nret = $mesg->count;
        if ($nret > 1) {
                $error="Multiple instance found for <$uid>";
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$v);
                closelog();
                return 0;
        }
        if ($nret < 1) {
                $error="No instance found for <$uid>";
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$v);
                closelog();
                return 0;
        }

	my $entry = $mesg->entry ( 0 );

	printLog('LOG_DEBUG',"action=ldapsearch status=success uid=$uid mailHost=".$entry->get_value('mailHost'),$v);
	$mesg = $ldap->unbind;   # take down session
	$ldap->disconnect ($ldapServer, port => $ldapPort);
	closelog();
	return 1;
}
