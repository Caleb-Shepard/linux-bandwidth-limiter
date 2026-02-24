#!/usr/bin/env bash
set -euo pipefail

# ==============================
# DEFAULTS (only used on first install)
# ==============================
DEFAULT_DOWNLOAD="10"
DEFAULT_UPLOAD="2"

INSTALL_PATH="/usr/local/sbin/bandwidth-limit"
CONFIG_PATH="/etc/default/bandwidth-limit"
SERVICE_PATH="/etc/systemd/system/bandwidth-limit.service"
SERVICE_NAME="bandwidth-limit.service"

# ==============================
# Safety Checks
# ==============================

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo)."
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemd not detected. This installer requires systemd."
    exit 1
fi

if ! command -v tc >/dev/null 2>&1; then
    echo "tc (iproute2) not installed."
    exit 1
fi

# ==============================
# Prompt User to Choose Interface
# ==============================

echo "Available network interfaces:"
interfaces=($(ls /sys/class/net))

for i in "${!interfaces[@]}"; do
    echo "$((i+1))) ${interfaces[$i]}"
done

echo

while true; do
    read -rp "Enter the number of the interface to limit: " iface_index < /dev/tty
    
    # Check if input is a number
    if ! [[ "$iface_index" =~ ^[0-9]+$ ]]; then
        echo "Please enter a valid number."
        continue
    fi

    # Check range
    if (( iface_index < 1 || iface_index > ${#interfaces[@]} )); then
        echo "Selection out of range."
        continue
    fi

    break
done

SELECTED_INTERFACE="${interfaces[$((iface_index-1))]}"
echo "Selected interface: $SELECTED_INTERFACE"
echo

# ==============================
# Ask User for Bandwidth Limits
# ==============================

echo "Enter bandwidth limits in Mbps (press Enter to use defaults)."
echo

while true; do
    read -rp "Download limit [${DEFAULT_DOWNLOAD} Mbps]: " USER_DOWNLOAD < /dev/tty
    USER_DOWNLOAD="${USER_DOWNLOAD:-$DEFAULT_DOWNLOAD}"

    if [[ "$USER_DOWNLOAD" =~ ^[0-9]+$ ]] && (( USER_DOWNLOAD > 0 )); then
        break
    else
        echo "Please enter a valid positive number."
    fi
done

while true; do
    read -rp "Upload limit [${DEFAULT_UPLOAD} Mbps]: " USER_UPLOAD < /dev/tty
    USER_UPLOAD="${USER_UPLOAD:-$DEFAULT_UPLOAD}"

    if [[ "$USER_UPLOAD" =~ ^[0-9]+$ ]] && (( USER_UPLOAD > 0 )); then
        break
    else
        echo "Please enter a valid positive number."
    fi
done

echo
echo "Download limit set to: ${USER_DOWNLOAD} Mbps"
echo "Upload limit set to:   ${USER_UPLOAD} Mbps"
echo

# ==============================
# Write Config File
# ==============================

cat > "$CONFIG_PATH" << EOF
INTERFACE="$SELECTED_INTERFACE"
DOWNLOAD_MBIT="$USER_DOWNLOAD"
UPLOAD_MBIT="$USER_UPLOAD"
EOF

echo "Config written to $CONFIG_PATH"

# ==============================
# Install Main Script
# ==============================

install -m 0755 /dev/stdin "$INSTALL_PATH" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG="/etc/default/bandwidth-limit"

if [[ ! -f "$CONFIG" ]]; then
    echo "Missing config: $CONFIG"
    exit 1
fi

source "$CONFIG"

IFACE="${INTERFACE}"
IFB_DEV="ifb0"
DOWNLOAD="${DOWNLOAD_MBIT}"
UPLOAD="${UPLOAD_MBIT}"

load_modules() {
    modprobe ifb || true
    modprobe sch_htb || true
    modprobe sch_fq_codel || true
}

clear_rules() {
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
    tc qdisc del dev "$IFB_DEV" root 2>/dev/null || true
    ip link set "$IFB_DEV" down 2>/dev/null || true
    ip link delete "$IFB_DEV" type ifb 2>/dev/null || true
}

apply_limit() {
    load_modules
    clear_rules

    # Upload
    tc qdisc add dev "$IFACE" root handle 1: htb default 10
    tc class add dev "$IFACE" parent 1: classid 1:1 htb rate ${UPLOAD}mbit ceil ${UPLOAD}mbit
    tc class add dev "$IFACE" parent 1:1 classid 1:10 htb rate ${UPLOAD}mbit ceil ${UPLOAD}mbit
    tc qdisc add dev "$IFACE" parent 1:10 fq_codel

    # Download (IFB)
    ip link add "$IFB_DEV" type ifb
    ip link set "$IFB_DEV" up

    tc qdisc add dev "$IFACE" handle ffff: ingress

    tc filter add dev "$IFACE" parent ffff: protocol ip u32 \
        match u32 0 0 action mirred egress redirect dev "$IFB_DEV"

    tc filter add dev "$IFACE" parent ffff: protocol ipv6 u32 \
        match u32 0 0 action mirred egress redirect dev "$IFB_DEV"

    tc qdisc add dev "$IFB_DEV" root handle 1: htb default 10
    tc class add dev "$IFB_DEV" parent 1: classid 1:1 htb rate ${DOWNLOAD}mbit ceil ${DOWNLOAD}mbit
    tc class add dev "$IFB_DEV" parent 1:1 classid 1:10 htb rate ${DOWNLOAD}mbit ceil ${DOWNLOAD}mbit
    tc qdisc add dev "$IFB_DEV" parent 1:10 fq_codel
}

case "${1:-}" in
    start)
        apply_limit
        ;;
    stop)
        clear_rules
        ;;
    restart)
        clear_rules
        apply_limit
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF

echo "Installed main script."

# ==============================
# Install Service
# ==============================

cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Persistent Traffic Control Bandwidth Limiter
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$INSTALL_PATH start
ExecStop=$INSTALL_PATH stop
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

echo "Installed systemd service."

# ==============================
# Enable + Start Idempotently
# ==============================

systemctl daemon-reload

if ! systemctl is-enabled --quiet "$SERVICE_NAME"; then
    systemctl enable "$SERVICE_NAME"
    echo "Service enabled."
fi

if systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl restart "$SERVICE_NAME"
    echo "Service restarted."
else
    systemctl start "$SERVICE_NAME"
    echo "Service started."
fi

echo
echo "Installation complete."
systemctl status "$SERVICE_NAME" --no-pager

echo
echo "📖 README:"
echo "https://github.com/Caleb-Shepard/linux-bandwidth-limiter/blob/main/README.md"
echo
