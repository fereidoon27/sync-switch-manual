#!/bin/bash

# Get script directory for finding config file
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INFO_PATH="$(dirname "$0")/Info"
SERVERS_CONF="$INFO_PATH/servers.conf"

# Log file setup
LOG_FILE="$HOME/sync_$(date +%Y%m%d).log"

# Function for logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if servers.conf exists
if [ ! -f "$SERVERS_CONF" ]; then
    log "ERROR: Configuration file $SERVERS_CONF not found"
    exit 1
fi

# Function to get unique datacenters from servers.conf
get_datacenters() {
    awk -F'|' '{print $1}' "$SERVERS_CONF" | sort -u
}

# Function to get VMs for a specific datacenter
get_vms_for_datacenter() {
    local datacenter="$1"
    awk -F'|' -v dc="$datacenter" '$1 == dc {print $2}' "$SERVERS_CONF"
}

# Function to get server info from servers.conf
get_server_info() {
    local datacenter="$1"
    local vm_name="$2"
    local field="$3"
    
    # Field mapping: 1=datacenter, 2=vm_name, 3=ip, 4=host, 5=username, 6=port
    local field_num
    case "$field" in
        "ip") field_num=3 ;;
        "host") field_num=4 ;;
        "username") field_num=5 ;;
        "port") field_num=6 ;;
        *) field_num=0 ;;
    esac
    
    if [ "$field_num" -eq 0 ]; then
        echo "unknown"
        return
    fi
    
    awk -F'|' -v dc="$datacenter" -v vm="$vm_name" -v fn="$field_num" \
        '$1 == dc && $2 == vm {print $fn}' "$SERVERS_CONF"
}

# Function to handle transfer failures
handle_failure() {
    local stage="$1"
    log "ERROR: Failed during $stage"
    [ -f "$PATTERN_FILE" ] && rm -f "$PATTERN_FILE"
    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
    
    # Close any persistent SSH connections
    for socket in /tmp/ssh-*-*; do
        if [ -S "$socket" ]; then
            ssh -O exit -o "ControlPath=$socket" 2>/dev/null
        fi
    done
    
    exit 1
}

# Setup SSH master connection for connection reuse
setup_ssh_master() {
    local user=$1
    local host=$2
    local port=$3
    local socket="/tmp/ssh-${user}-${host}-${port}"
    
    log "Setting up connection to $user@$host:$port..."
    ssh -M -o "ControlMaster=yes" -o "ControlPath=$socket" -o "ControlPersist=yes" \
        -o ConnectTimeout=10 -p $port "$user@$host" "echo Connection established" > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        log "ERROR: Cannot connect to $user@$host:$port"
        return 1
    else
        log "Connection to $user@$host:$port established"
        return 0
    fi
}

# Execute SSH command using control master
ssh_cmd() {
    local user=$1
    local host=$2
    local port=$3
    local cmd=$4
    local socket="/tmp/ssh-${user}-${host}-${port}"
    
    ssh -o "ControlPath=$socket" -p $port "$user@$host" "$cmd"
}

# First, ask for transfer type
echo "Transfer options:"
echo "1. VM to VM transfer"
echo "2. Main machine to VM transfer"
echo "3. VM to Main machine transfer"
read -p "Choose a transfer type (1-3): " TRANSFER_TYPE
TRANSFER_TYPE=${TRANSFER_TYPE:-1}

