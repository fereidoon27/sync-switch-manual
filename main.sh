#!/bin/bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

while true; do

    echo -e "${CYAN}========================================${RESET}"
    echo -e "\n${YELLOW}This script runs from the main VM (e.g., Main-Crypto-AZMA), which has access to all other VMs.${RESET}"
    echo -e "\n${YELLOW}Select the action you would like to perform:${RESET}\n"

    echo -e "${GREEN}1: VM Initialization & Package Installer${RESET}"
    echo -e "   - ${CYAN}Remotely updates, upgrades, reboots, and installs essential packages on an Ubuntu 22.04 VM via SSH.${RESET}"
    echo ""

    echo -e "${GREEN}2: Chrony Exporter Auto-Setup${RESET}"
    echo -e "   - ${CYAN}Deploys and configures Chrony Exporter on multiple VMs automatically.${RESET}"
    echo ""

    echo -e "${GREEN}3: Synchronize with sync.sh${RESET}"
    echo -e "   - ${CYAN}Sync a folder from a source VM to a destination VM.${RESET}"
    echo -e "   - ${CYAN}Direct synchronization or via an intermediate machine if needed.${RESET}"
    echo ""

    echo -e "${GREEN}4: Set environment variable & Edit EDN Based on IP${RESET}"
    echo -e "   - ${CYAN}Connects to a remote server via SSH.${RESET}"
    echo -e "   - ${CYAN}Detects network environment (internal/external).${RESET}"
    echo -e "   - ${CYAN}Copies the appropriate environment file.${RESET}"
    echo -e "   - ${CYAN}Modifies proxy settings in configuration files accordingly.${RESET}"
    echo ""

    echo -e "${GREEN}5: Deploy action.sh${RESET}"
    echo -e "   - ${CYAN}Remotely execute sequential actions on a target VM.${RESET}"
    echo -e "   - ${CYAN}Logs the timestamps for each action to keep track of progress.${RESET}"
    echo ""

    echo -e "${RED}0: Exit - Terminate the main script.${RESET}"
    echo -e "${CYAN}========================================${RESET}"

    # Prompt the user for input
    read -p "Enter a number (0, 1, 2, 3, 4, 5): " choice

    case $choice in
        1)
            # Run install_packages.sh script
            echo "Running VM Initialization & Package Installer..."
            ./install_packages.sh
            ;;
        2)
            # Run Chrony Exporter setup script
            echo "Running Chrony Exporter Auto-Setup..."
            ./chrony_exporter/setup_chrony_exporter_on_vms.sh
            ;;
        3)
            # Run sync.sh script
            echo "Running sync.sh..."
            ./sync.sh
            ;;
        4)
            # Run edit_edn_base_on_ip.sh script
            echo "Running Set Environment Variable & Edit EDN Based on IP..."
            ./edit_edn_base_on_ip.sh
            ;;
        5)
            # Run action.sh script
            echo "Running action.sh..."
            ./action.sh
            ;;
        0)
            # Exit the script
            echo "Exiting Main Script. Goodbye!"
            break
            ;;
        *)
            # Handle invalid input
            echo "Invalid choice. Please enter a valid number (0, 1, 2, 3, 4, or 5)."
            ;;
    esac
done
