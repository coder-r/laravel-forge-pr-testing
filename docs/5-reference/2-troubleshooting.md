# Troubleshooting Guide - PR Testing Environment System

⚠️ **REFERENCE GUIDE**: This is your "what to do when X fails" guide. Use Ctrl+F to search for your specific problem.

## Table of Contents

1. [Environment Creation Issues](#environment-creation-issues)
2. [Database Issues](#database-issues)
3. [Deployment Issues](#deployment-issues)
4. [Access Issues](#access-issues)
5. [Performance Issues](#performance-issues)
6. [Cleanup Issues](#cleanup-issues)
7. [Quick Diagnosis Commands](#quick-diagnosis-commands)
8. [Emergency Recovery Procedures](#emergency-recovery-procedures)

---

## Environment Creation Issues

### Problem: "/preview" Command Doesn't Work

**Symptoms:**
- Comment `/preview` on PR, nothing happens
- No GitHub Action workflow triggered
- No bot response on PR

**Diagnosis:**
```bash
# Check if GitHub webhook is configured
# Go to: GitHub repo → Settings → Webhooks
# Look for webhook pointing to GitHub Actions

# Check GitHub Actions tab for workflow runs
# Look for "PR Testing Environment" workflow

# Check workflow file exists
ls -la .github/workflows/pr-testing.yml
```

**Solution:**

**Step 1: Verify Webhook Configuration**
```bash
# In GitHub repository:
1. Settings → Webhooks
2. Check for webhook with "issue_comment" event
3. Check "Recent Deliveries" for errors
4. Verify webhook secret matches workflow secret
```

**Step 2: Check Workflow Permissions**
```yaml
# In .github/workflows/pr-testing.yml
# Verify permissions section exists:
permissions:
  issues: write
  pull-requests: write
  contents: read
```

**Step 3: Test Manually**
```bash
# Manually trigger workflow to test
# GitHub → Actions → PR Testing Environment → Run workflow
# Select PR branch and run
```

**Step 4: Check Comment Format**
```bash
# Make sure comment is exactly: /preview
# Not: /Preview or / preview or //preview
# Must be on its own line or at start of comment
```

**Prevention:**
- Set up webhook monitoring/alerting
- Test workflow after any GitHub Actions changes
- Document exact comment format for team
- Add workflow status badge to README

---

### Problem: Site Creation Fails

**Symptoms:**
- GitHub Action runs but fails at "Create Forge site" step
- Error message: "Failed to create site" or API timeout
- Workflow shows red X

**Diagnosis:**
```bash
# Check GitHub Action logs
# Look for specific error from Forge API

# Check Forge server status
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID} \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}"

# Check server disk space
ssh forge@{SERVER_IP} 'df -h'

# Check existing sites count
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" | jq '. | length'
```

**Solution:**

**Step 1: Verify Forge API Token**
```bash
# Test API token is valid
curl https://forge.laravel.com/api/v1/user \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}"

# If token invalid, regenerate in Forge:
# Forge → Account → API → Create New Token
# Update GitHub secret: FORGE_API_TOKEN
```

**Step 2: Check Server Resources**
```bash
# SSH to server and check resources
ssh forge@{SERVER_IP}

# Check disk space (need >10GB free)
df -h

# Check memory
free -h

# Check CPU load
uptime
```

**Step 3: Verify Server ID**
```bash
# List all servers to confirm ID
curl https://forge.laravel.com/api/v1/servers \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" | jq '.'

# Update workflow if server ID changed
```

**Step 4: Check Site Limits**
```bash
# Forge may have site limits per plan
# Log into Forge UI → Check plan limits
# Upgrade plan if at limit
```

**Step 5: Retry with Logging**
```bash
# Add debug logging to workflow
- name: Create Forge site
  run: |
    echo "Creating site for PR ${{ github.event.issue.number }}"
    echo "Server ID: $FORGE_SERVER_ID"
    echo "Domain: pr-${{ github.event.issue.number }}.staging.kitthub.com"
    # ... rest of script
```

**Prevention:**
- Monitor server resources (disk, RAM)
- Set up alerts for low disk space (<20GB)
- Implement retry logic in workflow
- Keep Forge plan current

---

### Problem: Database Creation Fails

**Symptoms:**
- Site created successfully
- Database creation step fails
- Error: "Database already exists" or "Permission denied"

**Diagnosis:**
```bash
# SSH to server and check databases
ssh forge@{SERVER_IP}

# List existing databases
mysql -u forge -p -e "SHOW DATABASES LIKE 'pr_%';"

# Check database user privileges
mysql -u forge -p -e "SELECT user, host FROM mysql.user WHERE user LIKE 'pr_%';"

# Check database creation permissions
mysql -u forge -p -e "SHOW GRANTS FOR 'forge'@'localhost';"
```

**Solution:**

**Step 1: Check for Existing Database**
```bash
# If database already exists from previous failed attempt
mysql -u forge -p -e "DROP DATABASE IF EXISTS pr_{PR_NUMBER}_customer_db;"
mysql -u forge -p -e "DROP USER IF EXISTS 'pr_{PR_NUMBER}_user'@'localhost';"
```

**Step 2: Verify Forge Database Credentials**
```bash
# Check Forge database password is correct
# Forge → Server → Database
# Test connection
mysql -u forge -p{FORGE_DB_PASSWORD}
```

**Step 3: Check Database Name Length**
```bash
# MySQL has 64 character limit for database names
# If PR number + project name too long, truncate

# Before: pr_123_keatchen_customer_app_db (too long)
# After:  pr_123_customer_db (better)
```

**Step 4: Manual Creation for Testing**
```bash
# Create database manually to test
mysql -u forge -p << EOF
CREATE DATABASE pr_{PR_NUMBER}_customer_db;
CREATE USER 'pr_{PR_NUMBER}_user'@'localhost' IDENTIFIED BY 'strong_password';
GRANT ALL PRIVILEGES ON pr_{PR_NUMBER}_customer_db.* TO 'pr_{PR_NUMBER}_user'@'localhost';
FLUSH PRIVILEGES;
EOF
```

**Prevention:**
- Implement database name validation in workflow
- Add cleanup of orphaned databases
- Log database creation details
- Test database creation in dev environment first

---

### Problem: SSL Certificate Fails

**Symptoms:**
- Site accessible via HTTP but not HTTPS
- Browser shows "Connection not secure"
- Forge UI shows certificate status as "failed"

**Diagnosis:**
```bash
# Check DNS resolution
dig pr-{PR_NUMBER}.staging.kitthub.com

# Check port 80 and 443 accessibility
curl -I http://pr-{PR_NUMBER}.staging.kitthub.com
curl -I https://pr-{PR_NUMBER}.staging.kitthub.com

# Check Forge certificate status
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/certificates \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" | jq '.'

# Check Let's Encrypt rate limits
# https://crt.sh/?q=%.staging.kitthub.com
```

**Solution:**

**Step 1: Verify DNS Propagation**
```bash
# Wait for DNS to propagate (can take up to 1 hour)
watch -n 10 'dig pr-{PR_NUMBER}.staging.kitthub.com'

# Check from multiple locations
# Use: https://www.whatsmydns.net/
```

**Step 2: Check Wildcard DNS**
```bash
# Verify wildcard DNS record exists
dig *.staging.kitthub.com

# Should return A record pointing to server IP
# If not, add in DNS provider:
# Type: A
# Name: *.staging.kitthub.com
# Value: {SERVER_IP}
# TTL: 3600
```

**Step 3: Check Let's Encrypt Rate Limits**
```bash
# Let's Encrypt limit: 50 certificates per week per domain
# Check current certificate count
curl "https://crt.sh/?q=%.staging.kitthub.com&output=json" | jq '. | length'

# If at limit, wait or use different subdomain pattern
```

**Step 4: Retry Certificate Issuance**
```bash
# Via Forge API
curl -X POST https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/certificates/letsencrypt \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "domains": ["pr-{PR_NUMBER}.staging.kitthub.com"]
  }'
```

**Step 5: Temporary HTTP Fallback**
```bash
# If SSL continues failing, use HTTP temporarily
# Post comment on PR:
"⚠️ Environment ready but SSL pending. Use HTTP for now:
http://pr-{PR_NUMBER}.staging.kitthub.com"
```

**Prevention:**
- Implement retry logic with exponential backoff
- Monitor Let's Encrypt rate limit usage
- Consider wildcard certificate (more complex setup)
- Add DNS propagation wait time before SSL issuance

---

### Problem: Deployment Fails

**Symptoms:**
- Site and database created
- Deployment step hangs or fails
- Site shows Forge default page or 502 error

**Diagnosis:**
```bash
# Check deployment status via API
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/deployment-log \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}"

# SSH to site and check logs
ssh forge@{SERVER_IP}
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
tail -100 storage/logs/laravel.log

# Check deployment script
cat .forge-deploy

# Check PHP errors
tail -50 /var/log/nginx/pr-{PR_NUMBER}.staging.kitthub.com-error.log
```

**Solution:**

**Step 1: Check Git Branch**
```bash
# Verify PR branch exists and is accessible
git ls-remote https://github.com/{OWNER}/{REPO} | grep {PR_BRANCH}

# Check repository connection in Forge
# Forge → Site → Git Repository
```

**Step 2: Check Composer Install**
```bash
# SSH to site directory
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com

# Try composer install manually
composer install --no-interaction --prefer-dist

# Check for composer.lock conflicts
git status

# Common errors:
# - Composer auth required → Add GitHub token to Forge
# - Memory limit → Increase PHP memory_limit
# - Network timeout → Check server connectivity
```

**Step 3: Check Environment Variables**
```bash
# Verify .env file exists and is populated
cat .env | head -20

# Check database credentials
php artisan tinker
DB::connection()->getPdo();

# If fails, environment variables not set correctly
```

**Step 4: Check Migrations**
```bash
# Try running migrations manually
php artisan migrate --force

# Check migration status
php artisan migrate:status

# If fails, check database connection and credentials
```

**Step 5: Redeploy**
```bash
# Trigger new deployment via API
curl -X POST https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/deployment/deploy \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}"

# Or via Forge UI
# Forge → Site → Deployments → Deploy Now
```

**Prevention:**
- Test deployment script in isolated environment
- Add deployment timeout handling
- Implement health check after deployment
- Log detailed deployment steps
- Add rollback mechanism

---

### Problem: Environment Never Becomes Ready

**Symptoms:**
- All steps complete in GitHub Action
- But site returns 502 Bad Gateway or times out
- No response from domain

**Diagnosis:**
```bash
# Check site status in Forge
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID} \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" | jq '.site.status'

# Check Nginx status
ssh forge@{SERVER_IP} 'sudo systemctl status nginx'

# Check PHP-FPM status
ssh forge@{SERVER_IP} 'sudo systemctl status php8.2-fpm'

# Check if site is responding locally on server
ssh forge@{SERVER_IP} 'curl -I http://127.0.0.1:80 -H "Host: pr-{PR_NUMBER}.staging.kitthub.com"'

# Check Nginx error logs
ssh forge@{SERVER_IP} 'sudo tail -100 /var/log/nginx/error.log'
```

**Solution:**

**Step 1: Restart Services**
```bash
# Restart Nginx
ssh forge@{SERVER_IP} 'sudo systemctl restart nginx'

# Restart PHP-FPM
ssh forge@{SERVER_IP} 'sudo systemctl restart php8.2-fpm'

# Check status
curl -I http://pr-{PR_NUMBER}.staging.kitthub.com
```

**Step 2: Check Nginx Configuration**
```bash
# View site Nginx config
ssh forge@{SERVER_IP} 'cat /etc/nginx/sites-available/pr-{PR_NUMBER}.staging.kitthub.com'

# Test Nginx configuration
ssh forge@{SERVER_IP} 'sudo nginx -t'

# Common issues:
# - Invalid fastcgi_pass socket path
# - Missing site configuration file
# - Syntax errors in config
```

**Step 3: Check File Permissions**
```bash
# Check site directory ownership
ssh forge@{SERVER_IP} 'ls -la /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com'

# Should be owned by pr{PR_NUMBER}user
# If not, fix permissions
ssh forge@{SERVER_IP} 'sudo chown -R pr{PR_NUMBER}user:pr{PR_NUMBER}user /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com'

# Check storage permissions
ssh forge@{SERVER_IP} 'sudo chmod -R 775 /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/storage'
```

**Step 4: Check Application Logs**
```bash
# View Laravel logs
ssh forge@{SERVER_IP} 'tail -100 /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/storage/logs/laravel.log'

# Common errors:
# - Database connection failed
# - Missing environment variables
# - Cache/session permission errors
# - Missing encryption key
```

**Step 5: Generate Application Key**
```bash
# If APP_KEY missing
ssh forge@{SERVER_IP}
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
php artisan key:generate
php artisan config:cache
```

**Prevention:**
- Implement comprehensive health checks
- Add readiness probe with timeout
- Log all service status during creation
- Test with minimal Laravel app first

---

## Database Issues

### Problem: Database Connection Errors

**Symptoms:**
- Site loads but shows database connection error
- Laravel error: "SQLSTATE[HY000] [1045] Access denied"
- Environment variable shows correct credentials

**Diagnosis:**
```bash
# Test database connection from site directory
ssh forge@{SERVER_IP}
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
php artisan tinker
DB::connection()->getPdo();

# Check .env file
cat .env | grep DB_

# Test MySQL connection directly
mysql -u pr_{PR_NUMBER}_user -p pr_{PR_NUMBER}_customer_db

# Check database exists
mysql -u forge -p -e "SHOW DATABASES LIKE 'pr_%';"

# Check user privileges
mysql -u forge -p -e "SHOW GRANTS FOR 'pr_{PR_NUMBER}_user'@'localhost';"
```

**Solution:**

**Step 1: Verify Database Credentials**
```bash
# Check environment variables in Forge
# Forge → Site → Environment → Edit

# Common issues:
# - DB_USERNAME doesn't match created user
# - DB_PASSWORD has special characters not escaped
# - DB_DATABASE name typo
# - DB_HOST should be 'localhost' not '127.0.0.1'
```

**Step 2: Recreate Database User**
```bash
mysql -u forge -p << EOF
DROP USER IF EXISTS 'pr_{PR_NUMBER}_user'@'localhost';
CREATE USER 'pr_{PR_NUMBER}_user'@'localhost' IDENTIFIED BY '{PASSWORD}';
GRANT ALL PRIVILEGES ON pr_{PR_NUMBER}_customer_db.* TO 'pr_{PR_NUMBER}_user'@'localhost';
FLUSH PRIVILEGES;
EOF
```

**Step 3: Clear Configuration Cache**
```bash
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
php artisan config:clear
php artisan cache:clear
php artisan config:cache
```

**Step 4: Check MySQL Max Connections**
```bash
# If error: "Too many connections"
mysql -u forge -p -e "SHOW VARIABLES LIKE 'max_connections';"

# Check current connections
mysql -u forge -p -e "SHOW PROCESSLIST;"

# Increase max_connections if needed
# Edit: /etc/mysql/mysql.conf.d/mysqld.cnf
# max_connections = 200
# sudo systemctl restart mysql
```

**Prevention:**
- Validate database credentials during creation
- Test connection before marking environment ready
- Use consistent password generation strategy
- Document credential format requirements

---

### Problem: Master Snapshot Missing

**Symptoms:**
- Database creation succeeds
- Database clone step fails with "Source database not found"
- Error: "Database 'keatchen_master' doesn't exist"

**Diagnosis:**
```bash
# Check if master snapshots exist
ssh forge@{SERVER_IP}
mysql -u forge -p -e "SHOW DATABASES LIKE '%master';"

# Check snapshot age
mysql -u forge -p -e "SELECT
  table_schema as database_name,
  SUM(data_length + index_length) / 1024 / 1024 as size_mb,
  MAX(update_time) as last_updated
FROM information_schema.tables
WHERE table_schema LIKE '%master'
GROUP BY table_schema;"

# Check cron job for weekly refresh
crontab -l | grep snapshot
```

**Solution:**

**Step 1: Create Master Snapshot Manually**
```bash
# For keatchen-customer-app
ssh forge@{SERVER_IP}

# Dump production database
mysqldump -u forge -p production_customer_db > /tmp/customer_snapshot.sql

# Create master database if doesn't exist
mysql -u forge -p -e "CREATE DATABASE IF NOT EXISTS keatchen_master;"

# Import snapshot
mysql -u forge -p keatchen_master < /tmp/customer_snapshot.sql

# Clean up
rm /tmp/customer_snapshot.sql

# Repeat for devpel-epos
mysqldump -u forge -p production_epos_db > /tmp/epos_snapshot.sql
mysql -u forge -p -e "CREATE DATABASE IF NOT EXISTS devpel_master;"
mysql -u forge -p devpel_master < /tmp/epos_snapshot.sql
rm /tmp/epos_snapshot.sql
```

**Step 2: Set Up Automatic Weekly Refresh**
```bash
# Create snapshot refresh script
cat > /home/forge/scripts/refresh-snapshots.sh << 'EOF'
#!/bin/bash

# Refresh keatchen master
echo "Refreshing keatchen_master snapshot..."
mysqldump -u forge -p${DB_PASSWORD} production_customer_db | mysql -u forge -p${DB_PASSWORD} keatchen_master
echo "Keatchen master refreshed at $(date)"

# Refresh devpel master
echo "Refreshing devpel_master snapshot..."
mysqldump -u forge -p${DB_PASSWORD} production_epos_db | mysql -u forge -p${DB_PASSWORD} devpel_master
echo "Devpel master refreshed at $(date)"
EOF

chmod +x /home/forge/scripts/refresh-snapshots.sh

# Add to crontab (Sunday 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * 0 /home/forge/scripts/refresh-snapshots.sh >> /home/forge/logs/snapshots.log 2>&1") | crontab -
```

**Step 3: Verify Snapshot Contents**
```bash
# Check tables exist
mysql -u forge -p -e "USE keatchen_master; SHOW TABLES;"

# Check row counts
mysql -u forge -p -e "
SELECT
  table_name,
  table_rows
FROM information_schema.tables
WHERE table_schema = 'keatchen_master'
ORDER BY table_rows DESC
LIMIT 10;"
```

**Prevention:**
- Monitor cron job execution
- Set up alerts if snapshot refresh fails
- Keep multiple snapshot versions (current + previous week)
- Document snapshot refresh process
- Test snapshot integrity after refresh

---

### Problem: Database Clone Fails

**Symptoms:**
- Master snapshot exists
- Clone operation times out or fails
- Error: "Lost connection to MySQL server during query"

**Diagnosis:**
```bash
# Check master snapshot size
ssh forge@{SERVER_IP}
mysql -u forge -p -e "
SELECT
  table_schema as database_name,
  SUM(data_length + index_length) / 1024 / 1024 as size_mb
FROM information_schema.tables
WHERE table_schema = 'keatchen_master';"

# Check MySQL timeout settings
mysql -u forge -p -e "SHOW VARIABLES LIKE '%timeout%';"

# Check disk space
df -h

# Check MySQL process list
mysql -u forge -p -e "SHOW PROCESSLIST;"

# Test clone manually
time (mysqldump -u forge -p keatchen_master | mysql -u forge -p pr_{PR_NUMBER}_customer_db)
```

**Solution:**

**Step 1: Increase MySQL Timeout**
```bash
# Edit MySQL config
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf

# Add or increase these values:
[mysqld]
max_allowed_packet=256M
net_read_timeout=300
net_write_timeout=300
wait_timeout=300

# Restart MySQL
sudo systemctl restart mysql
```

**Step 2: Use Optimized Clone Method**
```bash
# Instead of pipe, use direct copy
mysqldump -u forge -p \
  --quick \
  --single-transaction \
  --skip-lock-tables \
  keatchen_master > /tmp/snapshot.sql

mysql -u forge -p pr_{PR_NUMBER}_customer_db < /tmp/snapshot.sql

rm /tmp/snapshot.sql
```

**Step 3: Clone in Chunks (for very large databases)**
```bash
# Export structure only first
mysqldump -u forge -p --no-data keatchen_master | mysql -u forge -p pr_{PR_NUMBER}_customer_db

# Export and import table by table
for table in $(mysql -u forge -p -Nse "SHOW TABLES FROM keatchen_master"); do
  echo "Copying table: $table"
  mysqldump -u forge -p keatchen_master $table | mysql -u forge -p pr_{PR_NUMBER}_customer_db
done
```

**Step 4: Check Disk Space**
```bash
# Ensure enough space for clone operation
# Need: (source DB size × 2) + 5GB buffer
df -h

# Clean up old environments if needed
# See "Cleanup Issues" section
```

**Prevention:**
- Monitor database clone time
- Set realistic timeout in workflow (allow 5-10 minutes)
- Optimize master snapshot (remove unnecessary data)
- Consider database size reduction strategies
- Test clone performance regularly

---

### Problem: Data Looks Wrong/Empty

**Symptoms:**
- Database clone succeeds
- But tables are empty or have old data
- Application shows no orders, users, etc.

**Diagnosis:**
```bash
# Check when master snapshot was last refreshed
ssh forge@{SERVER_IP}
mysql -u forge -p -e "
SELECT
  table_schema,
  MAX(update_time) as last_updated
FROM information_schema.tables
WHERE table_schema = 'keatchen_master'
GROUP BY table_schema;"

# Check row counts in test environment
mysql -u forge -p pr_{PR_NUMBER}_customer_db -e "
SELECT
  table_name,
  table_rows
FROM information_schema.tables
WHERE table_schema = 'pr_{PR_NUMBER}_customer_db'
ORDER BY table_rows DESC
LIMIT 10;"

# Compare with production
mysql -u forge -p production_customer_db -e "
SELECT
  table_name,
  table_rows
FROM information_schema.tables
WHERE table_schema = 'production_customer_db'
ORDER BY table_rows DESC
LIMIT 10;"

# Check if master is actually being cloned
mysql -u forge -p -e "
SELECT COUNT(*) FROM keatchen_master.orders;
SELECT COUNT(*) FROM pr_{PR_NUMBER}_customer_db.orders;"
```

**Solution:**

**Step 1: Verify Clone Source**
```bash
# Check deployment script is using correct source
cat /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/.forge-deploy | grep mysqldump

# Should be: keatchen_master or devpel_master
# Not: production_customer_db directly
```

**Step 2: Force Master Snapshot Refresh**
```bash
# Run refresh script manually
sudo -u forge /home/forge/scripts/refresh-snapshots.sh

# Wait for completion
tail -f /home/forge/logs/snapshots.log

# Verify data
mysql -u forge -p -e "SELECT COUNT(*) as orders FROM keatchen_master.orders;"
```

**Step 3: Reclone Database**
```bash
# Drop and recreate test database
mysql -u forge -p << EOF
DROP DATABASE pr_{PR_NUMBER}_customer_db;
CREATE DATABASE pr_{PR_NUMBER}_customer_db;
EOF

# Clone again
mysqldump -u forge -p keatchen_master | mysql -u forge -p pr_{PR_NUMBER}_customer_db

# Verify
mysql -u forge -p pr_{PR_NUMBER}_customer_db -e "SELECT COUNT(*) FROM orders;"
```

**Step 4: Check for Cached Data**
```bash
# Application might be showing cached data
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
php artisan cache:clear
php artisan view:clear
php artisan route:clear
php artisan config:clear
```

**Prevention:**
- Add data validation checks after clone
- Log row counts during clone process
- Set up weekly snapshot refresh alerts
- Document expected data volumes
- Test data integrity regularly

---

### Problem: Migrations Fail

**Symptoms:**
- Database clone succeeds
- Deployment fails during migration step
- Error: "Migration table not found" or "Column already exists"

**Diagnosis:**
```bash
# Check migration status
ssh forge@{SERVER_IP}
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
php artisan migrate:status

# Check if migrations table exists
mysql -u pr_{PR_NUMBER}_user -p pr_{PR_NUMBER}_customer_db -e "SHOW TABLES LIKE 'migrations';"

# Check what's in migrations table
mysql -u pr_{PR_NUMBER}_user -p pr_{PR_NUMBER}_customer_db -e "SELECT * FROM migrations ORDER BY id DESC LIMIT 10;"

# Check for conflicting migrations
ls database/migrations/
```

**Solution:**

**Step 1: For Fresh Migration on Cloned Database**
```bash
# Master snapshot already has migrations applied
# So DON'T run migrations on clone

# Update deployment script to skip migrations
cat > .forge-deploy << 'EOF'
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
git pull origin {PR_BRANCH}
composer install --no-interaction --prefer-dist --optimize-autoloader
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan queue:restart
# NOTE: Migrations skipped - database cloned with migrations applied
EOF
```

**Step 2: For Fresh Migrations Only (if needed)**
```bash
# If PR includes NEW migrations not in master
# Run only new migrations

# Check which migrations are new
php artisan migrate:status | grep Pending

# Run migrations
php artisan migrate --force

# Or rollback and re-run
php artisan migrate:fresh --force
# WARNING: This drops all tables!
```

**Step 3: Handle Migration Conflicts**
```bash
# If error: "Column already exists"
# Migration is trying to add column that's already in cloned DB

# Options:
# 1. Skip the migration (if it's already applied)
# 2. Make migration idempotent (check if column exists first)
# 3. Fresh clone with latest master snapshot
```

**Prevention:**
- Document migration strategy in deployment script
- Make migrations idempotent (check before adding)
- Refresh master snapshot after major migrations
- Test migrations in isolated environment first
- Consider separate strategy for PR with schema changes

---

## Deployment Issues

### Problem: Code Doesn't Update

**Symptoms:**
- Push new commits to PR branch
- Site doesn't show changes
- Old code still running

**Diagnosis:**
```bash
# Check if deployment webhook is triggered
# Forge → Site → Deployments → View deployment history

# Check current commit on site
ssh forge@{SERVER_IP}
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
git log -1

# Compare with GitHub
git ls-remote origin {PR_BRANCH} | head -1

# Check deployment script
cat .forge-deploy

# Check if quick deploy is enabled
# Forge → Site → App → Quick Deploy (should be ON)
```

**Solution:**

**Step 1: Verify Git Connection**
```bash
# Check git remote
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
git remote -v

# Should point to correct repository
# If not, update
git remote set-url origin git@github.com:{OWNER}/{REPO}.git
```

**Step 2: Manual Pull**
```bash
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
git fetch origin {PR_BRANCH}
git reset --hard origin/{PR_BRANCH}

# Run deployment manually
bash .forge-deploy
```

**Step 3: Check Deployment Log**
```bash
# View last deployment
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/deployment-log \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}"

# Look for errors:
# - Git pull failed
# - Composer install failed
# - Permission errors
```

**Step 4: Trigger Deployment via API**
```bash
# Force new deployment
curl -X POST https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/deployment/deploy \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}"

# Or via Forge UI
# Forge → Site → Deployments → Deploy Now
```

**Step 5: Check Cache**
```bash
# Application might be serving cached content
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
php artisan cache:clear
php artisan view:clear
php artisan route:clear
php artisan config:clear

# Restart PHP-FPM
sudo systemctl restart php8.2-fpm
```

**Prevention:**
- Enable quick deploy in Forge
- Test webhook after site creation
- Add deployment confirmation comment to PR
- Monitor deployment success rate
- Implement deployment health check

---

### Problem: Deployment Script Errors

**Symptoms:**
- Deployment triggered
- Script fails partway through
- Error in deployment log

**Diagnosis:**
```bash
# View deployment log
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/deployment-log \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}"

# SSH and run commands manually
ssh forge@{SERVER_IP}
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com

# Test each command individually
git pull origin {PR_BRANCH}
composer install --no-interaction --prefer-dist
php artisan config:cache
# etc...
```

**Solution:**

**Step 1: Common Error - Git Pull Fails**
```bash
# Error: "Your local changes would be overwritten"
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
git reset --hard
git clean -fd
git pull origin {PR_BRANCH}

# Update deployment script to force pull
git reset --hard origin/{PR_BRANCH}
git clean -fd
```

**Step 2: Common Error - Composer Fails**
```bash
# Error: "Your requirements could not be resolved"
composer install --no-interaction --prefer-dist --no-scripts

# If memory error
php -d memory_limit=-1 /usr/local/bin/composer install

# Update composer
composer self-update
```

**Step 3: Common Error - Artisan Command Fails**
```bash
# Error: "No application encryption key"
php artisan key:generate

# Error: "Could not find driver"
# Install missing PHP extension
sudo apt-get install php8.2-mysql

# Error: "Class not found"
composer dump-autoload
```

**Step 4: Add Error Handling to Script**
```bash
# Update .forge-deploy with error handling
#!/bin/bash
set -e  # Exit on any error

cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com || exit 1

echo "Pulling latest code..."
git reset --hard origin/{PR_BRANCH}
git clean -fd
git pull origin {PR_BRANCH} || exit 1

echo "Installing dependencies..."
composer install --no-interaction --prefer-dist || exit 1

echo "Running migrations..."
if [ -f artisan ]; then
    php artisan migrate --force || echo "Migrations failed (non-fatal)"
fi

echo "Caching configuration..."
php artisan config:cache || exit 1
php artisan route:cache || exit 1
php artisan view:cache || exit 1

echo "Restarting queue..."
php artisan queue:restart || echo "Queue restart failed (non-fatal)"

echo "Deployment completed at $(date)"
```

**Prevention:**
- Test deployment script in isolation
- Add verbose logging
- Implement retry logic for network operations
- Keep deployment script simple
- Document common errors and fixes

---

### Problem: Composer Install Fails

**Symptoms:**
- Deployment starts
- Fails at "composer install" step
- Error: Memory exhausted, package not found, or auth required

**Diagnosis:**
```bash
# Check composer version
ssh forge@{SERVER_IP}
composer --version

# Try composer install manually
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
composer install --verbose

# Check memory limit
php -i | grep memory_limit

# Check composer.lock exists
ls -la composer.lock

# Check GitHub API rate limit
composer diagnose
```

**Solution:**

**Step 1: Memory Limit Error**
```bash
# Run with unlimited memory
php -d memory_limit=-1 /usr/local/bin/composer install --no-interaction

# Or update deployment script
$FORGE_COMPOSER install --no-interaction --prefer-dist --optimize-autoloader
# becomes
php -d memory_limit=-1 $FORGE_COMPOSER install --no-interaction --prefer-dist --optimize-autoloader
```

**Step 2: GitHub Auth Required**
```bash
# Add GitHub token to Forge
# Forge → Server → Composer
# Add GitHub personal access token

# Or add to composer.json
composer config -g github-oauth.github.com {TOKEN}
```

**Step 3: Package Not Found**
```bash
# Update composer
composer self-update

# Clear composer cache
composer clear-cache

# Remove vendor and reinstall
rm -rf vendor
composer install --no-interaction
```

**Step 4: Dependency Conflict**
```bash
# Check for conflicts
composer why-not php 8.2

# Update dependencies
composer update --no-interaction

# Or lock to specific versions in composer.json
```

**Prevention:**
- Add GitHub token to Forge before creating sites
- Test composer install in dev environment
- Keep composer.lock in version control
- Monitor composer performance
- Consider using prestissimo for faster installs

---

### Problem: Queue Workers Not Starting

**Symptoms:**
- Site deployed successfully
- Jobs not being processed
- Horizon dashboard shows no workers

**Diagnosis:**
```bash
# Check if queue workers are configured
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/workers \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" | jq '.'

# Check if workers are running
ssh forge@{SERVER_IP}
ps aux | grep queue:work

# Check Horizon status
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
php artisan horizon:status

# Check supervisor config
sudo supervisorctl status | grep pr-{PR_NUMBER}

# Check Laravel logs
tail -50 storage/logs/laravel.log
```

**Solution:**

**Step 1: Create Queue Workers via Forge API**
```bash
# Create default queue worker
curl -X POST https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/workers \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "connection": "redis",
    "queue": "default",
    "processes": 1,
    "timeout": 60
  }'
```

**Step 2: Restart Queue Workers**
```bash
# Restart via artisan
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
php artisan queue:restart

# Or via supervisor
sudo supervisorctl restart pr-{PR_NUMBER}-worker:*
```

**Step 3: Check Redis Configuration**
```bash
# Verify Redis connection
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
php artisan tinker
Redis::connection()->ping();

# Check Redis database number in .env
cat .env | grep REDIS_DB
# Should be: REDIS_DB={PR_NUMBER}

# Check queue connection
cat .env | grep QUEUE_CONNECTION
# Should be: QUEUE_CONNECTION=redis
```

**Step 4: Manual Queue Worker for Testing**
```bash
# Run queue worker manually to test
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
php artisan queue:work redis --queue=default --tries=3 --timeout=60

# Watch for errors
# If jobs process, supervisor config is the issue
```

**Step 5: Check Supervisor Configuration**
```bash
# View supervisor config
sudo cat /etc/supervisor/conf.d/pr-{PR_NUMBER}-worker.conf

# Should look like:
[program:pr-{PR_NUMBER}-worker]
command=php /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/artisan queue:work redis --queue=default --tries=3 --timeout=60
user=pr{PR_NUMBER}user
stdout_logfile=/home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/storage/logs/worker.log
redirect_stderr=true

# Reload supervisor
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start pr-{PR_NUMBER}-worker:*
```

**Prevention:**
- Create workers as part of site creation workflow
- Add worker health check
- Monitor queue job processing rate
- Document worker configuration
- Test queue functionality after deployment

---

### Problem: Cache Issues

**Symptoms:**
- Changes deployed but not visible
- Application showing old data
- Config changes not taking effect

**Diagnosis:**
```bash
# Check what's cached
ssh forge@{SERVER_IP}
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com

php artisan route:list | head
php artisan config:show app

# Check cache driver
cat .env | grep CACHE_DRIVER

# Check Redis cache
php artisan tinker
Cache::get('some_key');

# Check file cache
ls -la storage/framework/cache/data/
```

**Solution:**

**Step 1: Clear All Caches**
```bash
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com

# Clear application cache
php artisan cache:clear

# Clear config cache
php artisan config:clear

# Clear route cache
php artisan route:clear

# Clear view cache
php artisan view:clear

# Clear compiled classes
php artisan clear-compiled

# Optimize autoloader
composer dump-autoload --optimize
```

**Step 2: Clear OPcache**
```bash
# Restart PHP-FPM to clear OPcache
sudo systemctl restart php8.2-fpm

# Or reload
sudo systemctl reload php8.2-fpm
```

**Step 3: Clear Redis Cache for Environment**
```bash
# Flush specific Redis database
redis-cli -n {PR_NUMBER} FLUSHDB

# Or via artisan
php artisan cache:clear
```

**Step 4: Update Deployment Script**
```bash
# Add cache clearing to .forge-deploy
php artisan config:cache    # Caches config (faster than no cache)
php artisan route:cache     # Caches routes
php artisan view:cache      # Caches views
php artisan queue:restart   # Restarts queue workers

# Restart PHP-FPM
sudo systemctl reload php8.2-fpm
```

**Prevention:**
- Always clear caches after deployment
- Use cache:clear in deployment script
- Restart PHP-FPM after code changes
- Document cache clearing process
- Consider disabling certain caches in test environments

---

## Access Issues

### Problem: Can't Access Environment URL

**Symptoms:**
- Site created successfully
- URL doesn't resolve
- Browser shows "Site can't be reached"

**Diagnosis:**
```bash
# Test DNS resolution
dig pr-{PR_NUMBER}.staging.kitthub.com

# Test from multiple DNS servers
dig @8.8.8.8 pr-{PR_NUMBER}.staging.kitthub.com
dig @1.1.1.1 pr-{PR_NUMBER}.staging.kitthub.com

# Test server connectivity
ping {SERVER_IP}

# Check if site is listening
curl -I http://pr-{PR_NUMBER}.staging.kitthub.com

# Check Nginx configuration
ssh forge@{SERVER_IP} 'cat /etc/nginx/sites-available/pr-{PR_NUMBER}.staging.kitthub.com'
```

**Solution:**

**Step 1: Verify Wildcard DNS**
```bash
# Check wildcard record exists
dig *.staging.kitthub.com

# Should return:
# *.staging.kitthub.com. 3600 IN A {SERVER_IP}

# If not, add in DNS provider:
# Type: A
# Name: *.staging.kitthub.com
# Value: {SERVER_IP}
# TTL: 3600
```

**Step 2: Wait for DNS Propagation**
```bash
# DNS can take 5-60 minutes to propagate
# Check propagation status
# https://www.whatsmydns.net/#A/pr-{PR_NUMBER}.staging.kitthub.com

# While waiting, access via hosts file
# On your local machine:
# Add to /etc/hosts (Linux/Mac) or C:\Windows\System32\drivers\etc\hosts (Windows)
{SERVER_IP} pr-{PR_NUMBER}.staging.kitthub.com
```

**Step 3: Check Nginx Site Configuration**
```bash
ssh forge@{SERVER_IP}

# Check if site config exists
ls -la /etc/nginx/sites-available/ | grep pr-{PR_NUMBER}

# Check if site is enabled
ls -la /etc/nginx/sites-enabled/ | grep pr-{PR_NUMBER}

# Test Nginx configuration
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx
```

**Step 4: Check Firewall**
```bash
# Check if ports 80 and 443 are open
sudo ufw status | grep -E '80|443'

# Should show:
# 80/tcp ALLOW Anywhere
# 443/tcp ALLOW Anywhere

# If not, allow
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

**Prevention:**
- Set up wildcard DNS before creating first environment
- Document DNS propagation time (warn users)
- Add health check that waits for DNS
- Consider using DNS API for programmatic updates
- Test DNS resolution as part of creation workflow

---

### Problem: SSL Certificate Warnings

**Symptoms:**
- Site accessible via HTTP
- Browser shows "Not Secure" or certificate error
- Certificate invalid or self-signed

**Diagnosis:**
```bash
# Check certificate status
curl -I https://pr-{PR_NUMBER}.staging.kitthub.com

# Check certificate details
openssl s_client -connect pr-{PR_NUMBER}.staging.kitthub.com:443 -servername pr-{PR_NUMBER}.staging.kitthub.com < /dev/null 2>/dev/null | openssl x509 -text -noout

# Check in Forge
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/certificates \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" | jq '.'

# Check Let's Encrypt logs
ssh forge@{SERVER_IP} 'sudo cat /var/log/letsencrypt/letsencrypt.log'
```

**Solution:**

**Step 1: Wait for Certificate Issuance**
```bash
# SSL certificate can take 5-10 minutes
# Check status
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/certificates \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" | jq '.certificates[0].status'

# Watch for status change from "pending" to "active"
```

**Step 2: Retry Certificate Issuance**
```bash
# Via Forge API
curl -X POST https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID}/certificates/letsencrypt \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "domains": ["pr-{PR_NUMBER}.staging.kitthub.com"]
  }'

# Or via Forge UI
# Forge → Site → SSL → Let's Encrypt → Obtain Certificate
```

**Step 3: Check Let's Encrypt Rate Limits**
```bash
# Check how many certificates issued recently
curl "https://crt.sh/?q=%.staging.kitthub.com&output=json" | jq '. | group_by(.not_before[0:10]) | map({date: .[0].not_before[0:10], count: length})'

# Let's Encrypt limit: 50 certificates per week
# If at limit, either:
# - Wait for next week
# - Use different subdomain pattern
# - Use wildcard certificate (more complex)
```

**Step 4: Manual Certificate Installation**
```bash
# If Let's Encrypt continues failing, use manual certificate
ssh forge@{SERVER_IP}

# Install certbot
sudo apt-get update
sudo apt-get install certbot python3-certbot-nginx

# Obtain certificate manually
sudo certbot --nginx -d pr-{PR_NUMBER}.staging.kitthub.com

# Follow prompts
```

**Prevention:**
- Monitor Let's Encrypt rate limit usage
- Add retry logic with exponential backoff
- Implement health check for SSL status
- Consider wildcard certificate for heavy usage
- Document SSL troubleshooting steps

---

### Problem: Basic Auth Not Working

**Symptoms:**
- Site accessible without credentials
- Or credentials not accepted

**Diagnosis:**
```bash
# Test basic auth
curl -I http://pr-{PR_NUMBER}.staging.kitthub.com

# Should return 401 Unauthorized
# If returns 200 OK, basic auth not configured

# Check Nginx configuration
ssh forge@{SERVER_IP}
cat /etc/nginx/sites-available/pr-{PR_NUMBER}.staging.kitthub.com | grep auth_basic

# Check .htpasswd file exists
ls -la /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/.htpasswd
```

**Solution:**

**Step 1: Create .htpasswd File**
```bash
ssh forge@{SERVER_IP}

# Create htpasswd file
sudo htpasswd -c /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/.htpasswd testuser

# Enter password when prompted
# Username: testuser
# Password: (choose secure password)

# Set permissions
sudo chown pr{PR_NUMBER}user:pr{PR_NUMBER}user /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/.htpasswd
sudo chmod 644 /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/.htpasswd
```

**Step 2: Configure Nginx Basic Auth**
```bash
# Edit Nginx site configuration
sudo nano /etc/nginx/sites-available/pr-{PR_NUMBER}.staging.kitthub.com

# Add inside server block:
location / {
    auth_basic "Test Environment Access";
    auth_basic_user_file /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/.htpasswd;

    try_files $uri $uri/ /index.php?$query_string;
}

# Test configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

**Step 3: Test Access**
```bash
# Should require credentials
curl -I http://pr-{PR_NUMBER}.staging.kitthub.com
# Returns: 401 Unauthorized

# With credentials
curl -I -u testuser:password http://pr-{PR_NUMBER}.staging.kitthub.com
# Returns: 200 OK
```

**Step 4: Share Credentials**
```bash
# Post credentials on PR
# Via GitHub Action comment:
"🔐 Environment ready and secured with basic auth
URL: https://pr-{PR_NUMBER}.staging.kitthub.com
Username: testuser
Password: testpass123"
```

**Prevention:**
- Create .htpasswd during site creation
- Use consistent credentials across environments
- Document basic auth setup
- Consider IP whitelist as alternative
- Store credentials securely (GitHub secrets)

---

### Problem: DNS Not Resolving

**Symptoms:**
- Wildcard DNS configured
- But specific subdomain not resolving
- dig shows NXDOMAIN

**Diagnosis:**
```bash
# Check specific subdomain
dig pr-{PR_NUMBER}.staging.kitthub.com

# Check wildcard
dig *.staging.kitthub.com

# Check from authoritative nameserver
dig pr-{PR_NUMBER}.staging.kitthub.com @ns1.your-dns-provider.com

# Check DNS propagation globally
# https://www.whatsmydns.net/#A/pr-{PR_NUMBER}.staging.kitthub.com
```

**Solution:**

**Step 1: Verify Wildcard DNS Record**
```bash
# Log into DNS provider
# Check wildcard A record:
# Type: A
# Name: *.staging.kitthub.com (or *.staging)
# Value: {SERVER_IP}
# TTL: 3600

# Common mistakes:
# ❌ Name: staging.kitthub.com (missing *)
# ❌ Name: pr-*.staging.kitthub.com (wrong pattern)
# ✅ Name: *.staging.kitthub.com (correct)
```

**Step 2: Wait for Propagation**
```bash
# DNS can take 5-60 minutes
# Check TTL of old record
dig staging.kitthub.com | grep "^staging"

# Wait for TTL to expire
# Then check again
```

**Step 3: Flush DNS Cache**
```bash
# On your local machine:

# Linux
sudo systemd-resolve --flush-caches

# Mac
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Windows
ipconfig /flushdns
```

**Step 4: Test Direct Name Resolution**
```bash
# Add to hosts file temporarily
# /etc/hosts (Linux/Mac)
# C:\Windows\System32\drivers\etc\hosts (Windows)

{SERVER_IP} pr-{PR_NUMBER}.staging.kitthub.com

# Test access
curl -I http://pr-{PR_NUMBER}.staging.kitthub.com
```

**Prevention:**
- Set up wildcard DNS before creating environments
- Use low TTL (300-600) for testing
- Document DNS propagation time
- Add DNS check to site creation workflow
- Consider using DNS API for verification

---

## Performance Issues

### Problem: Environment Very Slow

**Symptoms:**
- Site loads but very slowly (>10 seconds)
- Database queries timing out
- High page load times

**Diagnosis:**
```bash
# Check server resources
ssh forge@{SERVER_IP}

# Check CPU usage
top -b -n 1 | head -20

# Check memory usage
free -h

# Check disk I/O
iostat -x 1 5

# Check load average
uptime

# Check slow queries
mysql -u forge -p -e "SELECT * FROM information_schema.processlist WHERE time > 5;"

# Check Laravel logs
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
tail -100 storage/logs/laravel.log | grep -E '(slow|timeout)'
```

**Solution:**

**Step 1: Check for Resource Exhaustion**
```bash
# If memory usage >90%
free -h

# Check which processes using memory
ps aux --sort=-%mem | head -20

# Kill unnecessary processes
# Or restart services
sudo systemctl restart php8.2-fpm
sudo systemctl restart nginx
```

**Step 2: Optimize PHP-FPM**
```bash
# Check PHP-FPM pool configuration
sudo nano /etc/php/8.2/fpm/pool.d/pr-{PR_NUMBER}.conf

# Adjust for test environment
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3

# Restart PHP-FPM
sudo systemctl restart php8.2-fpm
```

**Step 3: Enable Query Caching**
```bash
# Update .env
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com

# Enable query caching
CACHE_DRIVER=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis

# Clear and recache
php artisan config:cache
php artisan view:cache
php artisan route:cache
```

**Step 4: Check Database Performance**
```bash
# Enable slow query log temporarily
mysql -u forge -p << EOF
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;
SET GLOBAL slow_query_log_file = '/var/log/mysql/slow-query.log';
EOF

# Wait a few minutes, then check
sudo tail -50 /var/log/mysql/slow-query.log
```

**Step 5: Add Missing Indexes**
```bash
# Check for missing indexes on common queries
mysql -u forge -p pr_{PR_NUMBER}_customer_db

# Example: Add index to orders table
ALTER TABLE orders ADD INDEX idx_created_at (created_at);
ALTER TABLE orders ADD INDEX idx_user_id (user_id);

# Analyze tables
ANALYZE TABLE orders;
```

**Prevention:**
- Monitor server resources
- Set resource alerts (CPU >80%, RAM >90%)
- Limit concurrent test environments
- Optimize database queries
- Use caching aggressively
- Consider upgrading server for more environments

---

### Problem: Server Resources Exhausted

**Symptoms:**
- All environments slow or unresponsive
- Server showing high CPU/RAM usage
- New environment creation fails

**Diagnosis:**
```bash
# Check overall server health
ssh forge@{SERVER_IP}

# Memory usage
free -h
#               total        used        free
# Mem:           7.8G        7.5G        300M  ← Problem!

# CPU usage
top -b -n 1 | head -20

# Disk usage
df -h
# /dev/vda1       100G    95G     5G  95%  /  ← Problem!

# Load average (should be <CPU cores)
uptime
# load average: 8.5, 7.2, 6.8  ← Problem on 4-core!

# Check running sites
ls -la /home/ | grep pr | wc -l
# 6  ← Too many concurrent environments!
```

**Solution:**

**Step 1: Emergency Cleanup**
```bash
# List all PR environments
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  | jq '.sites[] | select(.name | startswith("pr-")) | {id, name}'

# Find closed PRs with orphaned environments
# Delete oldest/unused environments first

# Delete site
curl -X DELETE https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID} \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}"

# Delete database
mysql -u forge -p -e "DROP DATABASE pr_{PR_NUMBER}_customer_db;"
mysql -u forge -p -e "DROP USER 'pr_{PR_NUMBER}_user'@'localhost';"

# Flush Redis database
redis-cli -n {PR_NUMBER} FLUSHDB
```

**Step 2: Restart Services**
```bash
# Restart PHP-FPM
sudo systemctl restart php8.2-fpm

# Restart Nginx
sudo systemctl restart nginx

# Restart MySQL if needed (only if safe)
sudo systemctl restart mysql

# Restart Redis
sudo systemctl restart redis
```

**Step 3: Clear System Cache**
```bash
# Clear page cache
sync && echo 3 > /proc/sys/vm/drop_caches

# Clear old logs
sudo journalctl --vacuum-time=7d

# Clean apt cache
sudo apt-get clean
sudo apt-get autoclean
```

**Step 4: Implement Resource Limits**
```bash
# Limit concurrent environments in workflow
# Add check before creating new environment:

ACTIVE_ENVS=$(curl -s https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  | jq '[.sites[] | select(.name | startswith("pr-"))] | length')

if [ $ACTIVE_ENVS -ge 3 ]; then
  echo "❌ Maximum concurrent environments (3) reached. Please close some PRs."
  exit 1
fi
```

**Prevention:**
- Monitor server resources continuously
- Set up alerts (RAM >80%, CPU >70%)
- Implement automatic cleanup of stale environments
- Limit concurrent environments (max 3-5)
- Document resource capacity
- Plan for server upgrade path

---

### Problem: Database Queries Slow

**Symptoms:**
- Pages take >5 seconds to load
- Queries timing out
- Application showing "Maximum execution time exceeded"

**Diagnosis:**
```bash
# Enable Laravel query log temporarily
ssh forge@{SERVER_IP}
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com

# Add to .env
LOG_QUERIES=true

# Check database performance
mysql -u forge -p pr_{PR_NUMBER}_customer_db

# Show running queries
SHOW PROCESSLIST;

# Show slow queries
SELECT * FROM information_schema.processlist WHERE time > 5;

# Check table sizes
SELECT
  table_name,
  table_rows,
  ROUND(data_length / 1024 / 1024, 2) AS data_mb,
  ROUND(index_length / 1024 / 1024, 2) AS index_mb
FROM information_schema.tables
WHERE table_schema = 'pr_{PR_NUMBER}_customer_db'
ORDER BY (data_length + index_length) DESC
LIMIT 10;
```

**Solution:**

**Step 1: Add Missing Indexes**
```bash
mysql -u forge -p pr_{PR_NUMBER}_customer_db

# Common indexes for Laravel apps
ALTER TABLE orders ADD INDEX idx_user_id (user_id);
ALTER TABLE orders ADD INDEX idx_created_at (created_at);
ALTER TABLE orders ADD INDEX idx_status (status);

# Composite indexes
ALTER TABLE orders ADD INDEX idx_user_status (user_id, status);
ALTER TABLE order_items ADD INDEX idx_order_product (order_id, product_id);

# Analyze tables after adding indexes
ANALYZE TABLE orders;
```

**Step 2: Optimize Database**
```bash
# Optimize all tables
mysqlcheck -u forge -p --optimize pr_{PR_NUMBER}_customer_db

# Or specific tables
mysql -u forge -p pr_{PR_NUMBER}_customer_db -e "OPTIMIZE TABLE orders;"
```

**Step 3: Enable Query Cache (if not using MySQL 8+)**
```bash
# MySQL 5.7 only (query cache removed in MySQL 8.0)
mysql -u forge -p << EOF
SET GLOBAL query_cache_size = 67108864;
SET GLOBAL query_cache_type = 1;
EOF
```

**Step 4: Implement Application-Level Caching**
```bash
# Update application to cache common queries
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com

# Enable Redis caching
cat >> .env << EOF
CACHE_DRIVER=redis
SESSION_DRIVER=redis
EOF

php artisan config:cache
```

**Prevention:**
- Review slow query log regularly
- Add indexes during development
- Use database query builder efficiently
- Implement eager loading for relationships
- Cache frequently accessed data
- Monitor query performance

---

### Problem: Queue Jobs Backing Up

**Symptoms:**
- Jobs not being processed
- Queue size growing
- Horizon showing large backlog

**Diagnosis:**
```bash
# Check queue size
ssh forge@{SERVER_IP}
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com

# Check Horizon status
php artisan horizon:status

# Check Redis queue length
redis-cli -n {PR_NUMBER} LLEN queues:default

# Check queue workers
ps aux | grep "queue:work" | grep pr-{PR_NUMBER}

# Check failed jobs
php artisan queue:failed

# Check supervisor status
sudo supervisorctl status | grep pr-{PR_NUMBER}
```

**Solution:**

**Step 1: Restart Queue Workers**
```bash
# Via artisan
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com
php artisan queue:restart

# Via supervisor
sudo supervisorctl restart pr-{PR_NUMBER}-worker:*

# Check if workers started
php artisan horizon:status
```

**Step 2: Process Backlog**
```bash
# Check backlog size
redis-cli -n {PR_NUMBER} LLEN queues:default

# Increase workers temporarily
sudo nano /etc/supervisor/conf.d/pr-{PR_NUMBER}-worker.conf

# Change numprocs from 1 to 3
[program:pr-{PR_NUMBER}-worker]
numprocs=3

# Update supervisor
sudo supervisorctl reread
sudo supervisorctl update
```

**Step 3: Clear Failed Jobs**
```bash
# List failed jobs
php artisan queue:failed

# Retry all failed jobs
php artisan queue:retry all

# Or flush failed jobs
php artisan queue:flush
```

**Step 4: Check for Stuck Jobs**
```bash
# Check for long-running jobs
redis-cli -n {PR_NUMBER} LRANGE queues:default 0 10

# If jobs are stuck, clear queue (destructive!)
redis-cli -n {PR_NUMBER} DEL queues:default

# Restart workers
php artisan queue:restart
```

**Prevention:**
- Monitor queue length
- Set up alerts for large backlogs
- Implement job timeouts
- Test queue configuration during setup
- Document queue troubleshooting steps
- Consider increasing workers for test environments

---

## Cleanup Issues

### Problem: Environment Won't Delete

**Symptoms:**
- PR closed/merged
- Environment still exists
- Delete API call fails

**Diagnosis:**
```bash
# Check if site exists
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  | jq '.sites[] | select(.name == "pr-{PR_NUMBER}.staging.kitthub.com")'

# Try to delete manually
curl -X DELETE https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID} \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}"

# Check for error message
# Common errors:
# - Site has active deployments
# - Site deletion in progress
# - API rate limit reached
```

**Solution:**

**Step 1: Cancel Active Deployments**
```bash
# Check deployment status
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites/{SITE_ID} \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  | jq '.site.deployment_status'

# If deploying, wait or cancel via Forge UI
# Forge → Site → Deployments → Cancel
```

**Step 2: Delete via Forge UI**
```bash
# If API fails, use Forge UI
# Forge → Server → Sites → pr-{PR_NUMBER}.staging.kitthub.com → Delete

# Confirm deletion
```

**Step 3: Manual Cleanup**
```bash
ssh forge@{SERVER_IP}

# Stop services
sudo supervisorctl stop pr-{PR_NUMBER}-worker:*

# Delete supervisor config
sudo rm /etc/supervisor/conf.d/pr-{PR_NUMBER}-worker.conf
sudo supervisorctl reread
sudo supervisorctl update

# Delete Nginx config
sudo rm /etc/nginx/sites-available/pr-{PR_NUMBER}.staging.kitthub.com
sudo rm /etc/nginx/sites-enabled/pr-{PR_NUMBER}.staging.kitthub.com
sudo nginx -t
sudo systemctl reload nginx

# Delete site directory
sudo rm -rf /home/pr{PR_NUMBER}user

# Delete Linux user
sudo userdel pr{PR_NUMBER}user

# Delete database
mysql -u forge -p -e "DROP DATABASE IF EXISTS pr_{PR_NUMBER}_customer_db;"
mysql -u forge -p -e "DROP USER IF EXISTS 'pr_{PR_NUMBER}_user'@'localhost';"
mysql -u forge -p -e "FLUSH PRIVILEGES;"

# Clear Redis
redis-cli -n {PR_NUMBER} FLUSHDB
```

**Prevention:**
- Implement cleanup retry logic
- Add timeout to cleanup operations
- Log cleanup steps
- Monitor cleanup success rate
- Document manual cleanup procedure

---

### Problem: Orphaned Resources

**Symptoms:**
- Site deleted but database remains
- Database deleted but site remains
- Redis data not cleaned up

**Diagnosis:**
```bash
# Check for orphaned databases
ssh forge@{SERVER_IP}
mysql -u forge -p -e "SHOW DATABASES LIKE 'pr_%';"

# List PR databases
mysql -u forge -p -e "SELECT
  SCHEMA_NAME,
  ROUND(SUM(DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) AS size_mb
FROM information_schema.SCHEMATA
WHERE SCHEMA_NAME LIKE 'pr_%'
GROUP BY SCHEMA_NAME;"

# Check for orphaned sites
curl https://forge.laravel.com/api/v1/servers/{SERVER_ID}/sites \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  | jq '.sites[] | select(.name | startswith("pr-"))'

# Check orphaned site directories
ls -la /home/ | grep pr

# Check Redis databases
for i in {100..200}; do
  SIZE=$(redis-cli -n $i DBSIZE)
  if [ "$SIZE" -gt 0 ]; then
    echo "Redis DB $i: $SIZE keys"
  fi
done
```

**Solution:**

**Step 1: Find Closed PRs**
```bash
# Get list of closed PRs
# Via GitHub CLI
gh pr list --state closed --limit 100 --json number --jq '.[].number'

# Via API
curl -s https://api.github.com/repos/{OWNER}/{REPO}/pulls?state=closed&per_page=100 \
  | jq '.[].number'
```

**Step 2: Cross-Reference with Environments**
```bash
# Create cleanup script
cat > /tmp/cleanup-orphans.sh << 'EOF'
#!/bin/bash

# Get closed PR numbers
CLOSED_PRS=$(gh pr list --state closed --limit 100 --json number --jq '.[].number')

# Find orphaned databases
for db in $(mysql -u forge -p${DB_PASSWORD} -Nse "SHOW DATABASES LIKE 'pr_%';"); do
  # Extract PR number from database name
  PR_NUM=$(echo $db | sed 's/pr_\([0-9]*\)_.*/\1/')

  # Check if PR is closed
  if echo "$CLOSED_PRS" | grep -q "^${PR_NUM}$"; then
    echo "Cleaning up database for closed PR #${PR_NUM}: ${db}"
    mysql -u forge -p${DB_PASSWORD} -e "DROP DATABASE ${db};"
  fi
done

# Find orphaned users
for user in $(mysql -u forge -p${DB_PASSWORD} -Nse "SELECT user FROM mysql.user WHERE user LIKE 'pr_%';"); do
  PR_NUM=$(echo $user | sed 's/pr_\([0-9]*\)_.*/\1/')

  if echo "$CLOSED_PRS" | grep -q "^${PR_NUM}$"; then
    echo "Cleaning up user for closed PR #${PR_NUM}: ${user}"
    mysql -u forge -p${DB_PASSWORD} -e "DROP USER '${user}'@'localhost';"
  fi
done

mysql -u forge -p${DB_PASSWORD} -e "FLUSH PRIVILEGES;"
EOF

chmod +x /tmp/cleanup-orphans.sh
bash /tmp/cleanup-orphans.sh
```

**Step 3: Clean Up Orphaned Directories**
```bash
# List site directories
ls -la /home/ | grep pr

# For each directory, check if PR is closed
for dir in /home/pr*; do
  if [ -d "$dir" ]; then
    PR_NUM=$(basename $dir | sed 's/pr\([0-9]*\)user/\1/')
    echo "Found directory for PR #${PR_NUM}"

    # If PR is closed, remove directory
    # (Add PR check logic here)
    # sudo rm -rf $dir
  fi
done
```

**Step 4: Clean Up Redis Databases**
```bash
# Flush Redis databases for closed PRs
for pr_num in $CLOSED_PRS; do
  echo "Flushing Redis DB ${pr_num}"
  redis-cli -n ${pr_num} FLUSHDB
done
```

**Prevention:**
- Implement comprehensive cleanup function
- Run weekly orphan cleanup job
- Log all cleanup operations
- Add pre-cleanup verification
- Monitor resource usage to detect orphans

---

### Problem: Database Not Dropping

**Symptoms:**
- Delete database command fails
- Error: "Can't drop database; database doesn't exist"
- Error: "Database is in use"

**Diagnosis:**
```bash
# Check if database exists
mysql -u forge -p -e "SHOW DATABASES LIKE 'pr_{PR_NUMBER}%';"

# Check active connections to database
mysql -u forge -p -e "SELECT * FROM information_schema.processlist WHERE db = 'pr_{PR_NUMBER}_customer_db';"

# Check which users have access
mysql -u forge -p -e "SELECT user, host FROM mysql.user WHERE user LIKE 'pr_{PR_NUMBER}%';"
```

**Solution:**

**Step 1: Kill Active Connections**
```bash
# Get connection IDs
mysql -u forge -p -e "SELECT id FROM information_schema.processlist WHERE db = 'pr_{PR_NUMBER}_customer_db';" > /tmp/connections.txt

# Kill each connection
while read id; do
  if [ -n "$id" ]; then
    mysql -u forge -p -e "KILL $id;"
  fi
done < /tmp/connections.txt

# Now drop database
mysql -u forge -p -e "DROP DATABASE pr_{PR_NUMBER}_customer_db;"
```

**Step 2: Force Drop**
```bash
# If database still won't drop
mysql -u forge -p << EOF
-- First revoke all privileges
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'pr_{PR_NUMBER}_user'@'localhost';

-- Drop user
DROP USER IF EXISTS 'pr_{PR_NUMBER}_user'@'localhost';

-- Flush privileges
FLUSH PRIVILEGES;

-- Force drop database
DROP DATABASE IF EXISTS pr_{PR_NUMBER}_customer_db;
EOF
```

**Step 3: Check for Replication**
```bash
# If using replication, may need to stop slave
mysql -u forge -p << EOF
STOP SLAVE;
DROP DATABASE IF EXISTS pr_{PR_NUMBER}_customer_db;
START SLAVE;
EOF
```

**Prevention:**
- Close all connections before dropping
- Stop site services before database deletion
- Add retry logic with exponential backoff
- Log database deletion steps
- Implement force-delete option

---

## Quick Diagnosis Commands

### One-Liner Health Checks

```bash
# Check all test environments
curl -s https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites \
  -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
  | jq '.sites[] | select(.name | startswith("pr-")) | {name, status, php_version}'

# Check server resources
ssh forge@${SERVER_IP} 'echo "=== Memory ===" && free -h && echo "=== Disk ===" && df -h / && echo "=== Load ===" && uptime'

# Check all PR databases
ssh forge@${SERVER_IP} "mysql -u forge -p -e \"SELECT SCHEMA_NAME, ROUND(SUM(DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) AS size_mb FROM information_schema.SCHEMATA WHERE SCHEMA_NAME LIKE 'pr_%' GROUP BY SCHEMA_NAME;\""

# Check queue workers
ssh forge@${SERVER_IP} 'sudo supervisorctl status | grep pr-'

# Test all PR environment URLs
for pr in 123 456 789; do
  echo "Testing PR-${pr}:"
  curl -I -s https://pr-${pr}.staging.kitthub.com | head -1
done
```

### Rapid Troubleshooting Script

```bash
#!/bin/bash
# save as: troubleshoot-pr-env.sh

PR_NUMBER=$1
SERVER_IP="YOUR_SERVER_IP"
FORGE_TOKEN="YOUR_FORGE_TOKEN"
SERVER_ID="YOUR_SERVER_ID"

if [ -z "$PR_NUMBER" ]; then
  echo "Usage: $0 <PR_NUMBER>"
  exit 1
fi

echo "=== Troubleshooting PR-${PR_NUMBER} Environment ==="

# 1. Check DNS
echo -e "\n1. DNS Resolution:"
dig pr-${PR_NUMBER}.staging.kitthub.com +short

# 2. Check HTTP response
echo -e "\n2. HTTP Status:"
curl -I -s http://pr-${PR_NUMBER}.staging.kitthub.com | head -1

# 3. Check HTTPS response
echo -e "\n3. HTTPS Status:"
curl -I -s https://pr-${PR_NUMBER}.staging.kitthub.com | head -1

# 4. Check site in Forge
echo -e "\n4. Forge Site Status:"
curl -s https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites \
  -H "Authorization: Bearer ${FORGE_TOKEN}" \
  | jq ".sites[] | select(.name == \"pr-${PR_NUMBER}.staging.kitthub.com\") | {name, status, deployment_status}"

# 5. Check database
echo -e "\n5. Database Status:"
ssh forge@${SERVER_IP} "mysql -u forge -p -Nse \"SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = 'pr_${PR_NUMBER}_customer_db';\""

# 6. Check queue workers
echo -e "\n6. Queue Workers:"
ssh forge@${SERVER_IP} "sudo supervisorctl status | grep pr-${PR_NUMBER}"

# 7. Check recent errors
echo -e "\n7. Recent Errors:"
ssh forge@${SERVER_IP} "tail -20 /home/pr${PR_NUMBER}user/pr-${PR_NUMBER}.staging.kitthub.com/storage/logs/laravel.log 2>/dev/null | grep -E '(ERROR|CRITICAL|FATAL)'"

echo -e "\n=== Troubleshooting Complete ==="
```

---

## Emergency Recovery Procedures

### Complete Environment Rebuild

If an environment is completely broken, rebuild from scratch:

```bash
#!/bin/bash
# Emergency rebuild script

PR_NUMBER=$1
GITHUB_BRANCH=$2

# 1. Full cleanup
echo "Cleaning up broken environment..."
curl -X DELETE https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID} \
  -H "Authorization: Bearer ${FORGE_TOKEN}"

ssh forge@${SERVER_IP} "
  sudo supervisorctl stop pr-${PR_NUMBER}-worker:*
  sudo rm -f /etc/supervisor/conf.d/pr-${PR_NUMBER}-worker.conf
  sudo rm -f /etc/nginx/sites-*/pr-${PR_NUMBER}.staging.kitthub.com
  sudo rm -rf /home/pr${PR_NUMBER}user
  sudo userdel pr${PR_NUMBER}user 2>/dev/null
  mysql -u forge -p -e 'DROP DATABASE IF EXISTS pr_${PR_NUMBER}_customer_db;'
  mysql -u forge -p -e \"DROP USER IF EXISTS 'pr_${PR_NUMBER}_user'@'localhost';\"
  mysql -u forge -p -e 'FLUSH PRIVILEGES;'
  redis-cli -n ${PR_NUMBER} FLUSHDB
"

# 2. Recreate environment
echo "Recreating environment..."
# Run your normal creation workflow here
# Comment on PR: "/preview"
# Or trigger GitHub Action manually

echo "Environment rebuild initiated"
```

### Server Recovery

If the entire server is having issues:

```bash
#!/bin/bash
# Server recovery script

SERVER_IP="YOUR_SERVER_IP"

ssh forge@${SERVER_IP} << 'EOF'
# 1. Check system health
echo "=== System Health ==="
uptime
free -h
df -h

# 2. Restart all services
echo "=== Restarting Services ==="
sudo systemctl restart nginx
sudo systemctl restart php8.2-fpm
sudo systemctl restart mysql
sudo systemctl restart redis
sudo supervisorctl restart all

# 3. Clear caches
echo "=== Clearing Caches ==="
sync && echo 3 > /proc/sys/vm/drop_caches

# 4. Check service status
echo "=== Service Status ==="
sudo systemctl status nginx --no-pager
sudo systemctl status php8.2-fpm --no-pager
sudo systemctl status mysql --no-pager
sudo systemctl status redis --no-pager

# 5. Test basic functionality
echo "=== Testing Services ==="
curl -I http://localhost
mysql -u forge -p -e "SELECT 1;"
redis-cli PING

echo "=== Recovery Complete ==="
EOF
```

---

## Additional Resources

### Log Locations

```bash
# Laravel logs
/home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/storage/logs/laravel.log

# Nginx access logs
/var/log/nginx/pr-{PR_NUMBER}.staging.kitthub.com-access.log

# Nginx error logs
/var/log/nginx/pr-{PR_NUMBER}.staging.kitthub.com-error.log

# PHP-FPM logs
/var/log/php8.2-fpm.log

# MySQL error log
/var/log/mysql/error.log

# MySQL slow query log
/var/log/mysql/slow-query.log

# Redis log
/var/log/redis/redis-server.log

# Supervisor logs
/var/log/supervisor/

# Queue worker logs
/home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/storage/logs/worker.log
```

### Useful Commands Reference

```bash
# Forge API - List sites
curl https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites \
  -H "Authorization: Bearer ${FORGE_TOKEN}"

# Forge API - Get site details
curl https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID} \
  -H "Authorization: Bearer ${FORGE_TOKEN}"

# Forge API - Trigger deployment
curl -X POST https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID}/deployment/deploy \
  -H "Authorization: Bearer ${FORGE_TOKEN}"

# Forge API - Delete site
curl -X DELETE https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID} \
  -H "Authorization: Bearer ${FORGE_TOKEN}"

# Check site from server locally
curl -I http://127.0.0.1 -H "Host: pr-{PR_NUMBER}.staging.kitthub.com"

# Monitor deployment in real-time
watch -n 5 'curl -s https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID} | jq .site.deployment_status'

# Real-time log monitoring
ssh forge@${SERVER_IP} "tail -f /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com/storage/logs/laravel.log"
```

### Contact Information

When all else fails:

1. **Check GitHub Action logs**: GitHub → Actions → Select failed workflow → View logs
2. **Check Forge UI**: Forge → Server → Sites → pr-{PR_NUMBER}.staging.kitthub.com
3. **SSH to server**: Investigate directly on the server
4. **Review this guide**: Use Ctrl+F to search for specific errors
5. **Ask for help**: Share error messages and diagnosis results with team

---

**Remember**: Most issues can be resolved by:
1. Checking logs
2. Restarting services
3. Clearing caches
4. Retrying the operation

Good luck! 🚀
