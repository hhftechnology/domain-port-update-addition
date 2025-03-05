#!/bin/bash

# ========================================================================
# CROWDSEC DIAGNOSTICS FUNCTIONS
# ========================================================================

# Function to check container health
check_container_health() {
    local container=$1
    if docker ps | grep -q "$container"; then
        echo -e "${GREEN}✓ $container container is running${NC}"
        return 0
    else
        echo -e "${RED}✗ $container container is NOT running${NC}"
        return 1
    fi
}

# Function to check all containers
check_stack_health() {
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}   CHECKING CONTAINER HEALTH${NC}"
    echo -e "${BLUE}======================================================================${NC}"
    echo ""
    
    check_container_health "crowdsec"
    local crowdsec_running=$?
    
    check_container_health "traefik"
    local traefik_running=$?
    
    check_container_health "pangolin"
    local pangolin_running=$?
    
    check_container_health "gerbil"
    local gerbil_running=$?
    
    echo ""
    
    if [ $crowdsec_running -eq 0 ] && [ $traefik_running -eq 0 ] && [ $pangolin_running -eq 0 ] && [ $gerbil_running -eq 0 ]; then
        echo -e "${GREEN}All required containers are running.${NC}"
    else
        echo -e "${RED}One or more required containers are not running. Check the Docker logs.${NC}"
    fi
    
    echo ""
}

# Function to check CrowdSec bouncers
check_crowdsec_bouncers() {
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}   CHECKING CROWDSEC BOUNCERS${NC}"
    echo -e "${BLUE}======================================================================${NC}"
    echo ""
    
    if ! check_container_health "crowdsec"; then
        echo -e "${RED}CrowdSec container is not running. Cannot check bouncers.${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Listing registered CrowdSec bouncers:${NC}"
    docker exec crowdsec cscli bouncers list
    
    echo -e "${YELLOW}Verifying Traefik bouncer connection:${NC}"
    if docker exec crowdsec cscli bouncers list | grep -q "traefik"; then
        echo -e "${GREEN}✓ Traefik bouncer is registered with CrowdSec${NC}"
    else
        echo -e "${RED}✗ Traefik bouncer is NOT registered with CrowdSec${NC}"
        echo -e "${YELLOW}Check that the API key in the middleware configuration matches a registered bouncer.${NC}"
    fi
    
    echo ""
}

# Function to check CrowdSec decisions
check_crowdsec_decisions() {
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}   CHECKING CROWDSEC DECISIONS${NC}"
    echo -e "${BLUE}======================================================================${NC}"
    echo ""
    
    if ! check_container_health "crowdsec"; then
        echo -e "${RED}CrowdSec container is not running. Cannot check decisions.${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Listing active CrowdSec decisions (blocks/captchas):${NC}"
    docker exec crowdsec cscli decisions list
    
    echo -e "${YELLOW}Note: If there are no decisions, it means no malicious activity has been detected yet.${NC}"
    echo -e "${YELLOW}This does not necessarily indicate a problem with CrowdSec.${NC}"
    
    echo ""
}

