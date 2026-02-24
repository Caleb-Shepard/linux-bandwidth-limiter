# Linux Bandwidth Limiter

![License](https://img.shields.io/badge/license-GPLv3-blue)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)
![Status](https://img.shields.io/badge/status-stable-green)

Easily limit bandwidth on your Linux machine with a persistent **systemd service**. Supports both upload and download throttling using `tc` (Traffic Control). Created after a horrible incident where one failed download in a new client that will not be named retried itself silently dozens of times, racking up a painful bill.

---

## 🚀 Features

- Lists all network interfaces and lets you choose which one to limit.
- Set upload and download speeds in Mbit/s.
- Persistent limits across reboots via a systemd service.

---

## 💻 Pre-install (Ubuntu/Debian)

Install the required dependencies:

```bash
sudo apt update && sudo apt install -y tc curl
```

- tc – Traffic control utility for bandwidth management
- curl – Fetches the installer script

## ⚡ One-liner Install & Run

```bash
curl -sSLO https://raw.githubusercontent.com/Caleb-Shepard/linux-bandwidth-limiter/main/linux-bandwidth-limiter-installer.sh; chmod +x linux-bandwidth-limiter-installer.sh; sudo ./linux-bandwidth-limiter-installer.sh
```

Workflow:

- The script lists all network interfaces.
- You select an interface by number.
- Default download/upload limits are applied (you can edit the config later).
- A systemd service is installed to persist limits across reboots.

🖥 Example Usage

Plain text
Available network interfaces:
1) eth0
2) wlan0
3) lo

```
Enter the number of the interface to limit: 2

Selected interface: wlan0

Installation complete. Service started.
```

⚙️ Config & Customization

The configuration file is stored at:

`/etc/default/bandwidth-limit`

Example config:

```bash
INTERFACE="wlan0"
DOWNLOAD_MBIT="10"
UPLOAD_MBIT="2"
```

You can edit this file to change limits or the interface, then restart the service:

```bash
sudo systemctl restart bandwidth-limit.service
```

## 🛠 Control Cheat Sheet

| Command                                           | Action                        |
|--------------------------------------------------|-------------------------------|
| `sudo systemctl start bandwidth-limit.service`  | Apply limits                  |
| `sudo systemctl stop bandwidth-limit.service`   | Remove limits                 |
| `sudo systemctl restart bandwidth-limit.service`| Apply new limits              |
| `sudo systemctl status bandwidth-limit.service` | View service status           |

---

## 🔄 Reset or Remove Limits

To remove all bandwidth restrictions without uninstalling:

```bash
sudo systemctl stop bandwidth-limit.service
```

📂 Advanced

- Supports multiple traffic shaping modules: htb, fq_codel, and ifb.
- Can be extended to apply per-IP or per-port limits.

📜 License

GPLv3 License – see LICENSE

🏷️ Summary

This project provides a reliable, persistent bandwidth limiter for Linux systems. Perfect for servers, workstations, or testing environments where network throttling is required.
