#!/bin/bash

# Log file setup
ACTION_LOG="$HOME/service_actions_$(date +%Y%m%d).log"
TIMESTAMP_LOG="$HOME/service_timestamps_$(date +%Y%m%d).log"

# Set directory paths
INFO_PATH="$(dirname "$0")/Info"
DEPLOYMENT_SCRIPTS_PATH="$(dirname "$0")/deployment_scripts"

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

# Function to load defaults from file
load_defaults() {
    local file=$1
    if [ -f "$file" ]; then
        log "Loading defaults from $file"
        source "$file"
    else
        log "WARNING: Default file $file not found"
    fi
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
            description="Run 111-ACTION-deploy-services.sh in all van-buren directories"
            ;;
        2)
            action_script="start_all.sh"
            action_name="Start All Services"
            description="Run 222-ACTION-start-services.sh in all van-buren directories"
            ;;
        3)
            action_script="stop_all.sh"
            action_name="Stop All Services"
            description="Run 000-ACTION-stop-services.sh in all van-buren directories"
            ;;
        4)
            action_script="purge_all.sh"
            action_name="Purge All Services"
            description="Run 999-ACTION-purge-services.sh in all van-buren directories"
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
    
    # Check if the script is executable locally
    if [ ! -x "$DEPLOYMENT_SCRIPTS_PATH/$action_script" ]; then
        log "ERROR: Script $action_script is not executable"
        return 1
    fi
    
    # Create temp directory on remote machine if it doesn't exist
    $ssh_cmd "mkdir -p /tmp/deployment_scripts"
    
    # Copy the script to the remote machine
    log "Copying $action_script to remote machine..."
    scp -P "${target_port}" "$DEPLOYMENT_SCRIPTS_PATH/$action_script" "${target_user}@${target_ip}:/tmp/deployment_scripts/"
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to copy script to remote machine"
        return 1
    fi
    
    # Ensure the script is executable on the remote machine
    $ssh_cmd "chmod +x /tmp/deployment_scripts/$action_script"
    
    # Execute the script on the remote machine
    log "Executing $action_script on remote machine..."
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

# Load default values
load_defaults "$INFO_PATH/Info_Dest.txt"
load_defaults "$INFO_PATH/Info_Source.txt"

# Get source VM details with defaults
echo -e "\n--- SOURCE VM CONFIGURATION ---"
read -p "Enter source VM username [$SOURCE_USER]: " input_source_user
SOURCE_USER=${input_source_user:-$SOURCE_USER}

read -p "Enter source VM IP [$SOURCE_IP]: " input_source_ip
SOURCE_IP=${input_source_ip:-$SOURCE_IP}

read -p "Enter source VM SSH port [$SOURCE_PORT]: " input_source_port
SOURCE_PORT=${input_source_port:-$SOURCE_PORT}

read -p "Enter source VM path [$SOURCE_PATH]: " input_source_path
SOURCE_PATH=${input_source_path:-$SOURCE_PATH}

# Get destination VM details with defaults
echo -e "\n--- DESTINATION VM CONFIGURATION ---"
read -p "Enter destination VM username [$DEST_USER]: " input_dest_user
DEST_USER=${input_dest_user:-$DEST_USER}

read -p "Enter destination VM IP [$DEST_IP]: " input_dest_ip
DEST_IP=${input_dest_ip:-$DEST_IP}

read -p "Enter destination VM SSH port [$DEST_PORT]: " input_dest_port
DEST_PORT=${input_dest_port:-$DEST_PORT}

read -p "Enter destination VM path [$DEST_PATH]: " input_dest_path
DEST_PATH=${input_dest_path:-$DEST_PATH}

# Build SSH connection strings
SOURCE_SSH_CMD="ssh -p $SOURCE_PORT $SOURCE_USER@$SOURCE_IP"
DEST_SSH_CMD="ssh -p $DEST_PORT $DEST_USER@$DEST_IP"

# Choose which VM to operate on
echo -e "\n--- SELECT TARGET VM FOR OPERATIONS ---"
echo "1: Source VM ($SOURCE_USER@$SOURCE_IP:$SOURCE_PORT)"
echo "2: Destination VM ($DEST_USER@$DEST_IP:$DEST_PORT)"

