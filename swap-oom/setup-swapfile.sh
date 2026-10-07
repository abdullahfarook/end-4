#!/bin/sh
set -e
[ -e /swap ] || btrfs subvolume create /swap
[ -e /swap/swapfile ] || btrfs filesystem mkswapfile --size 16G /swap/swapfile
grep -q '^/swap/swapfile' /etc/fstab || echo '/swap/swapfile  none  swap  defaults,pri=10  0 0' >> /etc/fstab
swapon --priority 10 /swap/swapfile
