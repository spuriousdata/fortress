fortress
========================

Bare-bones jail manager using mostly built-in tools and methods.

Installation
------------------------
::

    ./install.sh
    
Examine *install.sh* for variables you can override.

Usage
------------------------

Initial Setup
************************

Minimal Configuration
########################

Copy /usr/local/etc/fortress.conf.sample to /usr/local/etc/fortress.conf. Then
set *DATASET* to the zfs dataset in which fortress will keep jails and
configuration and change *PUBLIC_IFACE* to the network interface to which your
jail's vnet will be bridged. You may also want to set *RESOLV_CONF* and
*DOMAIN*.

Do not change *MOUNT* unless you know what you're doing.

Then run::

    root@jailhost:~ # fortress setup

Create a Jail
***********************
Create the file /usr/local/etc/fortress/*JAILNAME*.conf, replacing *JAILNAME* with
the name of your jail. The file can be empty, but you will probably want to at
least define *IFCONFIG*. The variable *$name* will be replaced with your jail's
name when the config is loaded into fortress. The name of the interface inside
the jail will always be e0p_$name.::

    # Content of /usr/local/etc/fortress/JAILNAME.conf
    IFCONFIG=$(cat <<EOM
    ifconfig_e0p_$name="inet 192.168.12.129/24"
    defaultrouter="192.168.12.1"
    EOM
    )

Assuming we we call our new jail *test1* and have created
/usr/local/etc/fortress/test1.conf and set *IFCONFIG* . We can now run::

    root@jailhost:~ # fortress create test1
    
To list all fortress jails you can run::
    
    root@jailhost:~ # fortress list
    JID  IP             NAME   MOUNTPOINT             RUNNING
    n/a  192.168.60.13  test1  /fortress/jails/test1  no

Starting a jail
***********************
Now start your jail::

    root@jailhost:~ # fortress start test1
    Starting test1...
    e0a_test1
    e0b_test1
    
Listing jails
***********************
Once the jail is running you can list the jails with *fortress* or *jls*::

    root@jailhost:~ # fortress list
    JID  IP             NAME   MOUNTPOINT             RUNNING
    11   192.168.60.13  test1  /fortress/jails/test1  yes
    
However, if you use *jls*, it cannot show the IP address of vnet jails::

    root@jailhost:~ # jls
    JID  IP Address      Hostname                      Path
     11                  test1                         /fortress/jails/test1/root
     

Using jails
***********************
Now you can connect to the jail to use it::

    root@jailhost:~ # fortress console test1
    root@test1:~ # ll
    total 18
    -rw-r--r--  1 root  wheel  951 Feb  9 05:02 .cshrc
    -rw-r--r--  1 root  wheel  149 Feb  9 05:02 .k5login
    -rw-r--r--  1 root  wheel  392 Feb  9 05:02 .login
    -rw-r--r--  1 root  wheel  470 Feb  9 05:02 .profile
    root@test1:~ # uname -a
    FreeBSD test1 12.1-RELEASE-p2 FreeBSD 12.1-RELEASE-p2 GENERIC  amd64
    root@test1:~ # exit
    exit
    root@jailhost:~ #
     
Starting all jails at once
**************************
To start all 'automatic' jails at one time run::

    root@jailhost:~ # fortress startall

*startall* will start all jails except those that contain a file (empty or not)
called *NOAUTO*  inside the jail's main directory. For example, to disable our
*test1* jail with the default configuration, we would::

    root@jailhost:~ # touch /fortress/jails/test1/NOAUTO
    
Note that the *NOAUTO* file does not disable direct *start* commands, only
*startall*::

    root@jailhost$ touch /fortress/jails/test1/NOAUTO
    root@jailhost$ fortress startall
    Skipping test1 because /fortress/jails/test1/NOAUTO exists
    root@jailhost$ fortress start test1
    Starting test1...
    e0a_test1
    e0b_test1

Stopping all jails at once
**************************
To stop all running fortress jails::

    root@jailhost:~ # fortress stopall

Destroying jails
***********************
::

    root@jailhost:~ # fortress destroy test1
    Stopping test1...
    Stopping test1...
    Are you sure you want to destroy /fortress/jails/test1? [y/N]: y
    
Updating the base FreeBSD installation used to provide the os directories for
jails::

    root@jailhost:~ # fortress update
    Looking up update.FreeBSD.org mirrors... 3 mirrors found.
    Fetching public key from update2.freebsd.org... done.
    Fetching metadata signature for 12.1-RELEASE from update2.freebsd.org...
    done.
    Fetching metadata index... done.
    Fetching 2 metadata files... done.
    Inspecting system... done.
    Preparing to download files... done.
    Fetching 36 patches.....10....20....30... done.
    Applying patches... done.
    The following files will be updated as part of updating to
    12.1-RELEASE-p2:
    ...
    Installing updates... done.
    Updates installed. Restart jails then run 'fortress.sh etcupdate jail1 jail2 ... jailN'
    
Then run::

    root@jailhost:~ # fortress etcupdate test1
    Warnings:
        Needs update: /etc/localtime (required manual update via tzsetup(8))
    etcupdate complete. Restart jails a final time
    
Then::

    root@jailhost:~ # fortress restart test1
    
Additional Configuration
************************

The jail's configuration is located in */fortress/jails/test1/jail.conf*.
You can also edit */fortress/jails/test1/fstab* to append any additional
mountpoints your jail will need. 
