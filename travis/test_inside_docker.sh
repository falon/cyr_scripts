#!/bin/bash -x

OS_TYPE=$1
OS_VERSION=$2
CYR_VERSION=$3


# Clean the yum cache
echo -en "\n\n \e[48;5;17;97mClean YUM Cache\e[0m\n\n"
yum -y clean all
yum -y clean expire-cache
#yum -y update  # Update the OS packages

# First, install all the needed packages.
echo -en "\n\n \e[48;5;17;97m INSTALL REPOs AND MAIN SYSTEM REQUIREMENTS\e[0m\n\n"
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_VERSION}.noarch.rpm \
  http://repository.it4i.cz/mirrors/repoforge/redhat/el${OS_VERSION}/en/x86_64/rpmforge/RPMS/rpmforge-release-0.5.3-1.el${OS_VERSION}.rf.x86_64.rpm

yum -y install yum-plugin-priorities rpm-build git tar gzip autotools sudo

# Prepare the RPM environment
echo -en "\n\n \e[48;5;17;97m PREPARE THE RPM BUILD ENVIRONMENT\e[0m\n\n"
mkdir -vp /tmp/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
if [ "${OS_VERSION}" -eq "6" ]; then
	echo -en "\n\n \e[48;5;17;97m BUILD CYRUS 2.4\e[0m\n\n"
	yum install -y cyrus-sasl-devel tcp_wrappers openssl-devel pcre-devel krb5-devel flex bison automake zlib-devel openldap-devel perl-ExtUtils-MakeMaker gcc
	rpmbuild --define '_topdir /tmp/rpmbuild' --rebuild http://www.invoca.ch/pub/packages/cyrus-imapd/RPMS/ils-6/SRPMS/cyrus-imapd-2.4.20-2.el6.src.rpm
fi

# Install environment
echo -en "\n\n \e[48;5;17;97m INSTALL 389DS\e[0m\n\n"
yum install -y cyrus-sasl-plain \
	cyrus-sasl \
	389-ds-base

# Configure environment
# LDAP
echo -en "\n\n \e[48;5;17;97m CONFIGURE LDAP\e[0m\n\n"
if [ "${OS_VERSION}" -eq "6" ]; then
	echo Create user dirsrv...
	useradd -b /var/lib/dirsrv -d /var/lib/dirsrv -s /usr/sbin/nologin -U dirsrv
	chown -v dirsrv:dirsrv /var/lib/dirsrv
fi
sed -i 's/checkHostname {/checkHostname {\nreturn();/g' /usr/lib64/dirsrv/perl/DSUtil.pm
pushd /setup
setup-ds.pl --debug --silent --file=/setup/travis/ldap.inf
popd
ldapadd -D "cn=directory manager" -w ldapassword -vvv -f /setup/travis/user.ldif
# SASL
echo  -en "\n\n \e[48;5;17;97mCONFIGURE SASLAUTHD\e[0m\n\n"
sed -i 's|MECH=.*|MECH=ldap|' /etc/sysconfig/saslauthd
cp -v /setup/travis/saslauthd.conf /etc/
if [ "${OS_VERSION}" -eq "7" ]; then
	systemctl restart saslauthd
elif [ "${OS_VERSION}" -eq "6" ]; then
	service saslauthd start
fi
# IMAP
echo -en "\n\n \e[48;5;17;97mINSTALL CYRUS IMAP\e[0m\n\n"
if [ "${OS_VERSION}" -eq "6" ]; then
	yum -y install /tmp/rpmbuild/RPMS/x86_64/cyrus-imapd-2.4.20-2.el6.x86_64.rpm /tmp/rpmbuild/RPMS/x86_64/cyrus-imapd-utils-2.4.20-2.el6.x86_64.rpm
elif [ "${OS_VERSION}" -eq "7" ]; then
	if [ "${CYR_VERSION}" -eq "3" ]; then
		# Install Cyrus 3 from uxrepo
		yum -y install https://reposerv.unixadm.org/rhel/7/ux/x86_64/ux-release-0.18-1.el7.noarch.rpm
		yum-config-manager --enable ux-updates
	fi
	yum -y install cyrus-imapd cyrus-imapd-utils
fi
echo -en "\n\n \e[48;5;17;97m CONFIGURE CYRUS IMAP\e[0m\n\n"
cp -v /setup/travis/annoIMAP.conf /etc/
cp -v /setup/travis/imapd.conf /etc/
sed -i -r 's|^\s+imaps\s+.*||' /etc/cyrus.conf
sed -i -r 's/^\s+(http|nntp|pop3)(s|)\s+.*//' /etc/cyrus.conf

