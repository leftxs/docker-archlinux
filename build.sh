#!/bin/bash
set -e

# Change your to your user if this is a unique new image.
USER="hoverbear"

# Dependencies
function check () {
	hash $1 &>/dev/null || {
			echo "Could not find $1."
			exit 1
	}
}
check gpg
check docker
check curl

###
# Make some space
###
mkdir archbuild
cd archbuild

###
# Get the Image
###
VERSION=$(curl https://mirrors.kernel.org/archlinux/iso/latest/ | grep -Poh '(?<=archlinux-bootstrap-)\d*\.\d*\.\d*(?=\-x86_64)' | head -n 1)
curl https://mirrors.kernel.org/archlinux/iso/latest/archlinux-bootstrap-$VERSION-x86_64.tar.gz > archlinux-bootstrap-$VERSION-x86_64.tar.gz
curl https://mirrors.kernel.org/archlinux/iso/latest/archlinux-bootstrap-$VERSION-x86_64.tar.gz.sig > archlinux-bootstrap-$VERSION-x86_64.tar.gz.sig
# Pull Pierre Schmitz PGP Key.
# http://pgp.mit.edu:11371/pks/lookup?op=vindex&fingerprint=on&exact=on&search=0x4AA4767BBC9C4B1D18AE28B77F2D434B9741E8AC
gpg --keyserver pgp.mit.edu --recv-keys 9741E8AC
# Verify its integrity.
gpg --verify archlinux-bootstrap-$VERSION-x86_64.tar.gz.sig
VALID=$?
if [[ $VALID == 1 ]]; then
	echo "Verification Failed";
	exit 1;
fi

# Extract
tar xf archlinux-bootstrap-$VERSION-x86_64.tar.gz > /dev/null

###
# Do necessary install steps.
###
sudo ./root.x86_64/bin/arch-chroot root.x86_64 << EOF
	# Setup a mirror.
	echo 'Server = https://mirrors.kernel.org/archlinux/\$repo/os/\$arch' > /etc/pacman.d/mirrorlist
	# Setup Keys
	pacman-key --init
	pacman-key --populate archlinux
	# Base without the following packages, to save space.
	# linux jfsutils lvm2 cryptsetup groff man-db man-pages mdadm pciutils pcmciautils reiserfsprogs s-nail xfsprogs vi
	pacman -Syu --noconfirm bash bzip2 coreutils device-mapper dhcpcd gcc-libs gettext glibc grep gzip inetutils iproute2 iputils less libutil-linux licenses logrotate psmisc sed shadow sysfsutils systemd-sysvcompat tar texinfo usbutils util-linux which
	# Pacman doesn't let us force ignore files, so clean up.
	pacman -Scc --noconfirm
	# Install stuff
	echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
	locale-gen
	exit
EOF

###
# udev doesnt work in containers, rebuild /dev
# Taken from https://raw.githubusercontent.com/dotcloud/docker/master/contrib/mkimage-arch.sh
###
DEV=root.x86_64/dev
sudo bash << EOF
	rm -rf $DEV
	mkdir -p $DEV
	mknod -m 666 $DEV/null c 1 3
	mknod -m 666 $DEV/zero c 1 5
	mknod -m 666 $DEV/random c 1 8
	mknod -m 666 $DEV/urandom c 1 9
	mkdir -m 755 $DEV/pts
	mkdir -m 1777 $DEV/shm
	mknod -m 666 $DEV/tty c 5 0
	mknod -m 600 $DEV/console c 5 1
	mknod -m 666 $DEV/tty0 c 4 0
	mknod -m 666 $DEV/full c 1 7
	mknod -m 600 $DEV/initctl p
	mknod -m 666 $DEV/ptmx c 5 2
	ln -sf /proc/self/fd $DEV/fd
EOF

###
# Build the container., Import it.
###
sudo bash << EOF
	tar --numeric-owner -C root.x86_64 -c .  | docker import - $USER/archlinux
EOF

###
# Test run
###
docker run --rm=true $USER/archlinux echo "Success, $USER/archlinux prepared."
