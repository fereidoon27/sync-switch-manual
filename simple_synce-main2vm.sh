#!/bin/bash

# Get script directory for finding config file
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INFO_PATH="$(dirname "$0")/Info"
SERVERS_CONF="$INFO_PATH/servers.conf"

# Log file setup
LOG_FILE="$HOME/sync_$(date +%Y%m%d).log"

# ANSI color codes for modern UI
# Colors
readonly PRIMARY="\033[38;5;75m"    # Pastel blue
readonly SECONDARY="\033[38;5;245m" # Gray
readonly SUCCESS="\033[38;5;114m"   # Soft green
readonly WARNING="\033[38;5;221m"   # Soft yellow
readonly ERROR="\033[38;5;203m"     # Soft red
readonly RESET="\033[0m"            # Reset all formatting

# Text formatting
readonly BOLD="\033[1m"
readonly ITALIC="\033[3m"
readonly DIM="\033[2m"

# UI Elements
readonly SEPARATOR="────────────────────────────────────────────────────────"
readonly CHECK_MARK="✓"
readonly CROSS_MARK="✗"
readonly BULLET="•"
readonly ARROW="→"

# Function for UI elements
print_header() {
    echo ""
    echo -e "${PRIMARY}${BOLD}$1${RESET}"
    echo -e "${DIM}${SEPARATOR}${RESET}"
}

print_subheader() {
    echo ""
    echo -e "${SECONDARY}${BOLD}$1${RESET}"
}

print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "success")
            echo -e "  ${SUCCESS}${CHECK_MARK} ${RESET}${message}"
            ;;
        "warning")
            echo -e "  ${WARNING}! ${RESET}${message}"
            ;;
        "error")
            echo -e "  ${ERROR}${CROSS_MARK} ${RESET}${message}"
            ;;
        "info")
            echo -e "  ${PRIMARY}${BULLET} ${RESET}${message}"
            ;;
    esac
}

show_spinner() {
    local pid=$1
    local message="$2"
    local spin='-\|/'
    local i=0
    
    echo -ne "  ${SECONDARY}${message}${RESET} "
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        echo -ne "\b${spin:$i:1}"
        sleep .1
    done
    echo -ne "\b \b"
}

# Function for logging
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if servers.conf exists
if [ ! -f "$SERVERS_CONF" ]; then
    print_status "error" "Configuration file $SERVERS_CONF not found"
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

# Script header
clear
echo -e "${PRIMARY}${BOLD}"
echo "  Synchronization Tool"
echo -e "${RESET}${SECONDARY}  $(date '+%Y-%m-%d')${RESET}"
echo -e "${DIM}${SEPARATOR}${RESET}"

# Get unique datacenters
DATACENTERS=($(get_datacenters))

# Display datacenter options for destination
print_header "Available Datacenters"

for i in "${!DATACENTERS[@]}"; do
    num=$((i+1))
    echo -e "  ${PRIMARY}${BOLD}$num${RESET} ${SECONDARY}|${RESET} ${DATACENTERS[$i]}"
done

echo ""

# Get destination datacenter
while true; do
    echo -ne "${SECONDARY}Choose destination datacenter (1-${#DATACENTERS[@]}): ${RESET}"
    read DST_DC_CHOICE
    
    if [[ "$DST_DC_CHOICE" =~ ^[0-9]+$ ]] && [ "$DST_DC_CHOICE" -ge 1 ] && [ "$DST_DC_CHOICE" -le "${#DATACENTERS[@]}" ]; then
        DEST_DATACENTER="${DATACENTERS[$((DST_DC_CHOICE-1))]}"
        break
    fi
    print_status "error" "Invalid selection. Please try again."
done

print_status "success" "Selected datacenter: ${BOLD}$DEST_DATACENTER${RESET}"

# Get VMs for destination datacenter
DEST_VMS=($(get_vms_for_datacenter "$DEST_DATACENTER"))

# Display VM options for destination
print_header "Available VMs in $DEST_DATACENTER"

