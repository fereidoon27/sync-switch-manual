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

# Get VMs for source datacenter
SOURCE_VMS=($(get_vms_for_datacenter "$SOURCE_DATACENTER"))

# Display VM options for source
echo "Available VMs in $SOURCE_DATACENTER datacenter:"
for i in "${!SOURCE_VMS[@]}"; do
    echo "$((i+1)). ${SOURCE_VMS[$i]}"
done

# Get source VM(s)
while true; do
    echo "Enter VM numbers to select multiple VMs (e.g., '246' for VMs 2, 4, and 6)"
    echo "Or enter 'all' to select all VMs in this datacenter"
    read -p "Choose source VM(s) (1-${#SOURCE_VMS[@]}): " SRC_VM_CHOICE
    
    # Initialize array for selected VMs
    SELECTED_VMS=()
    
    if [[ "$SRC_VM_CHOICE" == "all" ]]; then
        # Select all VMs
        for ((i=0; i<${#SOURCE_VMS[@]}; i++)); do
            SELECTED_VMS+=("${SOURCE_VMS[$i]}")
        done
        break
    elif [[ "$SRC_VM_CHOICE" =~ ^[0-9]+$ ]]; then
        # Process each digit in the input
        valid_selection=true
        for ((i=0; i<${#SRC_VM_CHOICE}; i++)); do
            digit="${SRC_VM_CHOICE:$i:1}"
            if [[ "$digit" -ge 1 && "$digit" -le "${#SOURCE_VMS[@]}" ]]; then
                SELECTED_VMS+=("${SOURCE_VMS[$((digit-1))]}")
            else
                echo "Invalid VM number: $digit"
                valid_selection=false
                break
            fi
        done
        
        if [[ "$valid_selection" == true ]]; then
            break
        fi
    else
        echo "Invalid selection. Please try again."
    fi
done

# Display selected VMs
echo "Selected VMs:"
for vm in "${SELECTED_VMS[@]}"; do
    echo "- $vm"
done

# Create pattern file for rsync once
PATTERN_FILE="/tmp/rsync_patterns_$"
cat > "$PATTERN_FILE" << EOF
+ van-buren-*/
+ van-buren-*/**
+ *.sh
+ .secret/
+ .secret/**
- *
EOF

log "Pattern file created with the following patterns:"
cat "$PATTERN_FILE" | while read line; do log "  $line"; done

# Display configuration summary
echo -e "\nConfiguration Summary:"
echo "Source Datacenter: $SOURCE_DATACENTER"
echo "Destination: Main Machine ($(hostname))"
echo "Number of selected VMs: ${#SELECTED_VMS[@]}"
read -p "Continue? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    log "Operation canceled by user"
    rm -f "$PATTERN_FILE"
    exit 0
fi

# Process each selected VM
for SOURCE_VM in "${SELECTED_VMS[@]}"; do
    echo -e "\n========== Processing $SOURCE_VM =========="
    
    # Set connection parameters for current VM
    SOURCE_USER=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "username")
    SOURCE_HOST=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "host")
    SOURCE_IP=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "ip")
    SOURCE_PORT=$(get_server_info "$SOURCE_DATACENTER" "$SOURCE_VM" "port")

    # Extract VM number for destination directory
    VM_NUMBER=$(echo "$SOURCE_VM" | sed -E 's/^cr([0-9]+).*/\1/')
    DEST_PATH="$HOME/1111-binance-services/cr$VM_NUMBER"

    log "Current VM: $SOURCE_VM ($SOURCE_HOST)"
    log "Destination Directory: $DEST_PATH"

    # Build SSH connection string for source
    SOURCE_SSH="ssh -o ConnectTimeout=10 -p $SOURCE_PORT $SOURCE_USER@$SOURCE_IP"

    # Test SSH connection
    log "Testing connection to $SOURCE_VM ($SOURCE_USER@$SOURCE_IP:$SOURCE_PORT)..."
    if ! $SOURCE_SSH "echo Connection successful" > /dev/null 2>&1; then
        log "ERROR: Cannot connect to $SOURCE_VM, skipping this VM"
        continue
    fi
    log "Connection to $SOURCE_VM successful"

    # Get source home directory for proper path expansion
    SOURCE_HOME=$($SOURCE_SSH "echo \$HOME")
    log "Source home directory: $SOURCE_HOME"

    # Create destination directory
    mkdir -p "$DEST_PATH"

    # Perform transfer
    log "Starting pattern-based transfer from $SOURCE_VM to main machine..."
    if rsync -az --progress --include-from="$PATTERN_FILE" -e "ssh -p $SOURCE_PORT" "$SOURCE_USER@$SOURCE_IP:$SOURCE_HOME/" "$DEST_PATH/"; then
        log "Transfer from $SOURCE_VM completed successfully to $DEST_PATH"
    else
        log "ERROR: Transfer from $SOURCE_VM failed"
    fi
    
    echo "========== Completed $SOURCE_VM =========="
done

# Cleanup
rm -f "$PATTERN_FILE"

log "All transfers completed"