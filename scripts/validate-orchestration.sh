#!/bin/bash

################################################################################
# validate-orchestration.sh
#
# Validates the PR orchestration system setup and API connectivity
#
# Checks:
#   - Required tools installed (curl, jq, openssl)
#   - Forge API token is valid and working
#   - Cloud provider connectivity
#   - Script files are executable
#   - Directory structure is correct
#   - Logging directories exist
#
# Usage:
#   ./scripts/validate-orchestration.sh
#   ./scripts/validate-orchestration.sh --verbose
#   ./scripts/validate-orchestration.sh --api-only
#
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
FORGE_API_URL="${FORGE_API_URL:-https://forge.laravel.com/api/v1}"
FORGE_API_TOKEN="${FORGE_API_TOKEN:-}"
VERBOSE="${VERBOSE:-false}"
API_ONLY="${API_ONLY:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
CHECKS_TOTAL=0
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

################################################################################
# Utility Functions
################################################################################

log_pass() {
    echo -e "${GREEN}✓${NC} $*"
    ((CHECKS_PASSED++))
    ((CHECKS_TOTAL++))
}

log_fail() {
    echo -e "${RED}✗${NC} $*"
    ((CHECKS_FAILED++))
    ((CHECKS_TOTAL++))
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
    ((CHECKS_WARNING++))
    ((CHECKS_TOTAL++))
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "  DEBUG: $*"
    fi
}

