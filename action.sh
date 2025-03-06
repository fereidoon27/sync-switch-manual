#!/bin/bash

# Log file setup
ACTION_LOG="$HOME/service_actions_$(date +%Y%m%d).log"

# Set directory paths
INFO_PATH="$(dirname "$0")/Info"
DEPLOYMENT_SCRIPTS_PATH="$(dirname "$0")/deployment_scripts"
SERVERS_CONF="$INFO_PATH/servers.conf"

# SSH connection optimization
SSH_CONTROL_PATH="/tmp/ssh_mux_%h_%p_%r"
SSH_MUX_OPTS="-o ControlMaster=auto -o ControlPath=$SSH_CONTROL_PATH -o ControlPersist=1h"
SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15 $SSH_MUX_OPTS"

# Temporary dir for remote scripts
REMOTE_TMP_DIR="/tmp/deployment_scripts"

# Function for logging
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local action=$1
    local server=$2
    local status=$3
    local action_name=$4
    
    # Use a fixed-format template with tab-like spacing
    if [[ -n "$status" ]]; then
        local icon="   "
        if [[ "$status" == "Started" ]]; then
            icon="──▶"
        elif [[ "$status" == "Completed" ]]; then
            icon="✅ "
        elif [[ "$status" == "Failed" ]]; then
            icon="❌ "
        fi
        
        # Format timestamp
        local timestamp_field="[$timestamp]"
        
        # Format action field - ALWAYS exactly 30 characters wide regardless of content
        local action_field
        action_field=$(printf "[Action %s]" "$action")
        action_field=$(printf "%-30s" "$action_field")
        
        # Format action name field - ALWAYS exactly 20 characters
        local action_name_field=$(printf "%-20s" "$action_name")
        
        # Format server field - ALWAYS exactly 15 characters
        local server_field=$(printf "%-15s" "$server")
        
        # Fixed format that ensures perfect alignment for all fields
        echo "$timestamp_field $icon $action_field $action_name_field | Server: $server_field | STATUS: $status" | tee -a "$ACTION_LOG"
    else
        # Simple log line for messages without structured format
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

# Function to establish SSH connection (open multiplexed connection)
setup_ssh_connection() {
    local user=$1
    local host=$2
    local port=$3
    local vm_name=$4
    
    # Check if connection is already established
    ssh -O check $SSH_MUX_OPTS -p $port $user@$host 2>/dev/null
    if [ $? -ne 0 ]; then
        log "Setting up SSH connection" "$vm_name" "Started" "SSH Connection"
        # Create a background connection that will persist
        ssh $SSH_OPTS -p $port -M -f -N $user@$host
        if [ $? -ne 0 ]; then
            log "Setting up SSH connection" "$vm_name" "Failed" "SSH Connection"
            return 1
        fi
        log "Setting up SSH connection" "$vm_name" "Completed" "SSH Connection"
    fi
    return 0
}

# Function to close SSH connection
close_ssh_connection() {
    local user=$1
    local host=$2
    local port=$3
    local vm_name=$4
    
    log "Closing SSH connection" "$vm_name" "Started" "SSH Connection"
    ssh -O exit $SSH_MUX_OPTS -p $port $user@$host 2>/dev/null
    log "Closing SSH connection" "$vm_name" "Completed" "SSH Connection"
}

# Function to copy all deployment scripts at once
copy_deployment_scripts() {
    local user=$1
    local host=$2
    local port=$3
    local vm_name=$4
    
    # Create remote tmp directory in one shot
    ssh $SSH_OPTS -p $port $user@$host "mkdir -p $REMOTE_TMP_DIR"
    if [ $? -ne 0 ]; then
        log "Create remote directory" "$vm_name" "Failed" "Copy Scripts"
        return 1
    fi
    
    # Copy all deployment scripts at once (faster than individual copies)
    log "Copying deployment scripts" "$vm_name" "Started" "Copy Scripts"
    tar -cf - -C $DEPLOYMENT_SCRIPTS_PATH . | ssh $SSH_OPTS -p $port $user@$host "tar -xf - -C $REMOTE_TMP_DIR && chmod +x $REMOTE_TMP_DIR/*.sh"
    if [ $? -ne 0 ]; then
        log "Copying deployment scripts" "$vm_name" "Failed" "Copy Scripts"
        return 1
    fi
    log "Copying deployment scripts" "$vm_name" "Completed" "Copy Scripts"
    
    return 0
}

