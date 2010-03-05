#!/bin/bash

if test -z "$MYSQL_SRC"
then
    echo "MYSQL_SRC variable pointing at MySQL/wsrep sources is not set. Can't continue."
    exit -1
fi

usage()
{
    echo -e "Usage: build.sh [OPTIONS] \n" \
"Options:                      \n" \
"    --stage <initial stage>   \n" \
"    --last-stage <last stage> \n" \
"    -s|--scratch    build everything from scratch\n"\
"    -c|--configure  reconfigure the build system (implies -s)\n"\
"    -b|--bootstap   rebuild the build system (implies -c)\n"\
"    -o|--opt        configure build with debug disabled (implies -c)\n"\
"    -m32/-m64       build 32/64-bit binaries on x86\n"\
"    -d|--debug      configure build with debug enabled (implies -c)\n"\
"    --with-spread   configure build with Spread (implies -c)\n"\
"    --no-strip      prevent stripping of release binaries\n"\
"    -r|--release <galera release>, otherwise revisions will be used\n"\
"    -p|--package    create Debian packages\n"
"    --sb|--skip-build skip the actual build, use the existing binaries"
"\n -s and -b options affect only Galera build.\n"
}

# Initializing variables to defaults
uname -m | grep -q i686 && CPU=pentium || CPU=amd64
DEBUG=no
NO_STRIP=no
RELEASE=""
TAR=no
PACKAGE=no
INSTALL=no
CONFIGURE=no
SKIP_BUILD=no

GCOMM_IMPL=${GCOMM_IMPL:-"galeracomm"}

# Parse command line
while test $# -gt 0
do
    case $1 in
        -b|--bootstrap)
            BOOTSTRAP="yes" # Bootstrap the build system
            ;;
        -c|--configure)
            CONFIGURE="yes" # Reconfigure the build system
            ;;
        -s|--scratch)
            SCRATCH="yes"   # Build from scratch (run make clean)
            ;;
        -o|--opt)
            OPT="yes"       # Compile without debug
            ;;
        -d|--debug)
            DEBUG="yes"     # Compile with debug
            NO_STRIP="yes"  # Don't strip the binaries
            ;;
        -r|--release)
            RELEASE="$2"    # Compile without debug
            shift
            ;;
        -t|--tar)
            TAR="yes"       # Create a TGZ package
            ;;
        -i|--install)
            INSTALL="yes"
            ;;
        -p|--package)
            PACKAGE="yes"   # Create a DEB package
            ;;
        --no-strip)
            NO_STRIP="yes"  # Don't strip the binaries
            ;;
        --with*-spread)
            WITH_SPREAD="$1"
            ;;
        -m32)
            CFLAGS="$CFLAGS -m32"
            CXXFLAGS="$CXXFLAGS -m32"
            CONFIGURE="yes"
            CPU="pentium"
            ;;
        -m64)
            CFLAGS="$CFLAGS -m64"
            CXXFLAGS="$CXXFLAGS -m64"
            CONFIGURE="yes"
            CPU="amd64"
            ;;
        --sb|--skip-build)
            SKIP_BUILD="yes"
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unrecognized option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

if [ "$OPT"     == "yes" ]; then CONFIGURE="yes"; fi
if [ "$DEBUG"   == "yes" ]; then CONFIGURE="yes"; fi
if [ "$INSTALL" == "yes" ]; then TAR="yes"; fi
if [ "$SKIP_BUILD" == "yes" ]; then CONFIGURE="no"; fi

# export command options for Galera build
export BOOTSTRAP CONFIGURE SCRATCH OPT DEBUG WITH_SPREAD CFLAGS CXXFLAGS \
       PACKAGE CPU SKIP_BUILD RELEASE

set -eu

