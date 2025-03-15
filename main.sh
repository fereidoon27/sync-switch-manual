#!/bin/bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
BLINK='\033[5m'
BG_BLUE='\033[44m'
BG_BLACK='\033[40m'
BG_GREEN='\033[42m'
BG_RED='\033[41m'
BG_YELLOW='\033[43m'
BG_CYAN='\033[46m'
UNDERLINE='\033[4m'
RESET='\033[0m'

# Fixed width for alignment
MENU_WIDTH=72

# Function to repeat a character
repeat_char() {
    local char="$1"
    local count="$2"
    local result=""
    for ((i=0; i<count; i++)); do
        result="${result}${char}"
    done
    echo "$result"
}

# Function to create properly aligned text
align_text() {
    local text="$1"
    local width="$2"
    local pad_length=$((width - ${#text}))
    echo -n "$text"
    repeat_char " " $pad_length
}

# Create horizontal divider
DIVIDER=$(repeat_char "━" $MENU_WIDTH)
THIN_DIVIDER=$(repeat_char "─" $MENU_WIDTH)

# Function to print gradient text
print_gradient() {
    local text="$1"
    local colors=("36" "36" "34" "34" "32" "32")
    local result=""
    
    for ((i=0; i<${#text}; i++)); do
        local color_index=$((i % ${#colors[@]}))
        local char="${text:$i:1}"
        result="${result}\033[1;${colors[$color_index]}m${char}"
    done
    
    echo -e "${result}${RESET}"
}

# Function to draw a section header
draw_header() {
    local title="$1"
    local bg_color="$2"
    local fg_color="$3"
    
    echo -e "${bg_color}${fg_color}${BOLD} $(align_text "${title}" $((MENU_WIDTH-1))) ${RESET}"
}

# Function to draw a menu option
draw_option() {
    local number="$1"
    local title="$2"
    local desc1="$3"
    local desc2="$4"
    local desc3="${5:-}"  # Optional 3rd description line
    local color="$6"
    
    echo -e "${color}${BOLD} ${number} ${WHITE}⟹  ${UNDERLINE}${title}${RESET}"
    echo -e "${color}    ┗━ ${desc1}${RESET}"
    echo -e "${color}    ┗━ ${desc2}${RESET}"
    
    if [ -n "$desc3" ]; then
        echo -e "${color}    ┗━ ${desc3}${RESET}"
    fi
    
    echo ""
}

# Clear screen for a clean start
clear

while true; do
    # ASCII Art Banner with glow effect
    echo -e "${CYAN}${BOLD}"
    echo "                                                                        "
    echo "    ██████╗ ██████╗ ███╗   ██╗████████╗██████╗  ██████╗ ██╗            "
    echo "   ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔══██╗██╔═══██╗██║            "
    echo "   ██║     ██║   ██║██╔██╗ ██║   ██║   ██████╔╝██║   ██║██║            "
    echo "   ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══██╗██║   ██║██║            "
    echo "   ╚██████╗╚██████╔╝██║ ╚████║   ██║   ██║  ██║╚██████╔╝███████╗       "
    echo "    ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝       "
    echo "        ██████╗ ███████╗███╗   ██╗████████╗███████╗██████╗             "
    echo "       ██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝██╔════╝██╔══██╗            "
    echo "       ██║      █████╗  ██╔██╗ ██║   ██║   █████╗  ██████╔╝            "
    echo "       ██║      ██╔══╝  ██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗            "
    echo "       ╚██████╗ ███████╗██║ ╚████║   ██║   ███████╗██║  ██║            "
    echo "        ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝            "
    echo -e "${RESET}"
    
    # Main header
    echo -e "\n${BG_BLUE}${WHITE}${BOLD} $(align_text "VIRTUAL MACHINE MANAGEMENT CENTER" $((MENU_WIDTH-1))) ${RESET}"
    echo -e "${YELLOW} - This script runs from the main VM (e.g., Main-Crypto-AZMA),${RESET}"
    echo -e "${YELLOW} - Main VM has access to all other VMs.${RESET}"
    
    # Gradient divider
    echo -e "${BLUE}${DIVIDER}${RESET}"
    
    # Operations header
    draw_header "SELECT YOUR OPERATION" "${BG_BLUE}" "${WHITE}"
    echo ""
    
    # Option 1
    draw_option "1" "Synchronize with sync.sh" \
               "Sync a folder from a source VM to a destination VM." \
               "Direct synchronization or via an intermediate machine." \
               "" \
               "${BLUE}"
    
    # Option 2
    draw_option "2" "Set environment variable & Edit EDN Based on IP" \
               "Connects to a remote server via SSH." \
               "Detects network environment (internal/external)." \
               "Modifies proxy settings in configuration files." \
               "${BLUE}"
    
    # Option 3
    draw_option "3" "Deploy action.sh" \
               "Remotely execute sequential actions on a target VM." \
               "Logs the timestamps for each action to track progress." \
               "" \
               "${BLUE}"
    
    # Exit option
    draw_option "0" "Exit - Terminate the main script." \
               "Returns to the command line." \
               "All current operations will be stopped." \
               "" \
               "${RED}"
    
    # System info footer with gradient background
    echo -e "${BLUE}${THIN_DIVIDER}${RESET}"
    echo -e "${WHITE}${BOLD} SYSTEM_INFO ${RESET} ${CYAN}$(hostname) | User: $(whoami) | Date: $(date "+%Y-%m-%d %H:%M")${RESET}"
    echo -e "${BLUE}${DIVIDER}${RESET}\n"

    # Enhanced user input prompt with highlighting
    echo -e "${BG_BLUE}${WHITE}${BOLD} COMMAND ${RESET} ${YELLOW}Enter your selection (0-3):${RESET} ${CYAN}${BOLD}\c${RESET}"
    read choice
    echo -e "\n"

    # Animated loading effect for selection
    echo -e "${YELLOW}Processing selection...\c${RESET}"
    for i in {1..3}; do
        echo -e "${YELLOW}.\c${RESET}"
        sleep 0.2
    done
    echo -e "\n"

    case $choice in
        1)
            # Run sync.sh script
            echo -e "${GREEN}${BOLD}▶ Running sync.sh...${RESET}"
            ./sync.sh
            ;;
        2)
            # Run edit_edn_base_on_ip.sh script
            echo -e "${GREEN}${BOLD}▶ Running Set Environment Variable & Edit EDN Based on IP...${RESET}"
            ./edit_edn_base_on_ip.sh
            ;;
        3)
            # Run action.sh script
            echo -e "${GREEN}${BOLD}▶ Running action.sh...${RESET}"
            ./action.sh
            ;;
        0)
            # Exit the script with animation
            echo -e "${RED}${BOLD}Exiting Main Script...${RESET}"
            for i in {1..20}; do
                echo -ne "${RED}${BOLD}█${RESET}\r"
                sleep 0.05
            done
            echo -e "${GREEN}${BOLD}Goodbye!${RESET}"
            break
            ;;
        *)
            # Handle invalid input with warning
            echo -e "${RED}${BOLD}⚠ Invalid choice. Please enter a valid number (0, 1, 2, or 3).${RESET}"
            sleep 1
            ;;
    esac
    
    # Wait for keypress before showing menu again
    if [ "$choice" != "0" ]; then
        echo -e "\n${YELLOW}Press Enter to return to the menu...${RESET}"
        read
        clear
    fi
done