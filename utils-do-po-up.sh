#!/bin/bash

# ========================================================================
# CONSTANTS AND GLOBAL VARIABLES
# ========================================================================

# File paths
readonly CONFIG_FILE="./config/config.yml"
readonly CONFIG_BACKUP="./config/config.yml.bak"
readonly DOCKER_COMPOSE_PATH="./docker-compose.yml"
readonly DOCKER_COMPOSE_BACKUP="./docker-compose.yml.bak"
readonly TRAEFIK_CONFIG_PATH="./config/traefik/traefik_config.yml"
readonly TRAEFIK_CONFIG_BACKUP="./config/traefik/traefik_config.yml.bak"
readonly DEFAULT_CERT_RESOLVER="letsencrypt"

# Terminal colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Global variables for user inputs
DOMAIN_NAME=""
PORT=""
TYPE=""
CERT_RESOLVER="$DEFAULT_CERT_RESOLVER"
SKIP_RESTART=false

# ========================================================================
# COMMON UTILITY FUNCTIONS
# ========================================================================

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to create backups of configuration files
create_backup() {
    local file="$1"
    local backup="$2"
    
    if [ -f "$file" ]; then
        cp "$file" "$backup"
        log_success "Created backup at $backup"
    else
        log_error "File not found: $file"
        return 1
    fi
}

# Function to check if the Pangolin stack is running
is_stack_running() {
    docker compose ps | grep -q 'pangolin'
}

# Function to wait for stack to be ready
wait_for_stack() {
    local timeout=30
    local counter=0
    
    log_info "Waiting for stack to be ready..."
    
    while ((counter < timeout)); do
        if docker compose ps | grep -q 'pangolin' && docker compose ps | grep -q -v 'starting'; then
            log_success "Pangolin stack is ready!"
            return 0
        fi
        echo -n "."
        sleep 2
        ((counter+=1))
    done
    
    log_error "Timeout waiting for stack to be ready. Please check your logs."
    return 1
}

# Function to restart the Pangolin stack
restart_stack() {
    log_info "Restarting Pangolin stack..."
    
    if is_stack_running; then
        docker compose down
        sleep 2
        docker compose up -d
        wait_for_stack
    else
        log_info "Pangolin stack wasn't running. Starting it now..."
        docker compose up -d
        wait_for_stack
    fi
}

# Function to prompt for restart confirmation
prompt_for_restart() {
    if [ "$SKIP_RESTART" = false ]; then
        echo ""
        read -p "Do you want to restart the Pangolin stack now? (y/n): " restart_confirm
        
        if [[ "$restart_confirm" =~ ^[Yy]$ ]]; then
            restart_stack
        else
            log_warning "Stack not restarted. Remember to restart manually for changes to take effect:"
            log_info "docker compose down && docker compose up -d"
        fi
    else
        log_warning "Stack not restarted (--skip-restart was specified)."
        log_warning "Remember to restart manually for changes to take effect:"
        log_info "docker compose down && docker compose up -d"
    fi
}

# Function for pausing before continuing
pause() {
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo ""
}