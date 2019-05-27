%global systemd (0%{?fedora} >= 18) || (0%{?rhel} >= 7)
%global upname cyr_scripts

Summary: An extra collection of cyrus-imapd utilities.
Name: cyrus-imapd-scripts
Version: 0.1.8
Release: 0%{?dist}
Group: System Environment/Base
License: Apache-2.0
URL: https://falon.github.io/%{upname}/
Source0: https://github.com/falon/%{upname}/archive/master.zip
BuildArch:	noarch

# Required for all versions
Requires: cyrus-imapd-utils >= 2.4
Requires: perl-Config-IniFiles >= 3
Requires: perl-version
Requires: perl-LDAP
Requires: perl-Date-Calc
Requires: perl-String-Scanf
Requires: perl-Mail-IMAPTalk
Requires: perl-Data-Validate-Domain
Requires: perl-Unicode-IMAPUtf7
Requires: perl-Proc-Daemon
Requires: perl-URI

%if %systemd
# Required for systemd
%{?systemd_requires}
Requires: systemd
Requires: perl-Env
Requires: perl-Sys-Syslog
Requires: systemd-unit-status-email
BuildRequires: systemd
%else
# Required for SysV
Requires(post): chkconfig
Requires(preun): chkconfig, initscripts
Requires(postun): initscripts
%endif


%description
%{upname} 
The cyrus-imapd-scripts package contains extra administrative tools for the
Cyrus IMAP server. In evidence:
- The Cyrus Partition Manager for virtdomains system. If you are not satisfied by
  the official partition management with this tool you can administer each
  domain into a separate sets of partitions.
- A Cyrus XFER utility to manage trasfer over server with profile on LDAP
  and web frontend in Open-Xchange
- A set of classic utility to manage users (create, change partition, delete...)
  LDAP profiled.
And many other things!

%clean
rm -rf %{buildroot}/

%prep
%autosetup -n %{upname}-master


%install

%if %systemd
sed -i 's|\/usr\/local\/%{upname}|\/opt\/%{upname}|' setPartitionAnno.service
mkdir -p %{buildroot}%{_unitdir}
mv setPartitionAnno.service %{buildroot}%{_unitdir}
mkdir -p %{buildroot}%{_tmpfilesdir}
mv setPartitionAnno.conf %{buildroot}%{_tmpfilesdir}
rm init_setPartitionAnno
%else
rm setPartitionAnno.service setPartitionAnno.conf
mkdir -p %{buildroot}%{_initrddir}
sed -i 's|\/usr\/local\/%{upname}|\/opt\/%{upname}|' init_setPartitionAnno
install -m 0755 init_setPartitionAnno %{buildroot}%{_initrddir}/setPartitionAnno
rm init_setPartitionAnno
%endif
rm -rf rpm travis
sed -i 's|\/usr\/local\/%{upname}|\/opt\/%{upname}|' cyr_scripts.sh
mkdir -p %{buildroot}/etc/profile.d
mv cyr_scripts.sh %{buildroot}%{_sysconfdir}/profile.d
mkdir -p %{buildroot}/opt/%{upname}
mkdir -p %{buildroot}%{_sysconfdir}/%{upname}
rm README.md *.yml
chmod 700 *.pl
sed -i 's|\/usr\/local\/%{upname}\/core\.pl|\/opt\/%{upname}\/core\.pl|' *.pl
sed -i "s|'\/usr\/local\/%{upname}\/cyr_scripts.ini'|'%{_sysconfdir}/%{upname}\/cyr_scripts.ini'|" *.pl
sed -i 's|\/usr\/local\/%{upname}|%{_sysconfdir}\/%{upname}|' cyr
install -m 0640 cyr_scripts.ini-default %{buildroot}%{_sysconfdir}/%{upname}/cyr_scripts.ini
rm cyr_scripts.ini-default
cp -a * %{buildroot}/opt/%{upname}
rm %{buildroot}/opt/%{upname}/LICENSE
find %{buildroot}/opt/%{upname} -mindepth 1 -type f | sed -e "s@$RPM_BUILD_ROOT@@" | grep -v core.pl | grep -v cyr_setPartitionAnno.pl > FILELIST

