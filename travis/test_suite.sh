#!/bin/bash

function travis_test {
    local ARGUMENTS=
    echo -en "=======\n\n\e[96m$@\e[0m\n\n" >> $LDIR/test.log
    if [ "$1" = "sudo" ]; then
	PROGNAME="$4 $5"
	PROG="$1 $2 $3 $4"
	for (( i=5; i <= "$#"; i++ )); do
		ARGUMENTS="$ARGUMENTS ${!i}"
	done
    else
	PROGNAME="$1 $2"
	PROG=$1
	for (( i=2; i <= "$#"; i++ )); do
                ARGUMENTS="$ARGUMENTS ${!i}"
        done
    fi 
    echo $ARGUMENTS | xargs $PROG >> $LDIR/test.log 2>&1
    local status=$?
    if [ $status -ne 0 ]; then
        printf "%-40s\t[\e[31m %s \e[0m]\n" "$PROGNAME" FAIL 
	echo -e "\e[31mExit Status: $status\e[0m" >> $LDIR/test.log
    else
        printf "%-40s\t[\e[32m %s \e[0m]\n" "$PROGNAME" OK
	echo -e "\e[32mExit Status: $status\e[0m" >> $LDIR/test.log
    fi
    return $status
}

${OS_TYPE}=$1

LDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
> $LDIR/test.log
status=0
while read  test || [ -n "$test" ]; do
	travis_test $test
	status=$(($status + $?))
done < $LDIR/TESTLIST

if [ "${OS_TYPE}" = "centos" ]; then
	# Verify preun/postun in the spec file
	travis_test yum remove -y 'cyrus-imapd-scripts'
	status=$(($status + $?))
fi

printf "%-40s\t[\e[93m %s \e[0m]\n" "./cyr_restorefolder.pl" SKIP
printf "%-40s\t[\e[93m %s \e[0m]\n" "./cyr_xfer" SKIP
exit $status
