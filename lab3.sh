#!/bin/bash

# ---------------------------------------------------------
# Configuration Management Deployment Script (lab3.sh)
# ---------------------------------------------------------

# 1. VERBOSE HANDLING
# Check if verbose mode is requested via command line argument
VERBOSE_FLAG=""
if [ "$1" == "-verbose" ]; then
    VERBOSE_FLAG="-verbose"
fi

# 2. PRE-FLIGHT CHECKS
# Ensure the worker script exists and is executable locally
if [ ! -x "./configure-host.sh" ]; then
    echo "Error: ./configure-host.sh does not exist or is not executable."
    echo "Please run: chmod +x configure-host.sh"
    exit 1
fi

# 3. SSH CONFIGURATION
# - StrictHostKeyChecking=no: Prevents "Are you sure?" yes/no prompts
# - UserKnownHostsFile=/dev/null: Prevents "Host Identification Changed" errors
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# ---------------------------------------------------------
# SERVER 1 CONFIGURATION
# ---------------------------------------------------------
echo "----------------------------"
echo "Configuring Server 1..."

# Copy script to server1
# Note: We copy to /root as per assignment instructions
scp $SSH_OPTS configure-host.sh remoteadmin@server1-mgmt:/root
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy script to server1. Skipping execution."
else
    # Run script on server1
    # We explicitly run 'chmod +x' first to prevent 'Permission denied' errors
    ssh $SSH_OPTS remoteadmin@server1-mgmt -- "chmod +x /root/configure-host.sh && /root/configure-host.sh $VERBOSE_FLAG -name loghost -ip 192.168.16.3 -hostentry webhost 192.168.16.4"
    
    if [ $? -ne 0 ]; then 
        echo "Error: Script execution failed on server1"
    else
        echo "Server 1 configured successfully."
    fi
fi

# ---------------------------------------------------------
# SERVER 2 CONFIGURATION
# ---------------------------------------------------------
echo "----------------------------"
echo "Configuring Server 2..."

# Copy script to server2
scp $SSH_OPTS configure-host.sh remoteadmin@server2-mgmt:/root
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy script to server2. Skipping execution."
else
    # Run script on server2
    ssh $SSH_OPTS remoteadmin@server2-mgmt -- "chmod +x /root/configure-host.sh && /root/configure-host.sh $VERBOSE_FLAG -name webhost -ip 192.168.16.4 -hostentry loghost 192.168.16.3"
    
    if [ $? -ne 0 ]; then 
        echo "Error: Script execution failed on server2"
    else
        echo "Server 2 configured successfully."
    fi
fi

# ---------------------------------------------------------
# LOCAL CONFIGURATION
# ---------------------------------------------------------
echo "----------------------------"
echo "Configuring Local Machine..."

# Update local /etc/hosts
./configure-host.sh $VERBOSE_FLAG -hostentry loghost 192.168.16.3
./configure-host.sh $VERBOSE_FLAG -hostentry webhost 192.168.16.4

echo "----------------------------"
echo "Deployment complete."
