#!/usr/bin/perl -w
#
# All this code written by Marco Fav, so you must use better code. You are advised!

#### Widely conf option ####
our $build = '0.1.2 - 22 Feb 2019';
our $sep = '/';
our $cyrus_server = "localhost";
our $cyrus_user = "cyrusadmin";
our $cyrus_pass = "cyrusadmin";
############################



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

	my ($mainproc, $auth, $Server, $v) = @_;	

	use Sys::Syslog;
	openlog("$mainproc/cyrusconn",'pid','LOG_MAIL');
	my $cyrus = Cyrus::IMAP::Admin->new($Server);
        if (! $cyrus->authenticate(%$auth) ) {
        	printLog('LOG_ALERT',"action=cyrusconnect status=fail error=\"Errors happen during authentication\" server=$Server mailHost=$Server",$v);
                $cyrus = 0;
	}
	else {
		printLog('LOG_DEBUG',"action=cyrusconnect status=success server=$Server mailHost=$Server",$v);
	}
	closelog();
	return $cyrus;
}

sub createMailbox {

  use Sys::Syslog;
  use Unicode::IMAPUtf7;
  use Encode;
  my ($mainproc, $cyrus, $user, $subfolder, $partition, $sep, $v) = @_;

  my $code = 'ISO-8859-1';
  my $imaputf7 = Unicode::IMAPUtf7->new();
  my $mailbox=composembx($user,$subfolder,$sep,'user');
  $cyrus->create($mailbox,$partition);
  openlog("$mainproc/addMbox", "pid", LOG_MAIL);
  $folder = decodefoldername($subfolder, $imaputf7, $code);
  if ($cyrus->error) {
    printLog('LOG_WARNING',"action=addmailbox mailbox=\"". $user."\" folder=\"$folder\" partition=\"$partition\" error=\"". $cyrus->error .'" status=fail', $v);
  } else {
    if (!defined($partition)) {$partition='root partition of mailbox or autoselected by Cyrus';}
    printLog('LOG_WARNING',"action=addmailbox status=success mailbox=\"$user\" folder=\"$folder\" partition=\"$partition\"", $v);
  }
  closelog();

}

sub deleteMailbox {

  use Sys::Syslog;
  use Unicode::IMAPUtf7;
  use Encode;
  my $code = 'ISO-8859-1';
  my $imaputf7 = Unicode::IMAPUtf7->new();
  my ($mainproc, $cyrus, $user, $subfolder, $sep, $v) = @_;
  my $mailbox=composembx($user,$subfolder,$sep,'user');
  openlog("$mainproc/delMbox", "pid", LOG_MAIL);
    $cyrus->delete('user'. $sep . $user);
  $folder = decodefoldername($subfolder, $imaputf7, $code);
  if ($cyrus->error) {
    printLog('LOG_WARNING',"action=delmailbox status=fail mailbox=\"$user\" folder=\"$folder\" error=\"".$cyrus->error.'"', $v);
    return 0;
  } else {
    printLog('LOG_WARNING',"action=delmailbox status=success mailbox=\"$user\" folder=\"$folder\"", $v);
    return 1;
  }
  closelog();
}


