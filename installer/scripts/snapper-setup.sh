#!/bin/bash
# Snapper + btrfs snapshot setup. Distro-aware package install; snap-pac (the
# pacman hook) only exists on Arch, so it is installed there alone.
. "$(dirname "${BASH_SOURCE[0]}")/pkgmanager.sh"

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

echo "Installing snapper ..."
pkg_install snapper
[ "$HYPRTK_PM" = pacman ] && pkg_install snap-pac

# 1. Create the initial configuration for root
# This will likely fail if /etc/snapper/configs/root exists, so we ignore errors
snapper -c root create-config /

# 2. Fix the subvolume layout for rollbacks
# Snapper creates a directory at /.snapshots. We want a Btrfs subvolume there instead.
echo "Reconfiguring /.snapshots as a Btrfs subvolume..."
umount /.snapshots 2>/dev/null
rm -rf /.snapshots
mkdir /.snapshots
mount -a # Ensure fstab is clean or mount manually

# Create the subvolume (assuming / is your btrfs mount point)
btrfs subvolume create /.snapshots

# 3. Set permissions
chmod 750 /.snapshots
chown :root /.snapshots

# 4. Configure Snapshot Retention (Optional but recommended)
echo "Updating retention policies in /etc/snapper/configs/root..."
sed -i 's/TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="5"/' /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_WEEKLY="0"/TIMELINE_LIMIT_WEEKLY="0"/' /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_MONTHLY="10"/TIMELINE_LIMIT_MONTHLY="0"/' /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_YEARLY="10"/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root

# 5. Enable Snapper Timers
echo "Enabling snapper timeline and cleanup timers..."
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

echo "-------------------------------------------------------"
echo "Setup Complete!"
echo "Your root snapshots are stored in /.snapshots (as a subvolume)."
echo "Snap-pac (where available) will now snapshot before/after package operations."
echo "-------------------------------------------------------"
