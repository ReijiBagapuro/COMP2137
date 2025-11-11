#!/bin/bash

# --- Configuration Variables ---
TARGET_IP="192.168.16.21"
TARGET_CIDR="24"
TARGET_NET="$TARGET_IP/$TARGET_CIDR"
TARGET_HOSTNAME="server1"
NETPLAN_DIR="/etc/netplan"
NETPLAN_FILE="$NETPLAN_DIR/99-static-config.yaml"
TARGET_SOFTWARE=("apache2" "squid")

USER_LIST=(
    "dennis:sudo"
    "aubrey"
    "captain"
    "snibbles"
    "brownie"
    "scooter"
    "sandy"
    "perrier"
    "cindy"
    "tiger"
    "yoda"
)

DENNIS_EXTERNAL_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"

# --- Formatting Functions ---

report_start() {
    echo -e "\n========================================================"
    echo -e "   🚀 Starting System Configuration Script ($0)"
    echo -e "========================================================"
    START_TIME=$(date +%s)
}

report_section() {
    echo -e "\n--- [ $1 ] ---"
}

report_status() {
    local status_type=$1
    local message=$2
    local icon=""
    
    case "$status_type" in
        PASS) icon="✅";;
        APPLY) icon="🛠️";;
        ERROR) icon="❌";;
        SKIP) icon="➡️";;
        CHECK) icon="🔍";;
        *) icon="💬";;
    esac
    
    echo -e " $icon $message"
}

report_error_exit() {
    report_status ERROR "$1"
    echo -e "\n========================================================"
    echo -e "   ❌ SCRIPT FAILED - Please resolve the error above."
    echo -e "========================================================"
    exit 1
}

report_finish() {
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    echo -e "\n========================================================"
    echo -e "   🎉 Script Completed Successfully in ${DURATION} seconds!"
    echo -e "========================================================"
}

# --- Core Logic Functions ---

# Function to identify the non-management interface (if not already set to target IP)
# This is complex and relies on environment. A robust script should find an interface 
# that is NOT the management interface (assuming management is already configured).
find_target_interface() {
    # Check if the target IP is already configured on any interface
    if ip a | grep -q "$TARGET_IP/$TARGET_CIDR"; then
        INTERFACE=$(ip a | grep "$TARGET_IP/$TARGET_CIDR" | awk '{print $NF}')
        report_status PASS "Target IP ($TARGET_NET) already set on interface: $INTERFACE"
        echo "$INTERFACE" # Return the interface name
        return 0
    fi

    # Assuming the management interface is the first one found that has an IP (or skip eth0/lo)
    # This logic is often environment-specific. We'll search for an unconfigured device.
    # The safest way for this assignment is often to assume an unconfigured device like eth0 or eth1
    
    # We will try to find a device that is UP and does NOT have an IP in a known private range 
    # (like 10.x.x.x, 172.16.x.x, 192.168.x.x, excluding the target range).
    # Since the assignment is on a controlled VM environment, we will look for a device that is UP
    # but has no primary IPv4 address, and assume it's the one we need to configure.

    UNCONFIGURED_DEVICES=$(ip -o link show | awk -F': ' '/UP/{print $2}' | grep -v 'lo')
    
    for IFACE in $UNCONFIGURED_DEVICES; do
        if ! ip a show dev "$IFACE" | grep -q "inet "; then
            report_status CHECK "Found unconfigured UP interface: $IFACE. Using this as target."
            echo "$IFACE"
            return 0
        fi
    done

    # If all else fails, use a common name like eth0 as a fallback, but warn the user.
    report_status CHECK "Could not auto-detect target interface. Falling back to 'eth0'. VERIFY THIS MANUALLY."
    echo "eth0"
    return 0
}

