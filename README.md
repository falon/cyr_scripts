![travis](https://travis-ci.org/falon/cyr_scripts.svg?branch=master)
# cyr_scripts

With these utilities you can manage Cyrus-IMAPD from command line with many classic command (create, del, set quota on accounts).
But there also other new facilities developed for my environment, such as:

- Cyrus Partition Manager. Do you are not satisfied how Cyrus deal with partitions on multidomain server?
With this tool you can define many partitions for each domain, and balance accounts over their own set of partitions only.

- Cyrus Restore Tool
Unexpunge and undeleted folders from one place. Deprecated. I suggest the new [PHP-Cyrus-Restore](https://falon.github.io/PHP-Cyrus-Restore/), a graphic interface to manage dalayed deleted items.

- cyr_showuser.pl
A list of mailboxes per domain, with quota report, partitions and Last update timestamp.

These tool are very customized to work with my environment. Each account is LDAP profiled with attribute mailHost (imapserver).
This poor documentation will be updated soon...
