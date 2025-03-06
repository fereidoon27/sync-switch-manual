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

# Extract VM number and determine matching destination VM
VM_NUMBER=$(echo "$SOURCE_VM" | sed 's/^[a-zA-Z]*\([0-9]\+\)[a-zA-Z]*$/\1/')
DEST_VM_PREFIX=$(echo "${SOURCE_VMS[0]}" | sed 's/^\([a-zA-Z]*\)[0-9]\+[a-zA-Z]*$/\1/')
DEST_VM="${DEST_VM_PREFIX}${VM_NUMBER}${DEST_DATACENTER}"

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

# Display options for transfer
echo -e "\nTransfer options:"
echo "1. Transfer a specific file or folder from source VM to destination VM"
echo "2. Transfer specific files/folders from home directory based on patterns"
echo "   (van-buren-* directories, .sh files, .secret/ folder)"
read -p "Choose an option (1-2) [1]: " TRANSFER_OPTION
TRANSFER_OPTION=${TRANSFER_OPTION:-1}

# Build SSH connection strings
SOURCE_SSH="ssh -o ConnectTimeout=10 -p $SOURCE_PORT $SOURCE_USER@$SOURCE_IP"
DEST_SSH="ssh -o ConnectTimeout=10 -p $DEST_PORT $DEST_USER@$DEST_IP"

# Function to test SSH connection
test_ssh() {
    local ssh_cmd="$1"
    local host_desc="$2"
    log "Testing connection to $host_desc..."
    
    if ! $ssh_cmd "echo Connection successful" > /dev/null 2>&1; then
        log "ERROR: Cannot connect to $host_desc"
        return 1
    else
        log "Connection to $host_desc successful"
        return 0
    fi
}

# Check SSH connections
if ! test_ssh "$SOURCE_SSH" "source VM ($SOURCE_USER@$SOURCE_IP:$SOURCE_PORT)"; then
    exit 1
fi

if ! test_ssh "$DEST_SSH" "destination VM ($DEST_USER@$DEST_IP:$DEST_PORT)"; then
    exit 1
fi

# Create directory on destination
log "Creating directory on destination..."
$DEST_SSH "mkdir -p $DEST_PATH"

# Get source home directory for proper path expansion
SOURCE_HOME=$($SOURCE_SSH "echo \$HOME")
log "Source home directory: $SOURCE_HOME"

# Based on option, get additional input
case $TRANSFER_OPTION in
    1)
        read -p "Enter the path to the specific file or folder on source VM: " SOURCE_PATH
        # Replace tilde with actual home directory if present
        SOURCE_PATH=${SOURCE_PATH/#\~/$SOURCE_HOME}
        ;;
    2)
        # Option 2 uses predefined patterns from home directory
        SOURCE_PATH="$SOURCE_HOME"
        ;;
    *)
        log "ERROR: Invalid option selected"
        exit 1
        ;;
esac

# Test if source can directly access destination
log "Testing direct connection from source to destination..."
DIRECT_ACCESS=$($SOURCE_SSH "ssh -p $DEST_PORT -o BatchMode=yes -o ConnectTimeout=5 $DEST_USER@$DEST_IP exit 2>/dev/null && echo yes || echo no")
log "Direct access: $DIRECT_ACCESS"

# Prepare rsync options based on the option selected
RSYNC_OPTS="-az --progress"

