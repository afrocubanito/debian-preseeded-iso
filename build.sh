#!/usr/bin/env bash
# Copyright (c) 2000 Your Name <your@address>
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the LICENSE file for more details.

# It's impossible to specify more than two option in the shebang
# Otherwise I would've put #!/usr/bin/env bash -e
set -e

which 7z > /dev/null || {
    echo "You need to install 7z:"
    echo "  * For Fedora: dnf install p7zip-plugins"
    echo "  * For Debian: apt-get install p7zip-full"
    exit 127
} > /dev/stderr

which genisoimage > /dev/null || {
    echo "You need to install genisoimage:"
    echo "  * For Fedora: dnf install genisoimage"
    echo "  * For Debian: apt-get install genisoimage"
    exit 127
} > /dev/stderr

TARGETNAME="debian"
TARGETDOMAIN="srv.inf3.ch"
SOURCE="debian.iso"
DEST="debian-preseeded.iso"
PRESEED="preseed.cfg"
USER="valdor"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]
then
    echo "Usage: $0 [-h hostname ($TARGETNAME)] [-d domain ($TARGETDOMAIN)] [-i source ($SOURCE)] [-o output ($DEST)] [-p preseed file ($PRESEED)] [-u user ($USER)]" >&2
    exit 0
fi


while getopts "h:d:i:o:p:u:" opt; do
  case $opt in
    h)
      TARGETNAME=$OPTARG
      ;;
    d)
      TARGETDOMAIN=$OPTARG
      ;;
    i)
      SOURCE=$OPTARG
      ;;
    o)
      DEST=$OPTARG
      ;;
    p)
      PRESEED=$OPTARG
      ;;
    u)
      USER=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done


if [ ! -f "$SOURCE" ]
then
    echo "error: $SOURCE not found" > /dev/stderr
    exit 127
fi

if [ -f "$DEST" ]
then
    echo "error: $DEST already exists" > /dev/stderr
    exit 127
fi

if [ ! -f "$PRESEED" ]
then
    echo "error: $PRESEED not found" > /dev/stderr
    exit 127
fi

TMP="$(mktemp -d)"

echo "Extracting the iso..."
7z x -o"$TMP" "$SOURCE" > /dev/null

echo "Copying the preseed file..."
cat "$PRESEED" | SUITE="jessie"  TARGETDOMAIN=$TARGETDOMAIN TARGETNAME=$TARGETNAME CREATEUSER=1 FULLUSER=$USER USER=$USER ./mo > "$TMP/preseed-jessie-autouser.cfg"
cat "$PRESEED" | SUITE="stretch" TARGETDOMAIN=$TARGETDOMAIN TARGETNAME=$TARGETNAME CREATEUSER=1 FULLUSER=$USER USER=$USER ./mo > "$TMP/preseed-stretch-autouser.cfg"
unset CREATEUSER FULLUSER USER
cat "$PRESEED" | SUITE="jessie"  TARGETDOMAIN=$TARGETDOMAIN TARGETNAME=$TARGETNAME                                                ./mo > "$TMP/preseed-jessie-manualuser.cfg"
cat "$PRESEED" | SUITE="stretch" TARGETDOMAIN=$TARGETDOMAIN TARGETNAME=$TARGETNAME                                                ./mo > "$TMP/preseed-stretch-manualuser.cfg"

echo "Copying preseed data files..."
mkdir "$TMP/preseed"
cat "preseed/minion" | TARGETDOMAIN=$TARGETDOMAIN TARGETNAME=$TARGETNAME ./mo > "$TMP/preseed/minion"


pushd "$TMP" > /dev/null
echo "Update isolinux config..."

perl -pi -e 's/timeout 0/timeout 150/' isolinux/*.cfg
perl -pi -e 's/\s*menu default//' isolinux/*.cfg

cat >> preseed-stretch-netboot.cfg <<EOC
d-i debian-installer/language         string   en
d-i debian-installer/country          string   GB
d-i debian-installer/locale           string   en_GB.UTF-8
d-i keyboard-configuration/xkb-keymap select   ch(fr)

d-i netcfg/choose_interface           select   auto

d-i netcfg/wireless_wep               string

d-i netcfg/get_hostname               string   newdebian
d-i netcfg/get_domain                 string

d-i netcfg/get_nameservers            string
d-i netcfg/get_ipaddress              string
d-i netcfg/get_netmask                string   255.255.255.0
d-i netcfg/get_gateway                string

d-i preseed/early_command             string   anna-install network-console

d-i network-console/password          password install
d-i network-console/password-again    password install
d-i network-console/start             select   continue
EOC

cat >> isolinux/txt.cfg <<EOE
label install-jessie-manualuser
	menu label ^Install Jessie $TARGETNAME (manual user)
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz auto=true file=/cdrom/preseed-jessie-manualuser.cfg
EOE

cat >> isolinux/txt.cfg <<EOE
label install-jessie-autouser
	menu label ^Install Jessie $TARGETNAME (auto user)
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz auto=true file=/cdrom/preseed-jessie-autouser.cfg
EOE

cat >> isolinux/txt.cfg <<EOE
label install-stretch-autouser
	menu label ^Install Stretch $TARGETNAME (manual user)
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz auto=true file=/cdrom/preseed-stretch-manualuser.cfg
EOE

cat >> isolinux/txt.cfg <<EOE
label install-stretch-autouser
	menu label ^Install Stretch $TARGETNAME (auto user)
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz auto=true file=/cdrom/preseed-stretch-autouser.cfg
EOE

cat >> isolinux/txt.cfg <<EOE
label install-stretch-netinstall
	menu label ^Install Stretch $TARGETNAME (netinstall)
	menu default
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz auto=true file=/cdrom/preseed-stretch-netboot.cfg
EOE

echo "Update the checksums..."
find -follow -type f -print0 | xargs --null md5sum > md5sum.txt
popd > /dev/null

echo "Generate the iso..."
genisoimage -o "$DEST" -r -J -quiet -no-emul-boot -boot-load-size 4 \
    -boot-info-table -b isolinux/isolinux.bin -c isolinux/boot.cat "$TMP"

echo "Removing the temporary directory..."
rm -rf "$TMP"

echo "Done..."
