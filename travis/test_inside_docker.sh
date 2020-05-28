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
if [ "${OS_VERSION}" -ne "8" ]; then
	yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_VERSION}.noarch.rpm \
	  http://repository.it4i.cz/mirrors/repoforge/redhat/el${OS_VERSION}/en/x86_64/rpmforge/RPMS/rpmforge-release-0.5.3-1.el${OS_VERSION}.rf.x86_64.rpm \
	  yum-plugin-priorities rpm-build git tar gzip autotools sudo rpmdevtools
else
	dnf install langpacks-en glibc-all-langpacks -y
	dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_VERSION}.noarch.rpm \
	  sudo rpmdevtools git
	dnf -y install 'dnf-command(config-manager)'
	dnf config-manager --set-enabled PowerTools
	dnf -y module enable 389-ds:1.4
fi


# Prepare the RPM environment
echo -en "\n\n \e[48;5;17;97m PREPARE THE RPM BUILD ENVIRONMENT\e[0m\n\n"
rpmdev-setuptree
if [ "${OS_VERSION}" -le "7" ] && [ "${CYR_VERSION}" -eq "2" ]; then
	echo -en "\n\n \e[48;5;17;97m BUILD CYRUS 2.4\e[0m\n\n"
	yum install -y groff make cyrus-sasl-devel tcp_wrappers openssl-devel pcre-devel krb5-devel flex bison automake zlib-devel openldap-devel perl-ExtUtils-MakeMaker gcc
	rpmbuild --rebuild /setup/travis/cyrus-imapd-2.4.20-4.el${OS_VERSION}.src.rpm
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
pushd /setup
if [ "${OS_VERSION}" -eq "8" ]; then
	dscreate -v from-file /setup/travis/ldap.inf
	ldapadd -D "cn=directory manager" -w ldapassword -vvv -f /setup/travis/CIT.ldif
	cp /setup/travis/97csi-InetMailUser.ldif /etc/dirsrv/slapd-example/schema/
	dsctl example restart
else
	sed -i 's/checkHostname {/checkHostname {\nreturn();/g' /usr/lib64/dirsrv/perl/DSUtil.pm
	setup-ds.pl --debug --silent --file=/setup/travis/ldap-old.inf
fi
popd
ldapadd -D "cn=directory manager" -w ldapassword -vvv -f /setup/travis/user.ldif
# SASL
echo  -en "\n\n \e[48;5;17;97mCONFIGURE SASLAUTHD\e[0m\n\n"
sed -i 's|MECH=.*|MECH=ldap|' /etc/sysconfig/saslauthd
cp -v /setup/travis/saslauthd.conf /etc/
if [ "${OS_VERSION}" -ge "7" ]; then
	systemctl restart saslauthd
elif [ "${OS_VERSION}" -eq "6" ]; then
	service saslauthd start
fi
# IMAP
echo -en "\n\n \e[48;5;17;97mINSTALL CYRUS IMAP\e[0m\n\n"
if [ "${OS_VERSION}" -le "7" ] && [ "${CYR_VERSION}" -eq "2" ]; then
	yum -y install $HOME/rpmbuild/RPMS/x86_64/cyrus-imapd-2.4.20-4.el${OS_VERSION}.x86_64.rpm $HOME/rpmbuild/RPMS/x86_64/cyrus-imapd-utils-2.4.20-4.el${OS_VERSION}.x86_64.rpm
elif [ "${OS_VERSION}" -eq "7" ]; then
	if [ "${CYR_VERSION}" -eq "3" ]; then
		# Install Cyrus 3 from uxrepo
		yum -y install https://reposerv.unixadm.org/rhel/7/ux/x86_64/ux-release-0.18-1.el7.noarch.rpm
		yum-config-manager --enable ux-updates
		yum -y install cyrus-imapd cyrus-imapd-utils
	fi

elif [ "${OS_VERSION}" -eq "8" ]; then
        if [ "${CYR_VERSION}" -eq "3" ]; then
                # Install Cyrus 3 from CSI repo
		curl -1sLf \
		  'https://dl.cloudsmith.io/public/csi/cyrus/cfg/setup/bash.rpm.sh' \
		  | sudo -E bash
		dnf -y install cyrus-imapd perl-Cyrus cyrus-imapd-libs
	fi

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
elif [ "${OS_VERSION}" -eq "8" ]; then
	systemctl enable --now cyrus-imapd
elif [ "${OS_VERSION}" -eq "6" ]; then
	service cyrus-imapd start
fi


# Install prerequisites
echo -en "\n\n \e[48;5;17;97mINSTALL SCRIPTS PREREQUISITES\e[0m\n\n"
curl -1sLf \
  'https://dl.cloudsmith.io/public/csi/cyrus-scripts/cfg/setup/bash.rpm.sh' \
  | sudo -E bash

