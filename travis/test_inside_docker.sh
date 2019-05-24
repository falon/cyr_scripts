#!/bin/bash -x

OS_VERSION=$1


# Clean the yum cache
yum -y clean all
yum -y clean expire-cache
#yum -y update  # Update the OS packages

# First, install all the needed packages.
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_VERSION}.noarch.rpm \
  http://repository.it4i.cz/mirrors/repoforge/redhat/el${OS_VERSION}/en/x86_64/rpmforge/RPMS/rpmforge-release-0.5.3-1.el${OS_VERSION}.rf.x86_64.rpm

# Broken mirror?
#echo "exclude=mirror.beyondhosting.net" >> /etc/yum/pluginconf.d/fastestmirror.conf

yum -y install yum-plugin-priorities rpm-build boost-devel  git tar gzip make autotools sudo


# Install environment
yum install -y cyrus-sasl-plain \
	cyrus-sasl \
	cyrus-imapd \
	389-ds-base

# Configure environment
# LDAP
sed -i 's/checkHostname {/checkHostname {\nreturn();/g' /usr/lib64/dirsrv/perl/DSUtil.pm
pushd /setup
setup-ds.pl --silent --file=/setup/travis/ldap.inf
popd
ldapadd -D "cn=directory manager" -w ldapassword -vvv -f /setup/travis/user.ldif
# SASL
sed -i 's|MECH=.*|MECH=ldap|' /etc/sysconfig/saslauthd
cp /setup/travis/saslauthd.conf /etc/
systemctl restart saslauthd
# IMAP
cp /setup/travis/annoIMAP.conf /etc/
cp /setup/travis/imapd.conf /etc/
sed -i -r 's|^\t+nntp\t+.*||' /etc/cyrus.conf
sed -i -r 's|^\t+http\t+.*||' /etc/cyrus.conf
## 2.4
sed -i -r 's|^configdirectory: \/var\/lib\/cyrus.*|configdirectory: /var/lib/imap|' /etc/imapd.conf

mkdir -pv /maildata/example.com/maildata1
mkdir -pv /maildata/example.com/maildata2
chown -R cyrus:mail /maildata

## 2.4
mkdir -pv /run/cyrus/proc
chown -R cyrus:mail /run/cyrus

systemctl restart cyrus-imapd


# Install prerequisites
# Local install
yum install -y /setup/rpm/perl-Config-IniFiles-3.000002-1.el${OS_VERSION}.noarch.rpm
if [ "${OS_VERSION}" -eq "7" ]; then
    yum -y install /setup/rpm/perl-String-Scanf-2.1-1.2.el${OS_VERSION}.rf.noarch.rpm \
        /setup/rpm/perl-Unicode-IMAPUtf7-2.01-1.el${OS_VERSION}.noarch.rpm \
	/setup/rpm/perl-Mail-IMAPTalk-4.04-1.el7.noarch.rpm \
        /setup/rpm/perl-Encode-IMAPUTF7-1.05-1.el7.rf.noarch.rpm \
	https://github.com/falon/systemd-unit-status-email/raw/master/systemd-unit-status-email-0.1.0-0.el7.noarch.rpm
    yum update -y http://repo.openfusion.net/centos7-x86_64//perl-Scalar-List-Utils-1.39-1.of.el7.x86_64.rpm
    mkdir -m 700 -pv /run/cyr_setPartitionAnno
elif [ "${OS_VERSION}" -eq "6" ]; then
	yum install -y http://repo.openfusion.net/centos6-x86_64//perl-Mail-IMAPTalk-3.01-1.of.el6.noarch.rpm \
		perl-Unicode-IMAPUtf7
fi
yum install -y cyrus-imapd-utils \
	perl-Data-Dumper \
	perl-Date-Calc \
	perl-Encode \
	perl-Env \
	perl-Getopt-Long \
	perl-libwww-perl \
	perl-LDAP \
	perl-Proc-Daemon \
	perl-String-Scanf \
	perl-Switch \
	perl-Sys-Syslog \
	perl-URI \
	perl-version \
	http://repo.openfusion.net/centos${OS_VERSION}-x86_64/perl-Data-Validate-Domain-0.14-1.of.el${OS_VERSION}.noarch.rpm

# Prepare the RPM environment
mkdir -p /tmp/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cp /setup/rpm/cyrus-imapd-scripts.spec /tmp/rpmbuild/SPECS
package_version=`grep Version /setup/rpm/cyrus-imapd-scripts.spec | awk '{print $2}'`
package_release=`grep Release: /setup/rpm/cyrus-imapd-scripts.spec | awk '{print $2}' | awk -F '%' '{print $1}'`
package_branch=master
pushd /setup
git archive --format=zip --prefix=cyr_scripts-${package_branch}/ HEAD \
	        -o /tmp/rpmbuild/SOURCES/${package_branch}.zip
popd
# Build the RPM
rpmbuild --define '_topdir /tmp/rpmbuild' -ba /tmp/rpmbuild/SPECS/cyrus-imapd-scripts.spec

# After building the RPM, try to install it
RPM_LOCATION=/tmp/rpmbuild/RPMS/noarch
yum install -y ${RPM_LOCATION}/cyrus-imapd-scripts-${package_version}-${package_release}.el${OS_VERSION}.noarch.rpm
if [ "${OS_VERSION}" -eq "7" ]; then
	systemd-tmpfiles --create
fi
. /etc/profile.d/cyr_scripts.sh


## REAL TEST
cd /opt/cyr_scripts
mkdir /opt/cyr_scripts/travis
cp -p /setup/travis/*.txt /opt/cyr_scripts/travis
sudo sed -i -r -e '/^\s*Defaults\s+secure_path/ s[=(.*)[=\1:/usr/lib/cyrus-imapd[' /etc/sudoers
/setup/travis/test_suite.sh
test_exit=$?

# Verify preun/postun in the spec file
yum remove -y 'cyrus-imapd-scripts'

exit $test_exit