case $TRANSFER_TYPE in
    1) # VM to VM transfer
        # Get unique datacenters
        DATACENTERS=($(get_datacenters))

        # Display datacenter options for source
        echo "Available datacenters:"
        for i in "${!DATACENTERS[@]}"; do
            echo "$((i+1)). ${DATACENTERS[$i]}"
        done

        # Get source datacenter
        while true; do
            read -p "Choose source datacenter (1-${#DATACENTERS[@]}): " SRC_DC_CHOICE
            if [[ "$SRC_DC_CHOICE" =~ ^[0-9]+$ ]] && [ "$SRC_DC_CHOICE" -ge 1 ] && [ "$SRC_DC_CHOICE" -le "${#DATACENTERS[@]}" ]; then
                SOURCE_DATACENTER="${DATACENTERS[$((SRC_DC_CHOICE-1))]}"
                break
            fi
            echo "Invalid selection. Please try again."
        done

        # Get destination datacenter
        while true; do
            read -p "Choose destination datacenter (1-${#DATACENTERS[@]}): " DST_DC_CHOICE
            if [[ "$DST_DC_CHOICE" =~ ^[0-9]+$ ]] && [ "$DST_DC_CHOICE" -ge 1 ] && [ "$DST_DC_CHOICE" -le "${#DATACENTERS[@]}" ]; then
                DEST_DATACENTER="${DATACENTERS[$((DST_DC_CHOICE-1))]}"
                break
            fi
            echo "Invalid selection. Please try again."
        done

        # Get VMs for source datacenter
        SOURCE_VMS=($(get_vms_for_datacenter "$SOURCE_DATACENTER"))

        # Display VM options for source
        echo "Available VMs in $SOURCE_DATACENTER datacenter:"
        for i in "${!SOURCE_VMS[@]}"; do
            echo "$((i+1)). ${SOURCE_VMS[$i]}"
        done

        # Get source VM
        while true; do
            read -p "Choose source VM (1-${#SOURCE_VMS[@]}): " SRC_VM_CHOICE
            if [[ "$SRC_VM_CHOICE" =~ ^[0-9]+$ ]] && [ "$SRC_VM_CHOICE" -ge 1 ] && [ "$SRC_VM_CHOICE" -le "${#SOURCE_VMS[@]}" ]; then
                SOURCE_VM="${SOURCE_VMS[$((SRC_VM_CHOICE-1))]}"
                break
            fi
            echo "Invalid selection. Please try again."
        done

        # Get VMs for destination datacenter
        DEST_VMS=($(get_vms_for_datacenter "$DEST_DATACENTER"))

        # Display VM options for destination
        echo "Available VMs in $DEST_DATACENTER datacenter:"
        for i in "${!DEST_VMS[@]}"; do
            echo "$((i+1)). ${DEST_VMS[$i]}"
        done

        # Get destination VM
        while true; do
            read -p "Choose destination VM (1-${#DEST_VMS[@]}): " DST_VM_CHOICE
            if [[ "$DST_VM_CHOICE" =~ ^[0-9]+$ ]] && [ "$DST_VM_CHOICE" -ge 1 ] && [ "$DST_VM_CHOICE" -le "${#DEST_VMS[@]}" ]; then
                DEST_VM="${DEST_VMS[$((DST_VM_CHOICE-1))]}"
                break
            fi
            echo "Invalid selection. Please try again."
        done

        # Set connection parameters
        SOURCE_USER=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "username")
        SOURCE_HOST=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "host")
        SOURCE_IP=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "ip")
        SOURCE_PORT=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "port")
        SOURCE_PATH="/home/$SOURCE_USER/"

        DEST_USER=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "username")
        DEST_HOST=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "host")
        DEST_IP=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "ip")
        DEST_PORT=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "port")
        DEST_PATH="/home/$DEST_USER/"

        # Display summary and confirm
        echo -e "\nConfiguration Summary:"
        echo "Source: $SOURCE_DATACENTER - Server: $SOURCE_VM ($SOURCE_HOST)"
        echo "Destination: $DEST_DATACENTER - Server: $DEST_VM ($DEST_HOST)"
        read -p "Continue? (y/n): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            log "Operation canceled by user"
            exit 0
        fi

        # Display VM-to-VM transfer options
        echo -e "\nVM-to-VM Transfer options:"
        echo "1. Transfer a specific file or folder from source VM to destination VM"
        echo "2. Transfer specific files/folders from home directory based on patterns"
        echo "   (van-buren-* directories, .sh files, .secret/ folder)"
        read -p "Choose an option (1-2) [1]: " VM_TRANSFER_OPTION
        VM_TRANSFER_OPTION=${VM_TRANSFER_OPTION:-1}

        # Setup SSH master connections for connection reuse
        log "Setting up persistent SSH connections to minimize connection overhead..."
        if ! setup_ssh_master "$SOURCE_USER" "$SOURCE_IP" "$SOURCE_PORT"; then
            handle_failure "setting up source SSH connection"
        fi
        
        if ! setup_ssh_master "$DEST_USER" "$DEST_IP" "$DEST_PORT"; then
            handle_failure "setting up destination SSH connection"
        fi
        
        # Get source home directory once and reuse
        SOURCE_HOME=$(ssh_cmd "$SOURCE_USER" "$SOURCE_IP" "$SOURCE_PORT" "echo \$HOME")
        log "Source home directory: $SOURCE_HOME"
        
        # Prepare rsync options - optimized for speed
        RSYNC_OPTS="-az --compress --compress-level=9 --partial --progress"
        
        # Case for VM-to-VM transfer options
        case $VM_TRANSFER_OPTION in
            1) # Transfer specific file/folder
                read -p "Enter the path to the specific file or folder on source VM: " SOURCE_PATH
                # Replace tilde with actual home directory if present
                SOURCE_PATH=${SOURCE_PATH/#\~/$SOURCE_HOME}
                
                # Get directory information and path type in a single SSH call to minimize connections
                PATH_INFO=$(ssh_cmd "$SOURCE_USER" "$SOURCE_IP" "$SOURCE_PORT" "if [ -d \"$SOURCE_PATH\" ]; then echo 'DIR'; else echo 'FILE'; fi")
                IS_DIR=$([ "$PATH_INFO" = "DIR" ] && echo "yes" || echo "no")
                
                # Determine default destination path
                if [ "$IS_DIR" = "yes" ]; then
                    # For directory
                    SOURCE_PATH="${SOURCE_PATH%/}"
                    DEFAULT_DEST_PATH="$DEST_PATH/$(basename "$SOURCE_PATH")"
                else
                    # For single file
                    FILE_NAME=$(basename "$SOURCE_PATH")
                    DEFAULT_DEST_PATH="$DEST_PATH/$FILE_NAME"
                fi
                
                # Ask user for destination path with the default
                read -p "Enter destination path on target VM [default: $DEFAULT_DEST_PATH]: " CUSTOM_DEST_PATH
                DEST_FULL=${CUSTOM_DEST_PATH:-$DEFAULT_DEST_PATH}
                
                # Ensure the destination directory exists - no separate SSH call needed
                if [ "$IS_DIR" = "yes" ]; then
                    DEST_PARENT=$(dirname "$DEST_FULL")
                    log "Transferring specific folder: $SOURCE_PATH to destination: $DEST_FULL"
                else
                    DEST_DIR=$(dirname "$DEST_FULL")
                    log "Transferring specific file: $SOURCE_PATH to destination: $DEST_FULL"
                fi
                
                # Create destination directory in the same call as the direct access check
                DIRECT_ACCESS_CHECK=$(ssh_cmd "$SOURCE_USER" "$SOURCE_IP" "$SOURCE_PORT" "mkdir -p /tmp/direct_check && chmod 700 /tmp/direct_check && cd /tmp/direct_check && ssh -p $DEST_PORT -o BatchMode=yes -o ConnectTimeout=5 $DEST_USER@$DEST_IP 'mkdir -p \"$(dirname \"$DEST_FULL\")\" && echo \"yes\"' 2>/dev/null || echo \"no\"")
                DIRECT_ACCESS=$(echo "$DIRECT_ACCESS_CHECK" | grep -o "yes\|no" | tail -1)
                
                log "Direct access check result: $DIRECT_ACCESS"
                
                if [ "$DIRECT_ACCESS" = "yes" ]; then
                    # Direct sync from source to destination
                    log "Direct access available. Performing direct sync..."
                    
                    # Execute rsync through source VM - single SSH call for the rsync operation
                    if [ "$IS_DIR" = "yes" ]; then
                        ssh_cmd "$SOURCE_USER" "$SOURCE_IP" "$SOURCE_PORT" "rsync $RSYNC_OPTS -r -e 'ssh -p $DEST_PORT' $SOURCE_PATH $DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "direct transfer"
                    else
                        ssh_cmd "$SOURCE_USER" "$SOURCE_IP" "$SOURCE_PORT" "rsync $RSYNC_OPTS -e 'ssh -p $DEST_PORT' $SOURCE_PATH $DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "direct transfer"
                    fi
                    
                    log "Direct sync completed successfully!"
                else
                    # Indirect sync through main VM
                    log "No direct access. Performing indirect sync through main VM..."
                    
                    # Create temporary directory on main VM
                    TEMP_DIR="/tmp/sync_$$"
                    mkdir -p "$TEMP_DIR" || handle_failure "creating temporary directory"
                    log "Temporary directory created: $TEMP_DIR"
                    
                    # Step 1: Source to Main - optimized rsync
                    log "Step 1: Copying from source to main VM..."
                    
                    if [ "$IS_DIR" = "yes" ]; then
                        # For directory transfers
                        rsync $RSYNC_OPTS -r -e "ssh -o ControlPath=/tmp/ssh-${SOURCE_USER}-${SOURCE_IP}-${SOURCE_PORT} -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$TEMP_DIR" || handle_failure "copy from source to main VM"
                    else
                        # For file transfers
                        rsync $RSYNC_OPTS -e "ssh -o ControlPath=/tmp/ssh-${SOURCE_USER}-${SOURCE_IP}-${SOURCE_PORT} -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$TEMP_DIR/" || handle_failure "copy from source to main VM"
                    fi
                    
                    # Step 2: Main to Destination - create directory and transfer in one go
                    log "Step 2: Copying from main VM to destination..."
                    
                    ssh_cmd "$DEST_USER" "$DEST_IP" "$DEST_PORT" "mkdir -p \"$(dirname \"$DEST_FULL\")\"" || handle_failure "creating destination directory"
                    
                    if [ "$IS_DIR" = "yes" ]; then
                        SOURCE_BASENAME=$(basename "$SOURCE_PATH")
                        rsync $RSYNC_OPTS -r -e "ssh -o ControlPath=/tmp/ssh-${DEST_USER}-${DEST_IP}-${DEST_PORT} -p $DEST_PORT" "$TEMP_DIR/$SOURCE_BASENAME" "$DEST_USER@$DEST_IP:$(dirname "$DEST_FULL")" || handle_failure "copy from main VM to destination"
                    else
                        SOURCE_BASENAME=$(basename "$SOURCE_PATH")
                        rsync $RSYNC_OPTS -e "ssh -o ControlPath=/tmp/ssh-${DEST_USER}-${DEST_IP}-${DEST_PORT} -p $DEST_PORT" "$TEMP_DIR/$SOURCE_BASENAME" "$DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "copy from main VM to destination"
                    fi
                    
                    # Cleanup
                    log "Cleaning up temporary files..."
                    rm -rf "$TEMP_DIR"
                    log "Indirect sync completed successfully!"
                fi
                ;;
                
            2) # Pattern-based transfer
                # Prepare pattern file once
                PATTERN_FILE="/tmp/rsync_patterns_$"
                cat > "$PATTERN_FILE" << EOF
