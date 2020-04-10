#!/bin/bash
#
# Automatic script to install Citadel on a target system.
# Copyright (C) 2004 Michael Hampton <error@citadel.org>
# Copyright (C) 2004-2019 Art Cancro <ajc@citadel.org>
#
# This program is open source software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# Reading this script?  Here's some helpful hints:
#
# If you're seeing this in your browser, it's probably not what you want.
# You can either save it to disk and run it, or do it the easy way:
#
# curl http://easyinstall.citadel.org/install | bash
#
# Note that this script installs software on your system and so it requires
# root privileges.  Feel free to inspect the script to make sure we didn't
# do anything stupid...
#
# We have provided you the source code according to the terms of the respective
# software licenses included in the source code packages, even if you choose
# not to keep the source code around.  You can always download it again later.


###############################################################################
#
# This is the general stuff we're going to do, in order:
#
# 1. Gather information about the target system
# 2. Present the installation steps (from 1 above) to the user
# 3. Present any pre-install customizations to the user
# 4. Do the installation
#    A. Download any source code files packages required
#    B. If we build our own, compile and install prerequisites then Citadel
# 5. Do post-installation setup
#
# Then call it a day.
#
###############################################################################


# Begin user customization area
#
# These two directories specify where Citadel and its private support
# libraries will be installed.  This keeps them safely tucked away from
# the rest of your system.  The defaults should be fine for most people.

SUPPORT=/usr/local/ctdlsupport
CITADEL=/usr/local/citadel
WEBCIT=/usr/local/webcit
WORKDIR=/tmp
BUILD=$WORKDIR/citadel-build.$$
export SUPPORT CITADEL WEBCIT
unset LANG

MAKEOPTS=""

# End user customization area

# We're now exporting a bunch of environment variables, and here's a list:
# CITADEL_INSTALLER	Set to "web" to indicate this script
# CITADEL		Directory where Citadel is installed
# WEBCIT		Directory where WebCit is installed
# SUPPORT		Directory where support programs are installed
# DISTRO_MAJOR		Linux distribution name, if applicable
# DISTRO_MINOR		Linux distribution name, if applicable
# DISTRO_VERSION	Linux distribution version (major digit) if applicable
# CC			C compiler being used
# MAKE			Make program being used
# CMAKE			CMake program being used
# CFLAGS		C compiler flags
# LDFLAGS		Linker flags
# IS_UPGRADE		Set to "yes" if upgrading an existing Citadel
# CTDL_DIALOG		Where (if at all) the "whiptail" or "dialog" program may be found

# Let Citadel setup recognize the Citadel installer
CITADEL_INSTALLER=web
export CITADEL_INSTALLER

SETUP="Citadel Easy Install"
DOWNLOAD_SITE=http://easyinstall.citadel.org

# Original source code packages.
DB_SOURCE=db-6.2.32.NC.tar.gz
LIBICAL_SOURCE=libical-3.0.3.tar.gz
LIBSIEVE_SOURCE=libsieve-2.2.7-ctdl2.tar.gz
EXPAT_SOURCE=expat-2.0.1.tar.gz
LIBCURL_SOURCE=curl-7.26.0.tar.gz
LIBCITADEL_SOURCE=libcitadel-easyinstall.tar.gz
CITADEL_SOURCE=citadel-easyinstall.tar.gz
WEBCIT_SOURCE=webcit-easyinstall.tar.gz
TEXTCLIENT_SOURCE=textclient-easyinstall.tar.gz
INCADD=
LDADD=

case `uname -s` in
	*BSD)
		LDADD="-L/usr/local/lib"
		INCADD="-I/usr/local/include"
	;;
esac



########################################################################
# Utility functions used throughout the rest of the script
########################################################################

show_info() {
	echo '[32m' ${*} '[0m'
}


show_alert() {
	echo '[31m' ${*} '[0m'
}


show_prompt() {
	echo -n '[33m' ${*} '[0m'
}


