#!/bin/bash

# Default values
DEFAULT_REMOTE_USER="ubuntu"
DEFAULT_REMOTE_IP="185.204.170.86"
DEFAULT_SSH_PORT="22"

# SSH options (Prevents SSH from asking about new host keys)
SSH_OPTS="-o StrictHostKeyChecking=no"

# Prompt user for input with defaults
read -p "Enter remote VM username [$DEFAULT_REMOTE_USER]: " REMOTE_USER
REMOTE_USER=${REMOTE_USER:-$DEFAULT_REMOTE_USER}

read -p "Enter remote VM IP address [$DEFAULT_REMOTE_IP]: " REMOTE_IP
REMOTE_IP=${REMOTE_IP:-$DEFAULT_REMOTE_IP}

read -p "Enter SSH port [$DEFAULT_SSH_PORT]: " SSH_PORT
SSH_PORT=${SSH_PORT:-$DEFAULT_SSH_PORT}

# Display selected values
echo "Using:"
echo " - User: $REMOTE_USER"
echo " - IP: $REMOTE_IP"
echo " - SSH Port: $SSH_PORT"
echo "--------------------------------------"

# Execute commands remotely before reboot
echo "Connecting to $REMOTE_USER@$REMOTE_IP via SSH..."
ssh $SSH_OPTS -p "$SSH_PORT" "$REMOTE_USER@$REMOTE_IP" <<EOF
    echo "Setting non-interactive mode..."
    export DEBIAN_FRONTEND=noninteractive
    export LC_ALL=C

    echo "Checking for unfinished dpkg operations..."
    sudo dpkg --configure -a

    echo "Removing potential lock files to prevent upgrade failures..."
    sudo rm -rf /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend
    sudo rm -rf /var/lib/apt/lists/lock
    sudo rm -rf /var/cache/apt/archives/lock

    echo "Updating package list..."
    sudo apt update -y

    echo "Fixing broken dependencies before upgrade..."
    sudo apt --fix-broken install -y

    echo "Upgrading installed packages (without prompts)..."
    sudo apt full-upgrade -y --allow-downgrades --allow-remove-essential --allow-change-held-packages

    echo "Cleaning up unused packages..."
    sudo apt autoremove -y
    sudo apt clean

    echo "Rebooting system..."
    nohup sudo reboot &
EOF

# Wait for VM to reboot
echo "Waiting for the VM to become available..."
while ! nc -z "$REMOTE_IP" "$SSH_PORT"; do
    sleep 5
done

# Install required packages after reboot
echo "Reconnecting to install additional packages..."
ssh $SSH_OPTS -p "$SSH_PORT" "$REMOTE_USER@$REMOTE_IP" <<EOF
    echo "Setting non-interactive mode..."
    export DEBIAN_FRONTEND=noninteractive
    export LC_ALL=C

    echo "Installing required packages (without prompts)..."
    sudo apt install -y zip unzip openjdk-17-jdk telnet chrony prometheus-node-exporter

    echo "Installation completed successfully!"
EOF

echo "Remote update and installation process completed!"