sed -i -r 's|^configdirectory: \/var\/lib\/cyrus.*|configdirectory: /var/lib/imap|' /etc/imapd.conf

mkdir -pv /maildata/example.com/maildata1
mkdir -pv /maildata/example.com/maildata2
chown -vR cyrus:mail /maildata

mkdir -pv /run/cyrus/proc
chown -vR cyrus:mail /run/cyrus

if [ "${OS_VERSION}" -eq "7" ]; then
	systemctl restart cyrus-imapd
elif [ "${OS_VERSION}" -eq "6" ]; then
	service cyrus-imapd start
fi


# Install prerequisites
# Local install
echo -en "\n\n \e[48;5;17;97mINSTALL SCRIPTS PREREQUISITES\e[0m\n\n"
yum install -y http://repo.openfusion.net/centos${OS_VERSION}-x86_64/perl-Scalar-List-Utils-1.39-1.of.el${OS_VERSION}.x86_64.rpm \
	/setup/rpm/perl-Config-IniFiles-3.000002-1.el${OS_VERSION}.noarch.rpm
if [ "${OS_VERSION}" -eq "7" ]; then
    yum -y install /setup/rpm/perl-String-Scanf-2.1-1.2.el${OS_VERSION}.rf.noarch.rpm \
        /setup/rpm/perl-Unicode-IMAPUtf7-2.01-1.el${OS_VERSION}.noarch.rpm \
	/setup/rpm/perl-Mail-IMAPTalk-4.04-1.el7.noarch.rpm \
        /setup/rpm/perl-Encode-IMAPUTF7-1.05-1.el7.rf.noarch.rpm \
	https://github.com/falon/systemd-unit-status-email/raw/master/systemd-unit-status-email-0.1.0-0.el7.noarch.rpm \
        http://repo.openfusion.net/centos${OS_VERSION}-x86_64/perl-Data-Validate-Domain-0.14-1.of.el${OS_VERSION}.noarch.rpm \
	perl-Getopt-Long perl-Encode perl-Env
elif [ "${OS_VERSION}" -eq "6" ]; then
	yum install -y http://repo.openfusion.net/centos6-x86_64/perl-Mail-IMAPTalk-3.01-1.of.el6.noarch.rpm \
		perl-Unicode-IMAPUtf7 perl-Data-Validate-Domain 
fi

yum install -y \
	perl-Data-Dumper \
	perl-Date-Calc \
	perl-libwww-perl \
	perl-LDAP \
	perl-Proc-Daemon \
	perl-String-Scanf \
	perl-Switch \
	perl-Sys-Syslog \
	perl-URI \
	perl-version \
# Prepare the RPM environment
echo -en "\n\n \e[48;5;17;97mMAKE YUM PACKAGES\e[0m\n\n"

cp -v /setup/rpm/cyrus-imapd-scripts.spec /tmp/rpmbuild/SPECS
package_version=`grep Version /setup/rpm/cyrus-imapd-scripts.spec | awk '{print $2}'`
package_release=`grep Release: /setup/rpm/cyrus-imapd-scripts.spec | awk '{print $2}' | awk -F '%' '{print $1}'`
package_branch=master
pushd /setup
git archive --format=zip --prefix=cyr_scripts-${package_branch}/ HEAD \
	        -o /tmp/rpmbuild/SOURCES/${package_branch}.zip
popd
# Build the RPM
echo RPMBUILD
rpmbuild --define '_topdir /tmp/rpmbuild' -ba /tmp/rpmbuild/SPECS/cyrus-imapd-scripts.spec

# After building the RPM, try to install it
echo -en "\n\n \e[48;5;17;97mINSTALL PACKAGES BUILT IN PREVIOUS STEP\e[0m\n\n"
RPM_LOCATION=/tmp/rpmbuild/RPMS/noarch
yum install -y ${RPM_LOCATION}/cyrus-imapd-scripts-${package_version}-${package_release}.el${OS_VERSION}.noarch.rpm
if [ "${OS_VERSION}" -eq "7" ]; then
	systemd-tmpfiles --create
fi
. /etc/profile.d/cyr_scripts.sh


## REAL TEST
echo -en "\n\n \e[48;5;17;97m** SCRIPTS TEST **\e[0m\n\n"
cd /opt/cyr_scripts
mkdir -v /opt/cyr_scripts/travis
cp -pv  /setup/travis/*.txt /opt/cyr_scripts/travis
sudo sed -i -r -e '/^\s*Defaults\s+secure_path/ s[=(.*)[=\1:/usr/lib/cyrus-imapd[' /etc/sudoers
/setup/travis/test_suite.sh ${OS_TYPE}
test_exit=$?

exit $test_exit
