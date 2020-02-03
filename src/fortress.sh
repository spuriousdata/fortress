#!/bin/sh

#set -x

FTPHOST=http://ftp.freebsd.org/pub/FreeBSD/releases/$(uname -m)
#SETS="base.txz lib32.txz ports.txz src.txz"
SETS="base.txz lib32.txz src.txz"
EUID=$(id -u)

PV=$(which pv)
if [ $? -ne 0 ]; then
	PV=""
fi
	

if [ -f ./fortress.conf ]; then
	. ./fortress.conf
fi

if [ -f /usr/local/etc/fortress.conf ]; then
	. /usr/local/etc/fortress.conf
fi


usage()
{
	stderr $0 "[setup|create|destroy|list|start|stop|restart|update|etcupdate|console]"
}

stderr()
{
	echo $@ >&2
}

mp()
{
	zfs get -H mountpoint $1 | awk '{print $3}'
}

setup()
{
	needsroot

	zfs list $DATASET > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo -n "fortress dataset '$DATASET' does not exist. Should I create it? [y/N]: "
		read RESPONSE
		case $RESPONSE in
			[Yy]|[Yy][Ee][Ss])
				zfs create -po mountpoint=/fortress $DATASET
				;;
			*)
				exit
				;;
		esac
	fi


	FS="jails sets/$RELEASE release/$RELEASE/root"
	
	for F in $FS
	do
		zfs list $DATASET/$F > /dev/null 2>&1
		if [ $? -ne 0 ]; then 
			zfs create -p $DATASET/$F
		fi
	done

	MP=$(mp $DATASET/sets/$RELEASE)
	RMP=$(mp $DATASET/release/$RELEASE)
	for SET in $SETS
	do
		if [ ! -f $MP/$SET ]; then
			echo Fetching $SET
			fetch -o $MP/$SET $FTPHOST/$RELEASE/$SET
		fi
	done
	
	for SET in $SETS
	do
		if [ -f $RMP/.fortress_extracted_$SET ]; then
			continue
		fi
		if [ $PV = "" ]; then 
			tar -C $RMP/root -xJf $MP/$SET
		else
			echo Extracting $MP/$SET in $RMP/root
			cat $MP/$SET | $PV -s $(stat -f %z $MP/$SET) | tar -C $RMP/root -xJf-
		fi
		
		touch $RMP/.fortress_extracted_$SET
	done
	
	if [ ! -d $RMP/root/etcupdate ]; then
		mkdir $RMP/root/etcupdate
	fi
	
	
	echo Checking for $RMP/root/etcupdate
	if [ ! -f $RMP/root/etcupdate/etcupdate-$RELEASE.tbz ]; then
		mount -t devfs devfs $RMP/root/dev
		chroot $RMP/root etcupdate build /etcupdate/etcupdate-$RELEASE.tbz
		umount $RMP/root/dev
	fi
}

mount_jail()
{
	local MP=$1
	
	SMP=$(mp $DATASET/release/$RELEASE/root)
	
	if [ ! -e $MP/var/ports ]; then
		mkdir -p $MP/var/ports
		mkdir -p $MP/var/ports/distfiles
		mkdir -p $MP/var/ports/packages
	fi
	
	if [ ! -e $MP/var/db ]; then
		mkdir $MP/var/db
	fi
	
	if [ ! -e $MP/compat ]; then
		mkdir $MP/compat
	fi
	
	if [ ! -e $MP/usr/obj ]; then
		mkdir -p $MP/usr/obj
	fi
	
	for _d in $MOUNT; do
		mount -t nullfs -o ro $SMP/$_d $MP/$_d
	done
	
	if [ ! -d $MP/dev ]; then
		mkdir $MP/dev
	fi
	mount -t devfs devfs $MP/dev
	
	if [ ! -d $MP/tmp ]; then
		mkdir $MP/tmp
	fi
	mount -t tmpfs tmpfs $MP/tmp
}

umount_jail()
{
	local MP=$1
	
	for _d in $MOUNT; do
		umount $MP/$_d
	done
	umount $MP/dev
	umount $MP/tmp
}

needsroot()
{
	if [ $EUID -ne 0 ]; then
		echo "create requires root privileges"
		exit
	fi
}

