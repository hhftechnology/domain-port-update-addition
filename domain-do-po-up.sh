#!/bin/bash

# ========================================================================
# DOMAIN MANAGEMENT FUNCTIONS
# ========================================================================

# Function to validate domain name format
validate_domain_format() {
    local domain="$1"
    
    if ! [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}(\.[a-zA-Z]{2,})?$ ]]; then
        log_error "Invalid domain format. Please enter a valid domain like 'example.com'"
        return 1
    fi
    
    return 0
}

# Function to check DNS resolution
check_dns_resolution() {
    local domain="$1"
    local ip=""
    
    log_info "Checking if domain '$domain' is properly configured in DNS..."
    
    if command_exists dig; then
        ip=$(dig +short "$domain" A | head -1)
    elif command_exists nslookup; then
        ip=$(nslookup "$domain" | grep 'Address:' | tail -1 | awk '{print $2}')
    elif command_exists host; then
        log_warning "'dig' and 'nslookup' not found, using basic 'host' command which may be less reliable."
        ip=$(host "$domain" | grep 'has address' | head -1 | awk '{print $4}')
    else
        log_warning "No DNS resolution tools found (dig, nslookup, or host). Skipping DNS check."
        return 0
    fi
    
    if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_warning "Domain '$domain' does not resolve to an IP address."
        log_warning "The domain should have an A or AAAA record pointing to your server IP address."
        
        read -p "Do you want to proceed anyway? (y/n): " proceed
        if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
            log_error "Operation canceled. Please configure DNS properly and try again."
            return 1
        fi
    else
        log_success "Domain '$domain' resolves to IP: $ip"
    fi
    
    return 0
}

# Function to validate a domain (format and DNS)
validate_domain() {
    local domain="$1"
    
    if ! validate_domain_format "$domain"; then
        return 1
    fi
    
    if ! check_dns_resolution "$domain"; then
        return 1
    fi
    
    return 0
}

# Function to check if the domain already exists in the config
domain_exists() {
    local domain="$1"
    grep -q "base_domain: \"$domain\"" "$CONFIG_FILE"
}

# Function to get the next domain number
get_next_domain_number() {
    local highest_num=0
    
    while read -r line; do
        if [[ "$line" =~ domain([0-9]+): ]]; then
            num="${BASH_REMATCH[1]}"
            if ((num > highest_num)); then
                highest_num=$num
            fi
        fi
    done < <(grep "^    domain[0-9]\+:" "$CONFIG_FILE")
    
    echo $((highest_num + 1))
}