# Function to execute action with optimized SSH connection
execute_action() {
    local action_num=$1
    local user=$2
    local host=$3
    local port=$4
    local target_path=$5
    local vm_name=$6
    
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
    
    log "$action_num" "$vm_name" "Started" "$action_name"
    
    # Execute the script on the remote machine (reusing connection)
    ssh $SSH_OPTS -p $port $user@$host "cd $target_path && $REMOTE_TMP_DIR/$action_script"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log "$action_num" "$vm_name" "Completed" "$action_name"
    else
        log "$action_num" "$vm_name" "Failed" "$action_name"
        echo "ERROR: Action $action_num ($action_name) failed on $vm_name"
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
    
    echo -e "\nJob #$job_number Configuration:"
    echo "Source: $source_datacenter - $SOURCE_VM ($SOURCE_HOST)"
    echo "Destination: $dest_datacenter - $DEST_VM ($DEST_HOST)"
    
    # Setup SSH connections once for both source and destination
    setup_ssh_connection "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_VM"
    setup_ssh_connection "$DEST_USER" "$DEST_HOST" "$DEST_PORT" "$DEST_VM"
    
    # Copy all deployment scripts to both servers at once
    copy_deployment_scripts "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_VM"
    copy_deployment_scripts "$DEST_USER" "$DEST_HOST" "$DEST_PORT" "$DEST_VM"
    
    # Execute actions on destination VM (deploy and start)
    echo -e "\nExecuting actions on Destination VM ($DEST_VM)..."
    local dest_success=true
    for action in 1 2; do
        echo -e "Executing step $action on Destination VM"
        if ! execute_action $action "$DEST_USER" "$DEST_HOST" "$DEST_PORT" "$DEST_PATH" "$DEST_VM"; then
            echo "Sequence failed at step $action on Destination VM"
            dest_success=false
            break
        fi
    done
    
    # Only continue to source VM actions if destination was successful
    if $dest_success; then
        # 10-second pause between destination and source actions
        echo "Pausing for 10 seconds before proceeding to source VM actions..."
        sleep 10
        
        # Execute actions on source VM (stop and purge)
        echo -e "\nExecuting actions on Source VM ($SOURCE_VM)..."
        for action in 3 4; do
            echo -e "Executing step $action on Source VM"
            if ! execute_action $action "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_PATH" "$SOURCE_VM"; then
                echo "Sequence failed at step $action on Source VM"
                dest_success=false
                break
            fi
        done
    fi
    
    # Close SSH connections
    close_ssh_connection "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_VM"
    close_ssh_connection "$DEST_USER" "$DEST_HOST" "$DEST_PORT" "$DEST_VM"
    
    if $dest_success; then
        echo -e "Job #$job_number completed successfully!\n"
        return 0
    else
        echo -e "Job #$job_number failed!\n"
        return 1
    fi
}

# Process multiple migration jobs in parallel
process_parallel_jobs() {
    local source_datacenter=$1
    local dest_datacenter=$2
    local source_vm_choices=$3
    local source_vms=("${@:4}")
    local max_parallel_jobs=${MAX_PARALLEL_JOBS:-2}  # Default to 2 parallel jobs
    
    local active_jobs=0
    local job_pids=()
    local job_numbers=()
    
    for (( i=0; i<${#source_vm_choices}; i++ )); do
        local choice=${source_vm_choices:$i:1}
        local vm_index=$((choice-1))
        local job_number=$((i+1))
        
        echo -e "\n======================================================="
        echo "Starting migration job #$job_number: ${source_vms[$vm_index]}"
        echo "======================================================="
        
        # Run the job in background
        (process_migration_job "$job_number" "$source_datacenter" "$dest_datacenter" "$vm_index" "${source_vms[@]}") &
        local pid=$!
        job_pids+=($pid)
        job_numbers+=($job_number)
        active_jobs=$((active_jobs+1))
        
        # Wait if we've reached the maximum number of parallel jobs
        if [[ $active_jobs -ge $max_parallel_jobs ]]; then
            # Wait for any job to finish
            wait -n
            
            # Update active jobs count
            for (( j=0; j<${#job_pids[@]}; j++ )); do
                if ! kill -0 ${job_pids[$j]} 2>/dev/null; then
                    # Check if job was successful
                    wait ${job_pids[$j]}
                    local status=$?
                    
                    if [[ $status -ne 0 ]]; then
                        echo "Migration job #${job_numbers[$j]} failed!"
                        log "Migration job #${job_numbers[$j]} failed!"
                        
                        read -p "Continue with remaining jobs? (y/n): " continue_choice
                        if [[ $continue_choice != "y" && $continue_choice != "Y" ]]; then
                            log "Operation cancelled by user after job #${job_numbers[$j]} failure"
                            
                            # Kill all remaining jobs
                            for pid in "${job_pids[@]}"; do
                                kill $pid 2>/dev/null
                            done
                            
                            return 1
                        fi
                    fi
                    
                    # Remove this job from tracking arrays
                    unset job_pids[$j]
                    unset job_numbers[$j]
                    job_pids=("${job_pids[@]}")
                    job_numbers=("${job_numbers[@]}")
                    
                    active_jobs=$((active_jobs-1))
                    break
                fi
            done
        fi
    done
    
    # Wait for all remaining jobs to finish
    for (( j=0; j<${#job_pids[@]}; j++ )); do
        wait ${job_pids[$j]}
        local status=$?
        
        if [[ $status -ne 0 ]]; then
            echo "Migration job #${job_numbers[$j]} failed!"
            log "Migration job #${job_numbers[$j]} failed!"
        fi
    done
    
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
    
    # Ask for parallel job count
    read -p "Enter maximum number of parallel jobs [2]: " MAX_PARALLEL_JOBS
    MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS:-2}  # Default to 2 if empty
    
    # Validate input for parallel jobs
    if [[ ! $MAX_PARALLEL_JOBS =~ ^[1-9][0-9]*$ ]]; then
        echo "Invalid input. Using default value of 2 parallel jobs."
        MAX_PARALLEL_JOBS=2
    fi

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
    
    echo "Maximum parallel jobs: $MAX_PARALLEL_JOBS"
    
    read -p "Continue? (y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        log "Operation cancelled by user"
        exit 0
    fi

    # Process migration jobs in parallel
    process_parallel_jobs "$SOURCE_DATACENTER" "$DEST_DATACENTER" "$source_vm_choices" "${SOURCE_VMS[@]}"

    # Log completion
    log_header "All Service Transfer Operations Completed"
    
    echo -e "\nAll migration jobs completed!"
    echo "Action log: $ACTION_LOG"
}

# Run the main script
main