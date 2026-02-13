## Prevent a Monitor from Running in TTY or Early Boot (DDC/CI Power Control)

**This is a very niche hardware issue.**
One of my displays becomes unstable and appears to cause serious self-damage if it is driven at low refresh rates (for example 60 Hz during TTY or early boot). The goal of this workaround is to prevent the panel from being driven in that state by keeping it powered off until the graphical session starts at the correct refresh rate.

Yes, this sounds ridiculous. I thought so too, but it is real in my case.

This is not a general Linux problem and most users will never need to do this. If you only have one display and are experiencing behavior like this, the practical solution is to replace the panel. These directions are mainly intended to prevent further wear or damage while continuing to use the system.

---

## Requirements

Install required tools:

```bash
sudo pacman -S ddcutil i2c-tools
```

Load the I²C device module:

```bash
sudo modprobe i2c-dev
```

Ensure **DDC/CI** is enabled in the monitor’s OSD menu.

---

## Identify the Monitor

Detect displays:

```bash
sudo ddcutil detect
```

Example:

```
Display 2
   DRM_connector: card1-DP-3
   Model: XG2431
```

Note the **Display number** for the monitor you want to control.

---

## Test Power Control

Turn the monitor off:

```bash
sudo ddcutil --display 2 setvcp D6 05
```

Turn it back on:

```bash
sudo ddcutil --display 2 setvcp D6 01
```

If both commands work, automation will work.

---

## Power Off the Monitor Early in Boot

Create a systemd service:

```bash
sudo micro /etc/systemd/system/monitor-off-early.service
```

Contents:

```ini
[Unit]
Description=Power off fragile monitor early in boot (DDC/CI)
DefaultDependencies=no
After=systemd-modules-load.service systemd-udev-settle.service
Wants=systemd-udev-settle.service
Before=getty@tty1.service getty@tty2.service getty@tty3.service display-manager.service

[Service]
Type=oneshot
ExecStartPre=/usr/bin/modprobe i2c-dev
ExecStart=/usr/bin/ddcutil --display 2 setvcp D6 05
TimeoutSec=5
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable monitor-off-early.service
```

Reboot to test.

---

## Power the Monitor Back On in Hyprland

Edit:

```bash
micro ~/.config/hypr/hyprland.conf
```

Add:

```ini
exec-once = ddcutil --display 2 setvcp D6 01
```

If waking is unreliable, use retries:

```ini
exec-once = bash -lc 'for i in 1 2 3 4 5; do ddcutil --display 2 setvcp D6 01 && exit 0; sleep 0.3; done; exit 0'
```

---

## Result

Boot sequence:

1. System boots.
2. The monitor powers off before any TTY or login screen drives it.
3. Hyprland starts.
4. The monitor powers back on at the correct refresh rate.

The panel never runs in the problematic low-refresh console state.

---

## Troubleshooting

Check whether the service ran:

```bash
systemctl status monitor-off-early.service
journalctl -b -u monitor-off-early.service
```

---

## Notes

* Display numbering in `ddcutil` may change if hardware configuration changes.
* Some monitors require multiple attempts to wake from DDC power-off.
* This method does not change TTY refresh rate; it avoids using the monitor during TTY entirely.
* This is a workaround for a hardware-specific issue, not a general recommendation.
