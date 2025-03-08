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

# Get destination VM(s)
while true; do
    echo "Enter VM numbers to select multiple VMs (e.g., '246' for VMs 2, 4, and 6)"
    echo "Or enter 'all' to select all VMs in this datacenter"
    read -p "Choose destination VM(s) (1-${#DEST_VMS[@]}): " DST_VM_CHOICE
    
    # Initialize array for selected VMs
    SELECTED_VMS=()
    
    if [[ "$DST_VM_CHOICE" == "all" ]]; then
        # Select all VMs
        for ((i=0; i<${#DEST_VMS[@]}; i++)); do
            SELECTED_VMS+=("${DEST_VMS[$i]}")
        done
        break
    elif [[ "$DST_VM_CHOICE" =~ ^[0-9]+$ ]]; then
        # Process each digit in the input
        valid_selection=true
        for ((i=0; i<${#DST_VM_CHOICE}; i++)); do
            digit="${DST_VM_CHOICE:$i:1}"
            if [[ "$digit" -ge 1 && "$digit" -le "${#DEST_VMS[@]}" ]]; then
                SELECTED_VMS+=("${DEST_VMS[$((digit-1))]}")
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
PATTERN_FILE="/tmp/rsync_patterns_$$"
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
echo "Source: Main Machine ($(hostname))"
echo "Destination Datacenter: $DEST_DATACENTER"
echo "Number of selected VMs: ${#SELECTED_VMS[@]}"
read -p "Continue? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    log "Operation canceled by user"
    rm -f "$PATTERN_FILE"
    exit 0
fi

# Process each selected VM
for DEST_VM in "${SELECTED_VMS[@]}"; do
    echo -e "\n========== Processing $DEST_VM =========="
    
    # Set connection parameters for current VM
    DEST_USER=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "username")
    DEST_HOST=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "host")
    DEST_IP=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "ip")
    DEST_PORT=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "port")

    # Extract VM number for source directory
    VM_NUMBER=$(echo "$DEST_VM" | sed -E 's/^cr([0-9]+).*/\1/')
    SOURCE_PATH="/home/amin/1111-binance-services/cr$VM_NUMBER"
    DEST_PATH="/home/$DEST_USER"

    log "Current VM: $DEST_VM ($DEST_HOST)"
    log "Source Directory: $SOURCE_PATH"
    log "Destination Directory: $DEST_PATH"

    # Build SSH connection string for destination
    DEST_SSH="ssh -o ConnectTimeout=10 -p $DEST_PORT $DEST_USER@$DEST_IP"

    # Test SSH connection
    log "Testing connection to $DEST_VM ($DEST_USER@$DEST_IP:$DEST_PORT)..."
    if ! $DEST_SSH "echo Connection successful" > /dev/null 2>&1; then
        log "ERROR: Cannot connect to $DEST_VM, skipping this VM"
        continue
    fi
    log "Connection to $DEST_VM successful"

    # Check if source directory exists
    if [ ! -d "$SOURCE_PATH" ]; then
        log "ERROR: Source directory $SOURCE_PATH does not exist, skipping this VM"
        continue
    fi

    # Ensure destination directory exists
    $DEST_SSH "mkdir -p $DEST_PATH"

    # Perform transfer
    log "Starting pattern-based transfer from main machine to $DEST_VM..."
    if rsync -az --progress --include-from="$PATTERN_FILE" -e "ssh -p $DEST_PORT" "$SOURCE_PATH/" "$DEST_USER@$DEST_IP:$DEST_PATH/"; then
        log "Transfer to $DEST_VM completed successfully"
    else
        log "ERROR: Transfer to $DEST_VM failed"
    fi
    
    echo "========== Completed $DEST_VM =========="
done

# Cleanup
rm -f "$PATTERN_FILE"

log "All transfers completed"