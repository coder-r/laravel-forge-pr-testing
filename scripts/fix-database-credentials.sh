#!/bin/bash
set -euo pipefail

#######################################################
# Fix Database Credentials and Re-deploy
#######################################################

# Site info
SITE_ID="2925742"
SERVER_ID="986747"
ORG="rameez-tariq-fvh"

# Database credentials
DB_PASSWORD="UVPfdFLCMpVW8XztQQDt"
DB_DATABASE="forge"
DB_USERNAME="forge"

echo "================================================"
echo "  Fixing Database Credentials"
echo "================================================"
echo ""
echo "Site ID: $SITE_ID"
echo "Database: $DB_DATABASE"
echo ""

# Step 1: Update environment variables via Forge API
echo "[1/3] Updating environment variables..."

# Create environment file content
ENV_CONTENT="APP_NAME=Laravel
APP_ENV=production
APP_KEY=base64:$(openssl rand -base64 32)
APP_DEBUG=false
APP_URL=http://pr-test-devpel.on-forge.com

LOG_CHANNEL=stack
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_DATABASE}
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DRIVER=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120
SANCTUM_STATEFUL_DOMAINS=pr-test-devpel.on-forge.com"

# Try v1 API first
echo "Trying v1 API..."
RESULT=$(curl -s -X PUT "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID}/env" \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"content\": $(echo "$ENV_CONTENT" | jq -Rs .)}" 2>&1)

if echo "$RESULT" | grep -q "Unauthenticated"; then
    echo "v1 API failed, trying org-scoped API..."

    # Try org-scoped API
    RESULT=$(curl -s -X PUT "https://forge.laravel.com/api/orgs/${ORG}/servers/${SERVER_ID}/sites/${SITE_ID}/environment" \
      -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -d "{\"environment\": $(echo "$ENV_CONTENT" | jq -Rs .)}" 2>&1)
fi

echo "$RESULT"

if echo "$RESULT" | grep -q "Unauthenticated"; then
    echo "❌ API authentication failed"
    echo ""
    echo "Manual fix required:"
    echo "1. Go to: https://forge.laravel.com/servers/${SERVER_ID}/sites/${SITE_ID}"
    echo "2. Click 'Environment' tab"
    echo "3. Update these values:"
    echo "   DB_DATABASE=${DB_DATABASE}"
    echo "   DB_USERNAME=${DB_USERNAME}"
    echo "   DB_PASSWORD=${DB_PASSWORD}"
    echo "4. Click 'Save'"
    echo "5. Go to 'App' tab and click 'Deploy Now'"
    exit 1
fi

echo "✅ Environment variables updated"
echo ""

# Step 2: Trigger deployment
echo "[2/3] Triggering deployment..."

DEPLOY_RESULT=$(curl -s -X POST "https://forge.laravel.com/api/orgs/${ORG}/servers/${SERVER_ID}/sites/${SITE_ID}/deployments" \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" 2>&1)

echo "$DEPLOY_RESULT"

if echo "$DEPLOY_RESULT" | grep -q "Unauthenticated"; then
    echo "❌ Deployment trigger failed"
    echo "Manual deployment required:"
    echo "Go to: https://forge.laravel.com/servers/${SERVER_ID}/sites/${SITE_ID}"
    echo "Click 'Deploy Now' button"
    exit 1
fi

echo "✅ Deployment triggered"
echo ""

# Step 3: Wait and check status
echo "[3/3] Waiting for deployment (30 seconds)..."
sleep 30

echo ""
echo "Testing site..."
curl -I http://159.65.213.130 -H "Host: pr-test-devpel.on-forge.com" 2>&1 | head -10

echo ""
echo "================================================"
echo "  Fix Complete!"
echo "================================================"
echo ""
echo "Check deployment status at:"
echo "https://forge.laravel.com/servers/${SERVER_ID}/sites/${SITE_ID}"
echo ""
echo "Test site at:"
echo "http://159.65.213.130"
echo "(or add '159.65.213.130 pr-test-devpel.on-forge.com' to /etc/hosts)"
echo ""