# Function to fix misplaced domains
fix_misplaced_domains() {
    log_info "Checking for misplaced domain entries..."
    
    local misplaced=$(grep -n "domain[0-9]\+:" "$CONFIG_FILE" | grep -v "^[0-9]\+:domains:" | grep -v "^[0-9]\+:    domain[0-9]\+:")
    
    if [ -n "$misplaced" ]; then
        log_warning "Found misplaced domain entries outside the domains section:"
        echo "$misplaced"
        
        read -p "Do you want to fix these misplaced domains? (y/n): " fix_domains
        if [[ "$fix_domains" =~ ^[Yy]$ ]]; then
            log_info "Creating a fixed config file..."
            
            local extracted_domains=$(awk '
            /^[[:space:]]+domain[0-9]+:/ && !/^[[:space:]]+domain[0-9]+:.*domains:/ {
                in_domain = 1
                domain_name = $0
                print domain_name
                next
            }
            in_domain == 1 && /^[[:space:]]+base_domain:/ {
                base_domain = $0
                print base_domain
                next
            }
            in_domain == 1 && /^[[:space:]]+cert_resolver:/ {
                cert_resolver = $0
                print cert_resolver
                in_domain = 0
                next
            }' "$CONFIG_FILE")
            
            if [ -n "$extracted_domains" ]; then
                log_info "Extracted domains:"
                echo "$extracted_domains"
                
                sed -i '/^[[:space:]]\+domain[0-9]\+:/,/^[[:space:]]\+cert_resolver:.*$/d' "$CONFIG_FILE"
                
                if grep -q "^domains:" "$CONFIG_FILE"; then
                    log_info "Adding extracted domains to the domains section..."
                    
                    local domains_end=$(awk '/^domains:/{in_domains=1} in_domains==1 && /^[a-zA-Z][^:]*:/ && !/^domains:/{print NR-1; exit}' "$CONFIG_FILE")
                    
                    if [ -z "$domains_end" ]; then
                        domains_end=$(wc -l < "$CONFIG_FILE")
                    fi
                    
                    sed -i "${domains_end}a\\$(echo "$extracted_domains" | sed 's/^/    /')" "$CONFIG_FILE"
                else
                    log_info "Creating domains section with extracted domains..."
                    
                    local app_end=$(awk '/^app:/{in_app=1} in_app==1 && /^[a-zA-Z][^:]*:/ && !/^app:/{print NR-1; exit}' "$CONFIG_FILE")
                    
                    if [ -z "$app_end" ]; then
                        app_end=1
                    fi
                    
                    sed -i "${app_end}a\\domains:\\$(echo "$extracted_domains" | sed 's/^/    /')" "$CONFIG_FILE"
                fi
                
                log_success "Fixed misplaced domains."
            fi
        fi
    else
        log_info "No misplaced domains found."
    fi
}

# Function to add domain to config
add_domain_to_config() {
    local domain="$1"
    local cert_resolver="$2"
    local next_domain_num
    
    fix_misplaced_domains
    
    if grep -q "^domains:" "$CONFIG_FILE"; then
        log_info "Domains section exists. Finding the last domain entry..."
        
        next_domain_num=$(get_next_domain_number)
        log_info "Using domain$next_domain_num for new entry"
        
        local domains_end=$(awk '/^domains:/{in_domains=1} in_domains==1 && /^[a-zA-Z][^:]*:/ && !/^domains:/{print NR-1; exit}' "$CONFIG_FILE")
        
        if [ -z "$domains_end" ]; then
            log_info "No next section found after domains, adding to end of file"
            domains_end=$(wc -l < "$CONFIG_FILE")
        fi
        
        sed -i "${domains_end}i\\    domain${next_domain_num}:\\n        base_domain: \"${domain}\"\\n        cert_resolver: \"${cert_resolver}\"" "$CONFIG_FILE"
    else
        log_info "Domains section does not exist. Creating it..."
        
        local app_end=$(awk '/^app:/{app=1} app==1 && /^[a-zA-Z][^:]*:/{if($0 !~ /^app:/) {print NR-1; exit}}' "$CONFIG_FILE")
        
        if [ -z "$app_end" ]; then
            log_info "Could not find end of app section, adding domains after first blank line"
            local blank_line=$(grep -n "^$" "$CONFIG_FILE" | head -1 | cut -d: -f1)
            if [ -z "$blank_line" ]; then
                log_info "No blank line found, adding domains at end of file"
                app_end=$(wc -l < "$CONFIG_FILE")
            else
                log_info "Found blank line at $blank_line, adding domains after it"
                app_end=$blank_line
            fi
        fi
        
        sed -i "${app_end}a\\\\ndomains:\\n    domain1:\\n        base_domain: \"${domain}\"\\n        cert_resolver: \"${cert_resolver}\"" "$CONFIG_FILE"
        
        next_domain_num=1
    fi
    
    log_info "Checking if domain was added:"
    grep -A2 -n "domain${next_domain_num}:" "$CONFIG_FILE"
    
    if grep -q "domain${next_domain_num}:" "$CONFIG_FILE" && \
       grep -q "base_domain: \"${domain}\"" "$CONFIG_FILE" && \
       grep -q "cert_resolver: \"${cert_resolver}\"" "$CONFIG_FILE"; then
        log_success "Added domain$next_domain_num: $domain with cert_resolver: $cert_resolver"
        return 0
    else
        log_error "Failed to add domain $domain. Please check the config file manually."
        return 1
    fi
}