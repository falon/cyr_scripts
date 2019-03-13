#!/bin/bash
VER=`rpm -qa | grep cyrus-imapd-utils`
RE='^cyrus-imapd-utils-([[:digit:]])\.'

if [[ $VER =~ $RE ]]
then
	VERSION=${BASH_REMATCH[1]}
fi

if [ $VERSION -gt 1 ]
then
	cp -p cyr_showuser.pl-v$VERSION cyr_showuser.pl
fi
