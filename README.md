# setupzfsbe9.sh - Install script for FreeBSD 9 with ZFS Boot Environment

*NOTE: This script was only ever intended for FreeBSD 9, and is therefore
obsolete.*

This script performs the initial installation of my home server as detailed in
the *thalia.md* build guide document.  It also does some post-config setup, but
the majority still needs to be done by hand, due to the need to compile ports
with specific options.

Depending on how the initial variables are configured, it can be used for
either the physical host, or the virtual dev/test host.

The initial installation was based on content at
<http://www.aisecure.net/2011/11/28/root-zfs-freebsd9/>,
<http://www.aisecure.net/2012/01/16/rootzfs/>, and
<http://www.leidinger.net/blog/2011/05/03/another-root-on-zfs-howto-optimized-for-4k-sector-drives/>.

This install differs slightly from those described in the above links due to
the adoption of a FreeBSD 10-style zroot, where the root file system is
considered separate to the descendant file systems.  That is, `/usr` and `/var`
are directories in the root filesystem, therefore `canmount` is set to `off`
for the `zroot/usr` and `zroot/var` ZFS file systems.

## How to Use

Configure the relevant variables at the start of the script, copy it into
`/root` on your install media, use the install media to
boot into a shell, run the script.

## Nostalgic Thoughts

This was quite the useful script for me back in the day when I wanted to
rebuild the dev environment quickly, and build the actual server quickly as
well.  But the question of why FreeBSD people never produced a viable
alternative to Linux' Kickstart or Solaris' Jumpstart is one for the ages.  You
can find guides online for PXE-boot based installs, but they require quite
a bit of work and don't support ZFS root filesystems.

