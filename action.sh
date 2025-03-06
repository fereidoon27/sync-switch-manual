#!/bin/bash

# Log file setup
ACTION_LOG="$HOME/service_actions_$(date +%Y%m%d).log"

# Set directory paths
INFO_PATH="$(dirname "$0")/Info"
DEPLOYMENT_SCRIPTS_PATH="$(dirname "$0")/deployment_scripts"
SERVERS_CONF="$INFO_PATH/servers.conf"

# SSH Options
SSH_OPTS="-o StrictHostKeyChecking=no"

# Function for logging
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local action=$1
    local server=$2
    local status=$3
    local action_name=$4
    
    # Pad action name to ensure consistent column width (25 characters)
    local padded_action_name=$(printf "%-25s" "$action_name")
    
    if [[ "$status" == "Started" ]]; then
        echo "[$timestamp] ──▶ [Action $action] $padded_action_name | Server: %-15s | STATUS: $status" "$server" | tee -a "$ACTION_LOG"
    elif [[ "$status" == "Completed" ]]; then
        echo "[$timestamp] ✅  [Action $action] $padded_action_name | Server: %-15s | STATUS: $status" "$server" | tee -a "$ACTION_LOG"
    elif [[ "$status" == "Failed" ]]; then
        echo "[$timestamp] ❌  [Action $action] $padded_action_name | Server: %-15s | STATUS: $status" "$server" | tee -a "$ACTION_LOG"
    else
        echo "[$timestamp] $1" | tee -a "$ACTION_LOG"
    fi
}

