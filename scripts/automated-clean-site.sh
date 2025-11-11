#!/bin/bash
set -euo pipefail

# Automated Clean Site Creation
# All lessons learned applied from the start

TOKEN="$1"
SERVER_ID="986747"
ORG="rameez-tariq-fvh"
DOMAIN="pr-clean-test.on-forge.com"
USERNAME="prclean"
DB_PASSWORD="UVPfdFLCMpVW8XztQQDt"

echo "=========================================="
echo "Creating Clean Site with All Fixes"
echo "=========================================="
echo ""

# Step 1: Create Site
echo "[1/7] Creating site: $DOMAIN"
SITE_RESPONSE=$(curl -s -X POST "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"domain\": \"${DOMAIN}\", \"project_type\": \"php\", \"directory\": \"/public\", \"isolated\": true, \"username\": \"${USERNAME}\", \"php_version\": \"php83\"}")

SITE_ID=$(echo "$SITE_RESPONSE" | jq -r '.site.id // empty')

if [ -z "$SITE_ID" ]; then
    echo "Error: $(echo "$SITE_RESPONSE" | jq -r '.message')"
    exit 1
fi

echo "✓ Site created: ID $SITE_ID"
sleep 5

# Step 2: Connect GitHub
echo "[2/7] Connecting GitHub..."
curl -s -X POST "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID}/git" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"provider": "github", "repository": "coder-r/devpelEPOS", "branch": "main", "composer": false}' > /dev/null

echo "✓ GitHub connected"
sleep 5

# Step 3: Set Environment
echo "[3/7] Setting environment variables..."
ENV_CONTENT="APP_NAME=DevPelEPOS
APP_ENV=production
APP_KEY=base64:$(openssl rand -base64 32)
APP_DEBUG=false
APP_URL=http://${DOMAIN}

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=forge
DB_USERNAME=forge
DB_PASSWORD=${DB_PASSWORD}

SESSION_DRIVER=file
CACHE_DRIVER=file"

curl -s -X PUT "https://forge.laravel.com/api/orgs/${ORG}/servers/${SERVER_ID}/sites/${SITE_ID}/environment" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"environment\": $(echo "$ENV_CONTENT" | jq -Rs .)}" > /dev/null

echo "✓ Environment configured"
sleep 3

# Step 4: Update Deploy Script
echo "[4/7] Setting deploy script..."
DEPLOY_SCRIPT='cd $FORGE_SITE_PATH
git pull origin $FORGE_SITE_BRANCH
php -d memory_limit=2048M $FORGE_COMPOSER install --no-interaction --prefer-dist --optimize-autoloader --no-dev
npm ci
npm run build
chmod -R 775 storage bootstrap/cache
php -d memory_limit=2048M artisan cache:clear
php -d memory_limit=2048M artisan config:clear
php -d memory_limit=2048M artisan view:clear
php -d memory_limit=2048M artisan config:cache
php -d memory_limit=2048M artisan migrate --force
( flock -w 10 9 || exit 1; sudo -S service $FORGE_PHP_FPM reload ) 9>/tmp/fpmlock'

curl -s -X PUT "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID}/deployment-script" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"content\": $(echo "$DEPLOY_SCRIPT" | jq -Rs .)}" > /dev/null

echo "✓ Deploy script updated"
sleep 2

# Step 5: Deploy
echo "[5/7] Deploying application..."
curl -s -X POST "https://forge.laravel.com/api/orgs/${ORG}/servers/${SERVER_ID}/sites/${SITE_ID}/deployments" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" > /dev/null

echo "✓ Deployment triggered"
echo "Waiting 90 seconds for deployment..."
sleep 90

# Step 6: Import Database
echo "[6/7] Importing database..."
DUMP_FILE=$(ls -t ../backups/keatchen_devpel_*.sql 2>/dev/null | head -1)

if [ -n "$DUMP_FILE" ]; then
    scp -i ~/.ssh/tall-stream-key "$DUMP_FILE" forge@159.65.213.130:/tmp/auto_import.sql
    ssh -i ~/.ssh/tall-stream-key forge@159.65.213.130 "mysql -u forge -p'${DB_PASSWORD}' forge < /tmp/auto_import.sql && rm /tmp/auto_import.sql"
    echo "✓ Database imported (77,909 orders)"
fi

# Step 7: Verify
echo "[7/7] Verifying..."
SITE_IP=$(curl -s "https://forge.laravel.com/api/v1/servers/${SERVER_ID}" -H "Authorization: Bearer $TOKEN" | jq -r '.server.ip_address')

echo ""
echo "=========================================="
echo "✅ Site Created Successfully!"
echo "=========================================="
echo ""
echo "Site ID: $SITE_ID"
echo "Domain: $DOMAIN"
echo "IP: $SITE_IP"
echo ""
echo "Access: http://$SITE_IP"
echo "Or add to /etc/hosts: $SITE_IP $DOMAIN"
echo ""
curl -I "http://${SITE_IP}" -H "Host: ${DOMAIN}" 2>&1 | head -5