# Function to check Traefik CrowdSec integration
check_traefik_crowdsec() {
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}   CHECKING TRAEFIK CROWDSEC INTEGRATION${NC}"
    echo -e "${BLUE}======================================================================${NC}"
    echo ""
    
    if ! check_container_health "traefik"; then
        echo -e "${RED}Traefik container is not running. Cannot check integration.${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Verifying Traefik middleware configuration:${NC}"
    
    found_middleware=0
    
    if grep -q "crowdsec" ./config/traefik/traefik_config.yml 2>/dev/null; then
        echo -e "${GREEN}✓ CrowdSec referenced in Traefik main config${NC}"
        found_middleware=1
    fi
    
    if grep -q "crowdsec" ./config/traefik/dynamic_config.yml 2>/dev/null; then
        echo -e "${GREEN}✓ CrowdSec middleware found in dynamic config${NC}"
        found_middleware=1
    fi
    
    if grep -q "crowdsec@file" ./config/traefik/*.yml 2>/dev/null; then
        echo -e "${GREEN}✓ CrowdSec middleware (@file) found in configuration${NC}"
        found_middleware=1
    fi
    
    if [ $found_middleware -eq 0 ]; then
        echo -e "${RED}✗ CrowdSec middleware not found in Traefik configuration files${NC}"
    fi
    
    echo ""
}

# Function to check CrowdSec metrics
check_crowdsec_metrics() {
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}   CHECKING CROWDSEC METRICS${NC}"
    echo -e "${BLUE}======================================================================${NC}"
    echo ""
    
    if ! check_container_health "crowdsec"; then
        echo -e "${RED}CrowdSec container is not running. Cannot check metrics.${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}CrowdSec Prometheus metrics (showing first 10 lines):${NC}"
    curl -s http://localhost:6060/metrics | grep crowdsec | head -n 10
    
    echo -e "${YELLOW}Checking AppSec metrics specifically:${NC}"
    appsec_metrics=$(curl -s http://localhost:6060/metrics | grep appsec)
    if [ -z "$appsec_metrics" ]; then
        echo -e "${RED}No AppSec metrics found. LAPI AppSec may not be enabled or working.${NC}"
    else
        echo -e "${GREEN}AppSec metrics found:${NC}"
        echo "$appsec_metrics"
    fi
    
    echo -e "${YELLOW}CrowdSec internal metrics:${NC}"
    docker exec crowdsec cscli metrics
    
    echo ""
}

# Function to run complete diagnostic check
run_complete_check() {
    check_stack_health
    check_crowdsec_bouncers
    check_crowdsec_decisions
    check_crowdsec_metrics
    check_traefik_crowdsec
    
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}   DIAGNOSTIC SUMMARY${NC}"
    echo -e "${BLUE}======================================================================${NC}"
    echo ""
    
    echo -e "${YELLOW}Verifying key configuration settings:${NC}"
    
    lapi_key_found=0
    appsec_enabled=0
    middleware_configured=0
    
    for config_file in $(find ./config -type f -name "*.yml" -o -name "*.yaml" | xargs grep -l "crowdsec" 2>/dev/null); do
        if grep -q "crowdsecLapiKey\|lapiKey\|crowdsecLapi" "$config_file" 2>/dev/null; then
            echo -e "${GREEN}✓ CrowdSec LAPI key found in $config_file${NC}"
            lapi_key_found=1
        fi
        
        if grep -q "crowdsecAppsecEnabled: *true\|appsecEnabled: *true" "$config_file" 2>/dev/null; then
            echo -e "${GREEN}✓ CrowdSec AppSec is enabled in $config_file${NC}"
            appsec_enabled=1
        fi
        
        if grep -q "middleware.*crowdsec\|crowdsec.*middleware\|crowdsec@file\|crowdsec:" "$config_file" 2>/dev/null; then
            echo -e "${GREEN}✓ CrowdSec middleware configured in $config_file${NC}"
            middleware_configured=1
        fi
    done
    
    if [ $lapi_key_found -eq 0 ]; then
        echo -e "${RED}✗ No CrowdSec LAPI key found in configuration files${NC}"
    fi
    
    if [ $appsec_enabled -eq 0 ]; then
        echo -e "${RED}✗ CrowdSec AppSec not explicitly enabled in configuration files${NC}"
    fi
    
    if [ $middleware_configured -eq 0 ]; then
        echo -e "${RED}✗ CrowdSec middleware not properly configured in Traefik${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}=== FINAL VERDICT ===${NC}"
    
    if check_container_health "crowdsec" > /dev/null && \
       curl -s http://localhost:6060/metrics 2>/dev/null | grep -q "crowdsec" && \
       ([ $lapi_key_found -eq 1 ] || [ $middleware_configured -eq 1 ]);
    then
        echo -e "${GREEN}CrowdSec appears to be working correctly.${NC}"
    else
        echo -e "${RED}CrowdSec may not be functioning properly. Review the diagnostics above.${NC}"
    fi
    
    echo ""
}