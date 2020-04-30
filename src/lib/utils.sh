load_local_overrides()
{
	local name=${1:?jail name is required}
	local localconf=/usr/local/etc/fortress/$name.conf

	if [ ! -f $localconf ]; then
		echo -n "Missing $localconf. Create it? [Y/n] "
		read RESPONSE
		case $RESPONSE in
			""|[Yy]|[Yy][Ee][Ss])
				cp /usr/local/etc/fortress/SAMPLE.conf $localconf
				$EDITOR $localconf
				;;
			*)
				stderr Cannot continue. Create $localconf -- it should contain zero or more overrides of variables from $CONFIG.
				exit 1
				;;
		esac
	fi

	sync
	. $localconf
}

create_jailconf()
{
	local name=$1
	local mountpoint=$2

	load_local_overrides $name

	local pairs=""
	local x=0
	local i=""
	for i in $PUBLIC_IFACE; do
		if [ "x${pairs}" = "x" ]; then
			pairs="e${x}b_\$name"
		else
			pairs="$pairs, e${x}b_\$name"
		fi
		let x=$x+1
	done

	cat > $mountpoint/jail.conf <<EOF
$name {
	host.hostname = "\$name.$DOMAIN";
	path = "$mountpoint/root";

	mount.devfs;
	mount.fstab = "$mountpoint/fstab";

	vnet;
	vnet.interface = ${pairs};

	exec.system_user = "root";
	exec.jail_user = "root";
	
	exec.clean;
	exec.start = "/bin/sh /etc/rc";
	exec.stop = "/bin/sh /etc/rc.shutdown";
	exec.consolelog = "/var/log/jail_\${name}_console.log";
	exec.prestart += "$JIB addm \${name} $PUBLIC_IFACE";
	exec.poststop += "$JIB destroy \${name}";
}
EOF
}

get_jail_names()
{
	local args=""
	local dataset=$DATASET

	if [ ! -z ${1+is_set} ]; then
		args=",$1"
	fi
	zfs list -r -d1 -oname$args $dataset/jails | tail -n+3 | sed "s@$dataset/jails/@@"
}

needsroot()
{
	if [ $(id -u) -ne 0 ]; then
		stderr "Command requires root privileges"
		exit
	fi
}

stderr()
{
	echo $@ >&2
}

warn()
{
	if [ ${NOWARN:-0} -ne 1 ]; then
		stderr $1
	fi
}

checkrc()
{
	rc=-1
	eval "$*;rc=$?"
	if [ $rc -ne 0 ]; then
		stderr Error running $*
		exit $rc
	fi
}

mp()
{
	zfs get -H mountpoint $1 2>/dev/null | awk '{print $3}'
}

mount_jail()
{
	local MP=$1
	local SMP=$(mp $DATASET/release/$RELEASE/root)
	
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
		chmod 1777 $MP/tmp
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

setupcomplete()
{
	MP=$(mp $DATASET)
	if [ -f $MP/.fortress_setup_complete ]; then
		echo 1
	else
		echo 0
	fi
}

is_running()
{
	local jail=$1

	jls -j $jail >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo 1
	else
		echo 0
	fi
}