sub renameMailbox {

  use Sys::Syslog;
  my ($mainproc, $cyrus, $user_old, $folder_old, $user_new, $folder_new, $partition, $sep, $v) = @_;
  use Unicode::IMAPUtf7;
  use Encode;
  my $code = 'ISO-8859-1';
  my $imaputf7 = Unicode::IMAPUtf7->new();
  openlog("$mainproc/renMbox", "pid", LOG_MAIL);

  if ($partition eq '') { $partition = NULL; }

  $mailbox_old = composembx($user_old, $folder_old, $sep, 'user');
  $mailbox_new = composembx($user_new, $folder_new, $sep, 'user');

  if ($partition ne NULL) { $cyrus->rename($mailbox_old, $mailbox_new, $partition); }
  else { $cyrus->rename($mailbox_old, $mailbox_new); }

  $folder_old = decodefoldername($folder_old, $imaputf7, $code);
  $folder_new = decodefoldername($folder_new, $imaputf7, $code);
  if ($cyrus->error) {
    printLog('LOG_WARNING',"action=renmailbox status=fail mailbox=\"$user_old\" folder=\"$folder_old\" newmailbox=\"$user_new\" newfolder=\"$folder_new\" partition=$partition error=\"" . $cyrus->error . '"', $v);
  } else {
	if ($partition eq NULL) {
		printLog('LOG_WARNING',"action=renmailbox status=success mailbox=\"$user_old\" folder=\"$folder_old\" newmailbox=\"$user_new\" newfolder=\"$folder_new\"", $v);
	}
	else {
		printLog('LOG_WARNING',"action=renmailbox status=success mailbox=\"$user_old\" folder=\"$folder_old\" newmailbox=\"$user_new\" newfolder=\"$folder_new\" partition=$partition", $v);
	}
  }
  closelog();
}


sub transferMailbox {

  use Sys::Syslog;
  my ($mainproc, $cyrus, $user, $destServer, $partition, $sep, $v) = @_;
  openlog("$mainproc/xferMbox", "pid", LOG_MAIL);
  if ($partition eq '') { $partition = NULL; }

  $mailbox = "user". $sep . $user;

  if ($partition ne NULL) { $cyrus->xfermailbox($mailbox, $destServer, $partition); }
  else { $cyrus->xfermailbox($mailbox, $destServer); }

  if ($cyrus->error) {
    syslog('LOG_WARNING',"action=cyrxfer status=fail mailbox=\"$user\" error=\"". $cyrus->error . '"', $v);
    closelog();
    return 0;
  } else {
        if ($partition eq NULL) {
                printLog('LOG_WARNING',"action=cyrxfer status=success mailbox=\"$user\" mailHost=$destServer", $v);
        }
        else {
		printLog('LOG_WARNING',"action=cyrxfer status=success mailbox=\"$user\" mailHost=$destServer partition=$partition", $v);
        }
  }
  closelog();
  return 1;
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



sub setAnnotationMailbox {

  my ($mainproc, $cyrus, $user, $subfolder, $attr, $value, $sep, $v) = @_;
  use Sys::Syslog;
  use Unicode::IMAPUtf7;
  use Encode;
  my $folder;
  my $code = 'ISO-8859-1';
  my $imaputf7 = Unicode::IMAPUtf7->new();
  openlog("$mainproc/setAnMbox", "pid", LOG_MAIL);

  $mailbox=composembx($user,$subfolder,$sep,'user');
  $folder = decodefoldername($subfolder, $imaputf7, $code);
  $cyrus->mboxconfig($mailbox,$attr,$value);
  if ($cyrus->error) {
	$status='fail';
	$error=$cyrus->error;
	$sev='LOG_ERR';
	$return=0;
  }
  else {
	$status='success';
	$sev='LOG_WARNING';
	$return=1;
	$error='';
  } 
  printLog($sev,"action=setimapmetadata status=$status mailbox=\"$user\" folder=\"$folder\" meta_name=\"$attr\" meta_value=\"$value\" error=\"$error\"", $v);
  closelog();
  return($return);
}



sub setAnnotationServer {

  my ($mainproc, $imap, $path, $anno, $valuetype, $value, $v) = @_;
  openlog("$mainproc/setAnServer", "pid", LOG_MAIL);

  $return=1;
  $error='';
  $detail=$error;
  $sev='LOG_INFO';
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
	$detail='value changed';
  }

  printLog($sev, "action=setimapmetadata status=$status error=\"$error\" detail=\"$detail\" meta_name=\"$anno\" meta_oldvalue=\"$oldvalue\" meta_value=\"$value\" path=\"$path\"", $v);
  closelog();
  return $return;
}