GetVersionFromFile() {
	VERSION=`cat $1 | tr "\n" ' ' | sed s/.*VERSION.*=\ // `
}


die() {
	show_alert $SETUP is aborting.
	show_alert The last few lines above this message may indicate what went wrong.
	show_alert $OSSTR
	cd ~
	rm -fr $BUILD
	exit 1
}


download_this() {
	WGET=`which wget 2>/dev/null`
	CURL=`which curl 2>/dev/null`
	if [ -n "${WGET}" -a -x "${WGET}" ]; then
		$WGET $DOWNLOAD_SITE/$FILENAME || die
	else
		if [ -n "${CURL}" -a -x "${CURL}" ]; then
			$CURL $DOWNLOAD_SITE/$FILENAME -o $FILENAME || die
		else
			show_alert Unable to find a wget or curl command.
			show_alert $SETUP cannot continue.
			die;
		fi
	fi
}


########################################################################
# END OF UTILITY FUNCTIONS -- MAIN SECTION BEGINS HERE 
########################################################################


########################################################################
# Test to make sure we're running as root
########################################################################

PERMSTESTDIR=/usr/local/ctdltest.$$
mkdir $PERMSTESTDIR || {
	show_alert 'Easy Install is unable to create subdirectories in /usr/local.'
	show_alert 'Did you forget to run the install command as the root user?'
	show_alert 'Please become root (with a command like "su" or "sudo -s") and'
	show_alert 'try again.'
	exit 1
}
rmdir $PERMSTESTDIR 2>/dev/null


########################################################################
# Gather information about the target system
########################################################################

os=`uname`
OS=`uname -s`
REV=`uname -r`
MACH=`uname -m`

if [ "${OS}" = "SunOS" ] ; then
	OS=Solaris
	ARCH=`uname -p`	
	OSSTR="${OS} ${REV}(${ARCH} `uname -v`)"
elif [ "${OS}" = "AIX" ] ; then
	OSSTR="${OS} `oslevel` (`oslevel -r`)"
elif [ "${OS}" = "Linux" ] ; then
	KERNEL=`uname -r`
	if [ -f /etc/redhat-release ] ; then
		DIST='RedHat'
		PSEUDONAME=`cat /etc/redhat-release | sed s/.*\(// | sed s/\)//`
		REV=`cat /etc/redhat-release | sed s/.*release\ // | sed s/\ .*//`
	elif [ -f /etc/SUSE-release ] ; then
		DIST=`cat /etc/SUSE-release | tr "\n" ' '| sed s/VERSION.*//`
		REV=`cat /etc/SUSE-release | tr "\n" ' ' | sed s/.*=\ //`
	elif [ -f /etc/mandrake-release ] ; then
		DIST='Mandrake'
		PSEUDONAME=`cat /etc/mandrake-release | sed s/.*\(// | sed s/\)//`
		REV=`cat /etc/mandrake-release | sed s/.*release\ // | sed s/\ .*//`
	elif [ -f /etc/debian_version ] ; then
		DIST='Debian'
		REV=`cat /etc/debian_version`

	fi
	OSSTR="${OS} ${DIST} ${REV}(${PSEUDONAME} ${KERNEL} ${MACH})"
elif [ "${OS}" = "Darwin" ] ; then
	DIST='MacOS'
fi

rm -rf $BUILD 2>/dev/null
mkdir -p $BUILD || die
cd $BUILD || die


########################################################################
# Test to see whether whiptail is usable by presenting a dialog box
########################################################################

if whiptail --infobox "Welcome to Citadel Easy Install" 10 70 2>/dev/null
then
	CTDL_DIALOG=`which whiptail`
	export CTDL_DIALOG
fi


########################################################################
# Test to make sure our build directory works
########################################################################

tempfilename=test$$.sh

echo '#!/bin/sh' >$tempfilename
echo '' >>$tempfilename
echo 'exit 0' >>$tempfilename
chmod 700 $tempfilename