# Absolute path of this script folder
BUILD_ROOT=$(cd $(dirname $0); pwd -P)
GALERA_SRC=${GALERA_SRC:-$BUILD_ROOT/../../}
# Source paths are either absolute or relative to script, get absolute
MYSQL_SRC=$(cd $MYSQL_SRC; pwd -P; cd $BUILD_ROOT)
GALERA_SRC=$(cd $GALERA_SRC; pwd -P; cd $BUILD_ROOT)

######################################
##                                  ##
##          Build Galera            ##
##                                  ##
######################################
# Also obtain SVN revision information
if [ "$TAR" == "yes" ]
then
    cd $GALERA_SRC
    GALERA_REV=$(svnversion | sed s/\:/,/g)
    export GALERA_VER=${RELEASE:-$GALERA_REV}

    scripts/build.sh # options are passed via environment variables
fi

######################################
##                                  ##
##           Build MySQL            ##
##                                  ##
######################################
# Obtain MySQL version and revision of Galera patch
cd $MYSQL_SRC
MYSQL_REV=$(bzr revno)
# this does not work on an unconfigured source MYSQL_VER=$(grep '#define VERSION' $MYSQL_SRC/include/config.h | sed s/\"//g | cut -d ' ' -f 3 | cut -d '-' -f 1-2)
MYSQL_VER=$(grep AM_INIT_AUTOMAKE\(mysql, configure.in | awk '{ print $2 }' | sed s/\)//)

if [ "$PACKAGE" == "yes" ] # fetch and patch pristine sources
then
    cd /tmp
    mysql_tag=mysql-$MYSQL_VER
    if [ "$SKIP_BUILD" == "no" ] || [ ! -d $mysql_tag ]
    then
        mysql_orig_tar_gz=$mysql_tag.tar.gz
#        url=http://ftp.sunet.se/pub/unix/databases/relational/mysql/Downloads/MySQL-5.1
        url=http://mysql.dataphone.se/Downloads/MySQL-5.1
#        url=http://anduin.linuxfromscratch.org/sources/BLFS/svn/m
        echo "Downloading $mysql_orig_tar_gz... currently works only for 5.1.x"
        wget -N $url/$mysql_orig_tar_gz
        echo "Getting wsrep patch..."
        patch_file=$(${BUILD_ROOT}/get_patch.sh $mysql_tag $MYSQL_SRC)
        echo "Patching source..."
        rm -rf $mysql_tag # need clean sources for a patch
        tar -xzf $mysql_orig_tar_gz
        cd $mysql_tag/
        patch -p1 -f < $patch_file >/dev/null || :
        chmod a+x ./BUILD/*wsrep
        CONFIGURE="yes"
    else
        cd $mysql_tag/
    fi
    MYSQL_SRC=$(pwd -P)
    if [ "$CONFIGURE" == "yes" ]
    then
        echo "Regenerating config files"
        time ./BUILD/autorun.sh
    fi
fi

echo  "Building mysqld"

export MYSQL_REV
export GALERA_REV
if [ "$SKIP_BUILD" == "no" ]
then
    if [ "$CONFIGURE" == "yes" ]
    then
        rm -f config.status
        if [ "$DEBUG" == "yes" ]
        then
            DEBUG_OPT="-debug"
        else
            DEBUG_OPT=""
        fi

        export MYSQL_BUILD_PREFIX="/usr"
        BUILD/compile-${CPU}${DEBUG_OPT}-wsrep > /dev/null
    else  # just recompile and relink with old configuration
        #set -x
        make > /dev/null
        #set +x
    fi
fi # SKIP_BUILD

# gzip manpages
# this should be rather fast, so we can repeat it every time
if [ "$PACKAGE" == "yes" ]
then
    cd $MYSQL_SRC/man && for i in *.1 *.8; do gzip -c $i > $i.gz; done || :
fi

######################################
##                                  ##
##      Making of demo tarball      ##
##                                  ##
######################################

if [ $TAR == "yes" ]; then
echo "Creating demo distribution"
# Create build directory structure
DIST_DIR=$BUILD_ROOT/dist
MYSQL_DIST_DIR=$DIST_DIR/mysql
MYSQL_DIST_CNF=$MYSQL_DIST_DIR/etc/my.cnf
GALERA_DIST_DIR=$DIST_DIR/galera
cd $BUILD_ROOT
rm -rf $DIST_DIR

# Install required MySQL files in the DIST_DIR
MYSQL_LIBS=$MYSQL_DIST_DIR/lib/mysql
mkdir -p $MYSQL_LIBS
MYSQL_PLUGINS=$MYSQL_DIST_DIR/lib/mysql/plugin
mkdir -p $MYSQL_PLUGINS
install -m 644 LICENSE $DIST_DIR
install -m 755 mysql-galera $DIST_DIR
install -m 644 LICENSE.mysql $MYSQL_DIST_DIR
install -m 644 README $DIST_DIR
install -m 644 QUICK_START $DIST_DIR
install -D -m 644 $MYSQL_SRC/sql/share/english/errmsg.sys $MYSQL_DIST_DIR/share/mysql/english/errmsg.sys
install -D -m 755 $MYSQL_SRC/sql/mysqld $MYSQL_DIST_DIR/libexec/mysqld
install -D -m 755 $MYSQL_SRC/libmysql/.libs/libmysqlclient.so $MYSQL_LIBS
install -D -m 755 $MYSQL_SRC/storage/innodb_plugin/.libs/ha_innodb_plugin.so $MYSQL_PLUGINS
install -D -m 755 $MYSQL_SRC/client/.libs/mysql       $MYSQL_DIST_DIR/bin/mysql
install -D -m 755 $MYSQL_SRC/client/.libs/mysqldump   $MYSQL_DIST_DIR/bin/mysqldump
install -D -m 755 $MYSQL_SRC/client/.libs/mysqladmin     $MYSQL_DIST_DIR/bin/mysqladmin
install -D -m 755 $MYSQL_SRC/scripts/wsrep_sst_mysqldump $MYSQL_DIST_DIR/bin/wsrep_sst_mysqldump
install -D -m 644 my.cnf $MYSQL_DIST_CNF
cat $MYSQL_SRC/support-files/wsrep.cnf >> $MYSQL_DIST_CNF
tar -xzf mysql_var.tgz -C $MYSQL_DIST_DIR

# Copy required Galera libraries
GALERA_LIBS=$GALERA_DIST_DIR/lib
mkdir -p $GALERA_LIBS
install -m 644 LICENSE.galera $GALERA_DIST_DIR
cp -P $GALERA_SRC/galerautils/src/.libs/libgalerautils.so*   $GALERA_LIBS
cp -P $GALERA_SRC/galerautils/src/.libs/libgalerautils++.so* $GALERA_LIBS
cp -P $GALERA_SRC/gcomm/src/.libs/libgcomm.so* $GALERA_LIBS
cp -P $GALERA_SRC/gcs/src/.libs/libgcs.so* $GALERA_LIBS
cp -P $GALERA_SRC/wsdb/src/.libs/libwsdb.so* $GALERA_LIBS
cp -P $GALERA_SRC/galera/src/.libs/libmmgalera.so* $GALERA_LIBS

# Install vsbes stuff if it is available
GALERA_SBIN="$GALERA_DIST_DIR/galera/sbin"
    cp -P $GALERA_SRC/galeracomm/common/src/.libs/libgcommcommonpp.so* $GALERA_LIBS && \
    cp -P $GALERA_SRC/galeracomm/transport/src/.libs/libgcommtransportpp.so* $GALERA_LIBS && \
    cp -P $GALERA_SRC/galeracomm/vs/src/.libs/libgcommvspp.so* $GALERA_LIBS && \
    GALERA_SBIN=$GALERA_DIST_DIR/sbin && \
    mkdir -p $GALERA_SBIN && \
    install -D -m 755 $GALERA_SRC/galeracomm/vs/src/.libs/vsbes $GALERA_SBIN/vsbes && \
    install -m 755 vsbes $DIST_DIR || echo "Skipping vsbes"

strip $MYSQL_DIST_DIR/bin/mysql
strip $MYSQL_DIST_DIR/bin/mysqladmin
strip $MYSQL_DIST_DIR/bin/mysqldump
# Strip binaries if not instructed otherwise
if test "$NO_STRIP" != "yes"
then
    strip $GALERA_LIBS/lib*.so
#    if test $GCOMM_IMPL = "galeracomm"
#    then
        strip $GALERA_SBIN/* || echo "skipped"
#    fi
    strip $MYSQL_DIST_DIR/libexec/mysqld
fi

if [ "$RELEASE" != "" ]
then
    GALERA_RELEASE="galera-$RELEASE-$(uname -m)"
else
    GALERA_RELEASE="$MYSQL_REV,$GALERA_REV"
fi
RELEASE_NAME=$(echo mysql-$MYSQL_VER-$GALERA_RELEASE | sed s/\:/_/g)
rm -rf $RELEASE_NAME
mv $DIST_DIR $RELEASE_NAME

# Pack the release
#if [ "$TAR" == "yes" ]
#then
    tar -czf $RELEASE_NAME.tgz $RELEASE_NAME
#fi

if [ "$INSTALL" == "yes" ]
then
    cmd="$GALERA_SRC/tests/scripts/command.sh"
    $cmd stop
    $cmd install $RELEASE_NAME.tgz
fi

fi # if [ $TAR == "yes " ]

get_arch()
{
    if file $MYSQL_SRC/sql/mysqld.o | grep "80386" >/dev/null 2>&1
    then
        echo "i386"
    else
        echo "amd64"
    fi
}

build_packages()
{
    pushd $GALERA_SRC/scripts/mysql

    local ARCH=$(get_arch)
    local WHOAMI=$(whoami)
    local DEB=1

    if test ! -x "$(which dpkg 2>/dev/null)" # distribution test
    then
        DEB=0
        [ "$ARCH" == "amd64" ] && ARCH="x86_64"
    fi

    local STRIP_OPT=""
    [ "$NO_STRIP" == "yes" ] && STRIP_OPT="-g"

    export MYSQL_VER MYSQL_SRC GALERA_SRC RELEASE_NAME
    export WSREP_VER=${RELEASE:-"$MYSQL_REV"}

    echo $MYSQL_SRC $MYSQL_VER $ARCH
    rm -rf $ARCH

    set +e
    if [ $DEB -eq 1 ]
    then #build DEB
        sudo -E /usr/bin/epm -n -m "$ARCH" -a "$ARCH" -f "deb" \
             --output-dir $ARCH $STRIP_OPT mysql-wsrep
    else # build RPM
        (sudo -E /usr/bin/epm -vv -n -m "$ARCH" -a "$ARCH" -f "rpm" \
              --output-dir $ARCH --keep-files -k $STRIP_OPT mysql-wsrep || \
        /usr/bin/rpmbuild -bb --target "$ARCH" "$ARCH/mysql-wsrep.spec" \
              --buildroot="$ARCH/buildroot" )
    fi
    local RET=$?

    sudo /bin/chown -R $WHOAMI.users $ARCH
    set -e

    if [ $RET -eq 0 ] && [ $DEB -eq 0 ]
    then # RPM cleanup (some rpm versions put the package in RPMS)
        test -d $ARCH/RPMS/$ARCH && \
        mv $ARCH/RPMS/$ARCH/*.rpm $ARCH/ 1>/dev/null 2>&1 || :

        rm -rf $ARCH/RPMS $ARCH/buildroot $ARCH/rpms # $ARCH/mysql-wsrep.spec
    fi

    return $RET
}

if [ "$PACKAGE" == "yes" ]
then
    build_packages
fi
#