create()
{
	needsroot

	load_local_overrides $1
	
	local name=${1:?jail name is required}
	
	zfs list $DATASET/jails/$name > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		stderr "Jail $name already exists"
		return
	fi
	
	zfs create $DATASET/jails/$name
	zfs create $DATASET/jails/$name/root
	
	MP=$(mp $DATASET/jails/$name)
	
	for _d in $MOUNT; do
		mkdir -p $MP/root/$_d
	done
	
	RMP=$(mp $DATASET/release/$RELEASE/root)
	cd $RMP/etc && find . | cpio -dp --quiet $MP/root/etc
	cd $RMP/root && find . | cpio -dp --quiet $MP/root/root
	cp /etc/localtime $MP/root/etc

	cat > $MP/root/etc/rc.conf <<EOF
hostname=$name
cron_flags="-J 15"

$IFCONFIG

# Disable Sendmail by default
sendmail_enable="NONE"
sendmail_submit_enable="NO"
sendmail_outbound_enable="NO"
sendmail_msp_queue_enable="NO"

# Run secure syslog
syslogd_flags="-c -ss"
EOF

	if [ ! -z ${RESOLV_CONF+is_set} ]; then
		cat > $MP/root/etc/resolv.conf <<EOF
$RESOLV_CONF
EOF
	fi
	
	mount_jail $MP/root
	chroot $MP/root etcupdate extract -t /etcupdate/etcupdate-$RELEASE.tbz
	umount_jail $MP/root

	cat > $MP/jail.conf <<EOF
$name {
	host.hostname = "\$name.$DOMAIN";
	path = "$MP/root";

	mount.devfs;
	mount.fstab = "$MP/fstab";

	vnet;
	vnet.interface = "e0b_\$name";

	exec.system_user = "root";
	exec.jail_user = "root";
	
	exec.clean;
	exec.start = "/bin/sh /etc/rc";
	exec.stop = "/bin/sh /etc/rc.shutdown";
	exec.consolelog = "/var/log/jail_\${name}_console.log";
	exec.prestart += "/usr/local/scripts/jib addm \${name} $PUBLIC_IFACE";
	exec.poststop += "/usr/local/scripts/jib destroy \${name}";
}
EOF

	SMP=$(mp $DATASET/release/$RELEASE/root)
	(echo "#Device Mountpoint FStype Options Dump Pass"
	 for _d in $MOUNT; do
		echo $SMP/$_d $MP/root/$_d nullfs ro 0 0
	 done) | column -t > $MP/fstab
}

destroy()
{
	needsroot

	local name=${1:?jail name is required}

	jls -j $name >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo Stopping $name...
		stop $name
	fi
	
	MP=$(mp $DATASET/jails/$name)
	
	echo -n "Are you sure you want to destroy $MP? [y/N]: "
	read RESP
	RESP=${RESP:-N}
	if [ $RESP = 'y' -o $RESP = 'Y' ]; then
		zfs destroy $DATASET/jails/$name/root
		zfs destroy $DATASET/jails/$name
	fi
}

list()
{
	(echo JID IP NAME MOUNTPOINT RUNNING
	zfs list -r -d1 -oname,mountpoint $DATASET/jails | tail -n+3 | sed "s@$DATASET/jails/@@" | while read -r name mp
	do
		JID=$(jls -j $name -qn jid 2>/dev/null | cut -f2 -d=)

		if [ "x$JID" != "x" ]; then
			IP=$(jexec $name ifconfig e0b_$name | awk '/inet/{print $2}')
			RUNNING=yes
		else
			_ip=$(grep e0b_$name $mp/root/etc/rc.conf | awk 'match($0, /inet [\.0-9]+/){print substr($0, RSTART+5, RLENGTH-5)}')
			IP=${_ip:=n/a}
			RUNNING=no
			JID=n/a
		fi
		echo $JID $IP $name $mp $RUNNING
	done) | column -t

}

start()
{
	needsroot

	local name=${1:?jail name is required}

	MP=$(mp $DATASET/jails/$name)
	jail -cf $MP/jail.conf
}

stop()
{
	needsroot

	local name=${1:?jail name is required}

	MP=$(mp $DATASET/jails/$name)
	jail -rf $MP/jail.conf $name
}

update()
{
	needsroot

	ZR=$DATASET/release/$RELEASE/root
	R=$(mp $ZR)
	CMD="/usr/sbin/freebsd-update -b $R -d $R/var/db/freebsd-update/ -f $R/etc/freebsd-update.conf --not-running-from-cron"

	zfs list $ZR@pre-update >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "$ZR@pre-update already exists. Delete it first."
		exit 2
	fi

	zfs snap $ZR@pre-update
	if [ $? -ne 0 ]; then
		echo "Error taking snapshot"
		exit 1
	fi

	PAGER=cat $CMD fetch 
	$CMD install 
	if [ $? -eq 0 ]; then
		# rebuild etcupdate-$RELEASE.tbz
		mount -t devfs devfs $R/root/dev
		chroot $R/root etcupdate build /etcupdate/etcupdate-$RELEASE.tbz
		umount $R/root/dev
		echo "Updates installed. Restart jails then run 'fortress.sh etcupdate jail1 jail2 ... jailN'"
	else
		echo "No updates to install"
	fi
}

etcupdate()
{
	# This definitely doesn't do anything because etcupdate does not have access to the new stuff
	for jail in $@
	do
		jexec $jail /usr/sbin/etcupdate -F -t /etcupdate/etcupdate-$RELEASE.tbz
	done
	echo "etcupdate complete. Restart jails a final time"
}

load_local_overrides()
{
	local name=${1:?jail name is required}
	
	if [ -f $name.conf ]; then
		. $name.conf
	fi

	if [ -f /usr/local/etc/fortress/$name.conf ]; then
		. /usr/local/etc/fortress/$name.conf
	fi
}

case $1 in 
	setup)
		shift
		setup $@
		;;
	create)
		shift
		create $@
		;;
	destroy)
		shift
		destroy $@
		;;
	list)
		shift
		list $@
		;;
	start)
		shift
		start $@
		;;
	stop)
		shift
		stop $@
		;;
	restart)
		shift
		stop $@
		start $@
		;;
	update)
		shift
		update $@
		;;
	etcupdate)
		shift
		etcupdate $@
		;;
	console)
		shift
		jexec -l $1 /bin/csh
		;;
	*)
		usage
		;;
esac
