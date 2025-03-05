#!/bin/bash

# ========================================================================
# MENU FUNCTIONS
# ========================================================================

# Function to display the main menu
display_main_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${CYAN}          PANGOLIN DOMAIN and PORT CONFIGURATION MANAGER              ${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo ""
    echo -e "${CYAN}1.${NC} Add Domain"
    echo -e "${CYAN}2.${NC} Configure Port"
    echo -e "${CYAN}3.${NC} Restart Pangolin Stack"
    echo -e "${CYAN}4.${NC} CrowdSec Diagnostics"
    echo -e "${CYAN}0.${NC} Exit"
    echo ""
    echo -ne "${YELLOW}Enter your choice [0-4]:${NC} "
}

# Function to process the domain menu
domain_menu() {
    local return_val=0
    
    set +e
    
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${CYAN}                     DOMAIN MANAGEMENT                               ${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo ""
    
    echo -ne "${YELLOW}Enter domain name (e.g., example.com):${NC} "
    read DOMAIN_NAME
    
    if [ -z "$DOMAIN_NAME" ]; then
        log_error "Domain name cannot be empty."
        pause
        return_val=1
        return $return_val
    fi
    
    if ! validate_domain "$DOMAIN_NAME"; then
        pause
        return_val=1
        return $return_val
    fi
    
    if domain_exists "$DOMAIN_NAME"; then
        log_error "Domain '$DOMAIN_NAME' already exists in the config."
        pause
        return_val=1
        return $return_val
    fi
    
    echo ""
    echo -e "${YELLOW}Certificate resolver (default: letsencrypt):${NC}"
    echo -e "Press Enter to use default, or type a custom resolver name."
    read -p "> " custom_resolver
    
    if [ -n "$custom_resolver" ]; then
        CERT_RESOLVER="$custom_resolver"
    else
        CERT_RESOLVER="$DEFAULT_CERT_RESOLVER"
    fi
    
    echo ""
    echo -e "${YELLOW}Skip automatic restart prompt?${NC}"
    read -p "Skip restart? (y/n): " skip_restart
    if [[ "$skip_restart" =~ ^[Yy]$ ]]; then
        SKIP_RESTART=true
    else
        SKIP_RESTART=false
    fi
    
    echo ""
    echo -e "${YELLOW}Ready to add domain with these settings:${NC}"
    echo "  Domain name: $DOMAIN_NAME"
    echo "  Certificate resolver: $CERT_RESOLVER"
    echo "  Skip restart: $SKIP_RESTART"
    echo ""
    read -p "Proceed? (y/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Operation canceled."
        pause
        return_val=1
        return $return_val
    fi
    
    set -e
    
    if ! create_backup "$CONFIG_FILE" "$CONFIG_BACKUP"; then
        set +e
        pause
        return_val=1
        return $return_val
    fi
    
    if ! add_domain_to_config "$DOMAIN_NAME" "$CERT_RESOLVER"; then
        log_error "Failed to add domain to config. Reverting changes..."
        cp "$CONFIG_BACKUP" "$CONFIG_FILE"
        set +e
        pause
        return_val=1
        return $return_val
    fi
    
    set +e
    prompt_for_restart
    
    log_success "Domain $DOMAIN_NAME has been successfully added to the configuration."
    pause
    return_val=0
    return $return_val
}

# Function to process the port menu
port_menu() {
    local return_val=0
    
    set +e
    
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${CYAN}                     PORT CONFIGURATION                              ${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo ""
    
    echo -ne "${YELLOW}Enter port number (1-65535):${NC} "
    read PORT
    
    if ! validate_port "$PORT"; then
        pause
        return_val=1
        return $return_val
    fi
    
    echo ""
    echo -e "${YELLOW}Enter port type:${NC}"
    echo "1. TCP"
    echo "2. UDP"
    echo -ne "Select type [1-2]: "
    read port_type_choice
    
    case $port_type_choice in
        1) TYPE="tcp" ;;
        2) TYPE="udp" ;;
        *) log_error "Invalid selection. Please enter 1 for TCP or 2 for UDP."
           pause
           return_val=1
           return $return_val ;;
    esac
    
    if ! check_existing_port "$PORT" "$TYPE"; then
        pause
        return_val=1
        return $return_val
    fi
    
    echo ""
    echo -e "${YELLOW}Skip automatic restart prompt?${NC}"
    read -p "Skip restart? (y/n): " skip_restart
    if [[ "$skip_restart" =~ ^[Yy]$ ]]; then
        SKIP_RESTART=true
    else
        SKIP_RESTART=false
    fi
    
    echo ""
    echo -e "${YELLOW}Ready to configure port with these settings:${NC}"
    echo "  Port: $PORT"
    echo "  Type: $TYPE"
    echo "  Skip restart: $SKIP_RESTART"
    echo ""
    read -p "Proceed? (y/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Operation canceled."
        pause
        return_val=1
        return $return_val
    fi
    
    set -e
    
    create_backup "$DOCKER_COMPOSE_PATH" "$DOCKER_COMPOSE_BACKUP"
    create_backup "$TRAEFIK_CONFIG_PATH" "$TRAEFIK_CONFIG_BACKUP"
    
    log_info "Starting port configuration for $PORT/$TYPE..."
    
    if ! configure_firewall "$PORT" "$TYPE"; then
        log_warning "Firewall configuration failed but continuing..."
    fi
    
    if ! add_to_docker_compose "$PORT" "$TYPE"; then
        log_error "Failed to update docker-compose.yml. Restoring backups..."
        cp "$DOCKER_COMPOSE_BACKUP" "$DOCKER_COMPOSE_PATH"
        cp "$TRAEFIK_CONFIG_BACKUP" "$TRAEFIK_CONFIG_PATH"
        set +e
        pause
        return_val=1
        return $return_val
    fi
    
    if ! add_to_traefik "$PORT" "$TYPE"; then
        log_error "Failed to update traefik_config.yml. Restoring backups..."
        cp "$DOCKER_COMPOSE_BACKUP" "$DOCKER_COMPOSE_PATH"
        cp "$TRAEFIK_CONFIG_BACKUP" "$TRAEFIK_CONFIG_PATH"
        set +e
        pause
        return_val=1
        return $return_val
    fi
    
    set +e
    if ! verify_port_config "$PORT" "$TYPE"; then
        log_error "Verification failed. Configuration may be incomplete."
        read -p "Do you want to continue anyway? (y/n): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            log_error "Restoring backups..."
            cp "$DOCKER_COMPOSE_BACKUP" "$DOCKER_COMPOSE_PATH"
            cp "$TRAEFIK_CONFIG_BACKUP" "$TRAEFIK_CONFIG_PATH"
            pause
            return_val=1
            return $return_val
        fi
    fi
    
    prompt_for_restart
    
    log_success "Port $PORT/$TYPE has been configured successfully!"
    pause
    return_val=0
    return $return_val
}

