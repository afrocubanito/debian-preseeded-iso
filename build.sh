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

if [ "$1" = "--help" ] || [ "$1" = "-h" ]
then
    echo "Usage: $0 [hostname [debian.iso [debian-preseeded.iso [preseed.cfg]]]]"
fi

HOSTNAME="${1:-debian}"
SOURCE="${2:-debian.iso}"
DEST="${3:-debian-preseeded.iso}"
PRESEED="${4:-preseed.cfg}"

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
cat "$PRESEED" | SUITE="jessie"  TARGETNAME=$HOSTNAME CREATEUSER=1 ./mo > "$TMP/preseed-jessie-autouser.cfg"
cat "$PRESEED" | SUITE="stretch" TARGETNAME=$HOSTNAME CREATEUSER=1 ./mo > "$TMP/preseed-stretch-autouser.cfg"
unset CREATEUSER
cat "$PRESEED" | SUITE="jessie"  TARGETNAME=$HOSTNAME              ./mo > "$TMP/preseed-jessie-manualuser.cfg"
cat "$PRESEED" | SUITE="stretch" TARGETNAME=$HOSTNAME              ./mo > "$TMP/preseed-stretch-manualuser.cfg"

echo "Copying preseed data files..."
cp -r preseed "$TMP"

pushd "$TMP" > /dev/null
echo "Update isolinux config..."

cat >> isolinux/txt.cfg <<EOE
label install-jessie-manualuser
	menu label ^Install Jessie $HOSTNAME (manual user)
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz auto=true file=/cdrom/preseed-jessie-manualuser.cfg
EOE

cat >> isolinux/txt.cfg <<EOE
label install-jessie-autouser
	menu label ^Install Jessie $HOSTNAME (auto Valdor user)
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz auto=true file=/cdrom/preseed-jessie-autouser.cfg
EOE

cat >> isolinux/txt.cfg <<EOE
label install-stretch-autouser
	menu label ^Install Stretch $HOSTNAME (manual user)
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz auto=true file=/cdrom/preseed-stretch-manualuser.cfg
EOE

cat >> isolinux/txt.cfg <<EOE
label install-stretch-autouser
	menu label ^Install Stretch $HOSTNAME (auto Valdor user)
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz auto=true file=/cdrom/preseed-stretch-autouser.cfg
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