[ -x $tempfilename ] || {
	show_alert Cannot write to `pwd`
	show_alert 'Are you not running this program as root?'
	die
}

./$tempfilename || {
	show_alert Cannot execute a script.
	show_alert 'If /tmp is mounted noexec, please change this before continuing.'
	die
}



########################################################################
# Welcome the user to our installation experience.
########################################################################

show_info "Welcome to $SETUP"
show_info Running on: ${OSSTR}
show_info "We will perform the following actions:"
show_info ""
show_info "Installation:"
show_info "- Download/install supporting libraries (if needed)"
show_info "- Download/install Citadel (if needed)"
show_info "- Download/install WebCit (if needed)"
show_info ""
show_info "Configuration:"
show_info "- Configure Citadel"
show_info "- Configure WebCit"
show_info ""
show_prompt 'Perform the above installation steps now? '
read yesno </dev/tty
if [ "`echo $yesno | cut -c 1 | tr N n`" = "n" ]; then
	exit 2
fi

FILENAME=gpl.txt ; download_this
cat $FILENAME
show_info ""
show_info "Do you accept the terms of this license?"
show_info "If you do not accept the General Public License, Easy Install will exit."
show_prompt 'Enter Y or Yes to accept: '
read yesno </dev/tty
if [ "`echo $yesno | cut -c 1 | tr N n`" = "n" ]; then
	exit 2
fi

echo
if [ -f $CITADEL/data/cdb.00 ]
then
	IS_UPGRADE=yes
	show_info 'Upgrading your existing Citadel installation.'
else
	IS_UPGRADE=no
	show_info 'This is a NEW Citadel installation.'
fi

if [ x$IS_UPGRADE = xyes ]
then
	show_info 'This appears to be an upgrade of an existing Citadel installation.'
	show_prompt 'Have you performed a FULL BACKUP of your programs and data? '
	read yesno </dev/tty
	if [ "`echo $yesno | cut -c 1 | tr N n`" = "n" ]; then
		show_alert "citadel.org does not provide emergency support for sites"
		show_alert "which broke irrecoverably during a failed upgrade."
		show_alert "Easy Install will now exit."
		exit 2
	fi
fi

show_info "Installation will now begin."


########################################################################
# Remove components of libraries we used to build ourselves
# These are now supplied by the system libraries
########################################################################

find /usr/local/ctdlsupport | grep -i ical | xargs rm -v 2>/dev/null
find /usr/local/ctdlsupport | grep -i expat | xargs rm -v 2>/dev/null
find /usr/local/ctdlsupport | grep -i curl | xargs rm -v 2>/dev/null


########################################################################
# Offer to install dependencies from the operating system distributor
########################################################################

show_prompt 'Do you want Easy Install to attempt to install your OS dependencies? '
read yesno </dev/tty

if [ "`echo $yesno | cut -c 1 | tr N n`" = "n" ]; then
	show_prompt 'OS dependencies will not be installed.'
else
	if [ ${DIST} == 'RedHat' ]
	then
		show_info You are on a RedHat-like system.
		yum groupinstall "Development Tools" </dev/tty || die
		yum install \
			zlib-devel \
			openldap-devel \
			openssl-devel \
			libcurl-devel \
			libical-devel \
			expat-devel \
			</dev/tty || die
	elif [ ${DIST} == 'Debian' ]
	then
		show_info You are on a Debian-like system.
		apt-get install \
			make \
			build-essential \
			zlib1g-dev \
			libldap2-dev \
			libssl-dev \
			gettext \
			libical-dev \
			libexpat1-dev \
			libcurl4-openssl-dev \
			</dev/tty || die
	else
		show_alert 'Easy Install does not yet know how to do this on your operating system.'
		die
	fi
fi


########################################################################
# Make sure we are using GNU Make.  Old unix make doesn't work.
########################################################################

