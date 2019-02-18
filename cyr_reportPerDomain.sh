#!/bin/bash

# by Paolo Cravero - 20160223
#
# This script creates a report of Cyrus usage per-virtual_domain.
# One report per file. Each file name is timestamped.
# Each file can be emailed for further human processing

# initialize today's date
todayValue=$(date +"%Y-%m-%d")

# load list of domains
domains=($(grep 'vendor/CSI/partition' /etc/annoIMAP.conf | cut -d"," -f 1 | cut -d"/" -f 5))

for i in "${domains[@]}"
do
   cyr_showuser.pl -d $i > /tmp/$todayValue-$i.txt
done