sub setQuota {

  use Sys::Syslog;
  use Unicode::IMAPUtf7;
  use Encode;
  my ($mainproc, $cyrus, $user, $subfolder, $quota_size, $sep, $v) = @_;
  my $code = 'ISO-8859-1';
  my $imaputf7 = Unicode::IMAPUtf7->new();
  openlog("$mainproc/setQuota", "pid", LOG_MAIL);

  $mailbox=composembx($user,$subfolder,$sep,'user');
  $folder = decodefoldername($subfolder, $imaputf7, $code);
  if ($quota_size ne 'none') {
	  # quota provided in MB, but cyradm want KB:
	  $quota_size = $quota_size * 1024;
  }
  my @before=$cyrus->listquotaroot($mailbox);
  if ($cyrus->error) {
        $sev='LOG_ERR';
        $error=$cyrus->error;
        $status='fail';
        $return=0;
	printLog($sev, "action=setimapquota status=$status error=\"$error\" mailbox=\"$user\" folder=\"$folder\" detail=\"Error reading the old quota value\"", $v);
  }
  if (!$before[2][1]) {
	$before[2][1] = 0;
	$before[2][0] = 0;
  }

  #use Data::Dump qw(dump);
  #dump(@before);
  $cyrus->setquota($mailbox,"STORAGE",$quota_size);
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
	$error=$cyrus->error;
	$return=0;
  }
  else {
	$status='success';
	$sev='LOG_WARNING';
	$error='';
	$return=1;
  }
  $folder = decodefoldername($subfolder, $imaputf7, $code);
  printLog($sev,"action=setimapacl status=$status error=\"$error\" mailbox=\"$user\" folder=\"$folder\" uid=$who right=$right", $v);
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
                return 0;
        }
        if ( ($mesg=ldapbind($mainproc, $ldap, $ldapServer, $ldapPort, $ldapBindUid, $ldapBindPwd, $v)) == 0 ) {
                closelog();
                return 0;
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
                return 0;
        }


        $nret = $mesg->count;
	print "$nret mailboxes found!\n";
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
	return 1;
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
                return 0;
        }

	foreach $entry ( $mesg->entry ) {
		$cyrus_server = $entry->get_value( 'mailHost' );
		$uid = $entry->get_value( 'uid' );
		$dn= $entry->dn();
 
        	print "LDAP entry to remove: uid= <$uid>\tmailHost= <$cyrus_server>\n";

		## Remove from LDAP ##
                $mesg = $ldap->delete( $dn );
                if ($mesg->code) {
                	$error=$mesg->error;
                	$code=$mesg->code;
                	printLog('LOG_ALERT',"action=ldapdel status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\" mailHost=$cyrus_server",$v);
                	closelog();
                	return 0;
            	}

                print "Success - <$uid> removed from LDAP\n";
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
	        deleteMailbox ( $mainproc,$cyrus,$uid, 'INBOX' ,$sep, $v );
	}

	$mesg = $ldap->unbind;   # take down LDAP session
        $ldap->disconnect ($ldapServer, port => $ldapPort);
	closelog();
}



sub removeDelUser {

	use Sys::Syslog;
	use Date::Calc qw(Delta_Days Add_Delta_Days Today Date_to_Text_Long Decode_Language);
	use String::Scanf;

        my ($mainproc,$ldapServer,$ldapPort,$ldapBase,$ldapBindUid,$ldapBindPwd,$cyrus_server,$cyrus_user,$cyrus_pass,$gracedays,$sep,$v) = @_;

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
                printLog('LOG_ERR',"action=ldapsearch status=fail error=\"$error\" uid=$uid code=$code server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",$v);
                closelog();
                return 0;
        }
        $nret = $mesg->count;

        if ($nret < 1) {
		$error='REGULAR EXIT - No removable mailboxes found';
                printLog('LOG_INFO',"action=ldapsearch status=success detail=\"$error\" server=$ldapServer port=$ldapPort bind=\"$ldapBindUid\"",0);
                closelog();
                return 0;
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
		if ($status=='fail') {
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
