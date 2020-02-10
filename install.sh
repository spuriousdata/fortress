#!/bin/sh


: ${PREFIX:=/usr/local}
: ${STAGEPREFIX:=""}
: ${JIBPATH:=${PREFIX}/scripts/jib}
: ${JIBSRC:=/usr/local/share/examples/jails/jib}

D=$(dirname $(realpath $0))
INSTALLPATH=${STAGEPREFIX}${PREFIX}
JIBINSTALLPATH=$(dirname ${STAGEPREFIX}${JIBPATH})


if [ ! -d $JIBINSTALLPATH ]; then
	mkdir -p $JIBINSTALLPATH
fi

if [ ! -d $INSTALLPATH/etc/fortress ]; then
	mkdir -p $INSTALLPATH/etc/fortress
fi

T=$(mktemp) || exit 1

install -m555 $D/src/fortress  $INSTALLPATH/sbin/fortress
install -m555 $JIBSRC $JIBPATH
sed -e "s@{{JIB}}@JIB=$JIBPATH@" < $D/src/fortress.conf.sample.tmpl > $T
install -m644 $T $INSTALLPATH/etc/fortress.conf.sample
rm $T
