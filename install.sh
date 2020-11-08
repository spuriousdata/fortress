#!/bin/sh

: ${PREFIX:=/usr/local}
: ${STAGEPREFIX:=""}
: ${JIBPATH:=${PREFIX}/scripts/jib}
: ${JIBSRC:=/usr/share/examples/jails/jib}

D=$(dirname $(realpath $0))
INSTALLPATH=${STAGEPREFIX}${PREFIX}
JIBINSTALLPATH=$(dirname ${STAGEPREFIX}${JIBPATH})


if [ ! -d $JIBINSTALLPATH ]; then
	mkdir -p $JIBINSTALLPATH
fi

if [ ! -d $INSTALLPATH/etc/fortress ]; then
	mkdir -p $INSTALLPATH/etc/fortress
fi

if [ ! -d $INSTALLPATH/lib/fortress ]; then
	mkdir -p $INSTALLPATH/lib/fortress
fi

if [ ! -d $INSTALLPATH/sbin ]; then
	mkdir -p $INSTALLPATH/sbin
fi

T=$(mktemp) || exit 1

install -m555 $D/src/fortress  $INSTALLPATH/sbin/fortress
install -m555 $JIBSRC $JIBINSTALLPATH
install -m644 $D/src/lib/* $INSTALLPATH/lib/fortress
sed -e "s@{{JIB}}@JIB=$JIBPATH@" < $D/src/fortress.conf.sample.tmpl > $T
install -m644 $T $INSTALLPATH/etc/fortress.conf.sample
install -m644 $D/src/SAMPLE.conf $INSTALLPATH/etc/fortress/SAMPLE.conf
install -m644 $D/src/SAMPLE.fstab $INSTALLPATH/etc/fortress/SAMPLE.fstab
rm $T