%files -f FILELIST
%attr(0700,cyrus,mail) /opt/%{upname}/core.pl
%attr(0700,cyrus,mail) /opt/%{upname}/cyr_setPartitionAnno.pl
%attr(750,root,mail) %dir %{_sysconfdir}/cyr_scripts
%attr(640,root,mail) %config(noreplace) %{_sysconfdir}/cyr_scripts/cyr_scripts.ini
%{_sysconfdir}/profile.d/cyr_scripts.sh
%if %systemd
%{_unitdir}/setPartitionAnno.service
%{_tmpfilesdir}/setPartitionAnno.conf
%license LICENSE
%else
%{_initrddir}/setPartitionAnno
%doc LICENSE
%endif


%post
sed -i 's|\"||g' %{_sysconfdir}/%{upname}/cyr_scripts.ini
%if %systemd
%systemd_post setPartitionAnno.service
%else
/sbin/chkconfig --add setPartitionAnno || :
%endif

%preun
%if %systemd
%systemd_preun setPartitionAnno.service
%else
if [ $1 -eq 0 ]; then
        service setPartitionAnno stop >/dev/null || :
        /sbin/chkconfig --del setPartitionAnno || :
fi
exit 0
%endif

%postun
%if %systemd
%systemd_postun_with_restart setPartitionAnno.service
%else
if [ "$1" -ge "1" ] ; then
        /sbin/service setPartitionAnno restart >/dev/null 2>&1 || :
fi
exit 0
%endif


%changelog
* Thu May 22 2019 Marco Favero <marco.favero@csi.it> 0.1.8-0
- new version.
- many minor bug fixes.
- added TRAVIS integration.
* Thu May 02 2019 Marco Favero <marco.favero@csi.it> 0.1.6-0
- new version.
- added log for rundeck ENV, if any.
- normalized exit codes.
- Config::Simple replaced with Config::IniFiles.
- removed quotes from cyr_scripts.ini.
- handling CRLF in input files.
- many minor bug fixes and improvements.
* Mon Apr 08 2019 Marco Favero <marco.favero@csi.it> 0.1.5-0
- now cyr_moveMailboxPart let you to autodefine the dest part
- fixed warning BUG in cyr_setPartitionAnno
* Mon Apr 01 2019 Marco Favero <marco.favero@csi.it> 0.1.4-2
- yet another fix on env PATH for startscripts.
* Fri Mar 29 2019 Marco Favero <marco.favero@csi.it> 0.1.4-1
- fixed some env PATH in startscript of cyr_setPartitionAnno
* Mon Mar 25 2019 Marco Favero <marco.favero@csi.it> 0.1.4-0
- new release. New cyr_moveINBOX script.
* Wed Mar 13 2019 Marco Favero <marco.favero@csi.it> 0.1.3-0
- new release. Now all configurations are in a ini file.
- cyr_showuser version based.
- minor bug fixes.
* Mon Feb 25 2019 Marco Favero <marco.favero@csi.it> 0.1.2-3
- fixed bug in cyr_moveMailboxPart
* Mon Feb 25 2019 Marco Favero <marco.favero@csi.it> 0.1.2-2
- modified cyr_moveMailboxPart in batch mode
* Mon Feb 25 2019 Marco Favero <marco.favero@csi.it> 0.1.2-1
- Removed unnecessary exist commands.
* Fri Feb 22 2019 Marco Favero <marco.favero@csi.it> 0.1.2-0
- Replaced required separator char ',' with ';' for batch input file
* Mon Feb 18 2019 Marco Favero <marco.favero@csi.it> 0.1.1-0
- Fixed cyr_moveMailboxPart and cyr_setQuota
* Mon Nov 12 2018 Marco Favero <marco.favero@csi.it> 0.1.0-0
- Initial "official" release.
* Thu Nov 24 2011 Marco Favero <marco.favero@csi.it>
- Initial Internal Release
- Some piece of code contributed by Paolo Cravero