MAKE=xx
if gmake -v 2>&1 | grep -i GNU ; then
	MAKE=`which gmake`
else
	if make -v 2>&1 | grep -i GNU ; then
		MAKE=`which make`
	fi
fi
if [ $MAKE == xx ] ; then
	show_alert 'Easy Install requires gmake, which was not found.'
	show_alert 'Please install gmake and try again.'
	exit 1
fi

echo MAKE is $MAKE
export MAKE


#	########################################################################
#	# Install cmake (needed for libical)
#	########################################################################
#	
#	cmake --help >/dev/null 2>&1 || {
#		show_alert 'Easy Install also requires cmake, which was not found.'
#		show_alert 'Please install cmake and try again.'
#		exit 1
#	}


########################################################################
# Create the support directories if they don't already exist
########################################################################

mkdir $SUPPORT		2>/dev/null
mkdir $SUPPORT/bin	2>/dev/null
mkdir $SUPPORT/sbin	2>/dev/null
mkdir $SUPPORT/lib	2>/dev/null
mkdir $SUPPORT/libexec	2>/dev/null
mkdir $SUPPORT/include	2>/dev/null
mkdir $SUPPORT/etc	2>/dev/null


########################################################################
# Install libsieve
########################################################################

cd $BUILD || die
FILENAME=libsieve-easyinstall.sum ; download_this
SUM=`cat libsieve-easyinstall.sum`
SUMFILE=$SUPPORT/etc/libsieve-easyinstall.sum
if [ -r $SUMFILE ] ; then
	OLDSUM=`cat $SUMFILE`
else
	OLDSUM=does_not_exist
fi

if [ "$SUM" = "$OLDSUM" ] ; then
	show_info 'libsieve does not need updating.'
else
	show_info 'Downloading libsieve...'
	FILENAME=$LIBSIEVE_SOURCE ; download_this
	show_info 'Installing libsieve...'
	( gzip -dc $LIBSIEVE_SOURCE | tar -xf - ) || die
	cd $BUILD/libsieve-2.2.7/src || die
	./configure --prefix=$SUPPORT || die
	$MAKE $MAKEOPTS || die
	$MAKE install || die
	show_info 'Complete.'
	echo $SUM >$SUMFILE
	rm -f $CITADEL/citadel-easyinstall.sum 2>/dev/null
fi


#	########################################################################
#	# Install libical
#	########################################################################
#	
#	cd $BUILD || die
#	FILENAME=libical-easyinstall.sum ; download_this
#	SUM=`cat libical-easyinstall.sum`
#	SUMFILE=$SUPPORT/etc/libical-easyinstall.sum
#	if [ -r $SUMFILE ] ; then
#		OLDSUM=`cat $SUMFILE`
#	else
#		OLDSUM=does_not_exist
#	fi
#	
#	if [ "$SUM" = "$OLDSUM" ] ; then
#		show_info 'libical does not need updating.'
#	else
#		show_info 'Downloading libical...'
#		FILENAME=$LIBICAL_SOURCE ; download_this
#		show_info 'Installing libical...'
#		( gzip -dc $LIBICAL_SOURCE | tar -xf - ) || die
#		cd $BUILD/libical-3.0.3 || die
#		mkdir build || die
#		cd build || die
#		pwd
#		cmake .. -DICAL_GLIB=False -DWITH_CXX_BINDINGS=false -DICAL_ERRORS_ARE_FATAL=false \
#			-DCMAKE_INSTALL_LIBDIR=/usr/local/ctdlsupport/lib \
#			-DSHARED_ONLY=true -DICAL_BUILD_DOCS=false -DICAL_GLIB_VAPI=false \
#			-DCMAKE_INSTALL_INCLUDEDIR=/usr/local/ctdlsupport/include \
#			-DCMAKE_INSTALL_DATAROOTDIR=/usr/local/ctdlsupport/etc \
#			|| die
#		make || die
#		make install || die
#		show_info 'Complete.'
#		echo $SUM >$SUMFILE
#		rm -f $CITADEL/citadel-easyinstall.sum 2>/dev/null
#	fi


