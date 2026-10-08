# Disk layout (nvme0n1, Samsung 980 Pro 1TB, GPT)

Repartitioned 2026-10-08. The empty NTFS `Data` partition was deleted and its space split up.

| Part | Size | FS | Mount |
|---|---|---|---|
| p1 | 2G | vfat (EFI) | /boot/efi |
| p2 | 16M | Microsoft reserved | |
| p3 | 300G | NTFS Windows | |
| p4 | 2G | NTFS Recovery | |
| p6 | 377G (was 300G) | Btrfs CachyOS, grown online with `btrfs filesystem resize max /` | / and subvolumes |
| p5 | 150G | ext4, label `dev` | /mnt/dev (fstab, by UUID; projects in /mnt/dev/projects) |
| p7 | 100.5G | NTFS, label `Data` (shared with Windows) | not in fstab |

Tools: `sfdisk` (delete, resize in place keeping start sector 637569024, append), `partx -u`, `mkfs.ext4`, `mkfs.ntfs` (package `ntfsprogs`).
Pre-change snapshot: snapper #234 "pre-repartition". Old partition table: `~/backups/partition-table/*.sfdisk` (restore: `sfdisk /dev/nvme0n1 < file`).