if [ "$TRANSFER_OPTION" -eq 1 ]; then
    # Check if source path is a file or directory
    IS_DIR=$($SOURCE_SSH "[ -d \"$SOURCE_PATH\" ] && echo yes || echo no")
    
    if [ "$IS_DIR" = "yes" ]; then
        # For directory, preserve the structure
        # Remove any trailing slash from SOURCE_PATH
        SOURCE_PATH="${SOURCE_PATH%/}"
        
        if [[ "$SOURCE_PATH" == "$SOURCE_HOME"* ]]; then
            # If the source folder is under the home directory, use the parent folder relative to home
            PARENT_PATH=$(dirname "$SOURCE_PATH")
            RELATIVE_PATH=$(echo "$PARENT_PATH" | sed -e "s|^$SOURCE_HOME/||")
            DEST_FULL="$DEST_PATH/$RELATIVE_PATH"
        else
            # For system directories (like /etc/chrony), use its actual parent directory
            DEST_FULL="$(dirname "$SOURCE_PATH")"
        fi
        
        log "Transferring specific folder: $SOURCE_PATH to destination directory: $DEST_FULL"
    else
        # For single file, don't add trailing slash to SOURCE_PATH
        FILE_NAME=$(basename "$SOURCE_PATH")
        RELATIVE_PATH=$(dirname $(echo "$SOURCE_PATH" | sed -e "s|^$SOURCE_HOME/||"))
        
        if [[ "$RELATIVE_PATH" == "." || "$SOURCE_PATH" == /* ]]; then
            # Handle absolute paths or files in home directory
            DEST_FULL="$DEST_PATH/$FILE_NAME"
        else
            # Create subdirectory structure for files in subdirectories
            DEST_FULL="$DEST_PATH/$RELATIVE_PATH"
            # Create the directory structure on destination
            $DEST_SSH "mkdir -p \"$DEST_FULL\""
            DEST_FULL="$DEST_FULL/$FILE_NAME"
        fi
        log "Transferring specific file: $SOURCE_PATH to $DEST_FULL"
    fi
elif [ "$TRANSFER_OPTION" -eq 2 ]; then
    # For pattern matching, create a temporary file with the patterns
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
    RSYNC_OPTS="$RSYNC_OPTS --include-from=$PATTERN_FILE"
    log "Transferring pattern-matched files/folders from home directory"
    log "Pattern file created at $PATTERN_FILE with the following patterns:"
    cat "$PATTERN_FILE" | while read line; do log "  $line"; done
fi

# Function to handle transfer failures
handle_failure() {
    local stage="$1"
    log "ERROR: Failed during $stage"
    [ -f "$PATTERN_FILE" ] && rm -f "$PATTERN_FILE"
    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
    exit 1
}

if [ "$DIRECT_ACCESS" = "yes" ]; then
    # Direct sync from source to destination
    log "Direct access available. Performing direct sync..."
    
    # Create the rsync command
    if [ "$TRANSFER_OPTION" -eq 2 ]; then
        # For pattern matching, copy the pattern file to source VM
        REMOTE_PATTERN_FILE="/tmp/rsync_patterns_$.remote"
        scp -P "$SOURCE_PORT" "$PATTERN_FILE" "$SOURCE_USER@$SOURCE_IP:$REMOTE_PATTERN_FILE" || handle_failure "copying pattern file to source VM"
        
        # Execute the rsync command with the pattern file
        log "Starting direct transfer with patterns..."
        $SOURCE_SSH "rsync -az --progress --include-from=$REMOTE_PATTERN_FILE -e 'ssh -p $DEST_PORT' $SOURCE_PATH $DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "direct transfer"
        
        # Cleanup remote pattern file
        $SOURCE_SSH "rm -f $REMOTE_PATTERN_FILE"
    else
        # For file or directory
        log "Starting direct transfer..."
        $SOURCE_SSH "rsync $RSYNC_OPTS -e 'ssh -p $DEST_PORT' $SOURCE_PATH $DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "direct transfer"
    fi
    
    log "Direct sync completed successfully!"
else
    # Indirect sync through main VM
    log "No direct access. Performing indirect sync through main VM..."
    
    # Create temporary directory on main VM
    TEMP_DIR="/tmp/sync_$$"
    mkdir -p "$TEMP_DIR" || handle_failure "creating temporary directory"
    log "Temporary directory created: $TEMP_DIR"
    
    # Step 1: Source to Main
    log "Step 1: Copying from source to main VM..."
    
    if [ "$TRANSFER_OPTION" -eq 1 ]; then
        if [ "$IS_DIR" = "yes" ]; then
            # For directory, preserve directory structure
            TARGET_DIR=$(basename "$SOURCE_PATH")
            
            # Create local directory structure
            mkdir -p "$TEMP_DIR"
            
            log "Transferring directory from source to main VM preserving structure..."
            rsync $RSYNC_OPTS -r -e "ssh -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$TEMP_DIR/" || handle_failure "copy from source to main VM"
        else
            # For single file
            log "Transferring file from source to main VM..."
            
            # Create local directory structure if needed
            RELATIVE_PATH=$(dirname $(echo "$SOURCE_PATH" | sed -e "s|^$SOURCE_HOME/||"))
            if [[ "$RELATIVE_PATH" != "." && "$SOURCE_PATH" != /* ]]; then
                mkdir -p "$TEMP_DIR/$RELATIVE_PATH"
                rsync $RSYNC_OPTS -e "ssh -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$TEMP_DIR/$RELATIVE_PATH/" || handle_failure "copy from source to main VM"
            else
                rsync $RSYNC_OPTS -e "ssh -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$TEMP_DIR/" || handle_failure "copy from source to main VM"
            fi
        fi
    elif [ "$TRANSFER_OPTION" -eq 2 ]; then
        # For pattern matching
        log "Transferring pattern-matched files from source to main VM..."
        rsync $RSYNC_OPTS --include-from="$PATTERN_FILE" -e "ssh -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$TEMP_DIR/" || handle_failure "copy from source to main VM"
    fi
    
    # Step 2: Main to Destination
    log "Step 2: Copying from main VM to destination..."
    
    # Make sure target directory exists on destination
    $DEST_SSH "mkdir -p \"$DEST_PATH\""
    
    if [ "$TRANSFER_OPTION" -eq 1 ]; then
        if [ "$IS_DIR" = "yes" ]; then
            TARGET_DIR=$(basename "$SOURCE_PATH")
            log "Transferring directory $TARGET_DIR from main VM to destination..."
            
            # Create directory on destination
            $DEST_SSH "mkdir -p \"$DEST_FULL\""
            
            # Transfer with proper path
            rsync $RSYNC_OPTS -r -e "ssh -p $DEST_PORT" "$TEMP_DIR/$TARGET_DIR/" "$DEST_USER@$DEST_IP:$DEST_FULL/" || handle_failure "copy from main VM to destination"
        else
            FILE_NAME=$(basename "$SOURCE_PATH")
            DEST_DIR=$(dirname "$DEST_FULL")
            
            log "Transferring file $FILE_NAME from main VM to destination..."
            
            # Create directory structure on destination
            $DEST_SSH "mkdir -p \"$DEST_DIR\""
            
            RELATIVE_PATH=$(dirname $(echo "$SOURCE_PATH" | sed -e "s|^$SOURCE_HOME/||"))
            if [[ "$RELATIVE_PATH" != "." && "$SOURCE_PATH" != /* ]]; then
                rsync $RSYNC_OPTS -e "ssh -p $DEST_PORT" "$TEMP_DIR/$RELATIVE_PATH/$FILE_NAME" "$DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "copy from main VM to destination"
            else
                rsync $RSYNC_OPTS -e "ssh -p $DEST_PORT" "$TEMP_DIR/$FILE_NAME" "$DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "copy from main VM to destination"
            fi
        fi
    else
        log "Transferring pattern-matched files from main VM to destination..."
        rsync $RSYNC_OPTS -e "ssh -p $DEST_PORT" "$TEMP_DIR/" "$DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "copy from main VM to destination"
    fi
    
    # Cleanup
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    [ -f "$PATTERN_FILE" ] && rm -f "$PATTERN_FILE"
    log "Indirect sync completed successfully!"
fi

log "Sync operation completed!"
