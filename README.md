![travis](https://travis-ci.org/falon/cyr_scripts.svg?branch=master)
# cyr_scripts

With these utilities you can manage Cyrus IMAP from command line with many classic command (create, del, set quota on accounts).
But there also other new facilities developed for my environment, such as:

- Cyrus Partition Manager. Do you are not satisfied how Cyrus deal with partitions on multidomain server?
With this tool you can define many partitions for each domain, and balance accounts over their own set of partitions only.

- Cyrus Restore Tool
Unexpunge and undeleted folders from one place. Deprecated. I suggest the new [PHP-Cyrus-Restore](https://falon.github.io/PHP-Cyrus-Restore/), a graphic interface to manage dalayed deleted items.

- cyr_showuser.pl
A list of mailboxes per domain, with quota report, partitions and Last update timestamp.
This program has compatibility problems reading metadata if runs with Cyrus::IMAP::Admin for Cyrus 3.0.x.
The version of the Perl package is always 1.0.0, it's very difficult to implemente solutions version dependent.
Anyway, this program is deprecated. I suggest [LDAP-IMAPExplorer](https://github.com/falon/LDAP-IMAPExplorer) to view the accounts.

These tool are very customized to work with my environment. Each account is LDAP profiled with these attributes:

```
dn: uid=myname@example.com,o=example.com,`your baseDN in cyr_scripts.ini`
mailUserStatus: active
mailDeliveryOption: mailbox
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: mailRecipient
objectClass: inetMailUser
mailHost: imap.example.com
sn: surname
cn: my complete name
givenName: first name
uid: myname@example.com
mail: myname@example.com
mailAlternateAddress: mysecondemail@example.com
```

The annoIMAP.conf is

```
/vendor/csi/partition/example.com,server,string,backend,value.priv,lrswipkxtea
```

and the imapd.conf contains at least:
```
## Partitions
partition-example1: /maildata/example.com/maildata1
partition-example2: /maildata/example.com/maildata2
# If you want a new quotaroot for archive folder uncomment these two lines:
#partition-arcexample1:  /archivio/example.com/maildata1
#partition-arcexample2: /archivio/example.com/maildata2

## Metapartitions
metapartition-example1: /metamaildata/example.com/maildata1
metapartition-example2: /metamaildata/example.com/maildata2
#metapartition-arcexample1:  /metarchivio/example.com/maildata1
#metapartition-arcexample2: /metarchivio/example.com/maildata2

# Cyrus IMAP Archive Partitions
archivepartition-example1: /sysarchivio/example.com/maildata1
archivepartition-example2: /sysarchivio/example.com/maildata2

virtdomains: userid

annotation_definitions: /etc/annoIMAP.conf

# Archiving
archive_enabled: 1
archive_after: 30
archive_maxsize: 2048
archive_keepflagged: 1

# Moving
allowusermoves: 1

altnamespace: 0
unixhierarchysep: 1

admins: cyrusadmin
```

saslauthd.conf of Cyrus IMAP host is
```
ldap_servers: ldap://ldap.example.com:389
ldap_version:     3
ldap_timeout:     10
ldap_time_limit:  10
ldap_search_base: <baseDN in cyr_scripts.ini>
ldap_bind_dn:     uid=sasluser,o=admin.invalid,ou=People,<baseDN>
ldap_password:    sasluser
ldap_scope:       sub
ldap_filter_mode: yes
ldap_filter:      (&(uid=%u)(objectClass=mailRecipient)(|(mailUserStatus=active)(mailUserStatus=MBOXactive)))
ldap_restart:     yes
```

Using Postfix, a good config can at least provides:
```
mydestination = ldap:/etc/postfix/ldap-localdomain.cf
local_recipient_maps = ldap:/etc/postfix/ldap-localrecipient.cf
virtual_alias_maps = ldap:/etc/postfix/ldap-aliases.cf
smtpd_client_restrictions =
                permit_mynetworks,
                permit_sasl_authenticated,
                reject

smtpd_relay_restrictions =
                permit_mynetworks,
                permit_sasl_authenticated,
                reject_unauth_destination

smtpd_sender_restrictions =
                reject_non_fqdn_sender,
                reject_unknown_sender_domain,
                reject_unlisted_sender

smtpd_recipient_restrictions =
                reject_non_fqdn_recipient,
                reject_unknown_recipient_domain,
                reject_unlisted_recipient,
                permit

smtpd_sasl_auth_enable = yes
smtpd_tls_auth_only = yes
smtp_tls_security_level = may
```

The saslauthd.conf Postfix host is
```
ldap_servers: ldap://ldap.example.com:389
ldap_version:     3
ldap_timeout:     10
ldap_time_limit:  10
ldap_search_base: <base DN in cyr_scripts.ini>
ldap_bind_dn:     uid=sasluser,o=admin.invalid,<base DN>
ldap_password:    sasluser
ldap_scope:       sub
ldap_uidattr:     uid
ldap_filter_mode: yes
ldap_filter:      (&(uid=%u)(objectClass=mailRecipient)(mailUserStatus=active))
ldap_restart:     yes
```

/etc/postfix/ldap-localdomain.cf:
```
server_host =   ldap.example.com:389
                ldap2.example.com:389
timeout = 15
search_base = <base DN in your cyr_scripts_ini>
scope = one
bind_dn = uid=postfixuser,o=admin.invalid,<base DN>
bind_pw = password
query_filter = (&(objectclass=domainrelatedobject)(associateddomain=%s))
result_format  =  %s
result_attribute = associateddomain
```

/etc/postfix/ldap-localrecipient:
```
server_host =   ldap.example.com:389
                ldap2.example.com:389
timeout = 15
search_base = <base DN in your cyr_scripts_ini>
scope = one
bind_dn = uid=postfixuser,o=admin.invalid,<base DN>
bind_pw = password
query_filter = (&(|(mail=%s)(mailalternateaddress=%s))(|(mailuserstatus=active)(mailuserstatus=MBOXactive))(|(objectclass=mailrecipient)(objectclass=mailgroup)))
result_format  =  %s
result_attribute = mail
```

/etc/postfix/ldap-aliases.cf:
```
server_host =   ldap.example.com:389
                ldap2.example.com:389
timeout = 15
search_base = <base DN in your cyr_scripts_ini>
scope = one
bind_dn = uid=postfixuser,o=admin.invalid,<base DN>
bind_pw = password
query_filter = (&(!(|(mail=.*)(mailalternateaddress=.*)))(|(mail=%s)(mailalternateaddress=%s))(|(objectclass=mailgroup)(&(objectclass=mailrecipient)(mailDeliveryOption=mailbox)(mailuserstatus=active))))
result_attribute = mgrpRFC822mailmember
special_result_attribute = uniquemember,memberURL
terminal_result_attribute = uid,mailForwardingAddress
result_format = %s
```

You could need to extend your LDAP schema with this *97csi-inetmailuser.ldif* file:

```
dn: cn=schema

attributeTypes: ( 2.16.840.1.113730.3.1.778
  NAME ( 'mailUserStatus' )
  DESC 'user defined attribute'
  SYNTAX 1.3.6.1.4.1.1466.115.121.1.15
  SINGLE-VALUE
  X-ORIGIN 'user defined' )

objectclasses: (
  2.16.840.1.113730.3.2.146
  NAME 'inetMailUser'
  DESC 'user defined class for a cyrus messaging server user'
  SUP top
  AUXILIARY
  MUST ( )
  MAY ( mailUserStatus )
  X-ORIGIN 'user defined' )
```

Above schema works in 389DS.


Note: Cyrus::IMAP::Admin is Cyrus IMAP version dependent. Some issue could happen if you try to run these scripts to a Cyrus IMAP of different version.