########################################################################
# Install Berkeley DB
########################################################################

cd $BUILD || die
FILENAME=db-easyinstall.sum ; download_this
SUM=`cat db-easyinstall.sum`
SUMFILE=$SUPPORT/etc/db-easyinstall.sum
if [ -r $SUMFILE ] ; then
	OLDSUM=`cat $SUMFILE`
else
	OLDSUM=does_not_exist
fi

if [ "$SUM" = "$OLDSUM" ] ; then
	show_info 'Berkeley DB does not need updating.'
else
	show_info 'Downloading Berkeley DB...'
	FILENAME=$DB_SOURCE ; download_this
	show_info 'Installing Berkeley DB...'
	( gzip -dc $DB_SOURCE | tar -xf - ) || die
	cd $BUILD/db-6.2.32.NC/build_unix || die
	../dist/configure --prefix=$SUPPORT --disable-compat185 --disable-cxx --disable-debug --disable-dump185 --disable-java --disable-tcl --disable-test --without-rpm || die
	$MAKE $MAKEOPTS || die
	$MAKE install || die
	show_info 'Complete.'
	echo $SUM >$SUMFILE
	rm -f $CITADEL/citadel-easyinstall.sum 2>/dev/null
fi


#	########################################################################
#	# Install expat
#	########################################################################
#	
#	cd $BUILD || die
#	FILENAME=expat-easyinstall.sum ; download_this
#	SUM=`cat expat-easyinstall.sum`
#	SUMFILE=$SUPPORT/etc/expat-easyinstall.sum
#	if [ -r $SUMFILE ] ; then
#		OLDSUM=`cat $SUMFILE`
#	else
#		OLDSUM=does_not_exist
#	fi
#	
#	if [ "$SUM" = "$OLDSUM" ] ; then
#		show_info 'expat does not need updating.'
#	else
#		show_info 'Downloading expat...'
#		FILENAME=$EXPAT_SOURCE ; download_this
#		show_info 'Installing Expat...'
#		( gzip -dc $EXPAT_SOURCE | tar -xf - ) || die
#		cd $BUILD/expat-2.0.1 || die
#		./configure --prefix=$SUPPORT || die
#		$MAKE $MAKEOPTS || die
#		$MAKE install || die
#		show_info 'Complete.'
#		echo $SUM >$SUMFILE
#		rm -f $CITADEL/citadel-easyinstall.sum 2>/dev/null
#	fi


#	########################################################################
#	# Install libcurl
#	########################################################################
#	
#	cd $BUILD || die
#	FILENAME=libcurl-easyinstall.sum ; download_this
#	SUM=`cat libcurl-easyinstall.sum`
#	SUMFILE=$SUPPORT/etc/libcurl-easyinstall.sum
#	if [ -r $SUMFILE ] ; then
#		OLDSUM=`cat $SUMFILE`
#	else
#		OLDSUM=does_not_exist
#	fi
#	
#	if [ "$SUM" = "$OLDSUM" ] ; then
#		show_info 'libcurl does not need updating.'
#	else
#		show_info 'Downloading libcurl...'
#		FILENAME=$LIBCURL_SOURCE ; download_this
#		show_info 'Installing libcurl...'
#		( gzip -dc $LIBCURL_SOURCE | tar -xf - ) || die
#		CFLAGS="${CFLAGS} -I${SUPPORT}/include ${INCADD} -g"
#		CPPFLAGS="${CFLAGS}"
#		LDFLAGS="-L${SUPPORT}/lib -Wl,--rpath -Wl,${SUPPORT}/lib ${LDADD}"
#		export CFLAGS CPPFLAGS LDFLAGS
#		cd $BUILD/curl-7.26.0 || die
#		./configure --prefix=$SUPPORT --disable-file --disable-ldap --disable-ldaps \
#			--disable-dict --disable-telnet --disable-tftp --disable-manual \
#			--enable-thread --disable-sspi --disable-crypto-auth --disable-cookies \
#			--without-libssh2 --without-ca-path --without-libidn \
#			|| die
#		$MAKE $MAKEOPTS || die
#		$MAKE install || die
#		show_info 'Complete.'
#		echo $SUM >$SUMFILE
#		rm -f $CITADEL/citadel-easyinstall.sum 2>/dev/null
#	fi