for i in "${!DEST_VMS[@]}"; do
    num=$((i+1))
    if (( $num % 3 == 1 )); then
        echo -ne "  "
    fi
    
    padding="   "
    if (( $num > 9 )); then
        padding="  "
    fi
    
    echo -ne "${PRIMARY}${BOLD}$num${RESET}${SECONDARY}|${RESET} ${DEST_VMS[$i]}$padding"
    
    if (( $num % 3 == 0 )) || (( $num == ${#DEST_VMS[@]} )); then
        echo ""
    fi
done

# Add "all" as the last option
all_option=$((${#DEST_VMS[@]}+1))
if (( $all_option % 3 == 1 )); then
    echo -ne "  "
fi

padding="   "
if (( $all_option > 9 )); then
    padding="  "
fi

echo -e "${PRIMARY}${BOLD}$all_option${RESET}${SECONDARY}|${RESET} all$padding"

echo ""
print_subheader "Selection Options"
print_status "info" "Enter VM numbers to select multiple VMs (e.g., '246' for VMs 2, 4, and 6)"
print_status "info" "Or select option $all_option to choose all VMs"
echo ""

# Get destination VM(s)
while true; do
    echo -ne "${SECONDARY}Choose destination VM(s) (1-$all_option): ${RESET}"
    read DST_VM_CHOICE
    
    # Initialize array for selected VMs
    SELECTED_VMS=()
    
    if [[ "$DST_VM_CHOICE" == "$all_option" ]]; then
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
            elif [[ "$digit" == "$all_option" ]]; then
                # Handle the "all" option
                for ((j=0; j<${#DEST_VMS[@]}; j++)); do
                    SELECTED_VMS+=("${DEST_VMS[$j]}")
                done
            else
                print_status "error" "Invalid VM number: $digit"
                valid_selection=false
                break
            fi
        done
        
        if [[ "$valid_selection" == true ]]; then
            break
        fi
    else
        print_status "error" "Invalid selection. Please try again."
    fi
done

# Display selected VMs
print_header "Selected VMs"

for ((i=0; i<${#SELECTED_VMS[@]}; i++)); do
    vm="${SELECTED_VMS[$i]}"
    if (( $i % 3 == 0 )); then
        echo -ne "  "
    fi
    
    echo -ne "${SECONDARY}${BULLET}${RESET} ${vm}    "
    
    if (( $i % 3 == 2 )) || (( $i == ${#SELECTED_VMS[@]}-1 )); then
        echo ""
    fi
done

echo ""

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
print_header "Configuration Summary"
echo -e "  ${SECONDARY}Source:${RESET} Main Machine (${ITALIC}$(hostname)${RESET})"
echo -e "  ${SECONDARY}Destination Datacenter:${RESET} ${BOLD}$DEST_DATACENTER${RESET}"
echo -e "  ${SECONDARY}Selected VMs:${RESET}"

# Display selected VMs with their index
for ((i=0; i<${#SELECTED_VMS[@]}; i++)); do
    vm="${SELECTED_VMS[$i]}"
    num=$((i+1))
    if (( $i % 3 == 0 )); then
        echo -ne "    "
    fi
    
    padding="   "
    if (( $num > 9 )); then
        padding="  "
    fi
    
    echo -ne "${PRIMARY}${BOLD}$num${RESET}${SECONDARY}|${RESET} ${vm}$padding"
    
    if (( $i % 3 == 2 )) || (( $i == ${#SELECTED_VMS[@]}-1 )); then
        echo ""
    fi
done
echo ""
echo -e "${DIM}${SEPARATOR}${RESET}"
echo ""

echo -ne "${SECONDARY}Continue? (Y/n): ${RESET}"
read CONFIRM
if [[ ! "$CONFIRM" =~ ^([Yy]?)$ ]]; then
    print_status "warning" "Operation canceled by user"
    log "Operation canceled by user"
    rm -f "$PATTERN_FILE"
    exit 0
fi

# Process each selected VM
for DEST_VM in "${SELECTED_VMS[@]}"; do
    print_header "Processing $DEST_VM"
    
    # Set connection parameters for current VM
    DEST_USER=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "username")
    DEST_HOST=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "host")
    DEST_IP=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "ip")
    DEST_PORT=$(get_server_info "$DEST_DATACENTER" "$DEST_VM" "port")

    # Extract VM number for source directory
    VM_NUMBER=$(echo "$DEST_VM" | sed -E 's/^cr([0-9]+).*/\1/')
    SOURCE_PATH="$HOME/1111-binance-services/cr$VM_NUMBER"
    DEST_PATH="/home/$DEST_USER"

    print_status "info" "Source: ${ITALIC}$SOURCE_PATH${RESET}"
    print_status "info" "Destination: ${ITALIC}$DEST_PATH${RESET}"
    log "Current VM: $DEST_VM ($DEST_HOST)"
    log "Source Directory: $SOURCE_PATH"
    log "Destination Directory: $DEST_PATH"

    # Build SSH connection string for destination
    DEST_SSH="ssh -o ConnectTimeout=10 -p $DEST_PORT $DEST_USER@$DEST_IP"

    # Test SSH connection
    print_status "info" "Testing connection to ${BOLD}$DEST_VM${RESET} (${SECONDARY}$DEST_USER@$DEST_IP:$DEST_PORT${RESET})..."
    if ! $DEST_SSH "echo Connection successful" > /dev/null 2>&1; then
        print_status "error" "Cannot connect to $DEST_VM, skipping this VM"
        log "ERROR: Cannot connect to $DEST_VM, skipping this VM"
        continue
    fi
    print_status "success" "Connection to $DEST_VM successful"
    log "Connection to $DEST_VM successful"

    # Check if source directory exists
    if [ ! -d "$SOURCE_PATH" ]; then
        print_status "error" "Source directory $SOURCE_PATH does not exist, skipping this VM"
        log "ERROR: Source directory $SOURCE_PATH does not exist, skipping this VM"
        continue
    fi

    # Ensure destination directory exists
    $DEST_SSH "mkdir -p $DEST_PATH"

    # Perform transfer
    print_status "info" "Starting transfer to ${BOLD}$DEST_VM${RESET}..."
    log "Starting pattern-based transfer from main machine to $DEST_VM..."
    
    # Run rsync in background to allow for spinner
    (rsync -az --progress --include-from="$PATTERN_FILE" -e "ssh -p $DEST_PORT" \
          "$SOURCE_PATH/" "$DEST_USER@$DEST_IP:$DEST_PATH/" > /tmp/rsync_output_$$ 2>&1) &
    
    # Show spinner while transfer is running
    show_spinner $! "Transferring files to $DEST_VM"
    
    # Check if transfer was successful
    if [ $? -eq 0 ]; then
        print_status "success" "Transfer to $DEST_VM completed successfully"
        log "Transfer to $DEST_VM completed successfully"
    else
        print_status "error" "Transfer to $DEST_VM failed"
        log "ERROR: Transfer to $DEST_VM failed"
    fi
    
    echo -e "${DIM}${SEPARATOR}${RESET}"
done

# Cleanup
rm -f "$PATTERN_FILE"
rm -f /tmp/rsync_output_$$

print_header "Summary"
print_status "success" "All transfers completed"
log "All transfers completed"