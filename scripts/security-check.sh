#!/bin/bash

################################################################################
# security-check.sh
#
# Security validation script for orchestrate-pr-system.sh
#
# Checks for critical security vulnerabilities and validates that all
# security hardening measures are properly implemented.
#
# Usage:
#   ./security-check.sh
#
# Exit codes:
#   0 - All security checks passed
#   >0 - Number of security issues found
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/orchestrate-pr-system.sh"
ISSUES=0

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Security Audit for orchestrate-pr-system.sh${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Verify target script exists
if [[ ! -f "$TARGET_SCRIPT" ]]; then
    echo -e "${RED}[FAIL]${NC} Target script not found: $TARGET_SCRIPT"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Analyzing: $TARGET_SCRIPT"
echo ""

################################################################################
# Security Checks
################################################################################

# Check 1: State file permissions
echo -n "Checking state file permissions... "
if grep -q 'chmod 600.*STATE_FILE' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${RED}[FAIL]${NC}"
    echo "  Issue: State file permissions not secured with chmod 600"
    echo "  Impact: Sensitive credentials may be world-readable"
    echo "  Fix: Add 'chmod 600 \"\$STATE_FILE\"' after writing state"
    ((ISSUES++))
fi

# Check 2: OpenSSL requirement
echo -n "Checking OpenSSL requirement validation... "
if grep -q 'command -v openssl.*&> /dev/null' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${RED}[FAIL]${NC}"
    echo "  Issue: OpenSSL requirement check missing"
    echo "  Impact: Script may fail at runtime with cryptic error"
    echo "  Fix: Add openssl check to check_requirements() function"
    ((ISSUES++))
fi

# Check 3: Input sanitization function
echo -n "Checking input sanitization (slugify)... "
if grep -q 'slugify()' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${RED}[FAIL]${NC}"
    echo "  Issue: Input sanitization function (slugify) missing"
    echo "  Impact: Unsanitized input may cause injection vulnerabilities"
    echo "  Fix: Add slugify() function and use for PROJECT_NAME"
    ((ISSUES++))
fi

# Check 4: PROJECT_NAME sanitization
echo -n "Checking PROJECT_NAME sanitization... "
if grep -q 'PROJECT_NAME=.*slugify' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${RED}[FAIL]${NC}"
    echo "  Issue: PROJECT_NAME not sanitized before use"
    echo "  Impact: May allow injection attacks via domain/database names"
    echo "  Fix: Sanitize PROJECT_NAME in validate_arguments()"
    ((ISSUES++))
fi

# Check 5: PR_NUMBER numeric validation
echo -n "Checking PR_NUMBER numeric validation... "
if grep -q 'PR_NUMBER.*\^[0-9]\+\$' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${RED}[FAIL]${NC}"
    echo "  Issue: PR_NUMBER not validated as numeric"
    echo "  Impact: May allow injection via non-numeric values"
    echo "  Fix: Add regex validation for PR_NUMBER in validate_arguments()"
    ((ISSUES++))
fi

# Check 6: API token redaction in logs
echo -n "Checking API token redaction... "
if grep -q 'FORGE_API_TOKEN.*REDACTED' "$TARGET_SCRIPT" || \
   grep -q '\${FORGE_API_TOKEN}/\[REDACTED' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${RED}[FAIL]${NC}"
    echo "  Issue: API token not redacted from logs"
    echo "  Impact: Token exposure through log files"
    echo "  Fix: Add token redaction to log() function"
    ((ISSUES++))
fi

# Check 7: Payload logging redaction
echo -n "Checking payload logging redaction... "
if grep -q 'Payload.*REDACTED' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${YELLOW}[WARN]${NC}"
    echo "  Issue: API payloads may be logged in cleartext"
    echo "  Impact: Sensitive data exposure in debug logs"
    echo "  Recommendation: Redact payload content in api_request()"
fi

# Check 8: Password redaction in API responses
echo -n "Checking password redaction in errors... "
if grep -q 'password.*REDACTED' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${RED}[FAIL]${NC}"
    echo "  Issue: Passwords not redacted from API error responses"
    echo "  Impact: Password exposure in error logs"
    echo "  Fix: Add sed pattern to redact passwords in api_request() errors"
    ((ISSUES++))
fi

# Check 9: Database name sanitization
echo -n "Checking database name sanitization... "
if grep -q 'db_name=.*tr.*-cd' "$TARGET_SCRIPT" || \
   grep -q 'db_name.*\[:alnum:\]' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${YELLOW}[WARN]${NC}"
    echo "  Issue: Database names may not be fully sanitized"
    echo "  Impact: Special characters could cause SQL issues"
    echo "  Recommendation: Add alphanumeric-only filter for db_name"
fi

# Check 10: Secure temporary files
echo -n "Checking secure temporary file creation... "
if grep -q 'mktemp.*-t' "$TARGET_SCRIPT" || \
   grep -q 'chmod.*response_file' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${YELLOW}[WARN]${NC}"
    echo "  Issue: Temporary files may not be secured"
    echo "  Impact: Temporary files readable by other users"
    echo "  Recommendation: Use mktemp -t and chmod 600"
fi

# Check 11: HTTPS enforcement
echo -n "Checking HTTPS enforcement... "
if grep -q 'FORGE_API_URL.*https://' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${YELLOW}[WARN]${NC}"
    echo "  Issue: HTTPS not explicitly enforced"
    echo "  Impact: API communication may fall back to HTTP"
    echo "  Recommendation: Validate FORGE_API_URL starts with https://"
fi

# Check 12: Error handling with rollback
echo -n "Checking error handling and rollback... "
if grep -q 'execute_rollback' "$TARGET_SCRIPT" && \
   grep -q 'trap.*handle_error' "$TARGET_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${YELLOW}[WARN]${NC}"
    echo "  Issue: Error handling or rollback may be incomplete"
    echo "  Impact: Failed deployments may leave orphaned resources"
    echo "  Recommendation: Ensure comprehensive rollback coverage"
fi

# Check 13: Credentials in state file after append
echo -n "Checking state file security after credentials append... "
if grep -A3 'DB_PASSWORD=' "$TARGET_SCRIPT" | grep -q 'chmod 600'; then
    echo -e "${GREEN}[PASS]${NC}"
else
    echo -e "${RED}[FAIL]${NC}"
    echo "  Issue: State file not secured after appending DB credentials"
    echo "  Impact: Database credentials may be world-readable"
    echo "  Fix: Add chmod 600 after appending credentials in create_database_user()"
    ((ISSUES++))
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Security Audit Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

if [[ $ISSUES -eq 0 ]]; then
    echo -e "${GREEN}✓ All critical security checks passed!${NC}"
    echo ""
    echo "The script is production-ready from a security perspective."
    echo ""
else
    echo -e "${RED}✗ Found $ISSUES critical security issue(s)${NC}"
    echo ""
    echo "Please review and fix the issues listed above before deploying to production."
    echo ""
    echo "Documentation: docs/SECURITY-HARDENING-REPORT.md"
    echo ""
fi

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"

exit $ISSUES
