#!/bin/sh


error()
{
	echo $@ >&2
	exit 1
}

if [ $# -ne 1 ]; then
	error Usage: $0 jailname
fi

# Create a new interface to the bridge
new=$( ifconfig epair create ) || error Creating epair failed

# Rename the new interface
ifconfig $new name "epa_$1" || error Renaming $new failed
ifconfig ${new%a}b name "epb_$1" || error Renaming ${new%a}b failed
ifconfig "epa_$1" up || error Error brining up 
ifconfig "epb_$1" up || return
