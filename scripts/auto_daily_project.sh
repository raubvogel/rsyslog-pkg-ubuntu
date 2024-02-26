#!/bin/bash
# Build daily snapshot package
# ***current working directory must be project dir (e.g. rsyslog)***

# Note: Launchpad does not work with the git hash inside the version
# number, because it checks if the version number as whole is larger
# than what exists. This obviously is not always the case with hashes.
# As such, we rename the version to todays date and time. It looks like
# this works sufficiently good, even when the source code has the
# "right" (hash-based) version number.

#set -o xtrace  # useful for debugging
#set -v

echo package build for `pwd` $1/$2/$3
date


# params
szPlatform=$1	# trusty, vivid, ...
UPLOAD_PPA=$2	# path of the ppa (e.g. v8-devel)
BRANCH=$3	# branch to use (e.g. master)
		# Note: this must match the tarball branch
CUSTOMBUILD=$4	# Use if set, needed for rebuilds to make unique upload files
CUSTOMBUILD=$4
if [ -z "$CUSTOMBUILD" ]; then
    CUSTOMBUILD=$(date +%Y%m%d%H%M%S)
fi

rm -fv *.orig.tar.gz # clean up if left over, temporary work file!
# only a single .tar.gz must exist at any time
ls -l *.tar.gz # debug output
szSourceFile=`ls *.tar.gz`
szSourceBase=`basename $szSourceFile .tar.gz`
VERSION=`echo $szSourceBase|cut -d- -f2`
CUSTOMBUILD=$CUSTOMBUILD
LAUNCHPAD_VERSION=`echo $VERSION|cut -d. -f1-3`'-'`echo $CUSTOMBUILD`
PROJECT=`echo $szSourceBase | cut -d- -f1`
PROJECT_SONAME=$PROJECT`cat CURR_LIBSONAME`
szReplaceFile="${PROJECT}_$LAUNCHPAD_VERSION"
VERSION_FILE="LAST_VERSION.$BRANCH.$szPlatform"

echo PROJECT $PROJECT
echo PROJECT_SONAME $PROJECT_SONAME
echo VERSION $VERSION
echo LAUNCHPAD_VERSION $LAUNCHPAD_VERSION
echo Platform $szPlatform
echo PPA $PPA
echo UPLOAD_PPA $UPLOAD_PPA

if [ -z "$PROJECT" ]; then
	echo "variable PROJECT is unset" | mutt -s "$0 script error" $RS_NOTIFY_EMAIL
	exit
fi
if [ -z "$PROJECT_SONAME" ]; then
	echo "variable PROJECT_SONAME is unset" | mutt -s "$0 script error" $RS_NOTIFY_EMAIL
	exit
fi
if [ -z "$VERSION" ]; then
	echo "variable VERSION is unsetn" | mutt -s "$0 script error" $RS_NOTIFY_EMAIL
	exit
fi
if [ -z "$szPlatform" ]; then
	echo "variable szPlatform is unset" | mutt -s "$0 script error" $RS_NOTIFY_EMAIL
	exit
fi
if [ -z "$PPA" ]; then
	echo "variable PPA is unset" | mutt -s "$0 script error" $RS_NOTIFY_EMAIL
	exit
fi

# $VERSION_FILE must not exist. If it does not exist, an
# error message is emitted (this is OK) and the build is
# done. So you can delete it to trigger a new build.
if [ "$VERSION" == "`cat $VERSION_FILE`" ]; then
	echo "version $VERSION already built, exiting"
	rm *.tar.gz
	exit 0
fi

# clean up any old cruft (if it exists)
rm -f $PROJECT_*.changes
rm -f $PROJECT_*.dsc
rm -f $PROJECT_*.build
rm -f $PROJECT_*.debian.tar.gz
rm -f $PROJECT_*.orig.tar.gz
# Delete LAUNCHPAD_VERSION Dir if it exists and is in the current working directory
if [[ -d "./$LAUNCHPAD_VERSION" ]]; then
	echo "REMOVE existing directory $LAUNCHPAD_VERSION !"
	rm -rf "./$LAUNCHPAD_VERSION"
fi

# BEGIN ACTUAL BUILD PROCESS
tar xfz $szSourceFile
if [ $? -ne 0 ]; then
	echo error extracting source tarball
	exit 1
fi
mv $szSourceFile $szReplaceFile.orig.tar.gz

mv $szSourceBase $LAUNCHPAD_VERSION
cd $LAUNCHPAD_VERSION
ls -l ..
ls -l ../$szPlatform
ls -l ../$szPlatform/$BRANCH
ls -l ../$szPlatform/$BRANCH/debian
cp -rv ../$szPlatform/$BRANCH/debian .
pwd
ls -l

# create dummy changelog entry
echo "$PROJECT ($LAUNCHPAD_VERSION-0adiscon1$szPlatform) $szPlatform; urgency=low" > debian/changelog
echo "" >> debian/changelog
echo "  * daily build" >> debian/changelog
echo "" >> debian/changelog
echo " -- Adiscon package maintainers <adiscon-pkg-maintainers@adiscon.com>  `date -R`" >> debian/changelog 

# Build Source package now!
if [ -v PACKAGE_SIGNING_KEY_ID ]; then
	echo "RUN debuild -S -sa -rfakeroot -k $PACKAGE_SIGNING_KEY_ID
	debuild -S -sa -rfakeroot -k"$PACKAGE_SIGNING_KEY_ID"
else
	echo "RUN debuild -S -sa -rfakeroot -us -uc
        debuild -S -sa -rfakeroot -us -uc
fi
if [ $? -ne 0 ]; then
	echo "fail in debuild for $PROJECT_SONAME $VERSION on $szPlatform - check cron mail for details" | mutt -s "$PROJECT_SONAME daily build failed!" $RS_NOTIFY_EMAIL
        exit 1
fi

# we now need to climb out of the working tree, all distributable
# files are generated in the home directory.
cd ..

if [ -v PACKAGE_SIGNING_KEY_ID ]; then
	# This only works on bash >4.2 note no $ before the variable name
	# If there is a key defined, upload changes to PPA now!
	echo "Upload to $PPA/$UPLOAD_PPA"
	debsign -k $PACKAGE_SIGNING_KEY_ID `ls *.changes`
	dput -f $PPA/$UPLOAD_PPA `ls *.changes`
	if [ $? -ne 0 ]; then
	         echo "fail in dput, PPA upload to Launchpad failed" | mutt -s "$PROJECT_SONAME daily build failed!" $RS_NOTIFY_EMAIL
		exit 1
	fi
	#cleanup
	echo $VERSION >$VERSION_FILE
	#exit # do this for testing
	rm -rf $LAUNCHPAD_VERSION
	rm -v $szReplaceFile*.dsc $szReplaceFile*.build $szReplaceFile*.changes $szReplaceFile*.upload *.tar.gz
fi
