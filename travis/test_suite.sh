#!/bin/bash

function travis_test {
    local ARGUMENTS=
    echo -en "=======\n\n\e[96m$@\e[0m\n\n" >> travis/test.log
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
    echo $ARGUMENTS | xargs $PROG >> travis/test.log 2>&1
    local status=$?
    if [ $status -ne 0 ]; then
        printf "%-40s\t[\e[31m %s \e[0m]\n" "$PROGNAME" FAIL 
	echo -e "\e[31mExit Status: $status\e[0m" >> travis/test.log
    else
        printf "%-40s\t[\e[32m %s \e[0m]\n" "$PROGNAME" OK
	echo -e "\e[32mExit Status: $status\e[0m" >> travis/test.log
    fi
    return $status
}

> travis/test.log
status=0
while read  test || [ -n "$test" ]; do
	travis_test $test
	status=$(($status + $?))
done < travis/TESTLIST

printf "%-40s\t[\e[93m %s \e[0m]\n" "./cyr_restorefolder.pl" SKIP
printf "%-40s\t[\e[93m %s \e[0m]\n" "./cyr_xfer" SKIP
exit $status
