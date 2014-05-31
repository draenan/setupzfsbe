#!/bin/sh
#
# setupzfsbe9.sh
#
# This script performs the initial installation of my server as detailed in the
# "thalia-build.md" build guide document.  It also does some post-config setup,
# but the majority still needs to be done by hand.
#
# Depending on how the initial variables are configured, it can be used for
# either the physical production host, or the virtual dev/test host.
#
# Script is for FreeBSD 9.x only.
#

DISK1="ada0"
DISK2="ada1"

#USE4K="YES"

MNT="/tmp/mnt"
POOL="rpool"
BE="freebsd-92r-p0"
ROOTFS="${POOL}/ROOT/${BE}"

HOSTNAME="thalia-dev"
HOSTIP="192.168.5.160"
HOSTIP6=
HOSTIP_ALIAS="192.168.5.161"
GATEWAY="192.168.5.254"
IF="em0"

DOMAIN="draenan.net"
NAMESERVER="127.0.0.1"
NAMESERVER6="::1"

ATKBD_DISABLED="0"

echo "Preparing disk(s)..."

gpart create -s gpt $DISK1

gpart add -b 40   -s 128K -t freebsd-boot -l boot0 $DISK1
gpart add -b 2048 -s 8G   -t freebsd-swap -l swap0 $DISK1
gpart add                 -t freebsd-zfs  -l disk0 $DISK1

gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 $DISK1

if [ ! -z "$DISK2" ]; then
    gpart create -s gpt $DISK2

    gpart add -b 40   -s 128K -t freebsd-boot -l boot1 $DISK2
    gpart add -b 2048 -s 8G   -t freebsd-swap -l swap1 $DISK2
    gpart add                 -t freebsd-zfs  -l disk1 $DISK2

    gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 $DISK2

    kldload /boot/kernel/geom_mirror.ko
    gmirror label -b prefer swap gpt/swap0 gpt/swap1
fi

echo "Creating $POOL and filesystems..."

if [ ! -e "$MNT" ]; then
    mkdir -p $MNT
fi

if [ -z "$USE4K" ]; then
    if [ -z "$DISK2" ]; then
        zpool create -m none -o cachefile=/var/tmp/zpool.cache $POOL /dev/gpt/disk0
    else
        zpool create -m none -o cachefile=/var/tmp/zpool.cache $POOL mirror /dev/gpt/disk0 /dev/gpt/disk1
    fi
else
    if [ -z "$DISK2" ]; then
        gnop create -S 4096 /dev/gpt/disk0
        zpool create -m none -o cachefile=/var/tmp/zpool.cache $POOL /dev/gpt/disk0.nop
        zpool export $POOL
        gnop destroy /dev/gpt/disk0.nop
    else
        gnop create -S 4096 /dev/gpt/disk0
        gnop create -S 4096 /dev/gpt/disk1
        zpool create -m none -o cachefile=/var/tmp/zpool.cache $POOL mirror /dev/gpt/disk0.nop /dev/gpt/disk1.nop
        zpool export $POOL
        gnop destroy /dev/gpt/disk0.nop
        gnop destroy /dev/gpt/disk1.nop
    fi
    zpool import -o cachefile=/var/tmp/zpool.cache $POOL
fi

zfs set checksum=fletcher4 $POOL

zfs create                                                      ${POOL}/ROOT
zfs create -o mountpoint=${MNT}/${ROOTFS}                       $ROOTFS
zfs create -o mountpoint=none                                   ${POOL}/HOME

zfs create -o compression=on     -o exec=on    -o setuid=off    ${ROOTFS}/tmp
zfs create                                                      ${ROOTFS}/usr
zfs create -o compression=lz4                  -o setuid=off    ${ROOTFS}/usr/ports
zfs create -o compression=off    -o exec=off   -o setuid=off    ${ROOTFS}/usr/ports/distfiles
zfs create -o compression=off    -o exec=off   -o setuid=off    ${ROOTFS}/usr/ports/packages
zfs create -o compression=lz4    -o exec=off   -o setuid=off    ${ROOTFS}/usr/src
zfs create                                                      ${ROOTFS}/var
zfs create -o compression=lz4    -o exec=off   -o setuid=off    ${ROOTFS}/var/crash
zfs create                       -o exec=off   -o setuid=off    ${ROOTFS}/var/db
zfs create -o compression=lz4    -o exec=on    -o setuid=off    ${ROOTFS}/var/db/pkg
zfs create                       -o exec=off   -o setuid=off    ${ROOTFS}/var/empty
zfs create -o compression=lz4    -o exec=off   -o setuid=off    ${ROOTFS}/var/log
zfs create -o compression=lz4    -o exec=off   -o setuid=off    ${ROOTFS}/var/mail
zfs create                       -o exec=off   -o setuid=off    ${ROOTFS}/var/run
zfs create -o compression=lz4    -o exec=on    -o setuid=off    ${ROOTFS}/var/tmp