if [ "${OS_VERSION}" -ge "7" ]; then
	yum install -y \
		perl-Config-IniFiles \
		perl-String-Scanf \
		perl-Unicode-IMAPUtf7 \
		perl-Mail-IMAPTalk \
		perl-Encode-IMAPUTF7 \
		systemd-unit-status-email \
		perl-Data-Validate-Domain \
		perl-Getopt-Long \
		perl-Encode \
		perl-Env \
		perl-Data-Dumper \
		perl-Date-Calc \
		perl-libwww-perl \
		perl-LDAP \
		perl-Proc-Daemon \
		perl-String-Scanf \
		perl-Switch \
		perl-Sys-Syslog \
		perl-URI \
		perl-version


elif [ "${OS_VERSION}" -eq "6" ]; then
	yum install -y http://repo.openfusion.net/centos6-x86_64/perl-Mail-IMAPTalk-3.01-1.of.el6.noarch.rpm \
		/setup/rpm/perl-Config-IniFiles-3.000002-1.el${OS_VERSION}.noarch.rpm \
		perl-Unicode-IMAPUtf7 perl-Data-Validate-Domain perl-Data-Dumper perl-Date-Calc \
		perl-libwww-perl perl-LDAP perl-Proc-Daemon perl-String-Scanf perl-Switch perl-Sys-Syslog \
		perl-URI perl-version \
		http://repo.openfusion.net/centos${OS_VERSION}-x86_64/perl-Scalar-List-Utils-1.39-1.of.el${OS_VERSION}.x86_64.rpm \
		http://repo.openfusion.net/centos${OS_VERSION}-x86_64/perl-Params-Validate-1.13-1.of.el${OS_VERSION}.x86_64.rpm
fi

# Prepare the RPM environment
echo -en "\n\n \e[48;5;17;97mMAKE YUM PACKAGES\e[0m\n\n"

cp -v /setup/rpm/cyrus-imapd-scripts.spec $HOME/rpmbuild/SPECS
package_version=`grep Version /setup/rpm/cyrus-imapd-scripts.spec | awk '{print $2}'`
package_release=`grep Release: /setup/rpm/cyrus-imapd-scripts.spec | awk '{print $2}' | awk -F '%' '{print $1}'`
package_branch=master
pushd /setup
git archive --format=zip --prefix=cyr_scripts-${package_branch}/ HEAD \
	        -o $HOME/rpmbuild/SOURCES/${package_branch}.zip
popd
# Build the RPM
echo RPMBUILD
rpmbuild -ba $HOME/rpmbuild/SPECS/cyrus-imapd-scripts.spec

# After building the RPM, try to install it
echo -en "\n\n \e[48;5;17;97mINSTALL PACKAGES BUILT IN PREVIOUS STEP\e[0m\n\n"
RPM_LOCATION=$HOME/rpmbuild/RPMS/noarch
yum install -y ${RPM_LOCATION}/cyrus-imapd-scripts-${package_version}-${package_release}.el${OS_VERSION}.noarch.rpm
if [ "${OS_VERSION}" -ge "7" ]; then
	systemd-tmpfiles --create
fi
. /etc/profile.d/cyr_scripts.sh


## REAL TEST
echo -en "\n\n \e[48;5;17;97m** SCRIPTS TEST **\e[0m\n\n"
if [ ${CYR_VERSION} -eq "2" ]; then
	sed -i -r 's|type\=private|type=value.priv|' /setup/travis/TESTLIST
fi
cd /opt/cyr_scripts
mkdir -v /opt/cyr_scripts/travis
cp -pv  /setup/travis/*.txt /opt/cyr_scripts/travis
sudo sed -i -r -e '/^\s*Defaults\s+secure_path/ s[=(.*)[=\1:/usr/lib/cyrus-imapd[' /etc/sudoers
/setup/travis/test_suite.sh ${OS_TYPE}
test_exit=$?

if [ $test_exit -eq "0" ]  && [ "${CYR_VERSION}" -ne "2" ] && [ "${OS_VERSION}" -ne "7" ]; then
	export LC_ALL=en_US.utf-8
	export LANG=en_US.utf-8
	if [ "${OS_VERSION}" -ge "7" ]; then
		yum -y install python3-pip
	else
		yum -y install python34 python34-pip
	fi
	pip3 install --upgrade cloudsmith-cli
	export CLOUDSMITH_API_KEY=2665bf65dd124524a79903591128ee3d2ddc0c62
	cloudsmith push rpm csi/cyrus-scripts/el/${OS_VERSION} ${RPM_LOCATION}/cyrus-imapd-scripts-${package_version}-${package_release}.el${OS_VERSION}.noarch.rpm
	export CS=$?
	if [ ${CS} -ne "0" ]; then
		printf "%-40s\t[\e[31;5m %s \e[0m]\n" "Cloudsmith export" FAIL
	else
		printf "%-40s\t[\e[32m %s \e[0m]\n" "Cloudsmith export" OK
	fi
fi
exit $test_exit
