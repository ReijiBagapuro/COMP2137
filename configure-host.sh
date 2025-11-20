#!/bin/bash

# ---------------------------------------------------------
# Step 1: Ignore Signals
# The assignment requires ignoring TERM, HUP, and INT signals
# ---------------------------------------------------------
trap '' TERM HUP INT

VERBOSE=false

# Helper function for logging
log_message() {
    local msg="$1"
    if [ "$VERBOSE" = true ]; then
        echo "$msg"
    fi
    logger "$msg"
}

# ---------------------------------------------------------
# Step 2: Parse Command Line Arguments
# ---------------------------------------------------------
while [ "$#" -gt 0 ]; do
    case "$1" in
        -verbose)
            VERBOSE=true
            shift
            ;;
        -name)
            # -------------------------------------------------
            # Option 2: Update Hostname
            # -------------------------------------------------
            target_name="$2"
            current_name=$(hostname)
            
            if [ "$current_name" != "$target_name" ]; then
                # Change the current running hostname
                hostnamectl set-hostname "$target_name"
                
                # Update the persistent file /etc/hostname
                echo "$target_name" > /etc/hostname
                
                # Update the local entry in /etc/hosts
                sed -i "s/$current_name/$target_name/g" /etc/hosts
                
                log_message "Hostname changed from $current_name to $target_name"
            else
                log_message "Hostname is already $target_name"
            fi
            shift 2
            ;;
        -ip)
            # -------------------------------------------------
            # Option 3: Update IP Address
            # -------------------------------------------------
            target_ip="$2"
            # Find the current IP (ignoring 127.0.0.1)
            current_ip=$(hostname -I | awk '{print $1}')
            
            # Only change if the target IP is different
            if [ "$current_ip" != "$target_ip" ]; then
                # Update /etc/hosts to match the new IP
                sed -i "s/$current_ip/$target_ip/g" /etc/hosts
                
                # Update Netplan configuration (assuming standard lxc yaml file exists)
                # Note: We use a flexible grep to find the yaml file
                netplan_file=$(grep -l "addresses" /etc/netplan/*.yaml | head -n 1)
                
                if [ -n "$netplan_file" ]; then
                     # Replace the line containing the IP address
                     sed -i "s/$current_ip/$target_ip/g" "$netplan_file"
                     netplan apply
                     log_message "IP Address changed from $current_ip to $target_ip"
                else
                     log_message "Error: Could not find valid netplan file to update IP"
                fi
            else
                log_message "IP Address is already $target_ip"
            fi
            shift 2
            ;;
        -hostentry)
            # -------------------------------------------------
            # Option 4: Update /etc/hosts Entry
            # -------------------------------------------------
            entry_name="$2"
            entry_ip="$3"
            
            # Check if the name already exists in the hosts file
            if grep -qw "$entry_name" /etc/hosts; then
                # If it exists, check if the IP is correct
                current_entry_ip=$(grep -w "$entry_name" /etc/hosts | awk '{print $1}')
                
                if [ "$current_entry_ip" != "$entry_ip" ]; then
                    # Update the existing line using sed
                    sed -i "s/.*\b$entry_name\b/$entry_ip $entry_name/" /etc/hosts
                    log_message "Updated host entry for $entry_name to $entry_ip"
                else
                     log_message "Host entry for $entry_name is already correct"
                fi
            else
                # If it doesn't exist, add it to the end of the file
                echo "$entry_ip $entry_name" >> /etc/hosts
                log_message "Added host entry: $entry_name at $entry_ip"
            fi
            shift 3
            ;;
        *)
            shift
            ;;
    esac
done