# Function to display CrowdSec diagnostics menu
crowdsec_diagnostics_menu() {
    set +e
    
    local exit_menu=0
    
    while [ $exit_menu -eq 0 ]; do
        clear
        echo -e "${CYAN}======================================================================${NC}"
        echo -e "${CYAN}                   CROWDSEC DIAGNOSTICS                              ${NC}"
        echo -e "${CYAN}======================================================================${NC}"
        echo ""
        echo -e "${CYAN}1.${NC} Check Container Health"
        echo -e "${CYAN}2.${NC} Check CrowdSec Bouncers"
        echo -e "${CYAN}3.${NC} Check CrowdSec Decisions"
        echo -e "${CYAN}4.${NC} Check CrowdSec Metrics"
        echo -e "${CYAN}5.${NC} Check Traefik CrowdSec Integration"
        echo -e "${CYAN}6.${NC} Run Complete Diagnostic Check"
        echo -e "${CYAN}7.${NC} View CrowdSec Logs"
        echo -e "${CYAN}0.${NC} Back to Main Menu"
        echo ""
        echo -ne "${YELLOW}Enter your choice [0-7]:${NC} "
        read choice
        
        case $choice in
            1)
                clear
                check_stack_health
                pause
                ;;
            2)
                clear
                check_crowdsec_bouncers
                pause
                ;;
            3)
                clear
                check_crowdsec_decisions
                pause
                ;;
            4)
                clear
                check_crowdsec_metrics
                pause
                ;;
            5)
                clear
                check_traefik_crowdsec
                pause
                ;;
            6)
                clear
                run_complete_check
                pause
                ;;
            7)
                clear
                echo -e "${CYAN}======================================================================${NC}"
                echo -e "${CYAN}                  VIEWING CROWDSEC LOGS                             ${NC}"
                echo -e "${CYAN}======================================================================${NC}"
                echo ""
                log_info "Showing last 50 lines of CrowdSec logs..."
                docker compose logs crowdsec --tail=50
                
                echo ""
                read -p "Do you want to follow logs in real-time? (y/n): " follow_logs
                if [[ "$follow_logs" =~ ^[Yy]$ ]]; then
                    echo -e "${YELLOW}Press Ctrl+C to exit log view${NC}"
                    sleep 1
                    docker compose logs crowdsec -f
                fi
                pause
                ;;
            0)
                exit_menu=1
                ;;
            *)
                log_error "Invalid option. Please try again."
                pause
                ;;
        esac
    done
    
    return 0
}