chmod 1777 ${MNT}/${ROOTFS}/tmp
chmod 1777 ${MNT}/${ROOTFS}/var/tmp
mkdir -p ${MNT}/${ROOTFS}/usr/local/etc

zpool set bootfs=${ROOTFS} $POOL

echo "Installing FreeBSD..."

cd /usr/freebsd-dist
DESTDIR=${MNT}/${ROOTFS}
export DESTDIR
for file in base.txz lib32.txz kernel.txz doc.txz ports.txz src.txz; do
    (cat $file | tar --unlink -xpJf - -C ${DESTDIR:-/})
done;

cp /var/tmp/zpool.cache ${MNT}/${ROOTFS}/boot/zfs/zpool.cache

zfs set readonly=on ${ROOTFS}/var/empty

echo "Configuring files..."

cat > ${MNT}/${ROOTFS}/etc/rc.conf << EOF
zfs_enable="YES"

kldxref_enable="YES"
kldxref_clobber="YES"

hostname="${HOSTNAME}.${DOMAIN}"
ifconfig_${IF}="inet ${HOSTIP} netmask 255.255.255.0"
ifconfig_${IF}_alias0="inet ${HOSTIP_ALIAS} netmask 255.255.255.0"
ifconfig_${IF}_ipv6="inet6 accept_rtadv"
defaultrouter="${GATEWAY}"

firewall_enable="NO"
firewall_script="/usr/local/etc/ipfw/ipfw.rules"
firewall_logging="YES"
firewall_quiet="YES"

sshd_enable="YES"

ntpd_enable="YES"

named_enable="YES"

syslogd_flags="-l /var/db/dhcpd/var/run/log -c"

dhcpd_enable="NO"
dhcpd_flags="-q"
dhcpd_chroot_enable="YES"

apcupsd_enable="NO"
apcupsd_flags=""

fail2ban_enable="NO"

pixelserv_enable="NO"

slapd_enable="NO"
slapd_flags='-h "ldapi://%2fvar%2frun%2fopenldap%2fldapi/ ldap:///"'
slapd_sockets="/var/run/openldap/ldapi"
nscd_enable="YES"

openvpn_enable="NO"
openvpn_tcp_enable="NO"
openvpn_tcp_configfile="/usr/local/etc/openvpn/openvpn_tcp.conf"
gateway_enable="YES"

#devfs_system_ruleset="system"

cupsd_enable="NO"

mdnsd_enable="NO"

netatalk_enable="NO"

samba_enable="NO"
winbindd_enable="NO"

nginx_enable="NO"
php_fpm_enable="NO"
fcgiwrap_enable="NO"
fcgiwrap_user="www"

EOF

sed -e '5,$ d' -i '' ${MNT}/${ROOTFS}/etc/motd
sed -e 's_#Banner none_Banner /etc/banner_' -i '' ${MNT}/${ROOTFS}/etc/ssh/sshd_config

cat > ${MNT}/${ROOTFS}/etc/banner << EOF
+-----------------------------------------------------------------+
| This system is for the use of authorised users only.            |
| Individuals using this computer system without authority, or in |
| excess of their authority, are subject to having all of their   |
| activities on this system monitored and recorded by system      |
| personnel.                                                      |
|                                                                 |
| In the course of monitoring individuals improperly using this   |
| system, or in the course of system maintenance, the activities  |
| of authorised users may also be monitored.                      |
|                                                                 |
| Anyone using this system expressly consents to such monitoring  |
| and is advised that if such monitoring reveals possible         |
| evidence of criminal activity, system personnel may provide the |
| evidence of such monitoring to law enforcement officials.       |
+-----------------------------------------------------------------+
EOF

echo "search_domains=\"${DOMAIN}\"" > ${MNT}/${ROOTFS}/etc/resolvconf.conf
if [ ! -z "$NAMESERVER6" ]; then
    echo "name_servers=\"${NAMESERVER} ${NAMESERVER6}\"" >> ${MNT}/${ROOTFS}/etc/resolvconf.conf
else
    echo "name_servers=\"${NAMESERVER}\"" >> ${MNT}/${ROOTFS}/etc/resolvconf.conf
fi

sed -e "s/localhost.my.domain/localhost.${DOMAIN}/" -i '' ${MNT}/${ROOTFS}/etc/hosts
printf "${HOSTIP}\t${HOSTNAME}\t${HOSTNAME}.${DOMAIN}\n" >> ${MNT}/${ROOTFS}/etc/hosts
if [ ! -z "$HOSTIP6" ]; then
    printf "${HOSTIP6}\t${HOSTNAME}\t${HOSTNAME}.${DOMAIN}\n" >> ${MNT}/${ROOTFS}/etc/hosts
