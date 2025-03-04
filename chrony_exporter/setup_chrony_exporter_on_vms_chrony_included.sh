#!/bin/bash

# File containing the list of VM IP addresses
VM_IPS_FILE="vm_new"
CHRONY_EXPORTER_BINARY="chrony_exporter"

# Read VM IPs into an array
mapfile -t vm_ips < "$VM_IPS_FILE"

# Function to check and install chrony, and configure chrony_exporter on a remote VM
setup_chrony_and_chrony_exporter_on_vm() {
    local vm_ip=$1

    # Check if chrony is installed, if not, install it
    if ssh -o ConnectTimeout=5 "$vm_ip" 'dpkg -l | grep -qw chrony'; then
        echo "chrony is already installed on $vm_ip."
    else
        echo "Installing chrony on $vm_ip."
        ssh -o ConnectTimeout=5 "$vm_ip" 'sudo apt-get update && sudo apt-get install -y chrony'
    fi

    # Configure chrony with the specified time servers
    echo "Configuring chrony on $vm_ip."
    ssh -o ConnectTimeout=5 "$vm_ip" 'sudo bash -c '"'"'cat <<EOT > /etc/chrony/chrony.conf
server time.google.com iburst
server time1.google.com iburst
server time2.google.com iburst
server time3.google.com iburst
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
user _chrony
server ntp.ubuntu.com
server 0.ubuntu.pool.ntp.org
server 1.ubuntu.pool.ntp.org
server 2.ubuntu.pool.ntp.org
EOT'"'"''
    ssh -o ConnectTimeout=5 "$vm_ip" 'sudo systemctl restart chrony'

    # Check if port 9109 is listening on the remote VM
    if ssh -o ConnectTimeout=5 "$vm_ip" 'netstat -an | grep LISTEN | grep ":9109"' &>/dev/null; then
        echo "Port 9109 is already listening on $vm_ip. Skipping chrony_exporter setup."
        return
    fi

    # Check if chrony_exporter binary already exists on the remote VM
    if ssh -o ConnectTimeout=5 "$vm_ip" '[ -f /usr/local/bin/chrony_exporter ]'; then
        echo "chrony_exporter already exists on $vm_ip. Skipping binary copy."
    else
        echo "Copying chrony_exporter binary to $vm_ip."
        scp -o ConnectTimeout=5 "$CHRONY_EXPORTER_BINARY" "$vm_ip:/tmp/"
        ssh -o ConnectTimeout=5 "$vm_ip" 'sudo mv /tmp/chrony_exporter /usr/local/bin/ && sudo chmod +x /usr/local/bin/chrony_exporter'
    fi

    # Check if chrony_exporter user already exists
    if ssh -o ConnectTimeout=5 "$vm_ip" id -u chrony_exporter &>/dev/null; then
        echo "User chrony_exporter already exists on $vm_ip. Skipping user creation."
    else
        echo "Creating user chrony_exporter on $vm_ip."
        ssh -o ConnectTimeout=5 "$vm_ip" 'sudo useradd -rs /bin/false chrony_exporter'
    fi

    # Set ownership of chrony_exporter binary
    echo "Setting ownership of chrony_exporter binary on $vm_ip."
    ssh -o ConnectTimeout=5 "$vm_ip" 'sudo chown chrony_exporter:chrony_exporter /usr/local/bin/chrony_exporter'

    # Check if the systemd service file already exists
    if ssh -o ConnectTimeout=5 "$vm_ip" '[ -f /etc/systemd/system/chrony_exporter.service ]'; then
        echo "chrony_exporter service already exists on $vm_ip. Skipping service setup."
    else
        echo "Creating chrony_exporter service on $vm_ip."
        ssh -o ConnectTimeout=5 "$vm_ip" 'sudo bash -c '"'"'cat <<EOT > /etc/systemd/system/chrony_exporter.service
[Unit]
Description=Chrony Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=chrony_exporter
Group=chrony_exporter
Type=simple
ExecStart=/usr/local/bin/chrony_exporter --web.listen-address=:9109

[Install]
WantedBy=multi-user.target
EOT'"'"''
    fi

    # Reload systemd and start the service if not already running
    ssh -o ConnectTimeout=5 "$vm_ip" 'sudo systemctl daemon-reload'
    if ssh -o ConnectTimeout=5 "$vm_ip" 'sudo systemctl is-active --quiet chrony_exporter'; then
        echo "chrony_exporter service is already running on $vm_ip."
    else
        echo "Starting and enabling chrony_exporter service on $vm_ip."
        ssh -o ConnectTimeout=5 "$vm_ip" 'sudo systemctl start chrony_exporter && sudo systemctl enable chrony_exporter'
    fi
}

# Iterate over the array of VM IPs and setup chrony_exporter on each VM
for vm_ip in "${vm_ips[@]}"; do
    echo "Setting up chrony and chrony_exporter on VM: $vm_ip"
    setup_chrony_and_chrony_exporter_on_vm "$vm_ip"
done

