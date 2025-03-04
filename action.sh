#!/bin/bash

# Log file setup
ACTION_LOG="$HOME/service_actions_$(date +%Y%m%d).log"
TIMESTAMP_LOG="$HOME/service_timestamps_$(date +%Y%m%d).log"

# Set directory paths
INFO_PATH="$(dirname "$0")/Info"
DEPLOYMENT_SCRIPTS_PATH="$(dirname "$0")/deployment_scripts"
SERVERS_CONF="$INFO_PATH/servers.conf"

# Function for logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ACTION_LOG"
}

# Function for timestamp logging
log_timestamp() {
    local action=$1
    local status=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Action $action: $status" >> "$TIMESTAMP_LOG"
}

# Function to parse servers configuration
parse_servers_config() {
    if [ ! -f "$SERVERS_CONF" ]; then
        log "ERROR: Servers configuration file not found at $SERVERS_CONF"
        exit 1
    fi
    
    # Extract unique datacenters
    DATACENTERS=($(awk -F'|' '{print $1}' "$SERVERS_CONF" | sort | uniq))
}

# Function to get VM names for a specific datacenter
get_datacenter_vms() {
    local datacenter=$1
    awk -F'|' -v dc="$datacenter" '$1 == dc {print $2}' "$SERVERS_CONF"
}

# Function to get server details
get_server_details() {
    local datacenter=$1
    local vm_name=$2
    
    local details=$(awk -F'|' -v dc="$datacenter" -v vm="$vm_name" '$1 == dc && $2 == vm {print $0}' "$SERVERS_CONF")
    
    if [ -z "$details" ]; then
        log "ERROR: No details found for $datacenter $vm_name"
        exit 1
    fi
    
    # Split details into array
    IFS='|' read -r DATACENTER VM_NAME IP HOST USERNAME PORT <<< "$details"
}

# Function to execute action
execute_action() {
    local action_num=$1
    local ssh_cmd=$2
    local target_path=$3
    
    case $action_num in
        1)
            action_script="deploy_all.sh"
            action_name="Deploy All Services"
            ;;
        2)
            action_script="start_all.sh"
            action_name="Start All Services"
            ;;
        3)
            action_script="stop_all.sh"
            action_name="Stop All Services"
            ;;
        4)
            action_script="purge_all.sh"
            action_name="Purge All Services"
            ;;
        *)
            log "ERROR: Invalid action number: $action_num"
            return 1
            ;;
    esac
    
    log "Starting action $action_num: $action_name"
    log_timestamp "$action_name" "Started"
    
    # Check if the script exists locally
    if [ ! -f "$DEPLOYMENT_SCRIPTS_PATH/$action_script" ]; then
        log "ERROR: Script $action_script does not exist in $DEPLOYMENT_SCRIPTS_PATH"
        return 1
    fi
    
    # Create temp directory on remote machine if it doesn't exist
    $ssh_cmd "mkdir -p /tmp/deployment_scripts"
    
    # Copy the script to the remote machine
    scp -P "$PORT" "$DEPLOYMENT_SCRIPTS_PATH/$action_script" "${USERNAME}@${HOST}:/tmp/deployment_scripts/"
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to copy script to remote machine"
        return 1
    fi
    
    # Ensure the script is executable on the remote machine
    $ssh_cmd "chmod +x /tmp/deployment_scripts/$action_script"
    
    # Execute the script on the remote machine
    $ssh_cmd "cd $target_path && /tmp/deployment_scripts/$action_script"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log "Action $action_num ($action_name) completed successfully"
        log_timestamp "$action_name" "Completed"
    else
        log "ERROR: Action $action_num ($action_name) failed"
        log_timestamp "$action_name" "Failed"
        return 1
    fi
}

