#!/bin/bash
LPATH=/usr/local/cyr_scripts
VER=`rpm -qa | grep cyrus-imapd-utils`
RE='^cyrus-imapd-utils-([[:digit:]])\.'

if [[ $VER =~ $RE ]]
then
	VERSION=${BASH_REMATCH[1]}
fi

if [ $VERSION -gt 1 ]
then
	cp -p $LPATH/cyr_showuser.pl-v$VERSION $LPATH/cyr_showuser.pl
fi