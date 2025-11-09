#!/bin/bash

################################################################################
# apply-security-fixes.sh
#
# Applies comprehensive security hardening to orchestrate-pr-system.sh
#
# This script patches the orchestration script to fix:
#   - State file permissions (chmod 600)
#   - Missing openssl requirement check
#   - Input sanitization (slugify function)
#   - API token exposure in logs
#   - Database credential security
#
# Usage:
#   ./apply-security-fixes.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be changed without modifying files
#
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/orchestrate-pr-system.sh"
BACKUP_SCRIPT="${TARGET_SCRIPT}.backup-$(date +%Y%m%d_%H%M%S)"

DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Security Hardening for orchestrate-pr-system.sh${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}[DRY RUN MODE - No changes will be made]${NC}"
    echo ""
fi

# Verify target exists
if [[ ! -f "$TARGET_SCRIPT" ]]; then
    echo -e "${RED}[ERROR]${NC} Target script not found: $TARGET_SCRIPT"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Target: $TARGET_SCRIPT"
echo ""

################################################################################
# Create backup
################################################################################

if [[ "$DRY_RUN" == false ]]; then
    echo -n "Creating backup... "
    cp "$TARGET_SCRIPT" "$BACKUP_SCRIPT"
    echo -e "${GREEN}✓${NC}"
    echo "Backup saved to: $BACKUP_SCRIPT"
    echo ""
fi

################################################################################
# Apply fixes
################################################################################

TEMP_SCRIPT=$(mktemp)
cp "$TARGET_SCRIPT" "$TEMP_SCRIPT"

echo "Applying security fixes..."
echo ""

# Fix 1: Add slugify function after line 112 (after mkdir -p "$LOG_DIR")
echo -n "1. Adding slugify function... "
if ! grep -q 'slugify()' "$TEMP_SCRIPT"; then
    sed -i '/^mkdir -p "\$LOG_DIR"$/a\
\
# Slugify function for sanitizing input\
slugify() {\
    echo "$1" | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"' | tr -cd '"'"'[:alnum:]-'"'"' | tr -s '"'"'-'"'"' | sed '"'"'s/^-//;s/-$//'"'"'\
}\
\
# Redact API token for logging\
redact_token() {\
    local token="$1"\
    if [[ -n "$token" && ${#token} -gt 8 ]]; then\
        echo "${token:0:4}...${token: -4}"\
    else\
        echo "****"\
    fi\
}' "$TEMP_SCRIPT"
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}[SKIP - Already present]${NC}"
fi

# Fix 2: Update log function to redact API token
echo -n "2. Adding token redaction to log()... "
if ! grep -q 'FORGE_API_TOKEN.*REDACTED' "$TEMP_SCRIPT"; then
    sed -i '/^log() {$/,/^}$/{
        /local timestamp=.*$/a\
\
    # Redact API token from log messages\
    message="${message//${FORGE_API_TOKEN}/[REDACTED_TOKEN]}"
    }' "$TEMP_SCRIPT"
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}[SKIP - Already present]${NC}"
fi

# Fix 3: Add openssl to requirements check
echo -n "3. Adding openssl requirement check... "
if ! grep -q 'command -v openssl' "$TEMP_SCRIPT"; then
    sed -i '/if ! command -v jq &> \/dev\/null; then/a\
    fi\
\
    if ! command -v openssl \&> /dev/null; then\
        missing+=("openssl")' "$TEMP_SCRIPT"
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}[SKIP - Already present]${NC}"
fi

# Fix 4: Add input validation to validate_arguments
echo -n "4. Adding input sanitization... "
if ! grep -q 'PROJECT_NAME=.*slugify' "$TEMP_SCRIPT"; then
    # Add PR_NUMBER numeric validation
    sed -i '/if \[\[ -z "\$PR_NUMBER" \]\]; then/a\
        log_error "PR number is required (--pr-number)"\
        return 1\
    fi\
\
    # Validate PR_NUMBER is numeric\
    if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then\
        log_error "PR number must be numeric"' "$TEMP_SCRIPT"

    # Add PROJECT_NAME sanitization
    sed -i '/if \[\[ -z "\$PROJECT_NAME" \]\]; then/a\
        log_error "Project name is required (--project-name)"\
        return 1\
    fi\
\
    # Sanitize PROJECT_NAME for use in domain names and database names\
    local original_project_name="$PROJECT_NAME"\
    PROJECT_NAME=$(slugify "$PROJECT_NAME")\
\
    if [[ "$original_project_name" != "$PROJECT_NAME" ]]; then\
        log_info "Project name sanitized: '"'"'$original_project_name'"'"' -> '"'"'$PROJECT_NAME'"'"'"\
    fi\
\
    if [[ -z "$PROJECT_NAME" ]]; then\
        log_error "Project name invalid after sanitization"' "$TEMP_SCRIPT"
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}[SKIP - Already present]${NC}"
fi

