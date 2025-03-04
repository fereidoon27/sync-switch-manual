#!/bin/bash

# Get script directory for finding config file
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="$SCRIPT_DIR/ST_INFO.txt"

# Log file setup
LOG_FILE="$HOME/sync_$(date +%Y%m%d).log"

# Function for logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to read config value with default
read_config() {
    local key="$1"
    local default="$2"
    local value=""
    
    if [ -f "$CONFIG_FILE" ]; then
        value=$(grep "^$key=" "$CONFIG_FILE" | cut -d= -f2)
    fi
    
    echo "${value:-$default}"
}

# Load default values from config file
DEFAULT_SOURCE_USER=$(read_config "SOURCE_USER" "root")
DEFAULT_SOURCE_IP=$(read_config "SOURCE_IP" "127.0.0.1")
DEFAULT_SOURCE_PORT=$(read_config "SOURCE_PORT" "22")
DEFAULT_DEST_USER=$(read_config "DEST_USER" "root")
DEFAULT_DEST_IP=$(read_config "DEST_IP" "127.0.0.1")
DEFAULT_DEST_PORT=$(read_config "DEST_PORT" "22")
DEFAULT_DEST_PATH=$(read_config "DEST_PATH" "/tmp")

# Get input parameters with defaults
read -p "Enter source VM username [$DEFAULT_SOURCE_USER]: " SOURCE_USER
SOURCE_USER=${SOURCE_USER:-$DEFAULT_SOURCE_USER}

read -p "Enter source VM IP [$DEFAULT_SOURCE_IP]: " SOURCE_IP
SOURCE_IP=${SOURCE_IP:-$DEFAULT_SOURCE_IP}

read -p "Enter source VM SSH port [$DEFAULT_SOURCE_PORT]: " SOURCE_PORT
SOURCE_PORT=${SOURCE_PORT:-$DEFAULT_SOURCE_PORT}

read -p "Enter destination VM username [$DEFAULT_DEST_USER]: " DEST_USER
DEST_USER=${DEST_USER:-$DEFAULT_DEST_USER}

read -p "Enter destination VM IP [$DEFAULT_DEST_IP]: " DEST_IP
DEST_IP=${DEST_IP:-$DEFAULT_DEST_IP}

read -p "Enter destination VM SSH port [$DEFAULT_DEST_PORT]: " DEST_PORT
DEST_PORT=${DEST_PORT:-$DEFAULT_DEST_PORT}

read -p "Enter destination folder path [$DEFAULT_DEST_PATH]: " DEST_PATH
DEST_PATH=${DEST_PATH:-$DEFAULT_DEST_PATH}

# Display options for transfer
echo "Transfer options:"
echo "1. Transfer a specific file from source VM to destination VM"
echo "2. Transfer a specific folder from source VM to destination VM"
echo "3. Transfer specific files/folders from home directory based on patterns"
echo "   (van-buren-* directories, .sh files, .secret/ folder)"
read -p "Choose an option (1-3) [1]: " TRANSFER_OPTION
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
        read -p "Enter the path to the specific file on source VM: " SOURCE_PATH
        # Replace tilde with actual home directory if present
        SOURCE_PATH=${SOURCE_PATH/#\~/$SOURCE_HOME}
        ;;
    2)
        read -p "Enter the path to the specific folder on source VM: " SOURCE_PATH
        # Replace tilde with actual home directory if present
        SOURCE_PATH=${SOURCE_PATH/#\~/$SOURCE_HOME}
        ;;
    3)
        # Option 3 uses predefined patterns from home directory
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
    # For single file, don't add trailing slash to SOURCE_PATH
    FILE_NAME=$(basename "$SOURCE_PATH")
    DEST_FULL="$DEST_PATH/$FILE_NAME"
    log "Transferring specific file: $SOURCE_PATH to $DEST_FULL"
elif [ "$TRANSFER_OPTION" -eq 2 ]; then
    # For directory, add trailing slash to SOURCE_PATH to copy contents
    SOURCE_PATH="${SOURCE_PATH%/}/"
    DEST_FULL="$DEST_PATH"
    log "Transferring specific folder: $SOURCE_PATH to $DEST_FULL"
elif [ "$TRANSFER_OPTION" -eq 3 ]; then
    # For pattern matching, create a temporary file with the patterns
    PATTERN_FILE="/tmp/rsync_patterns_$$"
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
    if [ "$TRANSFER_OPTION" -eq 3 ]; then
        # For pattern matching, copy the pattern file to source VM
        REMOTE_PATTERN_FILE="/tmp/rsync_patterns_$$.remote"
        scp -P "$SOURCE_PORT" "$PATTERN_FILE" "$SOURCE_USER@$SOURCE_IP:$REMOTE_PATTERN_FILE" || handle_failure "copying pattern file to source VM"
        
        # Execute the rsync command with the pattern file
        log "Starting direct transfer with patterns..."
        $SOURCE_SSH "rsync -az --progress --include-from=$REMOTE_PATTERN_FILE -e 'ssh -p $DEST_PORT' $SOURCE_PATH $DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "direct transfer"
        
        # Cleanup remote pattern file
        $SOURCE_SSH "rm -f $REMOTE_PATTERN_FILE"
    else
        # For single file or directory
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
        # For single file
        log "Transferring file from source to main VM..."
        rsync $RSYNC_OPTS -e "ssh -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$TEMP_DIR/" || handle_failure "copy from source to main VM"
    elif [ "$TRANSFER_OPTION" -eq 2 ]; then
        # For directory
        log "Transferring directory from source to main VM..."
        rsync $RSYNC_OPTS -e "ssh -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$TEMP_DIR/" || handle_failure "copy from source to main VM"
    elif [ "$TRANSFER_OPTION" -eq 3 ]; then
        # For pattern matching
        log "Transferring pattern-matched files from source to main VM..."
        rsync $RSYNC_OPTS --include-from="$PATTERN_FILE" -e "ssh -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_PATH" "$TEMP_DIR/" || handle_failure "copy from source to main VM"
    fi
    
    # Step 2: Main to Destination
    log "Step 2: Copying from main VM to destination..."
    
    if [ "$TRANSFER_OPTION" -eq 1 ]; then
        # For single file, get filename
        FILE_NAME=$(basename "$SOURCE_PATH")
        log "Transferring $FILE_NAME from main VM to destination..."
        rsync $RSYNC_OPTS -e "ssh -p $DEST_PORT" "$TEMP_DIR/$FILE_NAME" "$DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "copy from main VM to destination"
    else
        # For directory or patterns
        log "Transferring all files from main VM to destination..."
        rsync $RSYNC_OPTS -e "ssh -p $DEST_PORT" "$TEMP_DIR/" "$DEST_USER@$DEST_IP:$DEST_FULL" || handle_failure "copy from main VM to destination"
    fi
    
    # Cleanup
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    [ -f "$PATTERN_FILE" ] && rm -f "$PATTERN_FILE"
    log "Indirect sync completed successfully!"
fi

log "Sync operation completed!"