section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$*${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

################################################################################
# Validation Functions
################################################################################

check_tools() {
    section "1. Checking Required Tools"

    # Check curl
    if command -v curl &> /dev/null; then
        local curl_version=$(curl --version | head -1)
        log_pass "curl is installed: $curl_version"
    else
        log_fail "curl is not installed"
        log_info "Install: sudo apt-get install curl"
    fi

    # Check jq
    if command -v jq &> /dev/null; then
        local jq_version=$(jq --version)
        log_pass "jq is installed: $jq_version"
    else
        log_fail "jq is not installed"
        log_info "Install: sudo apt-get install jq"
    fi

    # Check openssl
    if command -v openssl &> /dev/null; then
        local openssl_version=$(openssl version)
        log_pass "openssl is installed: $openssl_version"
    else
        log_fail "openssl is not installed"
        log_info "Install: sudo apt-get install openssl"
    fi

    # Check bash
    local bash_version=$(bash --version | head -1)
    log_pass "bash is available: $bash_version"
}

check_environment_variables() {
    section "2. Checking Environment Variables"

    if [[ -z "$FORGE_API_TOKEN" ]]; then
        log_fail "FORGE_API_TOKEN is not set"
        log_info "Set with: export FORGE_API_TOKEN=\"your-token-here\""
    else
        log_pass "FORGE_API_TOKEN is set"
        log_debug "Token length: ${#FORGE_API_TOKEN} characters"
    fi

    if [[ -z "$FORGE_API_URL" ]]; then
        log_warn "FORGE_API_URL is not set, using default: $FORGE_API_URL"
    else
        log_pass "FORGE_API_URL is set: $FORGE_API_URL"
    fi

    # Check optional variables
    if [[ -n "${PROVIDER:-}" ]]; then
        log_pass "PROVIDER is set: $PROVIDER"
    else
        log_warn "PROVIDER not set, will use default: digitalocean"
    fi

    if [[ -n "${REGION:-}" ]]; then
        log_pass "REGION is set: $REGION"
    else
        log_warn "REGION not set, will use default: nyc3"
    fi
}

check_script_files() {
    section "3. Checking Script Files"

    # Check main orchestration script
    if [[ -f "$SCRIPT_DIR/orchestrate-pr-system.sh" ]]; then
        if [[ -x "$SCRIPT_DIR/orchestrate-pr-system.sh" ]]; then
            log_pass "orchestrate-pr-system.sh exists and is executable"
        else
            log_fail "orchestrate-pr-system.sh exists but is not executable"
            log_debug "Run: chmod +x $SCRIPT_DIR/orchestrate-pr-system.sh"
        fi
    else
        log_fail "orchestrate-pr-system.sh not found"
        log_info "Expected at: $SCRIPT_DIR/orchestrate-pr-system.sh"
    fi

    # Check health check script
    if [[ -f "$SCRIPT_DIR/health-check.sh" ]]; then
        log_pass "health-check.sh exists"
    else
        log_warn "health-check.sh not found (optional)"
    fi

    # Check VPS creation script
    if [[ -f "$SCRIPT_DIR/create-vps-environment.sh" ]]; then
        log_pass "create-vps-environment.sh exists"
    else
        log_warn "create-vps-environment.sh not found (optional)"
    fi
}

check_directory_structure() {
    section "4. Checking Directory Structure"

    # Check scripts directory
    if [[ -d "$SCRIPT_DIR" ]]; then
        log_pass "scripts/ directory exists"
    else
        log_fail "scripts/ directory not found"
    fi

    # Check logs directory (or if it can be created)
    if [[ -d "$PROJECT_ROOT/logs" ]]; then
        log_pass "logs/ directory exists"
    else
        if mkdir -p "$PROJECT_ROOT/logs" 2>/dev/null; then
            log_pass "logs/ directory can be created"
        else
            log_fail "logs/ directory does not exist and cannot be created"
        fi
    fi

    # Check docs directory
    if [[ -d "$PROJECT_ROOT/docs" ]]; then
        log_pass "docs/ directory exists"
    else
        log_warn "docs/ directory not found"
    fi

    # Check examples directory
    if [[ -d "$PROJECT_ROOT/examples" ]]; then
        log_pass "examples/ directory exists"
    else
        log_warn "examples/ directory not found"
    fi
}

check_api_connectivity() {
    section "5. Checking Forge API Connectivity"

    if [[ -z "$FORGE_API_TOKEN" ]]; then
        log_fail "Cannot check API: FORGE_API_TOKEN is not set"
        return 1
    fi

    log_info "Testing API connection to: $FORGE_API_URL"

    local response_file=$(mktemp)
    local http_code

    http_code=$(curl -s -w "%{http_code}" \
        -X GET \
        -H "Authorization: Bearer $FORGE_API_TOKEN" \
        -H "Accept: application/json" \
        -o "$response_file" \
        "$FORGE_API_URL/servers" 2>/dev/null || echo "000")

    local response=$(cat "$response_file" 2>/dev/null || echo "")
    rm -f "$response_file"

    if [[ "$http_code" == "200" ]]; then
        log_pass "API connectivity: OK (HTTP $http_code)"

        # Parse server list
        if echo "$response" | jq . &>/dev/null; then
            local server_count=$(echo "$response" | jq '.servers | length')
            log_pass "Successfully retrieved server list: $server_count server(s)"

            # List servers
            if [[ "$VERBOSE" == "true" ]]; then
                echo ""
                echo "Servers:"
                echo "$response" | jq '.servers[] | "\(.name) (\(.id)) - \(.status)"' | sed 's/"//g' | sed 's/^/  /'
            fi
        else
            log_fail "API response is not valid JSON"
        fi
    elif [[ "$http_code" == "401" ]]; then
        log_fail "API authentication failed: HTTP $http_code (Unauthorized)"
        log_info "Check FORGE_API_TOKEN is correct"
    elif [[ "$http_code" == "403" ]]; then
        log_fail "API permission denied: HTTP $http_code (Forbidden)"
        log_info "Check FORGE_API_TOKEN has required permissions"
    elif [[ "$http_code" == "000" ]]; then
        log_fail "Could not connect to API"
        log_info "Check FORGE_API_URL and internet connectivity"
    else
        log_fail "API request failed: HTTP $http_code"
        log_debug "Response: $response"
    fi
}

check_cloud_provider_access() {
    section "6. Checking Cloud Provider Access"

    if [[ -z "$FORGE_API_TOKEN" ]]; then
        log_warn "Cannot check cloud provider: FORGE_API_TOKEN is not set"
        return 0
    fi

    log_info "Checking available cloud providers..."

    local response_file=$(mktemp)

    curl -s -X GET \
        -H "Authorization: Bearer $FORGE_API_TOKEN" \
        -H "Accept: application/json" \
        -o "$response_file" \
        "$FORGE_API_URL/servers" 2>/dev/null || true

    local response=$(cat "$response_file" 2>/dev/null || echo "")
    rm -f "$response_file"

    if echo "$response" | jq . &>/dev/null; then
        # Check if any servers exist and get their providers
        if echo "$response" | jq -e '.servers[0]' &>/dev/null; then
            local providers=$(echo "$response" | jq -r '.servers[].provider' | sort -u)
            log_pass "Found servers on providers: $(echo "$providers" | tr '\n' ', ')"
        else
            log_warn "No servers exist to check provider access"
            log_info "This is OK - you can create servers"
        fi
    fi
}

check_documentation() {
    section "7. Checking Documentation"

    # Check main documentation
    if [[ -f "$PROJECT_ROOT/docs/ORCHESTRATION_GUIDE.md" ]]; then
        log_pass "ORCHESTRATION_GUIDE.md exists"
    else
        log_warn "ORCHESTRATION_GUIDE.md not found"
    fi

    # Check quick reference
    if [[ -f "$PROJECT_ROOT/docs/ORCHESTRATION_QUICK_REFERENCE.md" ]]; then
        log_pass "ORCHESTRATION_QUICK_REFERENCE.md exists"
    else
        log_warn "ORCHESTRATION_QUICK_REFERENCE.md not found"
    fi

    # Check examples
    if [[ -f "$PROJECT_ROOT/examples/orchestration-example.sh" ]]; then
        log_pass "orchestration-example.sh exists"
    else
        log_warn "orchestration-example.sh not found"
    fi
}

check_permissions() {
    section "8. Checking File Permissions"

    # Check if user can write to logs directory
    if [[ -w "$PROJECT_ROOT/logs" ]]; then
        log_pass "Can write to logs/ directory"
    elif mkdir -p "$PROJECT_ROOT/logs" 2>/dev/null && [[ -w "$PROJECT_ROOT/logs" ]]; then
        log_pass "Can create and write to logs/ directory"
    else
        log_fail "Cannot write to logs/ directory"
        log_info "Run: sudo chmod 755 $PROJECT_ROOT/logs"
    fi

    # Check if scripts are readable
    if [[ -r "$SCRIPT_DIR/orchestrate-pr-system.sh" ]]; then
        log_pass "orchestrate-pr-system.sh is readable"
    else
        log_fail "orchestrate-pr-system.sh is not readable"
    fi
}

test_api_calls() {
    section "9. Testing Specific API Calls"

    if [[ -z "$FORGE_API_TOKEN" ]]; then
        log_warn "Skipping API tests: FORGE_API_TOKEN not set"
        return 0
    fi

    # Test GET /servers endpoint
    log_info "Testing GET /servers..."
    local response_file=$(mktemp)
    local http_code=$(curl -s -w "%{http_code}" \
        -X GET \
        -H "Authorization: Bearer $FORGE_API_TOKEN" \
        -H "Accept: application/json" \
        -o "$response_file" \
        "$FORGE_API_URL/servers" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
        log_pass "GET /servers: OK"
    else
        log_fail "GET /servers: HTTP $http_code"
    fi

    rm -f "$response_file"

    # Test if API token has required scopes
    log_info "Testing API token scopes..."

    local servers_response=$(curl -s \
        -X GET \
        -H "Authorization: Bearer $FORGE_API_TOKEN" \
        -H "Accept: application/json" \
        "$FORGE_API_URL/servers" 2>/dev/null || echo "{}")

    if echo "$servers_response" | jq -e '.servers' &>/dev/null; then
        log_pass "API token has read access to servers"
    else
        log_warn "Cannot verify API token scope"
    fi
}

print_summary() {
    section "Summary"

    local total=$CHECKS_TOTAL
    local passed=$CHECKS_PASSED
    local failed=$CHECKS_FAILED
    local warning=$CHECKS_WARNING

    echo ""
    echo "Total checks:   $total"
    echo -e "${GREEN}Passed:         $passed${NC}"

    if [[ $warning -gt 0 ]]; then
        echo -e "${YELLOW}Warnings:       $warning${NC}"
    fi

    if [[ $failed -gt 0 ]]; then
        echo -e "${RED}Failed:         $failed${NC}"
    fi

    echo ""

    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}Orchestration system is ready!${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Review ORCHESTRATION_QUICK_REFERENCE.md"
        echo "  2. Run: ./scripts/orchestrate-pr-system.sh --help"
        echo "  3. Create your first PR environment"
        return 0
    else
        echo -e "${RED}Please fix the failed checks above${NC}"
        return 1
    fi
}

show_usage() {
    cat << 'EOF'
Usage: ./scripts/validate-orchestration.sh [OPTIONS]

Options:
  --verbose       Show detailed output
  --api-only      Only check API connectivity
  --help          Show this help message

Examples:
  ./scripts/validate-orchestration.sh
  ./scripts/validate-orchestration.sh --verbose
  ./scripts/validate-orchestration.sh --api-only

This script validates:
  - Required tools (curl, jq, openssl)
  - Environment variables (FORGE_API_TOKEN)
  - Script files and executability
  - Directory structure
  - Forge API connectivity
  - File permissions
  - Documentation

EOF
}

################################################################################
# Main Execution
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --api-only)
                API_ONLY=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    echo ""
    echo -e "${BLUE}Orchestration System Validation${NC}"
    echo -e "${BLUE}================================${NC}"

    if [[ "$API_ONLY" == "true" ]]; then
        # Only check API
        check_tools
        check_environment_variables
        check_api_connectivity
    else
        # Full validation
        check_tools
        check_environment_variables
        check_script_files
        check_directory_structure
        check_api_connectivity
        check_cloud_provider_access
        check_documentation
        check_permissions
        test_api_calls
    fi

    # Print summary
    print_summary
}

main "$@"
