#!/bin/bash

# Default connection values
DEFAULT_USER="amin"
DEFAULT_IP="10.10.20.201"
DEFAULT_PORT="22"

# Ask for connection values with defaults
read -p "Enter username [$DEFAULT_USER]: " DEST_USER
DEST_USER=${DEST_USER:-$DEFAULT_USER}

read -p "Enter IP address [$DEFAULT_IP]: " DEST_IP
DEST_IP=${DEST_IP:-$DEFAULT_IP}

read -p "Enter SSH port [$DEFAULT_PORT]: " DEST_PORT
DEST_PORT=${DEST_PORT:-$DEFAULT_PORT}

# Execute a simple script to detect the network type
NETWORK_DETECT_SCRIPT="
#!/bin/bash
CURRENT_IP=\$(ip -4 -o addr show scope global | awk '{print \$4}' | cut -d/ -f1 | head -n1)
# CURRENT_IP=172.20.10.20 #just for test
if [[ \"\$CURRENT_IP\" == 172.20.* ]]; then
    echo \"internal\"
else
    echo \"external\"
fi
"

# Detect the network type
echo "Detecting network type on remote server..."
NETWORK_TYPE=$(ssh -p "$DEST_PORT" "${DEST_USER}@${DEST_IP}" "$NETWORK_DETECT_SCRIPT")

# Set variables based on network type
if [ "$NETWORK_TYPE" = "internal" ]; then
    echo "Network: Internal (172.20.*) - Setting proxy to true"
    SHOULD_USE_PROXY=true
    ENV_FILE="env.sh"
    # LOCAL_ENV_PATH="/home/ubuntu/ansible/env/env.sh"
    LOCAL_ENV_PATH="/home/amin/transfer/env/env.sh" #just for test

else
    echo "Network: External - Setting proxy to false"
    SHOULD_USE_PROXY=false
    ENV_FILE="env-newpin.sh"
    # LOCAL_ENV_PATH="/home/ubuntu/ansible/env/newpin/env-newpin.sh"
    LOCAL_ENV_PATH="/home/amin/transfer/env/newpin/env-newpin.sh" #just for test

fi

# Copy the appropriate environment file
echo "Copying $ENV_FILE to remote server..."
scp -P "$DEST_PORT" "$LOCAL_ENV_PATH" "${DEST_USER}@${DEST_IP}:/tmp/$ENV_FILE"
ssh -p "$DEST_PORT" "${DEST_USER}@${DEST_IP}" "sudo cp /tmp/$ENV_FILE /etc/profile.d/ && sudo chmod 644 /etc/profile.d/$ENV_FILE"

# Create the script for updating proxy settings and configuring environment
UPDATE_SCRIPT="
#!/bin/bash

# Set variables
SHOULD_USE_PROXY=\"$SHOULD_USE_PROXY\"
ENV_FILE=\"$ENV_FILE\"

echo \"Setting proxy to: \$SHOULD_USE_PROXY\"

# Process the proxy settings in system*.edn files
for dir in \$HOME/van-buren-*; do
    if [ -d \"\$dir\" ]; then
        find \"\$dir\" -name \"system*.edn\" | while read file; do
            echo \"Processing: \$file\"
            
            if [ \"\$SHOULD_USE_PROXY\" = \"true\" ]; then
                sed -i 's/\\(:use-proxy?[[:space:]]*\\)false/\\1true/g' \"\$file\"
                sed -i 's/\\(Set-Proxy?[[:space:]]*\\)false/\\1true/g' \"\$file\"
            else
                sed -i 's/\\(:use-proxy?[[:space:]]*\\)true/\\1false/g' \"\$file\"
                sed -i 's/\\(Set-Proxy?[[:space:]]*\\)true/\\1false/g' \"\$file\"
            fi
        done
    fi
done

# Add source command to .bashrc if not already present
if ! grep -q \"source /etc/profile.d/\$ENV_FILE\" \$HOME/.bashrc; then
    echo \"Adding source command to .bashrc\"
    echo \"source /etc/profile.d/\$ENV_FILE\" >> \$HOME/.bashrc
fi

echo \"Environment and proxy settings updated.\"
"

# Execute the update script
echo "Updating proxy settings and configuring environment..."
# ssh -p "$DEST_PORT" "${DEST_USER}@${DEST_IP}" "$UPDATE_SCRIPT"
ssh -p "$DEST_PORT" "${DEST_USER}@${DEST_IP}" "$UPDATE_SCRIPT && source ~/.bashrc"
echo "All operations completed successfully."