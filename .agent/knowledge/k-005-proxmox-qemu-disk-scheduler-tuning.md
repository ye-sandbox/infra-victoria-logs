---
id: "k-005"
title: "Proxmox QEMU Virtual Disk Scheduler Tuning and Dual Scheduling Prevention"
date: 2026-10-27
tags:
  - "proxmox"
  - "qemu"
  - "disk-io"
  - "udev"
  - "homelab"
severity: "medium"
affected_components:
  - "scripts/tune-disk-host.sh"
symptoms:
  - "Virtual disk reported as rotational (queue/rotational == 1) inside VM despite host NVMe/SSD"
  - "Double I/O scheduling overhead between guest kernel and host hypervisor"
  - "hdparm ioctl errors when tuning virtual disks"
---

# [k-005] Proxmox QEMU Virtual Disk Scheduler Tuning and Dual Scheduling Prevention

## Problem / Symptom

In Proxmox VE (KVM/QEMU), virtual SCSI/VirtIO disks default to `/sys/block/<dev>/queue/rotational == 1` inside the guest VM unless the `ssd=1` flag is explicitly enabled on the virtual drive hardware configuration in Proxmox.

Naive OS diagnostics incorrectly classify the disk as a mechanical HDD with a spinning spindle, recommending `mq-deadline` or issuing `hdparm` spin-down commands that fail with:

```text
HDIO_DRIVE_CMD(identify) failed: Invalid argument
```

This creates double scheduling overhead: the guest VM queues and reorders I/O, and the host ZFS/ext4 hypervisor queues it a second time.

---

## Approved Solution

1. **Guest I/O Scheduler Passthrough (`none`):**
   For virtualized disks (`/sys/devices/virtual` or QEMU block devices), set the scheduler to `none` (noop) to delegate all I/O queuing to the hypervisor host:
   ```bash
   echo "none" > /sys/block/sda/queue/scheduler
   ```

2. **Udev Rule Lexicographical Precedence:**
   Ensure legacy rules (e.g., `60-hdd-scheduler.rules`) are removed so they do not override modern `60-disk-scheduler.rules`:
   ```bash
   rm -f /etc/udev/rules.d/60-hdd-scheduler.rules
   udevadm trigger --action=change --subsystem-match=block
   ```

3. **Proxmox Hypervisor Flag:**
   In Proxmox VM Hardware settings, check `SSD emulation` (`ssd=1`) on VirtIO SCSI disks so the guest kernel detects non-rotational media automatically.

**Root Cause:** Virtual block devices pass I/O through hypervisor virtual rings. Reordering I/O in the guest kernel wastes CPU cycles and adds latency.

---

## What NEVER to Do
- ❌ **Anti-Pattern:** Running `hdparm -B` or `hdparm -S` on virtual disks (`/dev/vda`, `/dev/sda` under QEMU).
  - *Why:* Virtual disks do not implement ATA power management ioctls; commands fail and clutter system journals.
- ❌ **Anti-Pattern:** Applying `mq-deadline` to virtual block devices backed by host SSDs.
  - *Why:* Causes double queuing without physical head movement optimizations.

---

## Verification
```bash
cat /sys/block/*/queue/scheduler
# Expected for virtual disks: [none]
```

---

## References
- [Proxmox VE Storage Best Practices](https://pve.proxmox.com/wiki/Performance_Tweaks)
