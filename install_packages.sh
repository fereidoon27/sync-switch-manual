#!/bin/bash

# Use these default values
DEFAULT_USER="ubuntu"
DEFAULT_IP="185.204.169.249"
DEFAULT_SSH_PORT="22"

# Set variables directly without asking for input
USER=$DEFAULT_USER
IP=$DEFAULT_IP
SSH_PORT=$DEFAULT_SSH_PORT

# SSH connection string
SSH_CMD="ssh -p $SSH_PORT $USER@$IP"

echo "=== Connecting to remote server: $USER@$IP:$SSH_PORT ==="

# Function to forcefully remove apt locks
remove_apt_locks() {
    echo "Removing apt locks..."
    $SSH_CMD "
        sudo killall apt apt-get 2>/dev/null || true
        sudo rm /var/lib/apt/lists/lock 2>/dev/null || true
        sudo rm /var/cache/apt/archives/lock 2>/dev/null || true
        sudo rm /var/lib/dpkg/lock* 2>/dev/null || true
        sudo dpkg --configure -a || true
    "
    echo "Locks removed. Proceeding..."
}

# Step 1: Update packages
echo "=== Updating packages ==="
remove_apt_locks
$SSH_CMD "sudo apt update && echo 'Update completed successfully!'" || {
    echo "Failed to update packages. Exiting."
    exit 1
}

# Step 2: Upgrade packages
echo "=== Upgrading packages ==="
remove_apt_locks
$SSH_CMD "DEBIAN_FRONTEND=noninteractive sudo apt upgrade -y && echo 'Upgrade completed successfully!'" || {
    echo "Failed to upgrade packages. Exiting."
    exit 1
}

# Step 3: Install required packages
echo "=== Installing required packages ==="
remove_apt_locks
$SSH_CMD "DEBIAN_FRONTEND=noninteractive sudo apt install -y zip unzip openjdk-17-jdk telnet chrony prometheus-node-exporter && echo 'Installation completed successfully!'" || {
    echo "Failed to install packages. Exiting."
    exit 1
}

# Step 4: Reboot the system
echo "=== Rebooting the remote system ==="
echo "The system will reboot now. Connection will be lost temporarily."
$SSH_CMD "sudo reboot" || {
    echo "Failed to reboot the system."
    exit 1
}

echo "=== Script completed ==="
echo "The remote system is now rebooting. Please wait a few minutes before reconnecting."
echo "All requested actions have been completed:"
echo "✓ System updated"
echo "✓ System upgraded"
echo "✓ Required packages installed (zip, unzip, openjdk-17-jdk, telnet, chrony, prometheus-node-exporter)"
echo "✓ System rebooted"