# --- Task 1: Network Configuration (Netplan) ---
configure_netplan() {
    report_section "1. Network Configuration (Netplan)"

    INTERFACE_NAME=$(find_target_interface)
    
    # Check if the desired configuration already exists
    if [ -f "$NETPLAN_FILE" ] && grep -q "$TARGET_NET" "$NETPLAN_FILE" && grep -q "$INTERFACE_NAME" "$NETPLAN_FILE"; then
        report_status PASS "Netplan configuration already correctly defined in $NETPLAN_FILE."
        return 0
    fi
    
    report_status APPLY "Applying static IP $TARGET_NET to interface $INTERFACE_NAME via $NETPLAN_FILE..."

    # Create the new Netplan configuration file
    cat > "$NETPLAN_FILE" << EOF
network:
  version: 2
  ethernets:
    $INTERFACE_NAME:
      dhcp4: false
      addresses: [$TARGET_NET]
EOF

    # Apply configuration
    netplan generate || report_error_exit "Netplan generation failed."
    netplan apply || report_error_exit "Netplan application failed. Check interface name and network settings."
    
    # Verify the change
    if ip a | grep -q "$TARGET_NET"; then
        report_status PASS "Successfully applied $TARGET_NET."
    else
        report_error_exit "Netplan applied, but IP verification failed. Check networking."
    fi
}

# --- Task 2: /etc/hosts Configuration ---
configure_hosts() {
    report_section "2. /etc/hosts Configuration"
    
    HOSTS_FILE="/etc/hosts"
    NEW_ENTRY="$TARGET_IP\t$TARGET_HOSTNAME"

    # Check if the correct entry exists
    if grep -q "^$TARGET_IP\s*$TARGET_HOSTNAME" "$HOSTS_FILE"; then
        report_status PASS "Correct hosts entry already exists: $NEW_ENTRY"
        return 0
    fi
    
    report_status APPLY "Ensuring hosts file contains the correct entry and removing old ones."

    # 1. Remove any old lines mapping to TARGET_HOSTNAME that are NOT 127.0.0.1 or ::1
    # This uses a complex sed command for idempotency and safety
    sed -i "/$TARGET_HOSTNAME/ { /127.0.0.1/! { /::1/!d } }" "$HOSTS_FILE"
    
    # 2. Remove any old lines mapping to TARGET_IP (in case it was another hostname)
    sed -i "/^$TARGET_IP\s/d" "$HOSTS_FILE"

    # 3. Add the correct new entry
    echo -e "$NEW_ENTRY" >> "$HOSTS_FILE"

    # Final check
    if grep -q "^$TARGET_IP\s*$TARGET_HOSTNAME" "$HOSTS_FILE"; then
        report_status PASS "Hosts file updated successfully."
    else
        report_error_exit "Failed to update hosts file."
    fi
}

# --- Task 3: Software Installation ---
install_software() {
    report_section "3. Software Installation & Service Status"
    
    NEED_UPDATE=false
    
    for PKG in "${TARGET_SOFTWARE[@]}"; do
        if ! dpkg -s "$PKG" &> /dev/null; then
            report_status CHECK "$PKG is not installed."
            NEED_UPDATE=true
        else
            report_status PASS "$PKG is already installed."
        fi
    done
    
    # Install or update if needed
    if [ "$NEED_UPDATE" = true ]; then
        report_status APPLY "Running apt update and installing missing packages..."
        apt update -y || report_error_exit "apt update failed."
        apt install -y "${TARGET_SOFTWARE[@]}" || report_error_exit "Software installation failed."
    fi
    
    # Ensure services are running (idempotent)
    for PKG in "${TARGET_SOFTWARE[@]}"; do
        report_status CHECK "Verifying service status for $PKG."
        if ! systemctl is-active --quiet "$PKG"; then
            report_status APPLY "Starting and enabling $PKG service."
            systemctl enable --now "$PKG" || report_error_exit "Failed to start $PKG service."
            
            if systemctl is-active --quiet "$PKG"; then
                report_status PASS "$PKG service is now active."
            else
                report_error_exit "$PKG service failed to start."
            fi
        else
            report_status PASS "$PKG service is active and enabled."
        fi
    done
}

