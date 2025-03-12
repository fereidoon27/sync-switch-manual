#!/bin/bash

# Display help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -s, --services SERVICES    Comma-separated list of services (binance,kucoin,gateio)"
    echo "  -d, --datacenter DC        Name of datacenter"
    echo "  -v, --vms VMS              Comma-separated list of VMs"
    echo "  -p, --parallel NUM         Maximum number of parallel jobs (default: 3)"
    echo "  -a, --actions ACTIONS      Comma-separated list of actions (1,2,3,4)"
    echo "  -y, --yes                  Skip confirmation (assume yes)"
    echo "  -h, --help                 Show this help message"
    echo
    echo "Example:"
    echo "  $0 -s binance,kucoin -d arvan -v cr1arvan,cr2arvan -p 2 -a 1,2,3 -y"
    echo
    exit 0
}

# Parse command line arguments
parse_args() {
    # Default values
    CLI_SERVICES=""
    CLI_DATACENTER=""
    CLI_VMS=""
    CLI_PARALLEL=""
    CLI_ACTIONS=""
    CLI_SKIP_CONFIRM=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--services)
                CLI_SERVICES="$2"
                shift 2
                ;;
            -d|--datacenter)
                CLI_DATACENTER="$2"
                shift 2
                ;;
            -v|--vms)
                CLI_VMS="$2"
                shift 2
                ;;
            -p|--parallel)
                CLI_PARALLEL="$2"
                shift 2
                ;;
            -a|--actions)
                CLI_ACTIONS="$2"
                shift 2
                ;;
            -y|--yes)
                CLI_SKIP_CONFIRM=true
                shift
                ;;
            -h|--help)
                show_help
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

# Log file setup
ACTION_LOG="$HOME/service_actions_$(date +%Y%m%d).log"

# Set directory paths
INFO_PATH="$(dirname "$0")/Info"
DEPLOYMENT_SCRIPTS_PATH="$(dirname "$0")/deployment_scripts"
SERVERS_CONF="$INFO_PATH/servers.conf"

# Define colors for better visualization
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# SSH Options for automation
SSH_OPTS="-o StrictHostKeyChecking=no"

# Available services
SERVICES=("binance" "kucoin" "gateio")

# Variable to track job numbers
# Each VM gets its own job number

# Function for colorful headings
print_heading() {
    echo -e "\n${BLUE}╔═════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ ${WHITE}$1${BLUE} ║${NC}"
    echo -e "${BLUE}╚═════════════════════════════════════════════════════════╝${NC}"
}

# Create temporary directory for job logs
TMP_LOG_DIR=$(mktemp -d)

# Initialize log file with headers
initialize_log() {
    # Check if the log file already exists
    if [ ! -f "$ACTION_LOG" ]; then
        # Create new log file with headers
        echo "# Service Migration Log - Started $(date '+%a %b %d %I:%M:%S %p %z %Y')" > "$ACTION_LOG"
        echo "# Format: Timestamp | Action | Task Description | Server | Status | Job" >> "$ACTION_LOG"
        echo "# --------------------------------------------------------------------" >> "$ACTION_LOG"
        echo "" >> "$ACTION_LOG"
    else
        # Append a new section to existing log file
        echo "" >> "$ACTION_LOG"
        echo "# Service Migration Log - Started $(date '+%a %b %d %I:%M:%S %p %z %Y')" >> "$ACTION_LOG"
        echo "# Format: Timestamp | Action | Task Description | Server | Status | Job" >> "$ACTION_LOG"
        echo "# --------------------------------------------------------------------" >> "$ACTION_LOG"
        echo "" >> "$ACTION_LOG"
    fi
}

# Start a new job section in the log
start_job_section() {
    local job_num=$1
    local vm_name=$2
    local job_log_file="$TMP_LOG_DIR/job_${job_num}.log"
    
    # Create job log file with header
    echo "" > "$job_log_file"
    echo "------------------------------------------------------------" >> "$job_log_file"
    echo "|            Service Transfer Operation - Job $job_num            |" >> "$job_log_file"
    echo "|                   Server: $vm_name                      |" >> "$job_log_file"
    echo "------------------------------------------------------------" >> "$job_log_file"
    echo "" >> "$job_log_file"
    
    # Also print to console
    echo ""
    echo "------------------------------------------------------------"
    echo "|            Service Transfer Operation - Job $job_num            |"
    echo "|                   Server: $vm_name                      |"
    echo "------------------------------------------------------------"
    echo ""
}