while true; do
    read -p "Select VM (1 or 2): " vm_choice
    if [[ "$vm_choice" == "1" ]]; then
        ACTIVE_SSH_CMD="$SOURCE_SSH_CMD"
        ACTIVE_PATH="$SOURCE_PATH"
        ACTIVE_VM_NAME="Source VM"
        target_user="$SOURCE_USER"
        target_ip="$SOURCE_IP"
        target_port="$SOURCE_PORT"
        break
    elif [[ "$vm_choice" == "2" ]]; then
        ACTIVE_SSH_CMD="$DEST_SSH_CMD"
        ACTIVE_PATH="$DEST_PATH"
        ACTIVE_VM_NAME="Destination VM"
        target_user="$DEST_USER"
        target_ip="$DEST_IP"
        target_port="$DEST_PORT"
        break
    else
        echo "Invalid choice. Please enter 1 or 2."
    fi
done

# Test SSH connection
log "Testing SSH connection to $ACTIVE_VM_NAME..."
if ! $ACTIVE_SSH_CMD "exit" > /dev/null 2>&1; then
    log "ERROR: Cannot connect to $ACTIVE_VM_NAME"
    echo "ERROR: Cannot connect to $ACTIVE_VM_NAME"
    exit 1
fi

# Check if folder exists
if ! $ACTIVE_SSH_CMD "[ -d $ACTIVE_PATH ]"; then
    log "ERROR: Folder '$ACTIVE_PATH' does not exist on $ACTIVE_VM_NAME"
    echo "ERROR: Folder '$ACTIVE_PATH' does not exist on $ACTIVE_VM_NAME"
    exit 1
fi

# Display available actions
echo -e "\nAvailable actions:"
echo "1: Deploy All Services - Runs deploy_all.sh"
echo "   (Executes 111-ACTION-deploy-services.sh in all van-buren directories)"
echo "2: Start All Services - Runs start_all.sh"
echo "   (Executes 222-ACTION-start-services.sh in all van-buren directories)"
echo "3: Stop All Services - Runs stop_all.sh"
echo "   (Executes 000-ACTION-stop-services.sh in all van-buren directories)"
echo "4: Purge All Services - Runs purge_all.sh"
echo "   (Executes 999-ACTION-purge-services.sh in all van-buren directories)"

# Get sequence of actions
while true; do
    read -p "Enter sequence of actions (2-4 digits, e.g., 12 or 1234): " sequence
    if [[ ! $sequence =~ ^[1-4]{2,4}$ ]]; then
        echo "Error: Please enter 2-4 digits, using only numbers 1-4"
        continue
    fi
    break
done

# Confirm sequence
echo -e "\nYou entered sequence: $sequence"
echo "This will execute the following actions on $ACTIVE_VM_NAME:"
for (( i=0; i<${#sequence}; i++ )); do
    action_num=${sequence:$i:1}
    case $action_num in
        1) echo "$(($i+1)). Deploy All Services" ;;
        2) echo "$(($i+1)). Start All Services" ;;
        3) echo "$(($i+1)). Stop All Services" ;;
        4) echo "$(($i+1)). Purge All Services" ;;
    esac
done

read -p "Continue? (y/n): " confirm
if [[ $confirm != "y" ]]; then
    log "Sequence cancelled by user"
    exit 0
fi

# Execute sequence
echo -e "\nExecuting sequence on $ACTIVE_VM_NAME..."
for (( i=0; i<${#sequence}; i++ )); do
    action_num=${sequence:$i:1}
    echo -e "\nExecuting step $(($i+1)) of ${#sequence}: Action $action_num"
    if ! execute_action $action_num "$ACTIVE_SSH_CMD" "$ACTIVE_PATH"; then
        echo "Sequence failed at step $(($i+1))"
        exit 1
    fi
done

echo -e "\nSequence completed successfully on $ACTIVE_VM_NAME!"
echo "Timestamp log: $TIMESTAMP_LOG"
echo "Action log: $ACTION_LOG"