########################################################################
# Install libcitadel
########################################################################

cd $BUILD || die
FILENAME=libcitadel-easyinstall.sum ; download_this
SUM=`cat libcitadel-easyinstall.sum`
SUMFILE=$SUPPORT/etc/libcitadel-easyinstall.sum
if [ -r $SUMFILE ] ; then
	OLDSUM=`cat $SUMFILE`
else
	OLDSUM=does_not_exist
fi

if [ "$SUM" = "$OLDSUM" ] ; then
	show_info 'libcitadel does not need updating.'
else
	show_info 'Downloading libcitadel...'
	FILENAME=$LIBCITADEL_SOURCE ; download_this
	show_info 'Installing libcitadel...'
	( gzip -dc $LIBCITADEL_SOURCE | tar -xf - ) || die
	cd $BUILD/libcitadel || die
	./configure --prefix=$SUPPORT || die
	$MAKE $MAKEOPTS || die
	$MAKE install || die
	show_info 'Complete.'
	echo $SUM >$SUMFILE
	# Upgrading libcitadel forces the upgrade of programs which link to it
	rm -f $CITADEL/citadel-easyinstall.sum 2>/dev/null
	rm -f $CITADEL/webcit-easyinstall.sum 2>/dev/null
	rm -f $CITADEL/textclient-easyinstall.sum 2>/dev/null
fi


########################################################################
# Install Citadel Server
########################################################################

cd $BUILD || die
if [ x$IS_UPGRADE = xyes ]
then
	show_info 'Upgrading your existing Citadel installation.'
fi

CFLAGS="${CFLAGS} -I${SUPPORT}/include ${INCADD} -g"
CPPFLAGS="${CFLAGS}"
LDFLAGS="-L${SUPPORT}/lib -Wl,--rpath -Wl,${SUPPORT}/lib ${LDADD}"
export CFLAGS CPPFLAGS LDFLAGS

DO_INSTALL_CITADEL=yes
FILENAME=citadel-easyinstall.sum ; download_this
SUM=`cat citadel-easyinstall.sum`
SUMFILE=$CITADEL/citadel-easyinstall.sum
if [ -r $SUMFILE ] ; then
	OLDSUM=`cat $SUMFILE`
else
	OLDSUM=does_not_exist
fi

if [ "$SUM" = "$OLDSUM" ] ; then
	show_info 'Citadel does not need updating.'
	DO_INSTALL_CITADEL=no
fi

if [ $DO_INSTALL_CITADEL = yes ] ; then
	show_info 'Downloading Citadel...'
	FILENAME=$CITADEL_SOURCE ; download_this
	show_info 'Installing Citadel...'
	cd $BUILD || die
	( gzip -dc $CITADEL_SOURCE | tar -xf - ) || die
	cd $BUILD/citadel || die
	./configure --prefix=$CITADEL --with-db=$SUPPORT --with-pam || die
	$MAKE $MAKEOPTS || die
	if [ x$IS_UPGRADE = xyes ]
	then
		show_info 'Performing Citadel upgrade...'
		$MAKE upgrade || die
	else
		show_info 'Performing Citadel install...'
		$MAKE install || die
		useradd -c "Citadel service account" -d $CITADEL -s $CITADEL/citadel citadel 
	fi
	echo $SUM >$SUMFILE
fi