# Combine all job logs and write to main log file
combine_logs() {
    # First, find all job log files and sort them by job number
    for job_log in $(ls "$TMP_LOG_DIR"/job_*.log | sort -V); do
        # Append each job log to the main log file
        cat "$job_log" >> "$ACTION_LOG"
    done
    
    # Add completion footer
    echo "" >> "$ACTION_LOG"
    echo "------------------------------------------------------------" >> "$ACTION_LOG"
    echo "|        All Service Transfer Operations Completed         |" >> "$ACTION_LOG"
    echo "------------------------------------------------------------" >> "$ACTION_LOG"
    echo "" >> "$ACTION_LOG"
    
    # Also print to console
    echo ""
    echo "------------------------------------------------------------"
    echo "|        All Service Transfer Operations Completed         |"
    echo "------------------------------------------------------------"
    echo ""
    
    # Clean up temp directory
    rm -rf "$TMP_LOG_DIR"
}

# Function for logging
log() {
    local action=$1
    local description=$2
    local server=$3
    local status=$4
    local job_id=$5
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local status_symbol=""
    if [ "$status" == "Started" ]; then
        status_symbol="──▶"
    elif [ "$status" == "Completed" ]; then
        status_symbol="✅ "
    elif [ "$status" == "Failed" ]; then
        status_symbol="❌ "
    else
        status_symbol="   "
    fi
    
    # Pad fields to align columns
    local action_padded=$(printf "%-15s" "$action")
    local description_padded=$(printf "%-30s" "$description")
    local server_padded=$(printf "%-25s" "$server")
    local status_padded=$(printf "%-15s" "$status")
    
    # Format log entry
    local log_entry="[$timestamp] $status_symbol [Action $action_padded] | $description_padded | Server: $server_padded | STATUS: $status_padded | Job $job_id"
    
    # Write to the job's log file
    local job_log_file="$TMP_LOG_DIR/job_${job_id}.log"
    echo "$log_entry" >> "$job_log_file"
    
    # Also print to console
    echo "$log_entry"
}

# Check if servers.conf exists
if [ ! -f "$SERVERS_CONF" ]; then
    log "Config Error" "servers.conf not found" "N/A" "Failed" "0"
    echo -e "${RED}ERROR: servers.conf not found at $SERVERS_CONF${NC}"
    exit 1
fi

# Check if deployment scripts exist for each service
for service in "${SERVICES[@]}"; do
    for action in "deploy" "start" "stop" "purge"; do
        script_path="$DEPLOYMENT_SCRIPTS_PATH/${action}_all_${service}.sh"
        if [ ! -f "$script_path" ]; then
            echo -e "${YELLOW}WARNING: Script $script_path not found. This might cause issues if selected.${NC}"
        elif [ ! -x "$script_path" ]; then
            echo -e "${YELLOW}WARNING: Script $script_path is not executable. This might cause issues if selected.${NC}"
            chmod +x "$script_path"
            echo -e "${GREEN}Made script executable: $script_path${NC}"
        fi
    done
done

# Parse servers.conf and get unique datacenters
mapfile -t DATACENTERS < <(awk -F'|' '{print $1}' "$SERVERS_CONF" | sort -u | grep -v "^$")

