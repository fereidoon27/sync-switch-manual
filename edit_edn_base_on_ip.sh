#!/bin/bash

# Get script directory and config paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INFO_PATH="$(dirname "$0")/Info"
SERVERS_CONF="$INFO_PATH/servers.conf"

# Check if servers.conf exists
if [ ! -f "$SERVERS_CONF" ]; then
    echo "Error: servers.conf file not found at $SERVERS_CONF"
    exit 1
fi

# Extract unique datacenters from servers.conf
echo "Available datacenters:"
datacenters=($(awk -F'|' '{ print $1 }' "$SERVERS_CONF" | sort -u))
for i in "${!datacenters[@]}"; do
    echo "$((i+1)). ${datacenters[$i]}"
done

# Ask user to select a datacenter
read -p "Select datacenter (1-${#datacenters[@]}): " dc_choice
if ! [[ "$dc_choice" =~ ^[0-9]+$ ]] || [ "$dc_choice" -lt 1 ] || [ "$dc_choice" -gt "${#datacenters[@]}" ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

SELECTED_DC="${datacenters[$((dc_choice-1))]}"
echo "Selected datacenter: $SELECTED_DC"

# Extract servers for the selected datacenter
echo "Available VMs in $SELECTED_DC datacenter:"
servers=($(awk -F'|' -v dc="$SELECTED_DC" '$1 == dc { print $2 }' "$SERVERS_CONF"))
for i in "${!servers[@]}"; do
    echo "$((i+1)). ${servers[$i]}"
done

# Add "all" option
echo "$((${#servers[@]}+1)). all"

# Ask user to select servers (multiple selection allowed)
read -p "Choose destination VM(s) (e.g., 246 for multiple or '${#servers[@]}+1' for all): " server_choice

# Process server selection
selected_indices=()
if [ "$server_choice" == "$((${#servers[@]}+1))" ] || [ "$server_choice" == "all" ]; then
    # All servers selected
    for i in "${!servers[@]}"; do
        selected_indices+=($i)
    done
else
    # Process individual digits for multiple selection
    for (( i=0; i<${#server_choice}; i++ )); do
        digit=${server_choice:$i:1}
        if [[ "$digit" =~ ^[0-9]$ ]] && [ "$digit" -ge 1 ] && [ "$digit" -le "${#servers[@]}" ]; then
            selected_indices+=($((digit-1)))
        fi
    done
fi

# Check if at least one server was selected
if [ ${#selected_indices[@]} -eq 0 ]; then
    echo "No valid servers selected. Exiting."
    exit 1
fi

# Display selected servers
echo "Selected servers:"
for idx in "${selected_indices[@]}"; do
    echo "- ${servers[$idx]}"
done

# Create the network detection script using a here-document.
NETWORK_DETECT_SCRIPT=$(cat <<'EOF'
#!/bin/bash
CURRENT_IP=$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -n1)
# CURRENT_IP=172.20.10.20 #just for test
if [[ "$CURRENT_IP" == 172.20.* ]]; then
    echo "internal"
else
    echo "external"
fi
EOF
)

# Define the destination environment filename.
DEST_ENV_FILE="hermes-env.sh"

# Loop through each selected server and process it
for idx in "${selected_indices[@]}"; do
    SELECTED_SERVER="${servers[$idx]}"
    echo ""
    echo "==============================================="
    echo "Processing server: $SELECTED_SERVER"
    echo "==============================================="
    
    # Get server details
    SERVER_INFO=$(grep "^$SELECTED_DC|$SELECTED_SERVER|" "$SERVERS_CONF")
    DEST_IP=$(echo "$SERVER_INFO" | awk -F'|' '{ print $4 }')
    DEST_USER=$(echo "$SERVER_INFO" | awk -F'|' '{ print $5 }')
    DEST_PORT=$(echo "$SERVER_INFO" | awk -F'|' '{ print $6 }')

    echo "Using connection details: $DEST_USER@$DEST_IP:$DEST_PORT"

    # Detect the network type on the remote server.
    echo "Detecting network type on remote server..."
    NETWORK_TYPE=$(ssh -p "$DEST_PORT" "${DEST_USER}@${DEST_IP}" "$NETWORK_DETECT_SCRIPT")

    # Set variables based on network type.
    if [ "$NETWORK_TYPE" = "internal" ]; then
        echo "Network: Internal (172.20.*) - Setting proxy to true"
        SHOULD_USE_PROXY=true
        ENV_FILE="envs"
        LOCAL_ENV_PATH="/home/amin/ansible/env/envs"
    else
        echo "Network: External - Setting proxy to false"
        SHOULD_USE_PROXY=false
        ENV_FILE="envs"
        LOCAL_ENV_PATH="/home/amin/ansible/env/newpin/envs"
    fi

    # Copy the appropriate environment file and rename it on the remote server using rsync.
    echo "Copying environment file to remote server as $DEST_ENV_FILE..."
    # First create a temp directory to use for rsync
    TEMP_DIR=$(mktemp -d)
    cp "$LOCAL_ENV_PATH" "$TEMP_DIR/$ENV_FILE"

    # Use rsync to copy the file
    rsync -avz -e "ssh -p $DEST_PORT" "$TEMP_DIR/$ENV_FILE" "${DEST_USER}@${DEST_IP}:/tmp/$ENV_FILE"
    rm -rf "$TEMP_DIR"  # Clean up

    # Make sure the env file is properly formatted with a shebang
    ssh -p "$DEST_PORT" "${DEST_USER}@${DEST_IP}" "sudo bash -c 'if ! grep -q \"#!/bin/bash\" /tmp/$ENV_FILE; then sed -i \"1i#!/bin/bash\" /tmp/$ENV_FILE; fi'"

    # Ensure all variable definitions use export
    ssh -p "$DEST_PORT" "${DEST_USER}@${DEST_IP}" "sudo bash -c 'sed -i \"s/^[[:space:]]*\\([A-Za-z0-9_]*=\\)/export \\1/g\" /tmp/$ENV_FILE'"

    # Copy to destination, set permissions, and immediately source it system-wide
    ssh -p "$DEST_PORT" "${DEST_USER}@${DEST_IP}" "sudo cp /tmp/$ENV_FILE /etc/profile.d/$DEST_ENV_FILE && sudo chmod 755 /etc/profile.d/$DEST_ENV_FILE"

    # Create a script to update the system-wide environment and make sure it's loaded
    LOAD_ENV_SCRIPT=$(cat <<'EOF'
#!/bin/bash

# Source the environment file directly to make variables available now
source /etc/profile.d/__DEST_ENV_FILE__

# Export the environment variables to make them available to all shells
export $(grep -v '^#' /etc/profile.d/__DEST_ENV_FILE__ | cut -d= -f1)

# Verify that the environment file is sourced
echo "Environment variables from __DEST_ENV_FILE__ are now available:"
env | grep -E "^(HTTP_PROXY|HTTPS_PROXY|NO_PROXY|http_proxy|https_proxy|no_proxy)"
EOF
    )

    # Replace placeholder with actual value
    LOAD_ENV_SCRIPT=${LOAD_ENV_SCRIPT//__DEST_ENV_FILE__/$DEST_ENV_FILE}

    # Execute the environment loading script
    echo "Loading environment variables from $DEST_ENV_FILE..."
    echo "$LOAD_ENV_SCRIPT" | ssh -p "$DEST_PORT" "${DEST_USER}@${DEST_IP}" "bash -s"

    # Create the update script using a here-document.
    UPDATE_SCRIPT=$(cat <<'EOF'
#!/bin/bash

# Set variables (placeholders to be replaced locally)
SHOULD_USE_PROXY="__SHOULD_USE_PROXY__"
DEST_ENV_FILE="__DEST_ENV_FILE__"

echo "Setting proxy to: $SHOULD_USE_PROXY"

# Process the proxy settings in system*.edn files
for dir in $HOME/van-buren-*; do
    if [ -d "$dir" ]; then
        find "$dir" -name "system*.edn" | while read file; do
            echo "Processing: $file"
            
            if [ "$SHOULD_USE_PROXY" = "true" ]; then
                sed -i 's/\(:use-proxy?[[:space:]]*\)false/\1true/g' "$file"
                sed -i 's/\(Set-Proxy?[[:space:]]*\)false/\1true/g' "$file"
            else
                sed -i 's/\(:use-proxy?[[:space:]]*\)true/\1false/g' "$file"
                sed -i 's/\(Set-Proxy?[[:space:]]*\)true/\1false/g' "$file"
            fi
        done
    fi
done

# Ensure the environment file is sourced in multiple places for reliability

# 1. /etc/profile.d scripts are usually sourced automatically at login, but we'll make sure

# 2. Add to .bashrc if not already present
if ! grep -q "source /etc/profile.d/$DEST_ENV_FILE" $HOME/.bashrc; then
    echo "Adding source command to .bashrc"
    echo "source /etc/profile.d/$DEST_ENV_FILE" >> $HOME/.bashrc
fi

# 3. Add to .profile if not already present
if ! grep -q "source /etc/profile.d/$DEST_ENV_FILE" $HOME/.profile 2>/dev/null; then
    echo "Adding source command to .profile"
    echo "source /etc/profile.d/$DEST_ENV_FILE" >> $HOME/.profile
fi

echo "Environment and proxy settings updated."
EOF
    )

    # Replace placeholders with actual values.
    UPDATE_SCRIPT=${UPDATE_SCRIPT//__SHOULD_USE_PROXY__/$SHOULD_USE_PROXY}
    UPDATE_SCRIPT=${UPDATE_SCRIPT//__DEST_ENV_FILE__/$DEST_ENV_FILE}

    # Execute the update script on the remote server using standard input.
    echo "Updating proxy settings and configuring environment..."
    echo "$UPDATE_SCRIPT" | ssh -p "$DEST_PORT" "${DEST_USER}@${DEST_IP}" "bash -s"

    # Final verification that environment variables are set
    echo "Verifying environment variables are set correctly..."
    ssh -p "$DEST_PORT" "${DEST_USER}@${DEST_IP}" "source /etc/profile.d/$DEST_ENV_FILE && env | grep -E \"^(HTTP_PROXY|HTTPS_PROXY|NO_PROXY|http_proxy|https_proxy|no_proxy)\""

    echo "Operations completed successfully for $SELECTED_SERVER."
done

echo ""
echo "==============================================="
echo "All operations completed for all selected servers."
echo "NOTE: For the environment variables to be fully available in all new sessions, users may need to log out and log back in."
echo "==============================================="