# Fix 5: Secure state file permissions in save_state()
echo -n "5. Securing state file permissions... "
if ! grep -q 'chmod 600.*STATE_FILE' "$TEMP_SCRIPT"; then
    sed -i '/^save_state() {$/,/^}$/{
        /log_debug "State saved to/c\
    # Secure state file permissions (contains sensitive data)\
    chmod 600 "$STATE_FILE"\
    log_debug "State saved to: $STATE_FILE (permissions: 600)"
    }' "$TEMP_SCRIPT"
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}[SKIP - Already present]${NC}"
fi

# Fix 6: Redact payloads in api_request()
echo -n "6. Redacting API payloads in logs... "
if ! grep -q 'Payload.*REDACTED' "$TEMP_SCRIPT"; then
    sed -i 's/\[\[ -n "\$data" \]\] && log_debug "Payload: \$data"/[[ -n "$data" ]] \&\& log_debug "Payload: [REDACTED - $(echo \"$data\" | wc -c) bytes]"/' "$TEMP_SCRIPT"
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}[SKIP - Already present]${NC}"
fi

# Fix 7: Redact sensitive data in API error responses
echo -n "7. Redacting passwords in API errors... "
if ! grep -q 'password.*REDACTED' "$TEMP_SCRIPT"; then
    sed -i '/log_error "Response: \$response"/i\
        # Redact sensitive information from error response\
        local redacted_response=$(echo "$response" | sed '"'"'s/"password":"[^"]*"/"password":"[REDACTED]"/g'"'"' | sed '"'"'s/"token":"[^"]*"/"token":"[REDACTED]"/g'"'"')' "$TEMP_SCRIPT"
    sed -i 's/log_error "Response: \$response"/log_error "Response: $redacted_response"/' "$TEMP_SCRIPT"
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}[SKIP - Already present]${NC}"
fi

# Fix 8: Sanitize database names
echo -n "8. Sanitizing database names... "
if ! grep -q 'db_name=.*tr.*-cd' "$TEMP_SCRIPT"; then
    sed -i '/local db_name="pr_\${PR_NUMBER}"/a\
    # Database names should only contain alphanumeric and underscores\
    db_name=$(echo "$db_name" | tr -cd '"'"'[:alnum:]_'"'"')' "$TEMP_SCRIPT"
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}[SKIP - Already present]${NC}"
fi

# Fix 9: Secure state file after appending credentials
echo -n "9. Securing state file after DB credentials... "
if ! grep -A5 'cat >> "\$STATE_FILE" << EOF' "$TEMP_SCRIPT" | grep -q 'chmod 600'; then
    sed -i '/cat >> "\$STATE_FILE" << EOF/,/^EOF$/a\
\
        # Secure state file permissions after adding sensitive data\
        chmod 600 "$STATE_FILE"\
\
        log_debug "Database credentials saved to state file (secured with 600 permissions)"' "$TEMP_SCRIPT"
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}[SKIP - Already present]${NC}"
fi

################################################################################
# Validate and apply
################################################################################

echo ""
echo "Validating syntax..."

if bash -n "$TEMP_SCRIPT"; then
    echo -e "${GREEN}✓ Syntax validation passed${NC}"
    echo ""

    if [[ "$DRY_RUN" == false ]]; then
        echo "Applying changes..."
        mv "$TEMP_SCRIPT" "$TARGET_SCRIPT"
        chmod +x "$TARGET_SCRIPT"
        echo -e "${GREEN}✓ Security fixes applied successfully${NC}"
        echo ""
        echo "Backup: $BACKUP_SCRIPT"
    else
        echo -e "${YELLOW}[DRY RUN] Changes validated but not applied${NC}"
        rm -f "$TEMP_SCRIPT"
    fi
else
    echo -e "${RED}✗ Syntax validation failed${NC}"
    echo "Temporary file saved for inspection: $TEMP_SCRIPT"
    exit 1
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Next Steps${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "1. Run security validation:"
echo "   ./scripts/security-check.sh"
echo ""
echo "2. Test the script:"
echo "   ./scripts/orchestrate-pr-system.sh --help"
echo ""
echo "3. Review changes:"
echo "   diff $BACKUP_SCRIPT $TARGET_SCRIPT"
echo ""
echo "4. If issues occur, restore backup:"
echo "   cp $BACKUP_SCRIPT $TARGET_SCRIPT"
echo ""

exit 0