# Function to execute sequence of actions on a VM
execute_sequence() {
    local vm_name=$1
    local -n sequence_ref=$2  # Name reference to the array
    local datacenter=$3
    local job_id=$4
    local services=("${@:5}")  # Array of services passed as arguments
    local username=""
    local ip=""
    local host=""
    local port=""
    local ssh_cmd=""
    local target_path="$HOME"
    
    # Get VM details from servers.conf
    while IFS='|' read -r dc name ip_addr hostname user p || [ -n "$dc" ]; do
        if [ "$dc" == "$datacenter" ] && [ "$name" == "$vm_name" ]; then
            username="$user"
            ip="$ip_addr"
            host="$hostname"
            port="$p"
            break
        fi
    done < "$SERVERS_CONF"
    
    if [ -z "$username" ] || [ -z "$host" ] || [ -z "$port" ]; then
        log "Setting up SSH" "Finding VM details" "$vm_name" "Failed" "$job_id"
        return 1
    fi
    
    # Build SSH command
    ssh_cmd="ssh $SSH_OPTS -p $port $username@$host"
    
    # Test SSH connection
    log "Setting up S" "Establishing SSH connection" "$vm_name" "Started" "$job_id"
    if ! $ssh_cmd "exit" > /dev/null 2>&1; then
        log "Setting up S" "Establishing SSH connection" "$vm_name" "Failed" "$job_id"
        return 1
    fi
    log "Setting up S" "Establishing SSH connection" "$vm_name" "Completed" "$job_id"
    
    # Create temp directory on remote machine if it doesn't exist
    $ssh_cmd "mkdir -p /tmp/deployment_scripts"
    
    # Copy all needed scripts at once for each service
    local copied_scripts=()
    for service in "${services[@]}"; do
        log "Copying depl" "Copy Scripts for $service" "$vm_name" "Started" "$job_id"
        
        for action_num in "${sequence_ref[@]}"; do
            case $action_num in
                1) action_script="deploy_all_${service}.sh" ;;
                2) action_script="start_all_${service}.sh" ;;
                3) action_script="stop_all_${service}.sh" ;;
                4) action_script="purge_all_${service}.sh" ;;
                *) continue ;;
            esac
            
            # Check if we've already copied this script (avoid duplicates)
            if [[ " ${copied_scripts[*]} " == *" $action_script "* ]]; then
                continue
            fi
            
            copied_scripts+=("$action_script")
            
            if [ ! -f "$DEPLOYMENT_SCRIPTS_PATH/$action_script" ]; then
                log "Copying depl" "Finding script $action_script" "$vm_name" "Failed" "$job_id"
                return 1
            fi
            
            if [ ! -x "$DEPLOYMENT_SCRIPTS_PATH/$action_script" ]; then
                log "Copying depl" "Script $action_script not executable" "$vm_name" "Started" "$job_id"
                chmod +x "$DEPLOYMENT_SCRIPTS_PATH/$action_script"
                log "Copying depl" "Making script executable" "$vm_name" "Completed" "$job_id"
            fi
            
            scp $SSH_OPTS -P "$port" "$DEPLOYMENT_SCRIPTS_PATH/$action_script" "$username@$host:/tmp/deployment_scripts/" > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                log "Copying depl" "Copy script $action_script" "$vm_name" "Failed" "$job_id"
                return 1
            fi
            
            $ssh_cmd "chmod +x /tmp/deployment_scripts/$action_script"
        done
        
        log "Copying depl" "Copy Scripts for $service" "$vm_name" "Completed" "$job_id"
    done
    
    # Execute sequence in a single SSH session
    
    # Create a temporary script file
    local tmp_script=$(mktemp)
    echo "#!/bin/bash" > "$tmp_script"
    echo "cd $target_path" >> "$tmp_script"
    
    for action_num in "${sequence_ref[@]}"; do
        # For each action, run it for all selected services
        for service in "${services[@]}"; do
            case $action_num in
                1)
                    action_script="deploy_all_${service}.sh"
                    action_name="Deploy $service Service"
                    ;;
                2)
                    action_script="start_all_${service}.sh"
                    action_name="Start $service Service"
                    ;;
                3)
                    action_script="stop_all_${service}.sh"
                    action_name="Stop $service Service"
                    ;;
                4)
                    action_script="purge_all_${service}.sh"
                    action_name="Purge $service Service"
                    ;;
                *)
                    log "$action_num" "Invalid action number" "$vm_name" "Failed" "$job_id"
                    continue
                    ;;
            esac
            
            # Add logging before execution
            echo "echo \"LOGMARKER:START:$action_num:$action_name:$vm_name\"" >> "$tmp_script"
            
            # Execute the script
            echo "/tmp/deployment_scripts/$action_script" >> "$tmp_script"
            
            # Add logging after execution based on result
            echo "if [ \$? -ne 0 ]; then" >> "$tmp_script"
            echo "  echo \"LOGMARKER:FAIL:$action_num:$action_name:$vm_name\"" >> "$tmp_script"
            echo "  exit 1" >> "$tmp_script"
            echo "else" >> "$tmp_script"
            echo "  echo \"LOGMARKER:COMPLETE:$action_num:$action_name:$vm_name\"" >> "$tmp_script"
            echo "fi" >> "$tmp_script"
        done
    done
    
    # Copy and execute the temporary script
    scp $SSH_OPTS -P "$port" "$tmp_script" "$username@$host:/tmp/execute_sequence.sh" > /dev/null 2>&1
    
    # Execute the script and capture the output for logging
    $ssh_cmd "chmod +x /tmp/execute_sequence.sh" > /dev/null 2>&1
    ssh_output=$($ssh_cmd "/tmp/execute_sequence.sh" 2>&1)
    local result=$?
    
    # Process the log markers from the output
    while IFS= read -r line; do
        if [[ $line == LOGMARKER:* ]]; then
            # Parse the log marker
            IFS=':' read -r _ status action_num action_desc server <<< "$line"
            
            case "$status" in
                "START")
                    log "$action_num" "$action_desc" "$server" "Started" "$job_id"
                    ;;
                "COMPLETE")
                    log "$action_num" "$action_desc" "$server" "Completed" "$job_id"
                    ;;
                "FAIL")
                    log "$action_num" "$action_desc" "$server" "Failed" "$job_id"
                    ;;
            esac
        fi
    done <<< "$ssh_output"
    
    # Clean up
    rm -f "$tmp_script"
    
    # Close SSH connection
    log "Closing SSH" "Closing SSH connection" "$vm_name" "Started" "$job_id"
    $ssh_cmd "exit" > /dev/null 2>&1
    log "Closing SSH" "Closing SSH connection" "$vm_name" "Completed" "$job_id"
    
    if [ $result -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Show execution plan and get confirmation
show_execution_plan() {
    print_heading "EXECUTION PLAN"
    echo -e "${WHITE}Summary of selections:${NC}"
    echo -e "   ${CYAN}●${NC} ${WHITE}Selected datacenter:${NC} ${GREEN}$SELECTED_DC${NC}"
    echo -e "   ${CYAN}●${NC} ${WHITE}Selected VMs:${NC} ${GREEN}${SELECTED_VMS[*]}${NC}"
    echo -e "   ${CYAN}●${NC} ${WHITE}Selected services:${NC} ${GREEN}${SELECTED_SERVICES[*]}${NC}"
    echo -e "   ${CYAN}●${NC} ${WHITE}Parallel jobs:${NC} ${GREEN}$MAX_PARALLEL_JOBS${NC}"
    echo -e "   ${CYAN}●${NC} ${WHITE}Action sequence:${NC} ${PURPLE}${sequence_input}${NC}"
    
    echo -e "\n${WHITE}The following actions will be executed for each service on each VM:${NC}"
    
    # Show each action for each service
    for i in "${!sequence_array[@]}"; do
        action_num=${sequence_array[$i]}
        case $action_num in
            1) action_name="Deploy" ;;
            2) action_name="Start" ;;
            3) action_name="Stop" ;;
            4) action_name="Purge" ;;
        esac
        
        for service in "${SELECTED_SERVICES[@]}"; do
            echo -e "   ${CYAN}$(($i+1))${NC} │ ${GREEN}${action_name} All ${service} Services${NC}"
        done
    done
    
    echo
    read -p "$(echo -e "${YELLOW}Continue?${NC} (Y/n): ")" confirm
    if [[ "${confirm,,}" == "n" ]]; then
        return 1
    fi
    return 0
}

