#!/bin/bash

# ========================================================================
# PORT CONFIGURATION FUNCTIONS
# ========================================================================

# Function to validate port number
validate_port() {
    if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
        log_error "Invalid port number. Must be between 1 and 65535."
        return 1
    fi
    return 0
}

# Function to validate port type
validate_port_type() {
    if [[ "$1" != "tcp" && "$1" != "udp" ]]; then
        log_error "Invalid port type. Must be 'tcp' or 'udp'."
        return 1
    fi
    return 0
}

# Function to check if port is already configured
check_existing_port() {
    local port=$1
    local type=$2
    
    if grep -q "^ *- *$port:$port/$type" "$DOCKER_COMPOSE_PATH"; then
        log_error "Port $port/$type is already configured in docker-compose.yml"
        return 1
    fi
    
    if grep -q "\":$port/$type\"" "$TRAEFIK_CONFIG_PATH"; then
        log_error "Port $port/$type is already configured in traefik_config.yml"
        return 1
    fi
    
    return 0
}

# Function to add port to docker-compose.yml
add_to_docker_compose() {
    local port=$1
    local type=$2
    
    temp_file=$(mktemp)
    
    awk -v port="$port" -v type="$type" '
    BEGIN { 
        in_gerbil = 0
        ports_found = 0
        port_added = 0
    }
    
    /^[[:space:]]*gerbil:/ { 
        in_gerbil = 1 
    }
    
    /^[[:space:]]*ports:/ {
        if (in_gerbil && !ports_found) {
            ports_found = 1
            print $0
            printf "      - %d:%d/%s # Added by pangolin-config script\n", port, port, type
            port_added = 1
            next
        }
    }
    
    /^[^[:space:]].*:/ { 
        if ($0 !~ /^gerbil:/) {
            in_gerbil = 0
        }
    }
    
    { print }
    
    END {
        if (!port_added) {
            print "Debug: in_gerbil=" in_gerbil ", ports_found=" ports_found > "/dev/stderr"
            print "Failed to add port - please check the gerbil service configuration" > "/dev/stderr"
            exit 1
        }
    }
    ' "$DOCKER_COMPOSE_PATH" > "$temp_file"
    
    if grep -q "^ *- *$port:$port/$type" "$temp_file"; then
        mv "$temp_file" "$DOCKER_COMPOSE_PATH"
        log_success "Successfully added port $port/$type to gerbil service"
        return 0
    else
        log_error "Failed to add port to gerbil service"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to add entrypoint to traefik_config.yml
add_to_traefik() {
    local port=$1
    local type=$2
    
    temp_file=$(mktemp)
    
    awk -v port="$port" -v type="$type" '
    /entryPoints:/ {
        print $0
        in_entrypoints = 1
        next
    }
    
    in_entrypoints == 1 && /^[a-zA-Z]/ && !/^entryPoints:/ && !/^[[:space:]]/ {
        printf "  %s-%d:\n", type, port
        printf "    address: \":%d/%s\"\n\n", port, type
        in_entrypoints = 0
        port_added = 1
        print $0
        next
    }
    
    { print }
    
    END {
        if (in_entrypoints == 1) {
            printf "  %s-%d:\n", type, port
            printf "    address: \":%d/%s\"\n", port, type
        }
    }
    ' "$TRAEFIK_CONFIG_PATH" > "$temp_file"
    
    if grep -q "$type-$port:" "$temp_file" && grep -q ":$port/$type" "$temp_file"; then
        mv "$temp_file" "$TRAEFIK_CONFIG_PATH"
        log_success "Added $type-$port entrypoint to traefik_config.yml"
        return 0
    else
        log_error "Failed to add entrypoint to traefik_config.yml"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to configure firewall using UFW
configure_firewall() {
    local port=$1
    local type=$2
    
    if command_exists ufw; then
        log_info "Configuring UFW firewall..."
        if sudo ufw status | grep -q "Status: active"; then
            if sudo ufw allow "$port/$type"; then
                log_success "Firewall rule added for $port/$type"
                return 0
            else
                log_warning "Failed to add firewall rule. You may need to add it manually."
                return 1
            fi
        else
            log_warning "UFW is installed but not active. No firewall rule added."
            return 0
        fi
    else
        log_warning "UFW not found. Please manually configure your firewall to allow $port/$type"
        return 0
    fi
}

# Function to verify port configuration
verify_port_config() {
    local port=$1
    local type=$2
    local errors=0
    
    if ! grep -q "^ *- *$port:$port/$type" "$DOCKER_COMPOSE_PATH"; then
        log_error "Verification failed: Port $port/$type not found in docker-compose.yml"
        errors=$((errors + 1))
    fi
    
    if ! grep -q "$type-$port:" "$TRAEFIK_CONFIG_PATH" || \
       ! grep -q ":$port/$type" "$TRAEFIK_CONFIG_PATH"; then
        log_error "Verification failed: Entrypoint $type-$port not found in traefik_config.yml"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "Port configuration verified successfully"
        return 0
    else
        log_error "Verification found $errors error(s)"
        return 1
    fi
}