fi

touch ${MNT}/${ROOTFS}/etc/namedb/working/managed-keys.bind
chown bind ${MNT}/${ROOTFS}/etc/namedb/working/managed-keys.bind

cat > ${MNT}/${ROOTFS}/boot/loader.conf << EOF
ahci_load="YES"
zfs_load="YES"
aio_load="YES"
ipfw_load="YES"
amdtemp_load="YES"
geom_eli_load="YES"
hint.atkbdc.0.disabled="${ATKBD_DISABLED}"
hint.atkbd.0.disabled="${ATKBD_DISABLED}"
net.inet.ip.fw.default_to_accept="1"
vfs.root.mountfrom="zfs:${ROOTFS}"
EOF

if [ ! -z "$DISK2" ]; then
    sed -e ' /geom_eli/ a\
geom_mirror_load="YES"' -i '' ${MNT}/${ROOTFS}/boot/loader.conf
fi

cat >> ${MNT}/${ROOTFS}/etc/sysctl.conf << EOF
net.inet.ip.fw.verbose=1
EOF

cat > ${MNT}/${ROOTFS}/etc/make.conf << EOF
CFLAGS= -O2 -fno-strict-aliasing -pipe
NO_PROFILE= true
OPTIONS_UNSET= X11
USE_SVN= true
WITH_PKGNG= yes
EOF

sed -e '/set prompt = / s/".*"/"[%n@%m] %C04 %# "/' \
    -e '/set promptchars/ a\
\	set ellipsis' \
    -e '/set path = / s^set path = (\(.*\)\(/usr/local/sbin /usr/local/bin \)\(.*\))^set path = (\2\1\3)^' \
    -i '' ${MNT}/${ROOTFS}/root/.cshrc

sed -e '/set prompt = / s/".*"/"[%n@%m] %c04 %# "/' \
    -e '/set promptchars/ a\
\	set ellipsis' \
    -e '/set path = / s^set path = (\(.*\)\(/usr/local/sbin /usr/local/bin \)\(.*\))^set path = (\2\1\3)^' \
    -i '' ${MNT}/${ROOTFS}/usr/share/skel/dot.cshrc

sed -e '/PATH=/ s^PATH=\(.*\)\(/usr/local/sbin:/usr/local/bin:\)\(.*\)^PATH=\2\1\3^' \
    -i '' ${MNT}/${ROOTFS}/usr/share/skel/dot.profile

sed -e '/^IgnorePaths/ s^$^ /boot/kernel/linker.hints^' \
    -i '' ${MNT}/${ROOTFS}/etc/freebsd-update.conf

cat > ${MNT}/${ROOTFS}/tmp/chroot.sh << EOF
resolvconf -u
sed -e '/[[:space:]]*:path/ s#:path=\(.*\)\(/usr/local/sbin /usr/local/bin \)\(.*\):\\\\#:path=\2\1\3:\\\\#' -i '' /etc/login.conf
cap_mkdb /etc/login.conf
echo Setting root password...
passwd
tzsetup
echo Configuring mail aliases...
cd /etc/mail; make aliases
chmod 700 /root
EOF

chroot ${MNT}/${ROOTFS} sh /tmp/chroot.sh
rm ${MNT}/${ROOTFS}/tmp/chroot.sh

printf "# Device\t\tMountpoint\tFStype\tOptions\tDump\tPass#\n" >  ${MNT}/${ROOTFS}/etc/fstab
if [ -z "$DISK2" ]; then
    printf "/dev/gpt/swap0\t\tnone\t\tswap\tsw\t0\t0\n" >> ${MNT}/${ROOTFS}/etc/fstab
else
    printf "/dev/mirror/swap\tnone\t\tswap\tsw\t0\t0\n" >> ${MNT}/${ROOTFS}/etc/fstab
fi

if [ -e "./beupdate" ]; then
    if [ ! -e "${MNT}/${ROOTFS}/usr/local/sbin" ]; then
        mkdir -p ${MNT}/${ROOTFS}/usr/local/sbin
    fi
    install -o root -g wheel -m 0750 ./beupdate ${MNT}/${ROOTFS}/usr/local/sbin/beupdate
fi

echo Unmounting ZFS filesystems...

zfs umount -af
zfs set mountpoint=legacy $ROOTFS
zfs set mountpoint=/usr   ${ROOTFS}/usr
zfs set mountpoint=/var   ${ROOTFS}/var
zfs set mountpoint=/tmp   ${ROOTFS}/tmp
zfs umount -af

echo Installation complete.

