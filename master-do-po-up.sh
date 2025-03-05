#!/bin/bash

# Source all component scripts
source ./utils-do-po-up.sh
source ./domain-do-po-up.sh
source ./port-do-po-up.sh
source ./crowdsec-do-po-up.sh
source ./menu-do-po-up.sh

# Check for required commands
if ! command_exists docker; then
    log_error "Docker is not installed or not in PATH. This script requires Docker."
    exit 1
fi

# Main program loop
while true; do
    # Disable strict error handling for menu navigation
    set +e
    
    display_main_menu
    read choice
    
    case $choice in
        1)
            domain_menu
            ;;
        2)
            port_menu
            ;;
        3)
            clear
            echo -e "${CYAN}======================================================================${NC}"
            echo -e "${CYAN}                  RESTARTING PANGOLIN STACK                          ${NC}"
            echo -e "${CYAN}======================================================================${NC}"
            echo ""
            
            # Enable strict error handling for restart operation
            set -e
            restart_stack
            set +e  # Disable again for menu flow
            
            pause
            ;;
        4)
            crowdsec_diagnostics_menu
            ;;
        0)
            echo -e "${GREEN}Exiting. Goodbye!${NC}"
            exit 0
            ;;
        *)
            log_error "Invalid option. Please try again."
            pause
            ;;
    esac
done