########################################################################
# Install WebCit
########################################################################

cd $BUILD || die
DO_INSTALL_WEBCIT=yes
FILENAME=webcit-easyinstall.sum ; download_this
SUM=`cat webcit-easyinstall.sum`
SUMFILE=$WEBCIT/webcit-easyinstall.sum
if [ -r $SUMFILE ] ; then
	OLDSUM=`cat $SUMFILE`
else
	OLDSUM=does_not_exist
fi

if [ "$SUM" = "$OLDSUM" ] ; then
	show_info 'WebCit does not need updating.'
	DO_INSTALL_WEBCIT=no
fi

if [ $DO_INSTALL_WEBCIT = yes ] ; then
	show_info 'Downloading WebCit...'
	FILENAME=$WEBCIT_SOURCE ; download_this
	show_info 'Installing WebCit...'
	cd $BUILD || die
	( gzip -dc $WEBCIT_SOURCE | tar -xf - ) || die
	cd $BUILD/webcit || die
	./configure --prefix=$WEBCIT --with-libical || die
	$MAKE $MAKEOPTS || die
	rm -fr $WEBCIT/static 2>&1
	$MAKE install || die
	show_info 'Complete.'
	echo $SUM >$SUMFILE
fi


########################################################################
# Install text client
########################################################################

cd $BUILD || die
DO_INSTALL_TEXTCLIENT=yes
FILENAME=textclient-easyinstall.sum ; download_this
SUM=`cat textclient-easyinstall.sum`
SUMFILE=$CITADEL/webcit-easyinstall.sum
if [ -r $SUMFILE ] ; then
	OLDSUM=`cat $SUMFILE`
else
	OLDSUM=does_not_exist
fi

if [ "$SUM" = "$OLDSUM" ] ; then
	show_info 'Citadel text mode client does not need updating.'
	DO_INSTALL_TEXTCLIENT=no
fi

if [ $DO_INSTALL_TEXTCLIENT = yes ] ; then
	show_info 'Downloading the Citadel text mode client...'
	FILENAME=$TEXTCLIENT_SOURCE ; download_this
	show_info 'Installing the Citadel text mode client...'
	cd $BUILD || die
	( gzip -dc $TEXTCLIENT_SOURCE | tar -xf - ) || die
	cd $BUILD/textclient || die
	./configure --prefix=$CITADEL --bindir=$CITADEL || die
	$MAKE $MAKEOPTS || die
	$MAKE install || die
	echo "  Complete."
	echo $SUM >$SUMFILE
fi


########################################################################
# Configure the system
########################################################################

show_info 'Configuring your system ...'

if [ x$IS_UPGRADE = xyes ]
then
	show_info 'Upgrading your existing Citadel installation.'
else
	show_info 'This is a new Citadel installation.'
fi


show_info 'Trying to stop citserver ...'
t=60
while [ $t -gt 0 ]
do
	if [ $t -eq 60 ] ; then
		if systemctl >/dev/null 2>&1
		then
			show_info 'Attempting to stop citserver using systemd'
			systemctl stop citadel >/dev/null 2>&1
		fi
	fi
	if [ $t -eq 55 ] ; then
		echo -en '\r'
		show_info 'Attempting to stop citserver with SIGTERM'
		kill `ps ax | grep citserver | grep -v grep | awk ' { print $1 } '`
	fi
	if [ $t -eq 20 ] ; then
		echo -en '\r'
		show_info 'Attempting to stop citserver with SIGKILL'
		kill -9 `ps ax | grep citserver | grep -v grep | awk ' { print $1 } '`
	fi
	t=`expr $t - 1`
	sleep 1

	if ( ps ax | grep citserver | grep -v grep >/dev/null 2>&1 ) ; then
		echo -en .
	else
		t=0
	fi
done
echo -en '\r'


