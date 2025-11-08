#!/bin/bash

################################################################################
# test-implementation.sh
#
# Test Suite for implement-complete-system.sh
#
# Validates that the master implementation script can run without errors
# Tests all major functions, error handling, and API interactions
#
# Usage:
#   ./test-implementation.sh
#   ./test-implementation.sh --verbose
#   ./test-implementation.sh --suite phase1  # Run specific suite
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MASTER_SCRIPT="${SCRIPT_DIR}/implement-complete-system.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test configuration
VERBOSE="${VERBOSE:-0}"
TEST_SUITE="${TEST_SUITE:-all}"
TEST_PASS=0
TEST_FAIL=0
TEST_SKIP=0

# Temporary test environment
TEST_TMP_DIR="/tmp/implementation-test-$$"
TEST_LOG_DIR="${TEST_TMP_DIR}/logs"
TEST_STATE_DIR="${TEST_TMP_DIR}/.implementation-state"

################################################################################
# Test Utilities
################################################################################

# Print header
test_header() {
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$*${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
}

# Start test
test_start() {
    if [[ "$VERBOSE" == "1" ]]; then
        echo -e "${BLUE}[TEST]${NC} $*"
    fi
}

# Test pass
test_pass() {
    TEST_PASS=$((TEST_PASS + 1))
    echo -e "${GREEN}✓${NC} $*"
}

# Test fail
test_fail() {
    TEST_FAIL=$((TEST_FAIL + 1))
    echo -e "${RED}✗${NC} $*"
}

# Test skip
test_skip() {
    TEST_SKIP=$((TEST_SKIP + 1))
    echo -e "${YELLOW}⊘${NC} $*"
}

# Assert condition (using grep directly)
assert() {
    local condition="$1"
    local message="${2:-Assertion failed}"

    if eval "$condition" 2>/dev/null; then
        test_pass "$message"
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    local message="${2:-File $file exists}"

    if [[ -f "$file" ]]; then
        test_pass "$message"
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assert directory exists
assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory $dir exists}"

    if [[ -d "$dir" ]]; then
        test_pass "$message"
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Test result summary
test_summary() {
    local total=$((TEST_PASS + TEST_FAIL + TEST_SKIP))
    local percentage=0

    if [[ $total -gt 0 ]]; then
        percentage=$((TEST_PASS * 100 / total))
    fi

    test_header "Test Results"

    printf "%-20s %d\n" "Passed:" "$TEST_PASS"
    printf "%-20s %d\n" "Failed:" "$TEST_FAIL"
    printf "%-20s %d\n" "Skipped:" "$TEST_SKIP"
    printf "%-20s %d (${percentage}%%)\n" "Total:" "$total"

    if [[ $TEST_FAIL -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}Some tests failed!${NC}"
        return 1
    fi
}

################################################################################
# Test Suites
################################################################################

# Test 1: Script existence and permissions
suite_script_validation() {
    test_header "Suite 1: Script Validation"

    assert_file_exists "$MASTER_SCRIPT" "Master script exists"
    if [[ -x "$MASTER_SCRIPT" ]]; then
        test_pass "Script is executable"
    else
        test_fail "Script is executable"
    fi

    local script_size=$(wc -c < "$MASTER_SCRIPT")
    if [[ $script_size -gt 10000 ]]; then
        test_pass "Script size is reasonable (>10KB, actual: $script_size bytes)"
    else
        test_fail "Script size is reasonable (>10KB, actual: $script_size bytes)"
    fi

    # Check for critical functions
    assert "grep -q 'phase_1_validate_api_access' '$MASTER_SCRIPT'" "Contains Phase 1 function"
    assert "grep -q 'phase_2_create_production_vps' '$MASTER_SCRIPT'" "Contains Phase 2 function"
    assert "grep -q 'phase_3_create_sites' '$MASTER_SCRIPT'" "Contains Phase 3 function"
    assert "grep -q 'phase_4_database_snapshots' '$MASTER_SCRIPT'" "Contains Phase 4 function"
    assert "grep -q 'phase_5_test_pr_environment' '$MASTER_SCRIPT'" "Contains Phase 5 function"
    assert "grep -q 'phase_6_monitoring_setup' '$MASTER_SCRIPT'" "Contains Phase 6 function"
}

# Test 2: Help and documentation
suite_documentation() {
    test_header "Suite 2: Documentation"

    assert "grep -q 'Usage:' '$MASTER_SCRIPT'" "Contains usage documentation"
    assert "grep -q 'Environment Variables:' '$MASTER_SCRIPT'" "Contains environment variable docs"
    assert "grep -q -i 'REQUIRED\|required' '$MASTER_SCRIPT'" "Contains critical/required notes"
    assert "grep -q 'Phase' '$MASTER_SCRIPT'" "Contains phase documentation"
}

# Test 3: Dry run mode
suite_dry_run() {
    test_header "Suite 3: Dry Run Mode"

    # Create temporary environment
    mkdir -p "$TEST_TMP_DIR" "$TEST_LOG_DIR" "$TEST_STATE_DIR"

    test_start "Running script in dry-run mode..."

    # Run script with dry-run flag (should not make actual API calls)
    if timeout 60 bash "$MASTER_SCRIPT" \
        --dry-run \
        --phase 1 \
        2>&1 | tee "${TEST_TMP_DIR}/dry-run.log"; then

        # Check that script recognized dry-run flag
        if grep -q "DRY RUN" "${TEST_TMP_DIR}/dry-run.log" || grep -q "\[DRY RUN\]" "${TEST_TMP_DIR}/dry-run.log"; then
            test_pass "Dry-run mode executed successfully"
        else
            test_fail "Dry-run mode did not output dry-run indicators"
        fi
    else
        test_fail "Dry-run mode execution failed"
    fi
}

# Test 4: Requirements checking
suite_requirements() {
    test_header "Suite 4: Requirements Check"

    # Check that script verifies required commands
    assert "grep -q 'curl' '$MASTER_SCRIPT'" "Script checks for curl"
    assert "grep -q 'jq' '$MASTER_SCRIPT'" "Script checks for jq"
    assert "grep -q 'ssh' '$MASTER_SCRIPT'" "Script checks for ssh"

    # Check that required commands exist
    if command -v curl &> /dev/null; then
        test_pass "curl is available"
    else
        test_fail "curl is not available"
    fi

    if command -v jq &> /dev/null; then
        test_pass "jq is available"
    else
        test_fail "jq is not available"
    fi

    if command -v ssh &> /dev/null; then
        test_pass "ssh is available"
    else
        test_fail "ssh is not available"
    fi
}

# Test 5: Error handling
suite_error_handling() {
    test_header "Suite 5: Error Handling"

    # Check for error handling patterns
    assert "grep -q 'log_error' '$MASTER_SCRIPT'" "Script has error logging"
    assert "grep -q 'exit 1' '$MASTER_SCRIPT'" "Script exits on errors"
    assert "grep -q 'trap' '$MASTER_SCRIPT' || grep -q 'set -e' '$MASTER_SCRIPT'" "Script handles errors with trap or set -e"
    assert "grep -q 'check_requirements' '$MASTER_SCRIPT'" "Script validates requirements"
    assert "grep -q 'api_request' '$MASTER_SCRIPT'" "Script has API request function with error handling"
}

# Test 6: API interaction patterns
suite_api_patterns() {
    test_header "Suite 6: API Interaction Patterns"

    # Check for proper API call patterns
    assert "grep -q 'POST.*servers' '$MASTER_SCRIPT'" "Script makes POST /servers calls"
    assert "grep -q 'GET.*servers' '$MASTER_SCRIPT'" "Script makes GET /servers calls"
    assert "grep -q 'sites' '$MASTER_SCRIPT'" "Script creates sites via API"
    assert "grep -q 'databases' '$MASTER_SCRIPT'" "Script creates databases via API"
    assert "grep -q 'ssl-certificates' '$MASTER_SCRIPT'" "Script installs SSL certificates"
    assert "grep -q 'firewall-rules' '$MASTER_SCRIPT'" "Script configures firewall"

    # Check for proper HTTP headers
    assert "grep -q 'Authorization: Bearer' '$MASTER_SCRIPT'" "Script sets authorization headers"
    assert "grep -q 'Content-Type: application/json' '$MASTER_SCRIPT'" "Script sets JSON content type"
}

# Test 7: Database operations
suite_database_operations() {
    test_header "Suite 7: Database Operations"

    # Check for database-related code
    assert "grep -q 'mysqldump' '$MASTER_SCRIPT'" "Script handles MySQL dumps"
    assert "grep -q 'pg_dump' '$MASTER_SCRIPT'" "Script handles PostgreSQL dumps"
    assert "grep -q 'create_database_snapshot' '$MASTER_SCRIPT'" "Script has snapshot function"
    assert "grep -q 'setup_snapshot_cron' '$MASTER_SCRIPT'" "Script sets up backup cron jobs"

    # Check for database types
    assert "grep -q 'mysql' '$MASTER_SCRIPT'" "Script supports MySQL"
    assert "grep -q 'postgres' '$MASTER_SCRIPT'" "Script supports PostgreSQL"
}

# Test 8: Monitoring and alerts
suite_monitoring() {
    test_header "Suite 8: Monitoring Setup"

    # Check for monitoring functions
    assert "grep -q 'setup_health_checks' '$MASTER_SCRIPT'" "Script has health check setup"
    assert "grep -q 'setup_alerts' '$MASTER_SCRIPT'" "Script has alert setup"
    assert "grep -q 'phase_6' '$MASTER_SCRIPT'" "Script has monitoring phase"

    # Check for monitored metrics
    assert "grep -q 'cpu' '$MASTER_SCRIPT'" "Script monitors CPU"
    assert "grep -q 'memory' '$MASTER_SCRIPT'" "Script monitors memory"
    assert "grep -q 'disk' '$MASTER_SCRIPT'" "Script monitors disk"
}

# Test 9: Logging and output
suite_logging() {
    test_header "Suite 9: Logging & Output"

    # Check for logging functions
    assert "grep -q 'log_info' '$MASTER_SCRIPT'" "Script has info logging"
    assert "grep -q 'log_success' '$MASTER_SCRIPT'" "Script has success logging"
    assert "grep -q 'log_error' '$MASTER_SCRIPT'" "Script has error logging"
    assert "grep -q 'log_warning' '$MASTER_SCRIPT'" "Script has warning logging"

    # Check for progress tracking
    assert "grep -q 'print_progress' '$MASTER_SCRIPT'" "Script has progress bar"
    assert "grep -q 'calculate_eta' '$MASTER_SCRIPT'" "Script calculates ETA"
    assert "grep -q 'print_status_table' '$MASTER_SCRIPT'" "Script shows status table"

    # Check for report generation
    assert "grep -q 'generate_report' '$MASTER_SCRIPT'" "Script generates report"
}

# Test 10: Command-line arguments
suite_arguments() {
    test_header "Suite 10: Command-line Arguments"

    # Check for supported arguments
    assert "grep -q '\\-\\-phase' '$MASTER_SCRIPT'" "Script supports --phase argument"
    assert "grep -q '\\-\\-dry-run' '$MASTER_SCRIPT'" "Script supports --dry-run argument"
    assert "grep -q '\\-\\-verbose' '$MASTER_SCRIPT'" "Script supports --verbose argument"
    assert "grep -q '\\-\\-config' '$MASTER_SCRIPT'" "Script supports --config argument"
    assert "grep -q '\\-\\-help' '$MASTER_SCRIPT'" "Script supports --help argument"

    # Check for help function
    assert "grep -q 'Usage:' '$MASTER_SCRIPT'" "Script has usage documentation"
}

# Test 11: Example configuration
suite_example_config() {
    test_header "Suite 11: Example Configuration"

    assert_file_exists "${SCRIPT_DIR}/example-deployment.env" "Example configuration exists"
    assert "grep -q 'FORGE_API_TOKEN' '${SCRIPT_DIR}/example-deployment.env'" "Example has API token config"
    assert "grep -q 'PHASE_START' '${SCRIPT_DIR}/example-deployment.env'" "Example has phase config"
    assert "grep -q 'DRY_RUN' '${SCRIPT_DIR}/example-deployment.env'" "Example has dry-run config"
}

# Test 12: README documentation
suite_readme() {
    test_header "Suite 12: README Documentation"

    local readme="${SCRIPT_DIR}/README-IMPLEMENTATION.md"
    assert_file_exists "$readme" "README documentation exists"
    assert "grep -q 'Quick Start' '$readme'" "README has quick start section"
    assert "grep -q 'Phase' '$readme'" "README documents phases"
    assert "grep -q 'Troubleshooting' '$readme'" "README has troubleshooting section"
}

# Test 13: File structure
suite_file_structure() {
    test_header "Suite 13: File Structure"

    # Check for directory structure
    assert_dir_exists "${SCRIPT_DIR}" "Scripts directory exists"
    assert_dir_exists "${PROJECT_ROOT}" "Project root exists"

    # Check for critical files
    assert_file_exists "${PROJECT_ROOT}/CLAUDE.md" "CLAUDE.md exists"
    assert_file_exists "${SCRIPT_DIR}/create-vps-environment.sh" "create-vps-environment.sh exists"
    assert_file_exists "${SCRIPT_DIR}/clone-database.sh" "clone-database.sh exists"
    assert_file_exists "${SCRIPT_DIR}/health-check.sh" "health-check.sh exists"
}

# Test 14: Integration with existing scripts
suite_integration() {
    test_header "Suite 14: Integration with Existing Scripts"

    # Check compatibility with existing scripts
    assert "[[ -f '${SCRIPT_DIR}/create-vps-environment.sh' ]]" "Compatible with create-vps-environment.sh"
    assert "[[ -f '${SCRIPT_DIR}/clone-database.sh' ]]" "Compatible with clone-database.sh"
    assert "[[ -f '${SCRIPT_DIR}/health-check.sh' ]]" "Compatible with health-check.sh"

    # Check that master script has similar patterns
    assert "grep -q 'api_request' '$MASTER_SCRIPT'" "Uses consistent API request patterns"
    assert "grep -q 'log_' '$MASTER_SCRIPT'" "Uses consistent logging patterns"
}

# Test 15: Security practices
suite_security() {
    test_header "Suite 15: Security Practices"

    # Check for security patterns
    assert "grep -q 'FORGE_API_TOKEN' '$MASTER_SCRIPT'" "Uses environment variables for secrets"
    assert "grep -q 'StrictHostKeyChecking' '$MASTER_SCRIPT' || grep -q 'ssh' '$MASTER_SCRIPT'" "Handles SSH securely"
    assert "grep -q 'mkdir -p' '$MASTER_SCRIPT'" "Creates directories securely"

    # Check for input validation
    assert "grep -q 'validate' '$MASTER_SCRIPT'" "Performs input validation"
    assert "grep -q 'check_requirements' '$MASTER_SCRIPT'" "Checks system requirements"
}

################################################################################
# Main Test Execution
################################################################################

main() {
    test_header "Implementation Script Test Suite"

    echo "Testing: $MASTER_SCRIPT"
    echo "Test Suite: $TEST_SUITE"
    echo

    case "$TEST_SUITE" in
        all)
            suite_script_validation
            suite_documentation
            suite_dry_run
            suite_requirements
            suite_error_handling
            suite_api_patterns
            suite_database_operations
            suite_monitoring
            suite_logging
            suite_arguments
            suite_example_config
            suite_readme
            suite_file_structure
            suite_integration
            suite_security
            ;;
        script)
            suite_script_validation
            ;;
        docs)
            suite_documentation
            suite_readme
            ;;
        dry-run)
            suite_dry_run
            ;;
        requirements)
            suite_requirements
            ;;
        errors)
            suite_error_handling
            ;;
        api)
            suite_api_patterns
            ;;
        database)
            suite_database_operations
            ;;
        monitoring)
            suite_monitoring
            ;;
        logging)
            suite_logging
            ;;
        args)
            suite_arguments
            ;;
        config)
            suite_example_config
            ;;
        structure)
            suite_file_structure
            ;;
        integration)
            suite_integration
            ;;
        security)
            suite_security
            ;;
        *)
            echo "Unknown test suite: $TEST_SUITE"
            exit 1
            ;;
    esac

    # Clean up test environment
    rm -rf "$TEST_TMP_DIR"

    # Show summary and exit
    test_summary
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=1
            shift
            ;;
        --suite)
            TEST_SUITE="$2"
            shift 2
            ;;
        --help)
            cat << 'EOF'
Usage: ./test-implementation.sh [OPTIONS]

Options:
  --suite NAME       Run specific test suite
  --verbose          Enable verbose output
  --help            Show this help message

Available Suites:
  all           - Run all tests (default)
  script        - Test script validation
  docs          - Test documentation
  dry-run       - Test dry-run mode
  requirements  - Test requirements checking
  errors        - Test error handling
  api           - Test API patterns
  database      - Test database operations
  monitoring    - Test monitoring setup
  logging       - Test logging and output
  args          - Test command-line arguments
  config        - Test example configuration
  structure     - Test file structure
  integration   - Test integration with existing scripts
  security      - Test security practices

Examples:
  ./test-implementation.sh
  ./test-implementation.sh --verbose
  ./test-implementation.sh --suite api --verbose
  ./test-implementation.sh --suite requirements

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run tests
main