+ van-buren-*/
+ van-buren-*/**
+ *.sh
+ .secret/
+ .secret/**
- *
EOF
                SOURCE_PATH="$SOURCE_HOME/"
                DEST_FULL="$DEST_PATH"
                log "Pattern file created for selective sync"
                
                # Check direct access and create destination directory in one call
                DIRECT_ACCESS_CHECK=$(ssh_cmd "$SOURCE_USER" "$SOURCE_IP" "$SOURCE_PORT" "mkdir -p /tmp/direct_check && chmod 700 /tmp/direct_check && cd /tmp/direct_check && ssh -p $DEST_PORT -o BatchMode=yes -o ConnectTimeout=5 $DEST_USER@$DEST_IP 'mkdir -p \"$DEST_PATH\" && echo \"yes\"' 2>/dev/null || echo \"no\"")
                DIRECT_ACCESS=$(echo "$DIRECT_ACCESS_CHECK" | grep -o "yes\|no" | tail -1)
                
                log "Direct access check result: $DIRECT_ACCESS"
                
                if [ "$DIRECT_ACCESS" = "yes" ]; then
                    # Direct sync - single scp to transfer pattern file and execute rsync
                    log "Direct access available. Performing direct sync..."
                    
                    # Combine operations: upload pattern file and execute rsync in one connection
                    REMOTE_PATTERN_FILE="/tmp/rsync_patterns_$$.remote"
                    scp -P "$SOURCE_PORT" -o "ControlPath=/tmp/ssh-${SOURCE_USER}-${SOURCE_IP}-${SOURCE_PORT}" "$PATTERN_FILE" "$SOURCE_USER@$SOURCE_IP:$REMOTE_PATTERN_FILE" || handle_failure "copying pattern file to source VM"
                    
                    ssh_cmd "$SOURCE_USER" "$SOURCE_IP" "$SOURCE_PORT" \
                        "rsync $RSYNC_OPTS --include-from=$REMOTE_PATTERN_FILE -e 'ssh -p $DEST_PORT' $SOURCE_PATH $DEST_USER@$DEST_IP:$DEST_FULL && rm -f $REMOTE_PATTERN_FILE" || handle_failure "direct pattern transfer"
                    
                    log "Direct pattern sync completed successfully!"
                else
                    # Indirect sync - optimize with single connections
                    log "No direct access. Performing indirect sync through main VM..."
                    
                    # Create temporary directory once
                    TEMP_DIR="/tmp/sync_$$"
                    mkdir -p "$TEMP_DIR" || handle_failure "creating temporary directory"
                    
                    # Combined rsync command with pattern file
                    rsync $RSYNC_OPTS --include-from="$PATTERN_FILE" -e "ssh -o ControlPath=/tmp/ssh-${SOURCE_USER}-${SOURCE_IP}-${SOURCE_PORT} -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$TEMP_DIR/" || handle_failure "copy from source to main VM"
                    
                    # Create destination directory and transfer in one go
                    ssh_cmd "$DEST_USER" "$DEST_IP" "$DEST_PORT" "mkdir -p \"$DEST_PATH\"" || handle_failure "creating destination directory"
                    
                    rsync $RSYNC_OPTS -e "ssh -o ControlPath=/tmp/ssh-${DEST_USER}-${DEST_IP}-${DEST_PORT} -p $DEST_PORT" "$TEMP_DIR/" "$DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "copy from main VM to destination"
                    
                    # Cleanup
                    log "Cleaning up temporary files..."
                    rm -rf "$TEMP_DIR"
                    [ -f "$PATTERN_FILE" ] && rm -f "$PATTERN_FILE"
                    log "Indirect pattern sync completed successfully!"
                fi
                ;;
                
            *)
                log "ERROR: Invalid VM-to-VM transfer option selected"
                handle_failure "invalid option selection"
                ;;
        esac
        ;;
        
    2) # Main machine to VM transfer
        # Get unique datacenters
        DATACENTERS=($(get_datacenters))

        # Display datacenter options for destination
        echo "Available datacenters:"
        for i in "${!DATACENTERS[@]}"; do
            echo "$((i+1)). ${DATACENTERS[$i]}"
        done

        # Get destination datacenter
        while true; do
            read -p "Choose destination datacenter (1-${#DATACENTERS[@]}): " DST_DC_CHOICE
            if [[ "$DST_DC_CHOICE" =~ ^[0-9]+$ ]] && [ "$DST_DC_CHOICE" -ge 1 ] && [ "$DST_DC_CHOICE" -le "${#DATACENTERS[@]}" ]; then
                DEST_DATACENTER="${DATACENTERS[$((DST_DC_CHOICE-1))]}"
                break
            fi
            echo "Invalid selection. Please try again."
        done

        # Get VMs for destination datacenter
        DEST_VMS=($(get_vms_for_datacenter "$DEST_DATACENTER"))

        # Display VM options for destination
        echo "Available VMs in $DEST_DATACENTER datacenter:"
        for i in "${!DEST_VMS[@]}"; do
            echo "$((i+1)). ${DEST_VMS[$i]}"
        done

        # Get destination VM
        while true; do
            read -p "Choose destination VM (1-${#DEST_VMS[@]}): " DST_VM_CHOICE
            if [[ "$DST_VM_CHOICE" =~ ^[0-9]+$ ]] && [ "$DST_VM_CHOICE" -ge 1 ] && [ "$DST_VM_CHOICE" -le "${#DEST_VMS[@]}" ]; then
                DEST_VM="${DEST_VMS[$((DST_VM_CHOICE-1))]}"
                break
            fi
            echo "Invalid selection. Please try again."
        done

        # Set connection parameters for destination
        DEST_USER=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "username")
        DEST_HOST=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "host")
        DEST_IP=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "ip")
        DEST_PORT=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "port")
        DEST_PATH="/home/$DEST_USER/"

        # Display summary and confirm
        echo -e "\nConfiguration Summary:"
        echo "Source: Main Machine ($(hostname))"
        echo "Destination: $DEST_DATACENTER - Server: $DEST_VM ($DEST_HOST)"
        read -p "Continue? (y/n): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            log "Operation canceled by user"
            exit 0
        fi

        # Setup SSH master connection for destination
        if ! setup_ssh_master "$DEST_USER" "$DEST_IP" "$DEST_PORT"; then
            handle_failure "setting up destination SSH connection"
        fi

        # Get source and destination paths
        read -p "Enter the path to the specific file or folder on main machine: " LOCAL_SOURCE_PATH
        read -p "Enter the destination path on VM (default: $DEST_PATH): " CUSTOM_DEST_PATH
        CUSTOM_DEST_PATH=${CUSTOM_DEST_PATH:-$DEST_PATH}

        # Create destination directory once
        ssh_cmd "$DEST_USER" "$DEST_IP" "$DEST_PORT" "mkdir -p \"$CUSTOM_DEST_PATH\"" || handle_failure "creating destination directory"

        # Prepare rsync options - optimized for speed
        RSYNC_OPTS="-az --compress --compress-level=9 --partial --progress"

        # Check if local source path is a file or directory in a single operation
        if [ -d "$LOCAL_SOURCE_PATH" ]; then
            # For directory transfer - preserve the directory itself
            LOCAL_SOURCE_PATH="${LOCAL_SOURCE_PATH%/}"
            log "Transferring local directory: $LOCAL_SOURCE_PATH to destination: $CUSTOM_DEST_PATH"
            
            # Optimized rsync command using the master connection
            rsync $RSYNC_OPTS -r -e "ssh -o ControlPath=/tmp/ssh-${DEST_USER}-${DEST_IP}-${DEST_PORT} -p $DEST_PORT" "$LOCAL_SOURCE_PATH" "$DEST_USER@$DEST_IP:$CUSTOM_DEST_PATH" || handle_failure "copy from main machine to destination VM"
        else
            # For file transfer
            FILE_NAME=$(basename "$LOCAL_SOURCE_PATH")
            log "Transferring local file: $LOCAL_SOURCE_PATH to destination: $CUSTOM_DEST_PATH/$FILE_NAME"
            
            # Optimized rsync command using the master connection
            rsync $RSYNC_OPTS -e "ssh -o ControlPath=/tmp/ssh-${DEST_USER}-${DEST_IP}-${DEST_PORT} -p $DEST_PORT" "$LOCAL_SOURCE_PATH" "$DEST_USER@$DEST_IP:$CUSTOM_DEST_PATH/$FILE_NAME" || handle_failure "copy from main machine to destination VM"
        fi
        
        log "Transfer from main machine to VM completed successfully!"
        ;;
        
    3) # VM to Main machine transfer
        # Get unique datacenters
        DATACENTERS=($(get_datacenters))

        # Display datacenter options for source
        echo "Available datacenters:"
        for i in "${!DATACENTERS[@]}"; do
            echo "$((i+1)). ${DATACENTERS[$i]}"
        done

        # Get source datacenter
        while true; do
            read -p "Choose source datacenter (1-${#DATACENTERS[@]}): " SRC_DC_CHOICE
            if [[ "$SRC_DC_CHOICE" =~ ^[0-9]+$ ]] && [ "$SRC_DC_CHOICE" -ge 1 ] && [ "$SRC_DC_CHOICE" -le "${#DATACENTERS[@]}" ]; then
                SOURCE_DATACENTER="${DATACENTERS[$((SRC_DC_CHOICE-1))]}"
                break
            fi
            echo "Invalid selection. Please try again."
        done

        # Get VMs for source datacenter
        SOURCE_VMS=($(get_vms_for_datacenter "$SOURCE_DATACENTER"))

        # Display VM options for source
        echo "Available VMs in $SOURCE_DATACENTER datacenter:"
        for i in "${!SOURCE_VMS[@]}"; do
            echo "$((i+1)). ${SOURCE_VMS[$i]}"
        done

        # Get source VM
        while true; do
            read -p "Choose source VM (1-${#SOURCE_VMS[@]}): " SRC_VM_CHOICE
            if [[ "$SRC_VM_CHOICE" =~ ^[0-9]+$ ]] && [ "$SRC_VM_CHOICE" -ge 1 ] && [ "$SRC_VM_CHOICE" -le "${#SOURCE_VMS[@]}" ]; then
                SOURCE_VM="${SOURCE_VMS[$((SRC_VM_CHOICE-1))]}"
                break
            fi
            echo "Invalid selection. Please try again."
        done

        # Set connection parameters for source
        SOURCE_USER=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "username")
        SOURCE_HOST=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "host")
        SOURCE_IP=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "ip")
        SOURCE_PORT=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "port")
        SOURCE_PATH="/home/$SOURCE_USER/"

        # Display summary and confirm
        echo -e "\nConfiguration Summary:"
        echo "Source: $SOURCE_DATACENTER - Server: $SOURCE_VM ($SOURCE_HOST)"
        echo "Destination: Main Machine ($(hostname))"
        read -p "Continue? (y/n): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            log "Operation canceled by user"
            exit 0
        fi

        # Setup SSH master connection for source
        if ! setup_ssh_master "$SOURCE_USER" "$SOURCE_IP" "$SOURCE_PORT"; then
            handle_failure "setting up source SSH connection"
        fi

        # Get source home directory in a single call
        SOURCE_HOME=$(ssh_cmd "$SOURCE_USER" "$SOURCE_IP" "$SOURCE_PORT" "echo \$HOME")
        log "Source home directory: $SOURCE_HOME"

        # Get file/folder path on source VM
        read -p "Enter the path to the specific file or folder on source VM: " SOURCE_PATH
        # Replace tilde with actual home directory if present
        SOURCE_PATH=${SOURCE_PATH/#\~/$SOURCE_HOME}
        
        read -p "Enter the destination path on main machine: " LOCAL_DEST_PATH
        if [ -z "$LOCAL_DEST_PATH" ]; then
            LOCAL_DEST_PATH="$PWD"
        fi
        
        # Create local destination directory
        mkdir -p "$LOCAL_DEST_PATH" || handle_failure "creating local destination directory"
        
        # Check if source path is a file or directory in a single SSH call
        PATH_INFO=$(ssh_cmd "$SOURCE_USER" "$SOURCE_IP" "$SOURCE_PORT" "if [ -d \"$SOURCE_PATH\" ]; then echo 'DIR'; else echo 'FILE'; fi")
        IS_DIR=$([ "$PATH_INFO" = "DIR" ] && echo "yes" || echo "no")
        
        # Prepare rsync options - optimized for speed
        RSYNC_OPTS="-az --compress --compress-level=9 --partial --progress"
        
        if [ "$IS_DIR" = "yes" ]; then
            # For directory transfer
            SOURCE_PATH="${SOURCE_PATH%/}"
            log "Transferring remote directory: $SOURCE_PATH to local directory: $LOCAL_DEST_PATH"
            
            # Optimized rsync command using the master connection
            rsync $RSYNC_OPTS -r -e "ssh -o ControlPath=/tmp/ssh-${SOURCE_USER}-${SOURCE_IP}-${SOURCE_PORT} -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$LOCAL_DEST_PATH/" || handle_failure "copy from source VM to main machine"
        else
            # For file transfer
            FILE_NAME=$(basename "$SOURCE_PATH")
            LOCAL_DEST_FULL="$LOCAL_DEST_PATH/$FILE_NAME"
            
            log "Transferring remote file: $SOURCE_PATH to local path: $LOCAL_DEST_FULL"
            
            # Optimized rsync command using the master connection
            rsync $RSYNC_OPTS -e "ssh -o ControlPath=/tmp/ssh-${SOURCE_USER}-${SOURCE_IP}-${SOURCE_PORT} -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$LOCAL_DEST_FULL" || handle_failure "copy from source VM to main machine"
        fi
        
        log "Transfer from VM to main machine completed successfully!"
        ;;
        
    *)
        log "ERROR: Invalid transfer type selected"
        exit 1
        ;;
esac

# Close all SSH master connections to clean up
log "Closing SSH connections..."
for socket in /tmp/ssh-*-*-*; do
    if [ -S "$socket" ]; then
        ssh -O exit -o "ControlPath=$socket" 2>/dev/null
    fi
done

log "Sync operation completed!"