# Log section headers
log_header() {
    local header_text=$1
    local header_width=60
    local line=$(printf '%*s' "$header_width" | tr ' ' '-')
    local header=$(printf "|%*s%s%*s|" $(( (header_width - 2 - ${#header_text}) / 2 )) "" "$header_text" $(( (header_width - 2 - ${#header_text} + 1) / 2 )) "")
    
    echo "" | tee -a "$ACTION_LOG"
    echo "$line" | tee -a "$ACTION_LOG"
    echo "$header" | tee -a "$ACTION_LOG"
    echo "$line" | tee -a "$ACTION_LOG"
    echo "" | tee -a "$ACTION_LOG"
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
        return 1
    fi
    
    # Split details into array
    IFS='|' read -r DATACENTER VM_NAME IP HOST USERNAME PORT <<< "$details"
    return 0
}

# Function to execute action
execute_action() {
    local action_num=$1
    local ssh_cmd=$2
    local target_path=$3
    local vm_info=$4
    
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
    
    log "$action_num" "$vm_info" "Started" "$action_name"
    
    # Check if the script exists locally
    if [ ! -f "$DEPLOYMENT_SCRIPTS_PATH/$action_script" ]; then
        log "$action_num" "$vm_info" "Failed" "$action_name"
        echo "ERROR: Script $action_script does not exist in $DEPLOYMENT_SCRIPTS_PATH"
        return 1
    fi
    
    # Create temp directory on remote machine if it doesn't exist
    $ssh_cmd "mkdir -p /tmp/deployment_scripts"
    
    # Copy the script to the remote machine
    scp $SSH_OPTS -P "$PORT" "$DEPLOYMENT_SCRIPTS_PATH/$action_script" "${USERNAME}@${HOST}:/tmp/deployment_scripts/"
    if [ $? -ne 0 ]; then
        log "$action_num" "$vm_info" "Failed" "$action_name"
        echo "ERROR: Failed to copy script to remote machine"
        return 1
    fi
    
    # Ensure the script is executable on the remote machine
    $ssh_cmd "chmod +x /tmp/deployment_scripts/$action_script"
    
    # Execute the script on the remote machine
    $ssh_cmd "cd $target_path && /tmp/deployment_scripts/$action_script"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log "$action_num" "$vm_info" "Completed" "$action_name"
    else
        log "$action_num" "$vm_info" "Failed" "$action_name"
        echo "ERROR: Action $action_num ($action_name) failed on $vm_info"
        return 1
    fi
}

# Process a single migration job
process_migration_job() {
    local job_number=$1
    local source_datacenter=$2
    local dest_datacenter=$3
    local source_vm_index=$4
    local source_vms=("${@:5}")
    
    # Log job header
    log_header "Service Transfer Operation - Job $job_number"
    
    # Get the source VM name
    SOURCE_VM=${source_vms[$source_vm_index]}
    
    # Get source VM details
    if ! get_server_details "$source_datacenter" "$SOURCE_VM"; then
        log "ERROR: Failed to get details for source VM $SOURCE_VM in $source_datacenter"
        return 1
    fi
    
    SOURCE_USER=$USERNAME
    SOURCE_IP=$IP
    SOURCE_HOST=$HOST
    SOURCE_PORT=$PORT
    SOURCE_PATH="/home/$USERNAME/"
    
    # Generate destination VM name by replacing the datacenter name in the VM name
    local source_vm_number=$(echo "$SOURCE_VM" | sed "s/.*\([0-9]\+\).*/\1/")
    DEST_VM="cr${source_vm_number}${dest_datacenter}"
    
    # Get destination VM details
    if ! get_server_details "$dest_datacenter" "$DEST_VM"; then
        log "ERROR: Failed to get details for destination VM $DEST_VM in $dest_datacenter"
        return 1
    fi
    
    DEST_USER=$USERNAME
    DEST_IP=$IP
    DEST_HOST=$HOST
    DEST_PORT=$PORT
    DEST_PATH="/home/$USERNAME/"
    
    # Build SSH connection strings
    SOURCE_SSH_CMD="ssh $SSH_OPTS -p $SOURCE_PORT $SOURCE_USER@$SOURCE_HOST"
    DEST_SSH_CMD="ssh $SSH_OPTS -p $DEST_PORT $DEST_USER@$DEST_HOST"
    
    echo -e "\nJob #$job_number Configuration:"
    echo "Source: $source_datacenter - $SOURCE_VM ($SOURCE_HOST)"
    echo "Destination: $dest_datacenter - $DEST_VM ($DEST_HOST)"
    
    # Execute actions on destination VM (deploy and start)
    echo -e "\nExecuting actions on Destination VM ($DEST_VM)..."
    for action in 1 2; do
        echo -e "Executing step $action on Destination VM"
        if ! execute_action $action "$DEST_SSH_CMD" "$DEST_PATH" "$DEST_VM"; then
            echo "Sequence failed at step $action on Destination VM"
            return 1
        fi
    done
    
    # 10-second pause between destination and source actions
    echo "Pausing for 10 seconds before proceeding to source VM actions..."
    sleep 10
    
    # Execute actions on source VM (stop and purge)
    echo -e "\nExecuting actions on Source VM ($SOURCE_VM)..."
    for action in 3 4; do
        echo -e "Executing step $action on Source VM"
        if ! execute_action $action "$SOURCE_SSH_CMD" "$SOURCE_PATH" "$SOURCE_VM"; then
            echo "Sequence failed at step $action on Source VM"
            return 1
        fi
    done
    
    echo -e "Job #$job_number completed successfully!\n"
    return 0
}

# Main script execution
main() {
    # Clear log file at the start
    > "$ACTION_LOG"
    
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

    # Display source VM options with "all" option
    echo "Available Source VMs:"
    for i in "${!SOURCE_VMS[@]}"; do
        echo "$((i+1)). ${SOURCE_VMS[i]}"
    done
    echo "$((${#SOURCE_VMS[@]}+1)). all"

    # Select source VMs (multiple selection or all)
    while true; do
        read -p "Select source VMs (enter digits without spaces, e.g. 614 for VMs 6, 1, and 4, or select 'all'): " source_vm_input
        
        # Check if user selected "all"
        if [[ $source_vm_input =~ ^[aA][lL][lL]$ ]] || [[ $source_vm_input -eq $((${#SOURCE_VMS[@]}+1)) ]]; then
            # Generate sequence for all VMs: "123456..." up to the number of VMs
            source_vm_choices=""
            for (( i=1; i<=${#SOURCE_VMS[@]}; i++ )); do
                source_vm_choices="${source_vm_choices}${i}"
            done
            break
        fi
        
        # Validate input - only digits allowed
        if [[ ! $source_vm_input =~ ^[1-9]+$ ]]; then
            echo "Invalid input. Please enter only digits corresponding to VM numbers."
            continue
        fi
        
        # Validate that all digits are valid VM indices
        local invalid_choice=false
        for (( i=0; i<${#source_vm_input}; i++ )); do
            local choice=${source_vm_input:$i:1}
            if [[ $choice -gt ${#SOURCE_VMS[@]} ]]; then
                echo "Invalid choice: $choice. Maximum is ${#SOURCE_VMS[@]}."
                invalid_choice=true
                break
            fi
        done
        
        if [ "$invalid_choice" = true ]; then
            continue
        fi
        
        source_vm_choices=$source_vm_input
        break
    done

    # Show configuration summary and get final approval
    echo -e "\nConfiguration Summary:"
    echo -n "Source: $SOURCE_DATACENTER - Server Order: ("
    for (( i=0; i<${#source_vm_choices}; i++ )); do
        local choice=${source_vm_choices:$i:1}
        local vm_index=$((choice-1))
        echo -n "$((i+1))- ${SOURCE_VMS[$vm_index]} "
    done
    echo ")"
    
    echo -n "Destination: $DEST_DATACENTER - Server Order: ("
    for (( i=0; i<${#source_vm_choices}; i++ )); do
        local choice=${source_vm_choices:$i:1}
        local vm_index=$((choice-1))
        
        # Extract VM number from source VM name
        local source_vm_number=$(echo "${SOURCE_VMS[$vm_index]}" | sed "s/.*\([0-9]\+\).*/\1/")
        local dest_vm="cr${source_vm_number}${DEST_DATACENTER}"
        
        echo -n "$((i+1))- ${dest_vm} "
    done
    echo ")"
    
    read -p "Continue? (y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        log "Operation cancelled by user"
        exit 0
    fi

    # Process migration jobs
    for (( i=0; i<${#source_vm_choices}; i++ )); do
        local choice=${source_vm_choices:$i:1}
        local vm_index=$((choice-1))
        local job_number=$((i+1))
        
        echo -e "\n======================================================="
        echo "Starting migration job #$job_number: ${SOURCE_VMS[$vm_index]}"
        echo "======================================================="
        
        if ! process_migration_job "$job_number" "$SOURCE_DATACENTER" "$DEST_DATACENTER" "$vm_index" "${SOURCE_VMS[@]}"; then
            echo "Migration job #$job_number failed!"
            log "Migration job #$job_number for VM ${SOURCE_VMS[$vm_index]} failed!"
            
            read -p "Continue with next VM? (y/n): " continue_choice
            if [[ $continue_choice != "y" && $continue_choice != "Y" ]]; then
                log "Operation cancelled by user after job #$job_number failure"
                exit 1
            fi
        fi
    done

    # Log completion
    log_header "All Service Transfer Operations Completed"
    
    echo -e "\nAll migration jobs completed!"
    echo "Action log: $ACTION_LOG"
}

# Run the main script
main