# Main execution function
execute_jobs() {
    print_heading "EXECUTING JOBS"
    echo -e "${WHITE}Executing jobs on selected VMs (max parallel: ${CYAN}$MAX_PARALLEL_JOBS${WHITE})...${NC}"
    
    # Initialize the log file
    initialize_log
    
    # Array to store process IDs for parallel execution
    pids=()
    vm_job_map=()
    
    # Process each VM as a separate job - each in its own subshell to isolate logs
    job_id=1
    for vm in "${SELECTED_VMS[@]}"; do
        # Start job section in log
        start_job_section $job_id "$vm"
        vm_job_map+=("$vm:$job_id")
        
        # If we've reached the maximum number of parallel jobs, wait for one to finish
        while [ ${#pids[@]} -ge $MAX_PARALLEL_JOBS ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 ${pids[$i]} 2>/dev/null; then
                    wait ${pids[$i]}
                    unset pids[$i]
                    pids=("${pids[@]}")
                    break
                fi
            done
            sleep 0.5
        done
        
        # Launch a completely isolated job process with its own log file
        (
            # All log output for this job is already directed to its own file by the log() function
            execute_sequence "$vm" sequence_array "$SELECTED_DC" "$job_id" "${SELECTED_SERVICES[@]}"
            exit $?
        ) &
        
        # Store PID for job control
        pids+=($!)
        job_id=$((job_id + 1))
        sleep 0.5
    done
    
    # Wait for all remaining jobs to complete
    wait
    
    # Combine all logs
    combine_logs
}

# Main script execution starts here
main_loop() {
    # Check for command line arguments
    if [ $# -gt 0 ]; then
        parse_args "$@"
    fi
    
    while true; do
        # Display available services if not provided via CLI
        if [ -z "$CLI_SERVICES" ]; then
            print_heading "SELECT SERVICES"
            for i in "${!SERVICES[@]}"; do
                echo -e "${CYAN}   $((i+1))${NC} │ ${GREEN}${SERVICES[$i]}${NC}"
            done
            echo -e "${CYAN}   $((${#SERVICES[@]}+1))${NC} │ ${PURPLE}all${NC}"
            echo
            
            # Get service choices
            while true; do
                read -p "$(echo -e "${YELLOW}Select services${NC} (comma-separated, e.g., 1,2 or 1,3,4): ")" service_choices
                
                # Remove spaces if any
                service_choices=${service_choices// /}
                
                # Check if "all" option is selected
                if [[ "$service_choices" == "$((${#SERVICES[@]}+1))" ]]; then
                    # Select all services
                    SELECTED_SERVICES=("${SERVICES[@]}")
                    break
                fi
                
                # Check if input is comma-separated format
                if [[ ! "$service_choices" =~ ^[0-9](,[0-9])*$ ]]; then
                    echo -e "${RED}Error: Please enter comma-separated values (e.g., 1,2,3)${NC}"
                    continue
                fi
                
                # Parse comma-separated input
                IFS=',' read -ra service_indices <<< "$service_choices"
                
                SELECTED_SERVICES=()
                valid=true
                
                for index in "${service_indices[@]}"; do
                    if [[ "$index" =~ ^[0-9]$ ]] && [ "$index" -ge 1 ] && [ "$index" -le "${#SERVICES[@]}" ]; then
                        # Check if service is already selected (avoid duplicates)
                        if [[ ! " ${SELECTED_SERVICES[*]} " =~ " ${SERVICES[$((index-1))]} " ]]; then
                            SELECTED_SERVICES+=("${SERVICES[$((index-1))]}")
                        fi
                    else
                        echo -e "${RED}Invalid service number: $index${NC}"
                        valid=false
                        break
                    fi
                done
                
                if [ "$valid" = true ] && [ ${#SELECTED_SERVICES[@]} -gt 0 ]; then
                    break
                else
                    echo -e "${RED}Please enter valid service numbers between 1 and ${#SERVICES[@]}, or ${#SERVICES[@]}+1 for all.${NC}"
                fi
            done
            
            echo -e "\n${WHITE}Selected services:${NC} ${GREEN}${SELECTED_SERVICES[*]}${NC}"
        else
            # Use services from command line arguments
            SELECTED_SERVICES=()
            IFS=',' read -ra service_list <<< "$CLI_SERVICES"
            
            for service in "${service_list[@]}"; do
                # Check if service is valid
                if [[ " ${SERVICES[*]} " =~ " ${service} " ]]; then
                    SELECTED_SERVICES+=("$service")
                else
                    echo -e "${RED}Invalid service: $service${NC}"
                    exit 1
                fi
            done
            echo -e "${WHITE}Using services from command line:${NC} ${GREEN}${SELECTED_SERVICES[*]}${NC}"
        fi
        
        # Display available datacenters if not provided via CLI
        if [ -z "$CLI_DATACENTER" ]; then
            print_heading "SELECT DESTINATION DATACENTER"
            for i in "${!DATACENTERS[@]}"; do
                echo -e "${CYAN}   $((i+1))${NC} │ ${GREEN}${DATACENTERS[$i]}${NC}"
            done
            echo
            
            # Get datacenter choice
            while true; do
                read -p "$(echo -e "${YELLOW}Select datacenter${NC} (1-${#DATACENTERS[@]}): ")" dc_choice
                if [[ "$dc_choice" =~ ^[0-9]+$ ]] && [ "$dc_choice" -ge 1 ] && [ "$dc_choice" -le "${#DATACENTERS[@]}" ]; then
                    SELECTED_DC="${DATACENTERS[$((dc_choice-1))]}"
                    break
                else
                    echo -e "${RED}Invalid choice. Please enter a number between 1 and ${#DATACENTERS[@]}.${NC}"
                fi
            done
            
            echo -e "\n${WHITE}Selected datacenter:${NC} ${GREEN}$SELECTED_DC${NC}"
        else
            # Use datacenter from command line arguments
            # Check if datacenter is valid
            if [[ " ${DATACENTERS[*]} " =~ " ${CLI_DATACENTER} " ]]; then
                SELECTED_DC="$CLI_DATACENTER"
                echo -e "${WHITE}Using datacenter from command line:${NC} ${GREEN}$SELECTED_DC${NC}"
            else
                echo -e "${RED}Invalid datacenter: $CLI_DATACENTER${NC}"
                echo -e "${YELLOW}Available datacenters:${NC} ${GREEN}${DATACENTERS[*]}${NC}"
                exit 1
            fi
        fi
        
        # Get VMs for selected datacenter
        mapfile -t DC_VMS < <(awk -F'|' -v dc="$SELECTED_DC" '$1 == dc {print $2}' "$SERVERS_CONF")
        
        # Display available VMs if not provided via CLI
        if [ -z "$CLI_VMS" ]; then
            print_heading "SELECT DESTINATION VMs"
            for i in "${!DC_VMS[@]}"; do
                echo -e "${CYAN}   $((i+1))${NC} │ ${GREEN}${DC_VMS[$i]}${NC}"
            done
            echo -e "${CYAN}   $((${#DC_VMS[@]}+1))${NC} │ ${PURPLE}all${NC}"
            echo
            
            # Get VM choices
            while true; do
                read -p "$(echo -e "${YELLOW}Enter VM numbers${NC} (comma-separated or single number, e.g., 1,3,5): ")" vm_choices
                
                # Check if "all" option is selected
                if [[ "$vm_choices" == "$((${#DC_VMS[@]}+1))" ]]; then
                    # Select all VMs
                    SELECTED_VMS=("${DC_VMS[@]}")
                    break
                fi
                
                # Parse comma-separated input
                IFS=',' read -ra VM_INDICES <<< "$vm_choices"
                SELECTED_VMS=()
                
                valid=true
                for index in "${VM_INDICES[@]}"; do
                    if [[ "$index" =~ ^[0-9]+$ ]] && [ "$index" -ge 1 ] && [ "$index" -le "${#DC_VMS[@]}" ]; then
                        SELECTED_VMS+=("${DC_VMS[$((index-1))]}")
                    else
                        echo -e "${RED}Invalid VM number: $index${NC}"
                        valid=false
                        break
                    fi
                done
                
                if [ "$valid" = true ] && [ ${#SELECTED_VMS[@]} -gt 0 ]; then
                    break
                else
                    echo -e "${RED}Please enter valid VM numbers between 1 and ${#DC_VMS[@]}, or ${#DC_VMS[@]}+1 for all.${NC}"
                fi
            done
            
            echo -e "\n${WHITE}Selected VMs:${NC} ${GREEN}${SELECTED_VMS[*]}${NC}"
        else
            # Use VMs from command line arguments
            SELECTED_VMS=()
            IFS=',' read -ra vm_list <<< "$CLI_VMS"
            
            for vm in "${vm_list[@]}"; do
                # Check if VM is valid for the selected datacenter
                if [[ " ${DC_VMS[*]} " =~ " ${vm} " ]]; then
                    SELECTED_VMS+=("$vm")
                else
                    echo -e "${RED}Invalid VM for datacenter $SELECTED_DC: $vm${NC}"
                    echo -e "${YELLOW}Available VMs:${NC} ${GREEN}${DC_VMS[*]}${NC}"
                    exit 1
                fi
            done
            echo -e "${WHITE}Using VMs from command line:${NC} ${GREEN}${SELECTED_VMS[*]}${NC}"
        fi
        
        # Get maximum parallel jobs if not provided via CLI
        if [ -z "$CLI_PARALLEL" ]; then
            read -p "$(echo -e "${YELLOW}Enter maximum parallel jobs${NC} (default: 3): ")" MAX_PARALLEL_JOBS
            MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS:-3}
            echo -e "${WHITE}Running with${NC} ${CYAN}$MAX_PARALLEL_JOBS${WHITE} parallel jobs${NC}"
        else
            # Use parallel jobs from command line arguments
            if [[ "$CLI_PARALLEL" =~ ^[0-9]+$ ]] && [ "$CLI_PARALLEL" -ge 1 ]; then
                MAX_PARALLEL_JOBS="$CLI_PARALLEL"
                echo -e "${WHITE}Using parallel jobs from command line:${NC} ${CYAN}$MAX_PARALLEL_JOBS${NC}"
            else
                echo -e "${RED}Invalid number of parallel jobs: $CLI_PARALLEL${NC}"
                exit 1
            fi
        fi
        
        # Display available actions if not provided via CLI
        if [ -z "$CLI_ACTIONS" ]; then
            print_heading "AVAILABLE ACTIONS"
            echo -e "${CYAN}   1${NC} │ ${GREEN}Deploy All Services${NC} - Runs deploy_all_<service>.sh"
            echo -e "       ${WHITE}(Executes 111-ACTION-deploy-services.sh in all van-buren directories)${NC}"
            echo -e "${CYAN}   2${NC} │ ${GREEN}Start All Services${NC} - Runs start_all_<service>.sh"
            echo -e "       ${WHITE}(Executes 222-ACTION-start-services.sh in all van-buren directories)${NC}"
            echo -e "${CYAN}   3${NC} │ ${GREEN}Stop All Services${NC} - Runs stop_all_<service>.sh"
            echo -e "       ${WHITE}(Executes 000-ACTION-stop-services.sh in all van-buren directories)${NC}"
            echo -e "${CYAN}   4${NC} │ ${GREEN}Purge All Services${NC} - Runs purge_all_<service>.sh"
            echo -e "       ${WHITE}(Executes 999-ACTION-purge-services.sh in all van-buren directories)${NC}"
            
            # Get sequence of actions
            while true; do
                read -p "$(echo -e "${YELLOW}Enter sequence of actions${NC} (comma-separated, e.g., 1,2 or 3,1,2,4): ")" sequence_input
                
                # Remove spaces if any
                sequence_input=${sequence_input// /}
                
                # Check if input is comma-separated format or just a single digit
                if [[ "$sequence_input" =~ ^[1-4](,[1-4])*$ ]]; then
                    # Valid comma-separated sequence or single digit
                    IFS=',' read -ra sequence_array <<< "$sequence_input"
                    break
                else
                    echo -e "${RED}Error: Please enter comma-separated values using only numbers 1-4 (e.g., 1,2,3 or 2,4)${NC}"
                    continue
                fi
            done
        else
            # Use actions from command line arguments
            sequence_input="$CLI_ACTIONS"
            
            # Validate sequence format
            if [[ "$sequence_input" =~ ^[1-4](,[1-4])*$ ]]; then
                IFS=',' read -ra sequence_array <<< "$sequence_input"
                echo -e "${WHITE}Using action sequence from command line:${NC} ${PURPLE}$sequence_input${NC}"
            else
                echo -e "${RED}Invalid action sequence: $sequence_input${NC}"
                echo -e "${YELLOW}Sequence must be comma-separated values using only numbers 1-4 (e.g., 1,2,3)${NC}"
                exit 1
            fi
        fi
        
        # Show execution plan and get confirmation
        if [ "$CLI_SKIP_CONFIRM" = true ]; then
            # Skip confirmation if -y flag was used
            execute_jobs
            
            print_heading "EXECUTION SUMMARY"
            echo -e "${GREEN}All jobs completed successfully!${NC}"
            echo -e "${WHITE}Action log:${NC} ${CYAN}$ACTION_LOG${NC}"
            break
        elif show_execution_plan; then
            # User confirmed, execute the plan
            execute_jobs
            
            print_heading "EXECUTION SUMMARY"
            echo -e "${GREEN}All jobs completed successfully!${NC}"
            echo -e "${WHITE}Action log:${NC} ${CYAN}$ACTION_LOG${NC}"
            break
        else
            # User chose to restart
            echo -e "${YELLOW}Restarting selection process...${NC}"
            # Reset CLI parameters to force interactive mode in the next loop
            CLI_SERVICES=""
            CLI_DATACENTER=""
            CLI_VMS=""
            CLI_PARALLEL=""
            CLI_ACTIONS=""
            continue
        fi
    done
}

# Parse command line arguments and start the script
if [ $# -gt 0 ]; then
    main_loop "$@"
else
    main_loop
fi