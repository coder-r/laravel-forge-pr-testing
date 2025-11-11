#!/bin/bash
set -euo pipefail

#######################################################
# Create Clean PR Test Site with All Fixes Applied
#######################################################
# Uses all lessons learned to create a working site from scratch
#######################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
SERVER_ID="986747"
ORG="rameez-tariq-fvh"
SITE_DOMAIN="pr-clean-test.on-forge.com"
SITE_USERNAME="prclean"
DB_NAME="forge"
DB_PASSWORD="UVPfdFLCMpVW8XztQQDt"

echo -e "${BLUE}=========================================="
echo "Creating Clean PR Test Site"
echo "==========================================${NC}"
echo ""
echo "Domain: $SITE_DOMAIN"
echo "Server: curved-sanctuary ($SERVER_ID)"
echo "Database: $DB_NAME"
echo ""

# Step 1: Create Site
echo -e "${BLUE}[1/7] Creating site via Forge API...${NC}"

SITE_RESPONSE=$(curl -s -X POST "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites" \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{
    \"domain\": \"${SITE_DOMAIN}\",
    \"project_type\": \"php\",
    \"directory\": \"/public\",
    \"isolated\": true,
    \"username\": \"${SITE_USERNAME}\",
    \"php_version\": \"php83\"
  }")

SITE_ID=$(echo "$SITE_RESPONSE" | jq -r '.site.id // .id // empty')

if [ -z "$SITE_ID" ]; then
    echo -e "${YELLOW}Error creating site:${NC}"
    echo "$SITE_RESPONSE" | jq .
    exit 1
fi

echo -e "${GREEN}✓ Site created: ID ${SITE_ID}${NC}"
echo ""

# Step 2: Connect GitHub
echo -e "${BLUE}[2/7] Connecting GitHub repository...${NC}"

sleep 3

curl -s -X POST "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID}/git" \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "github",
    "repository": "coder-r/devpelEPOS",
    "branch": "main",
    "composer": false
  }' | jq .

echo -e "${GREEN}✓ GitHub connected${NC}"
echo ""

# Step 3: Set Environment Variables (CORRECT DATABASE!)
echo -e "${BLUE}[3/7] Configuring environment variables...${NC}"

sleep 2

ENV_VARS="APP_NAME=DevPelEPOS
APP_ENV=production
APP_KEY=base64:$(openssl rand -base64 32)
APP_DEBUG=false
APP_URL=http://${SITE_DOMAIN}

LOG_CHANNEL=stack
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=forge
DB_PASSWORD=${DB_PASSWORD}

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DRIVER=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120"

curl -s -X PUT "https://forge.laravel.com/api/orgs/${ORG}/servers/${SERVER_ID}/sites/${SITE_ID}/environment" \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"environment\": $(echo "$ENV_VARS" | jq -Rs .)}" | jq .

echo -e "${GREEN}✓ Environment configured${NC}"
echo ""

# Step 4: Update Deploy Script
echo -e "${BLUE}[4/7] Setting optimized deploy script...${NC}"

DEPLOY_SCRIPT='echo "Starting deployment..."
cd $FORGE_SITE_PATH

git pull origin $FORGE_SITE_BRANCH
echo "✓ Git pull completed"

# Composer with 2GB memory
php -d memory_limit=2048M $FORGE_COMPOSER install --no-interaction --prefer-dist --optimize-autoloader --no-dev
echo "✓ Composer completed"

# NPM
npm ci
npm run build
echo "✓ Assets built"

# Fix permissions
chmod -R 775 storage bootstrap/cache
echo "✓ Permissions fixed"

# Clear caches
php -d memory_limit=2048M artisan cache:clear
php -d memory_limit=2048M artisan config:clear
php -d memory_limit=2048M artisan view:clear
echo "✓ Caches cleared"

# Cache config only (skip routes)
php -d memory_limit=2048M artisan config:cache
echo "✓ Config cached"

# Migrations
php -d memory_limit=2048M artisan migrate --force
echo "✓ Migrations completed"

# Reload PHP
( flock -w 10 9 || exit 1
    echo "Restarting FPM..."; sudo -S service $FORGE_PHP_FPM reload ) 9>/tmp/fpmlock

echo "✅ Deployment completed!"'

curl -s -X PUT "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID}/deployment-script" \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"content\": $(echo "$DEPLOY_SCRIPT" | jq -Rs .)}" | jq .

echo -e "${GREEN}✓ Deploy script updated${NC}"
echo ""

# Step 5: Trigger Deployment
echo -e "${BLUE}[5/7] Deploying application...${NC}"

sleep 3

curl -s -X POST "https://forge.laravel.com/api/orgs/${ORG}/servers/${SERVER_ID}/sites/${SITE_ID}/deployments" \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  -H "Content-Type: application/json" | jq .

echo -e "${GREEN}✓ Deployment triggered${NC}"
echo ""
echo "Waiting for deployment to complete (60 seconds)..."
sleep 60

# Step 6: Import Database
echo -e "${BLUE}[6/7] Importing keatchen database...${NC}"

LATEST_DUMP=$(ls -t ${SCRIPT_DIR}/../backups/keatchen_devpel_*.sql 2>/dev/null | head -1)

if [ -n "$LATEST_DUMP" ]; then
    echo "Using existing dump: $LATEST_DUMP"

    # Transfer and import
    scp -i ~/.ssh/tall-stream-key "$LATEST_DUMP" forge@159.65.213.130:/tmp/clean_site_import.sql

    ssh -i ~/.ssh/tall-stream-key forge@159.65.213.130 \
        "mysql -u forge -p'${DB_PASSWORD}' ${DB_NAME} < /tmp/clean_site_import.sql && rm /tmp/clean_site_import.sql"

    echo -e "${GREEN}✓ Database imported (77,909 orders)${NC}"
else
    echo -e "${YELLOW}No backup found, creating fresh dump...${NC}"

    ssh -i ~/.ssh/tall-stream-key forge@18.135.39.222 \
        "mysqldump --single-transaction --quick --lock-tables=false -u forge -p'fXcAINwUflS64JVWQYC5' keatchen" | \
    ssh -i ~/.ssh/tall-stream-key forge@159.65.213.130 \
        "mysql -u forge -p'${DB_PASSWORD}' ${DB_NAME}"

    echo -e "${GREEN}✓ Database imported directly${NC}"
fi

echo ""

# Step 7: Verify
echo -e "${BLUE}[7/7] Verifying setup...${NC}"

SITE_IP=$(curl -s "https://forge.laravel.com/api/v1/servers/${SERVER_ID}" \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" | jq -r '.server.ip_address')

echo ""
echo "Testing site..."
curl -I "http://${SITE_IP}" -H "Host: ${SITE_DOMAIN}" 2>&1 | head -5

echo ""
echo "Database check..."
ssh -i ~/.ssh/tall-stream-key forge@159.65.213.130 \
    "mysql -u forge -p'${DB_PASSWORD}' ${DB_NAME} -e 'SELECT COUNT(*) as orders FROM orders;' 2>/dev/null"

echo ""
echo -e "${GREEN}=========================================="
echo "✅ Clean Site Creation Complete!"
echo "==========================================${NC}"
echo ""
echo "Site ID: ${SITE_ID}"
echo "Domain: ${SITE_DOMAIN}"
echo "IP: ${SITE_IP}"
echo ""
echo "Access via IP: http://${SITE_IP}"
echo "(Add to /etc/hosts: ${SITE_IP} ${SITE_DOMAIN})"
echo ""
echo "Next: Install SSL certificate in Forge for DNS to activate"
echo ""