# --- Task 4: User and SSH Key Management ---
manage_users() {
    report_section "4. User and SSH Key Management"
    
    for USER_ENTRY in "${USER_LIST[@]}"; do
        IFS=':' read -r USERNAME GROUPS <<< "$USER_ENTRY"
        
        report_status CHECK "Processing user: $USERNAME"
        
        USER_HOME="/home/$USERNAME"
        SSH_DIR="$USER_HOME/.ssh"
        AUTH_KEYS_FILE="$SSH_DIR/authorized_keys"

        # 1. Create User (Idempotent: checks for existence)
        if ! id -u "$USERNAME" >/dev/null 2>&1; then
            report_status APPLY "Creating user $USERNAME with home directory and /bin/bash shell."
            useradd -m -s /bin/bash "$USERNAME" || report_error_exit "Failed to create user $USERNAME."
        else
            report_status PASS "User $USERNAME already exists."
        fi

        # 2. Add Sudo Access for dennis (Idempotent: usermod handles existing groups)
        if [ "$USERNAME" == "dennis" ] && [[ "$GROUPS" == *"sudo"* ]]; then
            if ! groups "$USERNAME" | grep -q '\<sudo\>'; then
                report_status APPLY "Adding $USERNAME to 'sudo' group."
                usermod -aG sudo "$USERNAME" || report_error_exit "Failed to add $USERNAME to sudo group."
            else
                report_status PASS "$USERNAME is already a member of the 'sudo' group."
            fi
        fi

        # 3. Setup .ssh directory
        if [ ! -d "$SSH_DIR" ]; then
            report_status APPLY "Creating and securing $SSH_DIR."
            mkdir -p "$SSH_DIR"
            chown "$USERNAME":"$USERNAME" "$SSH_DIR"
            chmod 700 "$SSH_DIR"
        fi
        
        # Ensure authorized_keys file exists and has correct permissions
        if [ ! -f "$AUTH_KEYS_FILE" ]; then
            touch "$AUTH_KEYS_FILE"
        fi
        chown "$USERNAME":"$USERNAME" "$AUTH_KEYS_FILE"
        chmod 600 "$AUTH_KEYS_FILE"

        # 4. Generate and Install Keys (Idempotent: checks for key existence)
        
        # --- RSA Key ---
        if [ ! -f "$SSH_DIR/id_rsa.pub" ]; then
            report_status APPLY "Generating RSA key for $USERNAME."
            # Run as user for correct ownership and permissions
            sudo -u "$USERNAME" ssh-keygen -t rsa -b 4096 -f "$SSH_DIR/id_rsa" -N "" -q
            cat "$SSH_DIR/id_rsa.pub" >> "$AUTH_KEYS_FILE"
        fi
        
        # --- Ed25519 Key ---
        if [ ! -f "$SSH_DIR/id_ed25519.pub" ]; then
            report_status APPLY "Generating Ed25519 key for $USERNAME."
            sudo -u "$USERNAME" ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -q
            cat "$SSH_DIR/id_ed25519.pub" >> "$AUTH_KEYS_FILE"
        fi

        # 5. Add External Key for dennis (Idempotent: checks if key is already present)
        if [ "$USERNAME" == "dennis" ]; then
            if ! grep -q "$DENNIS_EXTERNAL_KEY" "$AUTH_KEYS_FILE"; then
                report_status APPLY "Adding external public key for $USERNAME."
                echo "$DENNIS_EXTERNAL_KEY" >> "$AUTH_KEYS_FILE"
            fi
        fi

        # 6. Final cleanup (Idempotent: removes duplicates)
        sort -u -o "$AUTH_KEYS_FILE" "$AUTH_KEYS_FILE"
        report_status PASS "Keys for $USERNAME verified and installed."
    done
}


# --- Script Execution ---

report_start

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    report_error_exit "Please run this script with 'sudo' or as root."
fi

# Run all tasks sequentially
configure_netplan
configure_hosts
install_software
manage_users

report_finish