# We really want Citadel Server to not be running right now.
if ( uname -a | grep -i linux >/dev/null 2>&1 ) ; then
	if ps ax | grep citserver | grep -v grep ; then
		show_alert 'Easy Install was unable to stop citserver, and cannot continue.'
		die
	fi
fi


# Remove old sysvinit scripts
rm -vf /etc/init.d/citadel /etc/rc?.d/???citadel 
if systemctl daemon-reload >/dev/null 2>/dev/null ; then
	show_info 'systemd detected - automatic installation will proceed'
else
	show_alert 'systemd was not found.  You will need to setup and start Citadel Server manually.'
	die
fi


# Install the systemd script
cat >/etc/systemd/system/citadel.service <<!
# Citadel Server unit file created by Easy Install
[Unit]
Description=Citadel Server
After=network.target
[Service]
ExecStart=/usr/local/citadel/citserver
ExecReload=/bin/kill $MAINPID
KillMode=process
Restart=on-failure
LimitCORE=infinity
[Install]
WantedBy=multi-user.target
!


# Start Citadel Server
systemctl enable citadel || die
systemctl start citadel || die


# Run the Citadel Server setup program
/usr/local/citadel/setup </dev/tty >/dev/tty 2>/dev/tty || die


# WebCit can be killed far more brutally with no ill effects
show_info 'Stopping all WebCit instances'
systemctl stop webcit >/dev/null 2>&1
systemctl stop webcits >/dev/null 2>&1
kill -9 `ps ax | grep citserver | grep -v grep | awk ' { print $1 } '` >/dev/null 2>&1
rm -vf /etc/init.d/webcit /etc/rc?.d/???webcit
systemctl daemon-reload >/dev/null 2>/dev/null


# FIXME if there's already a systemd unit file for webcit, don't overwrite it.



# Try to set up WebCit
show_info 'WebCit is a built-in Web service for the Citadel system.'
show_info 'If you are NOT running any other web server on this host,'
show_info 'you can run WebCit on ports 80 and 443.  Otherwise you must'
show_info 'select other ports, such as 8080, 8443, etc.'
echo

WEBCIT_PORT=0
while [ ${WEBCIT_PORT} -le 0 ] >/dev/null 2>&1
do
	show_prompt 'What HTTP port do you want to use for WebCit? '
	read WEBCIT_PORT </dev/tty
	[ ${WEBCIT_PORT} -ge 0 >/dev/null 2>&1 ] || WEBCIT_PORT=0
done

WEBCITS_PORT=0
while [ ${WEBCITS_PORT} -le 0 ] >/dev/null 2>&1
do
	show_prompt 'What HTTPS port do you want to use for WebCit? '
	read WEBCITS_PORT </dev/tty
	[ ${WEBCITS_PORT} -ge 0 >/dev/null 2>&1 ] || WEBCITS_PORT=0
done

sed s/WEBCIT_PORT/${WEBCIT_PORT}/g >/etc/systemd/system/webcit-http.service <<!
[Unit]
Description=Citadel web service
After=citadel.target
[Service]
ExecStart=/usr/local/webcit/webcit -pWEBCIT_PORT uds /usr/local/citadel
ExecReload=/bin/kill $MAINPID
KillMode=process
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
!

sed s/WEBCITS_PORT/${WEBCITS_PORT}/g >/etc/systemd/system/webcit-https.service <<!
[Unit]
Description=Citadel web service with encryption
After=citadel.target
[Service]
ExecStart=/usr/local/webcit/webcit -s -pWEBCITS_PORT uds /usr/local/citadel
ExecReload=/bin/kill $MAINPID
KillMode=process
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
!

# Start WebCit
systemctl enable webcit-http || die
systemctl start webcit-http || die
systemctl enable webcit-https || die
systemctl start webcit-https || die


# Success!
echo
ps ax | grep cit | grep -v grep
show_info 'All finished!  You are ready to log in.'

# Clean up
rm -fr $BUILD
exit 0

########################################################################
# End
########################################################################