# Main script execution
main() {
    # Parse servers configuration and get datacenters
    parse_servers_config

    # Display datacenter options
    echo "Available Datacenters:"
    for i in "${!DATACENTERS[@]}"; do
        echo "$((i+1)). ${DATACENTERS[i]}"
    done

    # Select source datacenter
    while true; do
        read -p "Select source datacenter (1-${#DATACENTERS[@]}): " source_dc_choice
        if [[ $source_dc_choice =~ ^[1-${#DATACENTERS[@]}]$ ]]; then
            SOURCE_DATACENTER=${DATACENTERS[$((source_dc_choice-1))]}
            break
        else
            echo "Invalid choice. Please try again."
        fi
    done

    # Select destination datacenter
    while true; do
        read -p "Select destination datacenter (1-${#DATACENTERS[@]}): " dest_dc_choice
        if [[ $dest_dc_choice =~ ^[1-${#DATACENTERS[@]}]$ ]]; then
            DEST_DATACENTER=${DATACENTERS[$((dest_dc_choice-1))]}
            # Ensure destination is different from source
            if [ "$DEST_DATACENTER" != "$SOURCE_DATACENTER" ]; then
                break
            else
                echo "Destination datacenter must be different from source. Please try again."
            fi
        else
            echo "Invalid choice. Please try again."
        fi
    done

    # Get VMs for source datacenter
    SOURCE_VMS=($(get_datacenter_vms "$SOURCE_DATACENTER"))

    # Display source VM options
    echo "Available Source VMs:"
    for i in "${!SOURCE_VMS[@]}"; do
        echo "$((i+1)). ${SOURCE_VMS[i]}"
    done

    # Select source VM
    while true; do
        read -p "Select source VM (1-${#SOURCE_VMS[@]}): " source_vm_choice
        if [[ $source_vm_choice =~ ^[1-${#SOURCE_VMS[@]}]$ ]]; then
            SOURCE_VM=${SOURCE_VMS[$((source_vm_choice-1))]}
            break
        else
            echo "Invalid choice. Please try again."
        fi
    done

    # Get source VM details
    get_server_details "$SOURCE_DATACENTER" "$SOURCE_VM"
    SOURCE_USER=$USERNAME
    SOURCE_IP=$IP
    SOURCE_HOST=$HOST
    SOURCE_PORT=$PORT
    SOURCE_PATH="/home/$USERNAME/"

    # Find matching VM in destination datacenter
    # Replace the datacenter name in the source VM name to match destination
    DEST_VM=$(echo "$SOURCE_VM" | sed "s/$SOURCE_DATACENTER/$DEST_DATACENTER/")

    # Get destination VM details
    get_server_details "$DEST_DATACENTER" "$DEST_VM"
    DEST_USER=$USERNAME
    DEST_IP=$IP
    DEST_HOST=$HOST
    DEST_PORT=$PORT
    DEST_PATH="/home/$USERNAME/"

    # Build SSH connection strings
    SOURCE_SSH_CMD="ssh -p $SOURCE_PORT $SOURCE_USER@$SOURCE_HOST"
    DEST_SSH_CMD="ssh -p $DEST_PORT $DEST_USER@$DEST_HOST"

    # Confirm configuration
    echo -e "\nConfiguration Summary:"
    echo "Source: $SOURCE_DATACENTER - $SOURCE_VM ($SOURCE_HOST)"
    echo "Destination: $DEST_DATACENTER - $DEST_VM ($DEST_HOST)"
    read -p "Continue? (y/n): " confirm
    if [[ $confirm != "y" ]]; then
        log "Operation cancelled by user"
        exit 0
    fi

    # Execute actions on destination VM (deploy and start)
    echo -e "\nExecuting actions on Destination VM..."
    for action in 1 2; do
        echo -e "\nExecuting step $action on Destination VM"
        if ! execute_action $action "$DEST_SSH_CMD" "$DEST_PATH"; then
            echo "Sequence failed at step $action on Destination VM"
            exit 1
        fi
    done

    # Execute actions on source VM (stop and purge)
    echo -e "\nExecuting actions on Source VM..."
    for action in 3 4; do
        echo -e "\nExecuting step $action on Source VM"
        if ! execute_action $action "$SOURCE_SSH_CMD" "$SOURCE_PATH"; then
            echo "Sequence failed at step $action on Source VM"
            exit 1
        fi
    done

    echo -e "\nAll operations completed successfully!"
    echo "Timestamp log: $TIMESTAMP_LOG"
    echo "Action log: $ACTION_LOG"
}

# Run the main script
main