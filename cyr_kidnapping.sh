#!/bin/bash
# Author: MFF
# Name: cyr_kidnapping.sh
# Description: copy all file from a mbpath to a destination folder.
#

echo -en "\n\n Welcome to Cyr Kidnapping\n"
echo -en "To use this tool you must run locally to a Cyrus IMAP server.\n"
echo -en "\nInsert the existing full path where to copy :-> "
read -r folder
if [ -z "${folder}" ] ; then
	echo -en "\e[31mType the full path, please!\e[39m\n\n"
	exit 1;
fi
echo -en "Ok. You have typed <$folder>."
echo -en "\nCheck if \e[33m$folder\e[39m exists..."
if [ -d "$folder" ]
then
	echo -en " \e[33mOK\e[39m\n"
else
	echo -en "\e[31m doesn't exist!\e[39m\n\n"
	exit 1;
fi

mbpath=`which mbpath`
if [ ! -x "$mbpath" ]; then
                echo -en "\e[31mI can't find mbpath command, or is not executable. Exiting\e[39m\n\n"
                exit 1;
        fi
 

echo -en "Insert the username to copy, please :-> "
read -r user
if [ -z "${user}" ] ; then
        echo -en "\e[31mType the username, please!\e[39m\n\n"
        exit 1;
fi
echo -en "Ok. You have typed <$user>. His path is:\n"
cyrpath=`$mbpath "user/$user"`
        if [ -z $cyrpath ]; then
                echo -en "\e[31mI can't retrieve the path. Exiting\e[39m\n\n"
                exit 1;
        fi
echo $cyrpath
echo  
echo "*** Copying <$user>... ***"
echo
cp -apr $cyrpath $folder
result=$?
        if [ "${result}" -ne "0" ] ; then
                echo -en "\e[31mError in copy. Please check source and destination!!\e[39m\n\n"
                exit 1;
        fi

echo "This is the destination folder now: "
cd $folder
ls -ltr
echo -en "\n\t\e[33m...DONE!\e[39m\n\n"
exit 0
