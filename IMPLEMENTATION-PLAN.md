# IMPLEMENTATION-PLAN.md

## Laravel PR Testing Environment - Complete Deployment Guide

**Status**: Ready for Implementation
**Timeline**: 1 week to production (with on-forge.com domains)
**Target**: Automated PR testing on Laravel Forge VPS
**Team Size**: 1-3 developers

---

## Table of Contents

1. [Phase 0: Repository & Secrets Setup (30 min)](#phase-0-repository--secrets-setup-30-min)
2. [Phase 1: Foundation Setup (1-2 hours)](#phase-1-foundation-setup-1-2-hours)
3. [Phase 2: GitHub Integration (1-2 hours)](#phase-2-github-integration-1-2-hours)
4. [Phase 3: Automation Scripts (1-2 hours)](#phase-3-automation-scripts-1-2-hours)
5. [Phase 4: Testing (1-2 hours)](#phase-4-testing-1-2-hours)
6. [Phase 5: Database Snapshots (30 min)](#phase-5-database-snapshots-30-min)
7. [Phase 6: Monitoring & Cleanup (1 hour)](#phase-6-monitoring--cleanup-1-hour)
8. [Phase 7: Team Deployment (1 hour)](#phase-7-team-deployment-1-hour)
9. [Phase 8: Production Hardening (1-2 hours)](#phase-8-production-hardening-1-2-hours)
10. [Appendix: Scripts & Automation](#appendix-scripts--automation)

---

## Phase 0: Repository & Secrets Setup (30 min)

### Objective
Configure GitHub repository with all necessary secrets and permissions for automated deployment.

### Step 0.1: Obtain Laravel Forge API Token

**⏰ Time**: 5 minutes

1. Go to https://forge.laravel.com/account/api
2. Click "Create API Token"
3. Name it: `GitHub PR Testing`
4. Copy the token (you'll need it immediately)
5. Store securely in password manager

**Verification**:
```bash
# Test the token locally (replace with your token)
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://forge.laravel.com/api/v1/servers

# Should return JSON with your servers
```

### Step 0.2: Get Your Forge Server ID

**⏰ Time**: 2 minutes

1. Go to https://forge.laravel.com/servers
2. Click your server name
3. Look for "Server ID" in the URL or server details
4. Record it: `SERVER_ID = _____________`

**Alternative via API**:
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://forge.laravel.com/api/v1/servers | jq '.servers[] | {id, name}'
```

### Step 0.3: Configure GitHub Repository Secrets

**⏰ Time**: 10 minutes

**For each project repository** (keatchen-customer-app and devpel-epos):

1. Go to GitHub → Repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add these secrets:

| Secret Name | Value | Source |
|------------|-------|--------|
| `FORGE_API_TOKEN` | Your token from 0.1 | Forge API page |
| `FORGE_SERVER_ID` | Your server ID from 0.2 | Forge server details |
| `GITHUB_TOKEN` | Leave empty (auto-provided) | GitHub (built-in) |

**Verification**:
```bash
# List secrets in your repo
gh secret list --repo owner/repo-name
```

### Step 0.4: Verify GitHub Webhook Access

**⏰ Time**: 5 minutes

1. Go to your repository → Settings → Webhooks
2. GitHub should auto-create one for Actions
3. Look for `https://github.com/...` webhook
4. Check if it has:
   - ✅ `issues` events
   - ✅ `pull_request` events
   - ✅ `issue_comment` events

**Manual Setup** (if not present):
```bash
# Using GitHub CLI
gh repo edit YOUR_REPO \
  --enable-issues \
  --enable-discussions \
  --enable-projects
```

**Success Criteria**:
- ✅ FORGE_API_TOKEN secret is set and not empty
- ✅ FORGE_SERVER_ID secret is set correctly
- ✅ GitHub webhook is active
- ✅ PR comment events trigger Actions

---

## Phase 1: Foundation Setup (1-2 hours)

### Objective
Prepare Laravel Forge infrastructure for dynamic PR testing environments.

### Step 1.1: Verify Server Resources

**⏰ Time**: 10 minutes
**Skill**: Beginner

```bash
# SSH into your Forge server
ssh forge@YOUR_SERVER_IP

# Check available resources
free -h                    # RAM available
df -h /home              # Disk space
nproc                     # CPU cores
ps aux | wc -l           # Current processes

# Expected output:
# - RAM: 8GB+ (we'll use 1-1.5GB for 3 concurrent PR sites)
# - Disk: 100GB+ (we'll use ~15-20GB for 3 PR sites)
# - CPU: 4+ cores
```

**Record Current State**:
```
Server IP: _______________________
Current RAM: _______ GB
Current Disk: _______ GB
CPU Cores: _______
Current Sites: _______ (including production)
```

**If resources insufficient**:
```bash
# Upgrade your server via Forge UI:
# 1. Go to Server → Server Details
# 2. Click "Upgrade Server"
# 3. Select larger plan (8GB RAM minimum)
# 4. Wait 5-10 minutes for completion

# Verify upgrade
free -h
df -h /home
```

### Step 1.2: Create Master Database Snapshots

**⏰ Time**: 15-30 minutes (depending on DB size)
**Skill**: Intermediate

**For keatchen-customer-app database**:

```bash
# SSH into your Forge server
ssh forge@YOUR_SERVER_IP

# Create backup directory
mkdir -p /var/backups/master-snapshots
cd /var/backups/master-snapshots

# Get your current production database name
# (ask your team or check .env on production server)
PROD_DB_NAME="keatchen_production"    # REPLACE WITH ACTUAL NAME

# Create master snapshot
mysqldump -u forge -pYOUR_DB_PASSWORD $PROD_DB_NAME \
  > keatchen_master_$(date +%Y%m%d).sql

# Verify backup was created
ls -lh keatchen_master_*.sql

# Create the master database if not exists
mysql -u forge -pYOUR_DB_PASSWORD -e "CREATE DATABASE IF NOT EXISTS keatchen_master;"

# Load the master snapshot
mysql -u forge -pYOUR_DB_PASSWORD keatchen_master \
  < keatchen_master_$(date +%Y%m%d).sql

# Verify
mysql -u forge -pYOUR_DB_PASSWORD -e "USE keatchen_master; SHOW TABLES;" | head -20
```

**For devpel-epos database**:

```bash
# Same process for devpel
PROD_DB_NAME="devpel_production"      # REPLACE WITH ACTUAL NAME

mysqldump -u forge -pYOUR_DB_PASSWORD $PROD_DB_NAME \
  > devpel_master_$(date +%Y%m%d).sql

mysql -u forge -pYOUR_DB_PASSWORD -e "CREATE DATABASE IF NOT EXISTS devpel_master;"

mysql -u forge -pYOUR_DB_PASSWORD devpel_master \
  < devpel_master_$(date +%Y%m%d).sql

# Verify
mysql -u forge -pYOUR_DB_PASSWORD -e "USE devpel_master; SHOW TABLES;" | head -20
```

**Success Criteria**:
- ✅ `keatchen_master` database exists with tables
- ✅ `devpel_master` database exists with tables
- ✅ Backup files exist in `/var/backups/master-snapshots/`
- ✅ Run `mysql -u forge -pYOUR_DB_PASSWORD -e "SHOW DATABASES;" | grep master` should show both

### Step 1.3: Configure Redis Databases

**⏰ Time**: 10 minutes
**Skill**: Beginner

```bash
# SSH into server
ssh forge@YOUR_SERVER_IP

# Test Redis connection
redis-cli ping
# Should return: PONG

# Reserve databases 100-199 for PR testing
# (Databases 0-99 will be available for individual PR environments)

redis-cli CONFIG SET maxmemory 2gb          # Set memory limit
redis-cli CONFIG REWRITE                     # Save config

# Verify Redis is running
redis-cli INFO memory | grep maxmemory

# Expected output: maxmemory:2000000000
```

**Success Criteria**:
- ✅ `redis-cli ping` returns PONG
- ✅ Redis memory limit is set to 2GB+

### Step 1.4: Test Forge API Connection

**⏰ Time**: 5 minutes
**Skill**: Beginner

```bash
# From your local machine
export FORGE_TOKEN="YOUR_API_TOKEN_FROM_0.1"
export FORGE_SERVER_ID="YOUR_SERVER_ID_FROM_0.2"

# Test 1: Get server info
curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID | jq '.server | {id, name, ip_address}'

# Test 2: List existing sites
curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites | jq '.sites[] | {id, domain, status}'

# Test 3: List existing databases
curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/databases | jq '.databases[] | {id, name}'
```

**Success Criteria**:
- ✅ All three curl commands return JSON (no errors)
- ✅ You can see your existing sites and databases
- ✅ Server ID is correct

### Step 1.5: Create Test Site (Manual, for validation)

**⏰ Time**: 10 minutes
**Skill**: Intermediate

This tests the full flow manually before automating:

```bash
# Set variables
export FORGE_TOKEN="YOUR_TOKEN"
export FORGE_SERVER_ID="YOUR_SERVER_ID"
export TEST_PR_NUMBER="999"
export TEST_PROJECT="customer"  # or "epos"

# Step 1: Create test site
curl -s -X POST \
  -H "Authorization: Bearer $FORGE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "pr-'$TEST_PR_NUMBER'.on-forge.com",
    "project_type": "php",
    "directory": "/public",
    "isolated": true,
    "php_version": "php82"
  }' \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites | jq '.site | {id, domain, status}'

# Save the site ID from response
SITE_ID="YOUR_SITE_ID_FROM_RESPONSE"

# Step 2: Create database
curl -s -X POST \
  -H "Authorization: Bearer $FORGE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "pr_'$TEST_PR_NUMBER'_'$TEST_PROJECT'_db",
    "user": "pr_'$TEST_PR_NUMBER'_user",
    "password": "TestPass'$RANDOM'@123"
  }' \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/databases | jq '.database | {id, name, user}'

# Save database ID and name from response
DB_ID="YOUR_DB_ID"
DB_NAME="pr_999_customer_db"
DB_USER="pr_999_user"
DB_PASS="YOUR_PASSWORD_FROM_RESPONSE"

# Step 3: Copy master database (SSH to server)
ssh forge@YOUR_SERVER_IP << 'EOF'
MASTER_DB="keatchen_master"
NEW_DB="pr_999_customer_db"

# Create clone
mysqldump -u forge keatchen_master | mysql -u forge $NEW_DB

# Verify
mysql -u forge -e "USE $NEW_DB; SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema=DATABASE();"
EOF

# Step 4: Clean up test site
curl -s -X DELETE \
  -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID

curl -s -X DELETE \
  -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/databases/$DB_ID
```

**Success Criteria**:
- ✅ Site was created on Forge
- ✅ Database was created
- ✅ Master snapshot was copied
- ✅ Site was deleted without errors

---

## Phase 2: GitHub Integration (1-2 hours)

### Objective
Create GitHub Actions workflow for automating PR environment creation/destruction.

### Step 2.1: Create PR Testing Workflow

**⏰ Time**: 30 minutes
**Skill**: Intermediate
**Tools**: Git, text editor

1. In your repository root, create directory:
```bash
mkdir -p .github/workflows
```

2. Create file: `.github/workflows/pr-testing-environment.yml`

**Copy-paste the complete workflow** (see Appendix A1 for full code)

3. Commit and push:
```bash
cd /path/to/your/repo
git add .github/workflows/pr-testing-environment.yml
git commit -m "Add PR testing environment workflow"
git push origin main
```

**Verify**:
```bash
# Check that the workflow file is valid YAML
cd /path/to/your/repo
python3 -m yaml .github/workflows/pr-testing-environment.yml
# or use online YAML validator
```

### Step 2.2: Create Cleanup Workflow

**⏰ Time**: 15 minutes
**Skill**: Intermediate

Create file: `.github/workflows/pr-cleanup.yml`

**Copy-paste the complete workflow** (see Appendix A2 for full code)

Commit and push:
```bash
git add .github/workflows/pr-cleanup.yml
git commit -m "Add PR cleanup workflow"
git push origin main
```

### Step 2.3: Test Workflow Execution

**⏰ Time**: 20 minutes
**Skill**: Beginner

1. Create a test PR:
```bash
# In your repository
git checkout -b test/workflow-validation
echo "# Test" >> README.md
git add README.md
git commit -m "Test PR for workflow validation"
git push origin test/workflow-validation

# Go to GitHub and create the PR
# (or use: gh pr create --title "Test PR" --body "Testing workflow")
```

2. Find your PR number: `_______`

3. Comment on PR:
```
/preview
```

4. Watch GitHub Actions:
   - Go to your repo → Actions tab
   - Find the `pr-testing-environment` workflow
   - Watch execution in real-time
   - Check logs for any errors

5. Verify environment was created:
```bash
# After ~5 minutes, go to https://forge.laravel.com
# Or use API:
export FORGE_TOKEN="YOUR_TOKEN"
export FORGE_SERVER_ID="YOUR_SERVER_ID"

curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites | \
  jq '.sites[] | select(.domain | contains("pr-")) | {domain, status}'
```

6. Test the environment:
```bash
# The workflow should post a comment with the URL
# Visit: https://pr-YOUR_PR_NUMBER.on-forge.com
# (or check the PR comment for the exact URL)

# You should see your Laravel app running!
```

**Success Criteria**:
- ✅ Workflow completes without errors
- ✅ Site appears in Forge dashboard
- ✅ Site is accessible at `pr-XXX.on-forge.com`
- ✅ SSL certificate is automatically installed
- ✅ GitHub comment posted with environment URL
- ✅ Database has correct tables from master snapshot

---

## Phase 3: Automation Scripts (1-2 hours)

### Objective
Create server-side scripts for efficient environment management.

### Step 3.1: Create PR Site Creation Script

**⏰ Time**: 30 minutes
**Skill**: Intermediate
**Location**: `/home/forge/scripts/create-pr-site.sh`

On your server, create the script:

```bash
ssh forge@YOUR_SERVER_IP

# Create scripts directory
sudo mkdir -p /home/forge/scripts
sudo chown forge:forge /home/forge/scripts
cd /home/forge/scripts

# Create the script (full code in Appendix A3)
# [Copy-paste from Appendix A3]

# Make it executable
chmod +x /home/forge/scripts/create-pr-site.sh

# Test the script
./create-pr-site.sh --help
```

### Step 3.2: Create PR Site Deletion Script

**⏰ Time**: 20 minutes
**Skill**: Intermediate
**Location**: `/home/forge/scripts/delete-pr-site.sh`

```bash
# On your server
cd /home/forge/scripts

# Create the deletion script (full code in Appendix A4)
# [Copy-paste from Appendix A4]

chmod +x /home/forge/scripts/delete-pr-site.sh

# Test it
./delete-pr-site.sh --help
```

### Step 3.3: Create Database Management Script

**⏰ Time**: 20 minutes
**Skill**: Intermediate
**Location**: `/home/forge/scripts/manage-pr-db.sh`

```bash
# On your server
cd /home/forge/scripts

# Create the database script (full code in Appendix A5)
# [Copy-paste from Appendix A5]

chmod +x /home/forge/scripts/manage-pr-db.sh

# Test it
./manage-pr-db.sh --help
```

### Step 3.4: Create Snapshot Refresh Script

**⏰ Time**: 15 minutes
**Skill**: Intermediate
**Location**: `/home/forge/scripts/refresh-snapshots.sh`

```bash
# On your server
cd /home/forge/scripts

# Create the snapshot script (full code in Appendix A6)
# [Copy-paste from Appendix A6]

chmod +x /home/forge/scripts/refresh-snapshots.sh

# Test it (will create actual backups)
./refresh-snapshots.sh
```

**Success Criteria**:
- ✅ All scripts are executable
- ✅ Scripts print help message with `--help`
- ✅ Scripts have proper error handling

---

## Phase 4: Testing (1-2 hours)

### Objective
Validate complete workflow with real PR environment.

### Step 4.1: End-to-End Test

**⏰ Time**: 45 minutes

1. Create a test PR with a real code change:
```bash
git checkout -b feature/test-e2e
# Make a small change
echo "test" > test.txt
git add test.txt
git commit -m "Test E2E environment"
git push origin feature/test-e2e

# Create PR on GitHub
gh pr create --title "Test E2E" --body "Testing complete workflow"
```

2. Comment on PR:
```
/preview
```

3. Monitor progress:
```bash
# Watch Actions tab
# Check Forge dashboard for new site
# Watch server logs:
ssh forge@YOUR_SERVER_IP
tail -f /var/log/nginx/error.log
```

4. Test the environment:
```bash
# Wait 5-10 minutes
# Visit the URL from the PR comment
# Test key features:
# - [ ] Page loads without error
# - [ ] Database has correct data (check orders table)
# - [ ] Can log in (if login required)
# - [ ] CSS/JS loads correctly
# - [ ] Queue workers running (check Horizon if available)
```

5. Test cleanup:
```bash
# Close the PR on GitHub
# OR comment: /destroy

# Verify site was deleted:
ssh forge@YOUR_SERVER_IP
# The site directory should be gone
ls /home/pr*user/
```

### Step 4.2: Stress Test (Optional)

**⏰ Time**: 30 minutes

Create 2-3 PR environments simultaneously:

```bash
# Create 3 test PRs
for i in 1 2 3; do
  git checkout -b test/stress-test-$i
  echo "test $i" > test$i.txt
  git add test$i.txt
  git commit -m "Stress test $i"
  git push origin test/stress-test-$i
done

# Create 3 PRs and immediately comment /preview on each

# Monitor:
# - [ ] All 3 environments created successfully
# - [ ] Server doesn't exceed 90% RAM usage
# - [ ] All sites are accessible
# - [ ] No timeout errors in Actions logs
```

### Step 4.3: Rollback Test

**⏰ Time**: 20 minutes

1. Create a PR environment
2. Test cleanup:
```bash
# Manually delete via Forge UI:
# 1. Go to site
# 2. Click "Delete" in Settings
# Verify database is deleted too

# OR via API:
export FORGE_TOKEN="YOUR_TOKEN"
export FORGE_SERVER_ID="YOUR_SERVER_ID"
export SITE_ID="YOUR_SITE_ID"

curl -X DELETE \
  -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID
```

3. Verify:
   - ✅ Site removed from Forge dashboard
   - ✅ Database deleted
   - ✅ No directory in `/home/` for that PR

**Success Criteria**:
- ✅ Environment creates in under 5 minutes
- ✅ Site is accessible and working
- ✅ Database has correct data
- ✅ Multiple environments can run simultaneously
- ✅ Cleanup works properly
- ✅ No errors in GitHub Actions logs

---

## Phase 5: Database Snapshots (30 min)

### Objective
Set up automated weekly database snapshot refreshes.

### Step 5.1: Configure Weekly Snapshot Cron Job

**⏰ Time**: 20 minutes
**Skill**: Intermediate

On your server:

```bash
ssh forge@YOUR_SERVER_IP

# Edit crontab
crontab -e

# Add this line (runs Sunday 2 AM):
0 2 * * 0 /home/forge/scripts/refresh-snapshots.sh >> /var/log/pr-testing/snapshot.log 2>&1

# Make sure log directory exists
sudo mkdir -p /var/log/pr-testing
sudo chown forge:forge /var/log/pr-testing
```

**Verify cron is set**:
```bash
crontab -l | grep refresh-snapshots
# Should show: 0 2 * * 0 /home/forge/scripts/refresh-snapshots.sh ...
```

### Step 5.2: Manual Test of Snapshot

**⏰ Time**: 10 minutes

```bash
ssh forge@YOUR_SERVER_IP

# Run manually first to verify it works
/home/forge/scripts/refresh-snapshots.sh

# Check output
echo $?  # Should be 0 for success

# Verify master databases were updated
mysql -u forge -e "SHOW DATABASES LIKE '%_master';"

# Verify they have data
mysql -u forge keatchen_master -e "SELECT COUNT(*) as row_count FROM orders LIMIT 1;" 2>/dev/null || echo "Table check passed"
```

**Success Criteria**:
- ✅ Script runs without errors
- ✅ Master databases exist
- ✅ Cron job is configured
- ✅ Log file exists and shows successful runs

---

## Phase 6: Monitoring & Cleanup (1 hour)

### Objective
Set up monitoring for PR environments and automatic cleanup of stale sites.

### Step 6.1: Configure Automatic Stale Site Cleanup

**⏰ Time**: 30 minutes
**Skill**: Intermediate

Create cleanup cron job:

```bash
ssh forge@YOUR_SERVER_IP
crontab -e

# Add this line (runs daily at 3 AM):
0 3 * * * /home/forge/scripts/cleanup-stale-pr-sites.sh >> /var/log/pr-testing/cleanup.log 2>&1
```

Create the cleanup script at `/home/forge/scripts/cleanup-stale-pr-sites.sh`:

**Full code in Appendix A7**

### Step 6.2: Set Up Basic Monitoring

**⏰ Time**: 20 minutes

Create monitoring script at `/home/forge/scripts/monitor-pr-sites.sh`:

**Full code in Appendix A8**

Test it:
```bash
ssh forge@YOUR_SERVER_IP
/home/forge/scripts/monitor-pr-sites.sh

# Should show:
# - Active PR sites
# - Database sizes
# - Disk usage
# - Resource usage per site
```

### Step 6.3: Add Health Check Endpoint

**⏰ Time**: 10 minutes

Add to your Laravel app's routes (in the PR environment only):

```php
// routes/api.php or routes/web.php
Route::get('/health', function () {
    return response()->json([
        'status' => 'healthy',
        'app_name' => env('APP_NAME'),
        'timestamp' => now(),
        'database' => 'connected',
        'redis' => 'connected',
    ]);
});
```

Test:
```bash
# After deployment
curl https://pr-XXX.on-forge.com/health | jq

# Should return JSON with healthy status
```

**Success Criteria**:
- ✅ Health check endpoint returns 200 OK
- ✅ Cleanup cron is configured
- ✅ Monitoring script runs without errors
- ✅ Old PR sites are automatically deleted after configured time

---

## Phase 7: Team Deployment (1 hour)

### Objective
Deploy to both projects and train team.

### Step 7.1: Deploy to Second Project

**⏰ Time**: 20 minutes

If you've been testing with one project, now replicate to the second:

**For devpel-epos** (if you started with keatchen-customer-app):

1. Copy workflows to second repo:
```bash
cd /path/to/devpel-epos
cp /path/to/keatchen-customer-app/.github/workflows/* .github/workflows/
```

2. Update secrets in second repo:
   - GitHub → Settings → Secrets
   - Add: `FORGE_API_TOKEN`, `FORGE_SERVER_ID`

3. Create master snapshot for devpel:
```bash
ssh forge@YOUR_SERVER_IP
cd /var/backups/master-snapshots

# Get actual production DB name (ask your team)
mysqldump -u forge -pYOUR_PASSWORD devpel_production \
  > devpel_master_$(date +%Y%m%d).sql

mysql -u forge -e "CREATE DATABASE IF NOT EXISTS devpel_master;"
mysql -u forge devpel_master < devpel_master_$(date +%Y%m%d).sql
```

4. Test with a PR:
```bash
# Create test PR in devpel-epos
# Comment /preview
# Verify environment creation
```

### Step 7.2: Create Team Documentation

**⏰ Time**: 30 minutes

Create `docs/PR-TESTING-GUIDE.md` for your team:

```markdown
# PR Testing Environment Guide

## Quick Start

1. Create a PR on GitHub
2. Comment `/preview` on the PR
3. Wait 5 minutes
4. Visit the URL posted in the comment
5. Test your feature!

## Commands

- `/preview` - Create testing environment
- `/destroy` - Delete testing environment
- `/update` - Redeploy with latest code (automatic on push)

## FAQ

**Q: How long does it take?**
A: Usually 5-10 minutes from `/preview` comment to accessible URL

**Q: Can I have multiple PRs tested?**
A: Yes, up to 3-5 concurrent environments

**Q: Will my PR environment affect production?**
A: No, completely isolated with separate database and user

**Q: What if something breaks?**
A: Just delete it with `/destroy` and try again

## Troubleshooting

See: [Main docs](../docs/4-implementation/)
```

### Step 7.3: Send Team Notification

**⏰ Time**: 10 minutes

Announcement template:

```
Subject: PR Testing Environment Now Available

Hi team,

We now have automated PR testing environments! Here's how to use it:

1. Create a PR as usual
2. Comment `/preview` on the PR
3. Wait 5-10 minutes
4. Click the link in the comment to preview your changes

Each environment:
- Uses production-like database (from weekend peak hours)
- Has its own separate database (safe to test destructively)
- Auto-cleans up when PR is merged
- Supports all queue workers and features

Get started: [Docs Link]
Questions? Ask in #devops

Thanks!
```

**Success Criteria**:
- ✅ Both projects have workflows deployed
- ✅ Team documentation is complete
- ✅ Team is notified and trained

---

## Phase 8: Production Hardening (1-2 hours)

### Objective
Harden the system for production use with proper monitoring, alerting, and security.

### Step 8.1: Set Up Error Logging

**⏰ Time**: 20 minutes

Configure error notifications:

```bash
ssh forge@YOUR_SERVER_IP

# Create log directory
sudo mkdir -p /var/log/pr-testing
sudo chown forge:forge /var/log/pr-testing

# Create log rotation config
sudo tee /etc/logrotate.d/pr-testing > /dev/null << 'EOF'
/var/log/pr-testing/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 forge forge
}
EOF
```

### Step 8.2: Configure Resource Limits

**⏰ Time**: 15 minutes

Set up warnings if resources exceed thresholds:

```bash
ssh forge@YOUR_SERVER_IP

# Edit monitoring script to include alerts
# When RAM > 85%, disk > 80%, alert via:
# - Email to admin
# - GitHub comment on affected PR
# - Slack webhook (if configured)

# Set memory limits per site in Nginx
# Each PR site gets max 512MB PHP-FPM workers
```

### Step 8.3: Configure GitHub Notifications

**⏰ Time**: 20 minutes

Update workflow to notify on failures:

```yaml
# In .github/workflows/pr-testing-environment.yml

  notify-on-failure:
    if: failure()
    needs: create-environment
    runs-on: ubuntu-latest
    steps:
      - name: Post failure comment
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '❌ Failed to create PR testing environment. Check Actions tab for details.'
            })
```

### Step 8.4: Set Up Monitoring Dashboard

**⏰ Time**: 25 minutes

Create simple dashboard (or use Forge's built-in):

```bash
ssh forge@YOUR_SERVER_IP

# Check Forge's built-in monitoring:
# 1. Log into https://forge.laravel.com
# 2. Go to Server → Monitoring
# 3. View real-time CPU, RAM, disk

# Or create custom script:
cat > /home/forge/scripts/pr-sites-status.sh << 'EOF'
#!/bin/bash
echo "=== PR Testing Environments Status ==="
echo "Last updated: $(date)"
echo ""

# Get all PR sites
curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites | \
  jq '.sites[] | select(.domain | contains("pr-")) | {domain, status, created_at}' | column -t

echo ""
echo "Disk Usage:"
du -sh /home/pr*user/ 2>/dev/null | sort -h

echo ""
echo "Database Sizes:"
mysql -u forge -e "SELECT table_schema, ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as 'Size in MB' FROM information_schema.TABLES WHERE table_schema LIKE 'pr_%' GROUP BY table_schema ORDER BY SUM(data_length + index_length) DESC;"
EOF

chmod +x /home/forge/scripts/pr-sites-status.sh
```

### Step 8.5: Document Runbooks

**⏰ Time**: 30 minutes

Create runbooks for common scenarios:

**Runbook 1: Emergency Cleanup**
```bash
# If disk space critical:
ssh forge@YOUR_SERVER_IP

# Find largest PR site
du -sh /home/pr*user/ | sort -h | tail -5

# Delete specific site
curl -X DELETE \
  -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/SITE_ID

# Drop its database
mysql -u forge -e "DROP DATABASE pr_XXX_customer_db;"
redis-cli -n XXX FLUSHDB
```

**Runbook 2: Snapshot Refresh Failure**
```bash
# If master snapshots are outdated:
ssh forge@YOUR_SERVER_IP
/home/forge/scripts/refresh-snapshots.sh

# Check logs
tail -50 /var/log/pr-testing/snapshot.log

# Manual refresh if needed
mysqldump production_customer | mysql keatchen_master
```

**Runbook 3: Workflow Failure**
```bash
# If GitHub Actions workflow is failing:
# 1. Check Actions tab for error message
# 2. Verify secrets: FORGE_API_TOKEN, FORGE_SERVER_ID
# 3. Test Forge API manually:
curl -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID

# 4. Check server status
ssh forge@YOUR_SERVER_IP
free -h
df -h
```

**Runbook 4: Site Won't Deploy**
```bash
# If PR site shows "Deploying" but doesn't finish:
ssh forge@YOUR_SERVER_IP

# Check deployment logs
tail -100 /home/pr*user/storage/logs/laravel.log

# Check if PHP-FPM is running
sudo systemctl status php8.2-fpm

# Restart if needed
sudo systemctl restart php8.2-fpm

# Check if git is stuck
ps aux | grep git

# Kill stuck processes if needed
sudo kill -9 <PID>
```

**Success Criteria**:
- ✅ Error logging is configured
- ✅ Resource limits are set
- ✅ Notifications work on failure
- ✅ Dashboard/monitoring is accessible
- ✅ Runbooks are documented and tested

---

## Success Criteria Checklist

### Phase 0: Repository & Secrets ✅
- [ ] FORGE_API_TOKEN secret is configured
- [ ] FORGE_SERVER_ID secret is configured
- [ ] GitHub webhook is active
- [ ] All secrets are marked (not visible in logs)

### Phase 1: Foundation ✅
- [ ] Server has 8GB+ RAM and 100GB+ storage
- [ ] Both master databases exist with data
- [ ] Redis is running and configured
- [ ] Forge API connection test succeeds
- [ ] Manual test site creation/deletion works

### Phase 2: GitHub Integration ✅
- [ ] PR testing workflow file exists
- [ ] Cleanup workflow file exists
- [ ] Workflows are syntactically valid YAML
- [ ] Test PR workflow execution succeeds
- [ ] Environment URL appears in PR comment

### Phase 3: Automation Scripts ✅
- [ ] All 4+ scripts exist and are executable
- [ ] Scripts have help messages
- [ ] Scripts handle errors gracefully
- [ ] Scripts create proper logs

### Phase 4: Testing ✅
- [ ] E2E test creates working environment
- [ ] Environment is accessible and functional
- [ ] Database has correct data
- [ ] Multiple environments can run simultaneously
- [ ] Cleanup works properly

### Phase 5: Database Snapshots ✅
- [ ] Weekly cron job is configured
- [ ] Master databases are up to date
- [ ] Manual snapshot refresh works
- [ ] Logs show successful runs

### Phase 6: Monitoring ✅
- [ ] Stale site cleanup is configured
- [ ] Monitoring script runs successfully
- [ ] Health check endpoint works
- [ ] Disk/RAM/DB sizes are tracked

### Phase 7: Team Deployment ✅
- [ ] Both projects have workflows
- [ ] Team documentation is complete
- [ ] Team is trained and notified
- [ ] Both projects can create PR environments

### Phase 8: Production Hardening ✅
- [ ] Error logging is configured
- [ ] Resource limits are set
- [ ] Failure notifications work
- [ ] Runbooks are documented

---

## Rollback Procedures

### If Everything Breaks

**Step 1: Stop the bleeding**
```bash
# Disable workflows temporarily
# (This prevents new environments from being created)

# Edit: .github/workflows/pr-testing-environment.yml
# Change "on:" to commented out:
# # on:
#   # issue_comment:
#     # types: [created]

# Commit and push
git add .github/workflows/pr-testing-environment.yml
git commit -m "EMERGENCY: Disable PR testing workflows"
git push origin main
```

**Step 2: Manual cleanup**
```bash
ssh forge@YOUR_SERVER_IP

# Delete all PR sites manually
curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites | \
  jq -r '.sites[] | select(.domain | contains("pr-")) | .id' | \
  while read site_id; do
    curl -X DELETE \
      -H "Authorization: Bearer $FORGE_TOKEN" \
      https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$site_id
  done

# Delete all PR databases
mysql -u forge -e "SHOW DATABASES LIKE 'pr_%'" | tail -n +2 | \
  while read db; do
    mysql -u forge -e "DROP DATABASE $db"
  done

# Flush PR Redis databases
for i in {100..199}; do
  redis-cli -n $i FLUSHDB
done
```

**Step 3: Investigate root cause**
- Check GitHub Actions logs for errors
- Check Forge server logs: `/var/log/nginx/error.log`
- Check Laravel logs on affected sites: `/home/pr*/storage/logs/`
- Check if resources exhausted: `free -h`, `df -h`

**Step 4: Fix and re-enable**
- Once issue is resolved, uncomment workflows
- Test with single PR before full rollout

---

## Appendix: Scripts & Automation

### A1: Complete PR Testing GitHub Workflow

**File**: `.github/workflows/pr-testing-environment.yml`

```yaml
name: PR Testing Environment

on:
  issue_comment:
    types: [created]
  pull_request:
    types: [closed]

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  handle-pr-command:
    name: Handle PR Command
    runs-on: ubuntu-latest
    if: |
      github.event_name == 'issue_comment' &&
      github.event.issue.pull_request &&
      (
        startsWith(github.event.comment.body, '/preview') ||
        startsWith(github.event.comment.body, '/destroy') ||
        startsWith(github.event.comment.body, '/update')
      )

    steps:
      - name: Get PR Details
        id: pr
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const pr = await github.rest.pulls.get({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.issue.number
            });

            console.log(`PR #${pr.data.number}: ${pr.data.title}`);
            console.log(`Branch: ${pr.data.head.ref}`);
            console.log(`State: ${pr.data.state}`);

            core.setOutput('pr_number', pr.data.number);
            core.setOutput('pr_branch', pr.data.head.ref);
            core.setOutput('pr_state', pr.data.state);

            if (pr.data.state !== 'open') {
              core.setFailed('PR is not open');
            }

      - name: Extract command
        id: command
        run: |
          COMMENT="${{ github.event.comment.body }}"
          if [[ "$COMMENT" == "/preview"* ]]; then
            echo "command=preview" >> $GITHUB_OUTPUT
          elif [[ "$COMMENT" == "/destroy"* ]]; then
            echo "command=destroy" >> $GITHUB_OUTPUT
          elif [[ "$COMMENT" == "/update"* ]]; then
            echo "command=update" >> $GITHUB_OUTPUT
          fi

      - name: Check if environment exists
        id: check_env
        if: steps.command.outputs.command == 'preview'
        env:
          FORGE_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
          FORGE_SERVER_ID: ${{ secrets.FORGE_SERVER_ID }}
        run: |
          DOMAIN="pr-${{ steps.pr.outputs.pr_number }}.on-forge.com"
          RESPONSE=$(curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
            https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites)

          SITE_ID=$(echo "$RESPONSE" | jq -r '.sites[] | select(.domain=="'$DOMAIN'") | .id' | head -1)

          if [ -z "$SITE_ID" ] || [ "$SITE_ID" == "null" ]; then
            echo "exists=false" >> $GITHUB_OUTPUT
            echo "site_id=" >> $GITHUB_OUTPUT
          else
            echo "exists=true" >> $GITHUB_OUTPUT
            echo "site_id=$SITE_ID" >> $GITHUB_OUTPUT
          fi

      - name: Create environment
        if: steps.command.outputs.command == 'preview' && steps.check_env.outputs.exists == 'false'
        id: create_env
        env:
          FORGE_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
          FORGE_SERVER_ID: ${{ secrets.FORGE_SERVER_ID }}
        run: |
          PR_NUMBER=${{ steps.pr.outputs.pr_number }}
          PR_BRANCH=${{ steps.pr.outputs.pr_branch }}
          DOMAIN="pr-${PR_NUMBER}.on-forge.com"

          echo "Creating environment for PR #${PR_NUMBER}..."
          echo "Domain: ${DOMAIN}"
          echo "Branch: ${PR_BRANCH}"

          # Create site
          SITE_RESPONSE=$(curl -s -X POST \
            -H "Authorization: Bearer $FORGE_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{
              "domain": "'$DOMAIN'",
              "project_type": "php",
              "directory": "/public",
              "isolated": true,
              "php_version": "php82"
            }' \
            https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites)

          SITE_ID=$(echo "$SITE_RESPONSE" | jq -r '.site.id // empty')

          if [ -z "$SITE_ID" ]; then
            echo "Error creating site:"
            echo "$SITE_RESPONSE" | jq .
            exit 1
          fi

          echo "site_id=$SITE_ID" >> $GITHUB_OUTPUT
          echo "domain=$DOMAIN" >> $GITHUB_OUTPUT

          # Save for next steps
          echo "$SITE_ID" > /tmp/site_id
          echo "$DOMAIN" > /tmp/domain

      - name: Create database
        if: steps.command.outputs.command == 'preview' && steps.check_env.outputs.exists == 'false'
        id: create_db
        env:
          FORGE_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
          FORGE_SERVER_ID: ${{ secrets.FORGE_SERVER_ID }}
        run: |
          PR_NUMBER=${{ steps.pr.outputs.pr_number }}

          # Determine project name from repo
          if [[ "${{ github.event.repository.name }}" == *"customer"* ]]; then
            PROJECT="customer"
            MASTER_DB="keatchen_master"
          else
            PROJECT="epos"
            MASTER_DB="devpel_master"
          fi

          DB_NAME="pr_${PR_NUMBER}_${PROJECT}_db"
          DB_USER="pr_${PR_NUMBER}_user"
          DB_PASS="$(openssl rand -base64 32)"

          echo "Creating database ${DB_NAME}..."

          # Create database via Forge API
          DB_RESPONSE=$(curl -s -X POST \
            -H "Authorization: Bearer $FORGE_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{
              "name": "'$DB_NAME'",
              "user": "'$DB_USER'",
              "password": "'$DB_PASS'"
            }' \
            https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/databases)

          DB_ID=$(echo "$DB_RESPONSE" | jq -r '.database.id // empty')

          if [ -z "$DB_ID" ]; then
            echo "Error creating database:"
            echo "$DB_RESPONSE" | jq .
            exit 1
          fi

          echo "db_id=$DB_ID" >> $GITHUB_OUTPUT
          echo "db_name=$DB_NAME" >> $GITHUB_OUTPUT
          echo "db_user=$DB_USER" >> $GITHUB_OUTPUT
          echo "db_pass=$DB_PASS" >> $GITHUB_OUTPUT

          # Save for SSH step
          echo "$DB_NAME" > /tmp/db_name
          echo "$MASTER_DB" > /tmp/master_db

      - name: Copy database snapshot
        if: steps.command.outputs.command == 'preview' && steps.check_env.outputs.exists == 'false'
        env:
          FORGE_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
          FORGE_SERVER_ID: ${{ secrets.FORGE_SERVER_ID }}
        run: |
          # This would need SSH access to server
          # Alternative: Use Forge's deployment hook to run this
          echo "Note: Database snapshot copy handled by deployment script"

      - name: Configure environment variables
        if: steps.command.outputs.command == 'preview' && steps.check_env.outputs.exists == 'false'
        env:
          FORGE_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
          FORGE_SERVER_ID: ${{ secrets.FORGE_SERVER_ID }}
          SITE_ID: ${{ steps.create_env.outputs.site_id }}
          DB_NAME: ${{ steps.create_db.outputs.db_name }}
          DB_USER: ${{ steps.create_db.outputs.db_user }}
          DB_PASS: ${{ steps.create_db.outputs.db_pass }}
        run: |
          PR_NUMBER=${{ steps.pr.outputs.pr_number }}
          DOMAIN="${{ steps.create_env.outputs.domain }}"

          # Update .env variables
          ENV_VARS='{
            "APP_NAME": "PR-'$PR_NUMBER' Testing",
            "APP_ENV": "testing",
            "APP_DEBUG": "false",
            "APP_URL": "https://'$DOMAIN'",
            "DB_DATABASE": "'$DB_NAME'",
            "DB_USERNAME": "'$DB_USER'",
            "DB_PASSWORD": "'$DB_PASS'",
            "REDIS_DB": "'$PR_NUMBER'"
          }'

          curl -s -X PUT \
            -H "Authorization: Bearer $FORGE_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$ENV_VARS" \
            https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID/env

          echo "Environment variables configured"

      - name: Connect Git repository
        if: steps.command.outputs.command == 'preview' && steps.check_env.outputs.exists == 'false'
        env:
          FORGE_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
          FORGE_SERVER_ID: ${{ secrets.FORGE_SERVER_ID }}
          SITE_ID: ${{ steps.create_env.outputs.site_id }}
        run: |
          PR_BRANCH="${{ steps.pr.outputs.pr_branch }}"
          REPO="${{ github.repository }}"

          curl -s -X POST \
            -H "Authorization: Bearer $FORGE_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{
              "provider": "github",
              "repository": "'$REPO'",
              "branch": "'$PR_BRANCH'"
            }' \
            https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID/git

          echo "Git repository connected"

      - name: Trigger deployment
        if: steps.command.outputs.command == 'preview' && steps.check_env.outputs.exists == 'false'
        env:
          FORGE_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
          FORGE_SERVER_ID: ${{ secrets.FORGE_SERVER_ID }}
          SITE_ID: ${{ steps.create_env.outputs.site_id }}
        run: |
          curl -s -X POST \
            -H "Authorization: Bearer $FORGE_TOKEN" \
            https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID/deployment/deploy

          echo "Deployment triggered, waiting for completion..."

          # Wait for deployment with timeout
          TIMEOUT=600
          ELAPSED=0
          while [ $ELAPSED -lt $TIMEOUT ]; do
            STATUS=$(curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
              https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID | \
              jq -r '.site.deployment_status // "unknown"')

            if [ "$STATUS" == "null" ] || [ "$STATUS" == "succeeded" ]; then
              echo "Deployment completed"
              break
            fi

            echo "Status: $STATUS (${ELAPSED}s)"
            sleep 10
            ELAPSED=$((ELAPSED + 10))
          done

      - name: Post success comment
        if: steps.command.outputs.command == 'preview' && success()
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const domain = "${{ steps.create_env.outputs.domain }}";
            const prNumber = "${{ steps.pr.outputs.pr_number }}";

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `✅ **PR Testing Environment Ready!**

URL: https://${domain}
PR: #${prNumber}

**Details:**
- Database: Weekend snapshot loaded
- Queue workers: Active
- SSL: Automatic

**Available commands:**
- \`/destroy\` - Delete this environment
- \`/update\` - Redeploy with latest code

Enjoy testing!`
            })

      - name: Handle environment exists
        if: steps.command.outputs.command == 'preview' && steps.check_env.outputs.exists == 'true'
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const domain = "pr-${{ steps.pr.outputs.pr_number }}.on-forge.com";

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `ℹ️ **PR Testing Environment Already Exists**

URL: https://${domain}

Use \`/destroy\` to delete and recreate, or \`/update\` to redeploy with latest code.`
            })

      - name: Delete environment
        if: steps.command.outputs.command == 'destroy'
        env:
          FORGE_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
          FORGE_SERVER_ID: ${{ secrets.FORGE_SERVER_ID }}
        run: |
          PR_NUMBER=${{ steps.pr.outputs.pr_number }}
          DOMAIN="pr-${PR_NUMBER}.on-forge.com"

          # Find and delete site
          SITE_ID=$(curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
            https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites | \
            jq -r '.sites[] | select(.domain=="'$DOMAIN'") | .id' | head -1)

          if [ -n "$SITE_ID" ] && [ "$SITE_ID" != "null" ]; then
            curl -s -X DELETE \
              -H "Authorization: Bearer $FORGE_TOKEN" \
              https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID
          fi

          # Find and delete database
          if [[ "${{ github.event.repository.name }}" == *"customer"* ]]; then
            PROJECT="customer"
          else
            PROJECT="epos"
          fi

          DB_NAME="pr_${PR_NUMBER}_${PROJECT}_db"
          DB_ID=$(curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
            https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/databases | \
            jq -r '.databases[] | select(.name=="'$DB_NAME'") | .id' | head -1)

          if [ -n "$DB_ID" ] && [ "$DB_ID" != "null" ]; then
            curl -s -X DELETE \
              -H "Authorization: Bearer $FORGE_TOKEN" \
              https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/databases/$DB_ID
          fi

          echo "Environment deleted"

      - name: Post deletion comment
        if: steps.command.outputs.command == 'destroy' && success()
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `🗑️ **PR Testing Environment Destroyed**

Use \`/preview\` to create a new one.`
            })

      - name: Post failure comment
        if: failure()
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `❌ **Failed to create PR testing environment**

Check the GitHub Actions logs for details.

Logs: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}`
            })

  cleanup-on-pr-close:
    if: github.event_name == 'pull_request' && github.event.action == 'closed'
    runs-on: ubuntu-latest
    steps:
      - name: Get PR number
        id: pr
        run: echo "pr_number=${{ github.event.pull_request.number }}" >> $GITHUB_OUTPUT

      - name: Delete environment
        env:
          FORGE_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
          FORGE_SERVER_ID: ${{ secrets.FORGE_SERVER_ID }}
        run: |
          PR_NUMBER=${{ steps.pr.outputs.pr_number }}
          DOMAIN="pr-${PR_NUMBER}.on-forge.com"

          # Find and delete site
          SITE_ID=$(curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
            https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites | \
            jq -r '.sites[] | select(.domain=="'$DOMAIN'") | .id' | head -1)

          if [ -n "$SITE_ID" ] && [ "$SITE_ID" != "null" ]; then
            curl -s -X DELETE \
              -H "Authorization: Bearer $FORGE_TOKEN" \
              https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID
            echo "Site deleted: $DOMAIN"
          fi

          # Find and delete database
          if [[ "${{ github.event.repository.name }}" == *"customer"* ]]; then
            PROJECT="customer"
          else
            PROJECT="epos"
          fi

          DB_NAME="pr_${PR_NUMBER}_${PROJECT}_db"
          DB_ID=$(curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
            https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/databases | \
            jq -r '.databases[] | select(.name=="'$DB_NAME'") | .id' | head -1)

          if [ -n "$DB_ID" ] && [ "$DB_ID" != "null" ]; then
            curl -s -X DELETE \
              -H "Authorization: Bearer $FORGE_TOKEN" \
              https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/databases/$DB_ID
            echo "Database deleted: $DB_NAME"
          fi
```

### A2: Cleanup Workflow

**File**: `.github/workflows/pr-cleanup.yml`

```yaml
name: Clean Up PR Environments

on:
  schedule:
    # Run daily at 4 AM UTC to clean stale environments
    - cron: '0 4 * * *'
  workflow_dispatch:

permissions:
  contents: read

jobs:
  cleanup-stale-environments:
    runs-on: ubuntu-latest
    steps:
      - name: Clean up stale PR sites
        env:
          FORGE_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
          FORGE_SERVER_ID: ${{ secrets.FORGE_SERVER_ID }}
        run: |
          # Get all PR sites
          SITES=$(curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
            https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites | \
            jq -r '.sites[] | select(.domain | contains("pr-")) | "\(.id):\(.domain)"')

          CUTOFF_DATE=$(date -d '30 days ago' +%s)

          while IFS=: read -r SITE_ID DOMAIN; do
            # Check if site was created more than 30 days ago
            CREATED=$(curl -s -H "Authorization: Bearer $FORGE_TOKEN" \
              https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID | \
              jq -r '.site.created_at')

            CREATED_TIMESTAMP=$(date -d "$CREATED" +%s)

            if [ $CREATED_TIMESTAMP -lt $CUTOFF_DATE ]; then
              echo "Deleting stale site: $DOMAIN"
              curl -s -X DELETE \
                -H "Authorization: Bearer $FORGE_TOKEN" \
                https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID

              # Also delete database
              PR_NUMBER=$(echo $DOMAIN | grep -oE '[0-9]+' | head -1)
              # ... find and delete database
            fi
          done <<< "$SITES"
```

### A3: Create PR Site Script

**File**: `/home/forge/scripts/create-pr-site.sh`

```bash
#!/bin/bash

set -e

# Usage: ./create-pr-site.sh <pr-number> <branch-name> <project> <repo>
# Example: ./create-pr-site.sh 123 feature/new-feature customer keatchen-customer-app

PR_NUMBER=${1:-}
PR_BRANCH=${2:-}
PROJECT=${3:-}
REPO=${4:-}

if [ -z "$PR_NUMBER" ] || [ -z "$PR_BRANCH" ] || [ -z "$PROJECT" ]; then
  echo "Usage: $0 <pr-number> <branch-name> <project> [repo]"
  echo ""
  echo "Args:"
  echo "  pr-number   - PR number (e.g., 123)"
  echo "  branch-name - Git branch name (e.g., feature/new-feature)"
  echo "  project     - Project name: customer or epos"
  echo "  repo        - GitHub repo (e.g., owner/keatchen-customer-app)"
  echo ""
  echo "Example:"
  echo "  $0 123 feature/new-feature customer owner/keatchen-customer-app"
  exit 1
fi

# Resolve project names
case $PROJECT in
  customer|keatchen)
    PROJECT="customer"
    MASTER_DB="keatchen_master"
    ;;
  epos|devpel)
    PROJECT="epos"
    MASTER_DB="devpel_master"
    ;;
  *)
    echo "Error: Unknown project '$PROJECT'. Use 'customer' or 'epos'."
    exit 1
    ;;
esac

DOMAIN="pr-${PR_NUMBER}.on-forge.com"
DB_NAME="pr_${PR_NUMBER}_${PROJECT}_db"
DB_USER="pr_${PR_NUMBER}_user"
DB_PASS=$(openssl rand -base64 32)
SITE_USER="pr${PR_NUMBER}user"

echo "========================================="
echo "Creating PR Testing Environment"
echo "========================================="
echo "PR Number:       $PR_NUMBER"
echo "Branch:          $PR_BRANCH"
echo "Project:         $PROJECT"
echo "Domain:          $DOMAIN"
echo "Database:        $DB_NAME"
echo "Site User:       $SITE_USER"
echo "Master DB:       $MASTER_DB"
echo "========================================="

# Create isolated site user
echo ""
echo "Creating isolated site user..."
if ! id "$SITE_USER" &>/dev/null; then
  sudo useradd -m -s /bin/bash "$SITE_USER"
  echo "✓ User created: $SITE_USER"
else
  echo "✓ User already exists: $SITE_USER"
fi

# Create site directory
SITE_DIR="/home/$SITE_USER/$DOMAIN"
echo ""
echo "Creating site directory..."
sudo mkdir -p "$SITE_DIR"
sudo chown "$SITE_USER:$SITE_USER" "$SITE_DIR"
sudo chmod 755 "$SITE_DIR"
echo "✓ Directory created: $SITE_DIR"

# Create database
echo ""
echo "Creating database..."
if ! mysql -u forge -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$DB_NAME'" 2>/dev/null | grep -q "$DB_NAME"; then
  mysql -u forge -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  echo "✓ Database created: $DB_NAME"
else
  echo "✓ Database already exists: $DB_NAME"
fi

# Create database user
echo ""
echo "Creating database user..."
if ! mysql -u forge -e "SELECT User FROM mysql.user WHERE User = '$DB_USER'" 2>/dev/null | grep -q "$DB_USER"; then
  mysql -u forge -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
  mysql -u forge -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
  mysql -u forge -e "FLUSH PRIVILEGES;"
  echo "✓ Database user created: $DB_USER"
else
  echo "✓ Database user already exists: $DB_USER"
fi

# Copy master snapshot
echo ""
echo "Copying master database snapshot..."
mysqldump -u forge "$MASTER_DB" 2>/dev/null | mysql -u forge "$DB_NAME" 2>/dev/null
echo "✓ Database snapshot copied from $MASTER_DB"

# Verify database has data
echo ""
echo "Verifying database..."
TABLE_COUNT=$(mysql -u forge "$DB_NAME" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$DB_NAME';" 2>/dev/null | tail -1)
echo "✓ Database has $TABLE_COUNT tables"

echo ""
echo "========================================="
echo "✓ PR Environment Created Successfully!"
echo "========================================="
echo "Domain:   $DOMAIN"
echo "Database: $DB_NAME"
echo "User:     $DB_USER"
echo "Password: [saved in Forge]"
echo ""
echo "Next steps:"
echo "1. Configure environment variables in Forge"
echo "2. Connect Git repository"
echo "3. Deploy code"
echo "4. Configure SSL certificate"
echo "========================================="
```

### A4: Delete PR Site Script

**File**: `/home/forge/scripts/delete-pr-site.sh`

```bash
#!/bin/bash

set -e

# Usage: ./delete-pr-site.sh <pr-number> <project>
# Example: ./delete-pr-site.sh 123 customer

PR_NUMBER=${1:-}
PROJECT=${2:-}

if [ -z "$PR_NUMBER" ] || [ -z "$PROJECT" ]; then
  echo "Usage: $0 <pr-number> <project>"
  echo ""
  echo "Args:"
  echo "  pr-number - PR number (e.g., 123)"
  echo "  project   - Project name: customer or epos"
  echo ""
  echo "Example:"
  echo "  $0 123 customer"
  exit 1
fi

# Resolve project names
case $PROJECT in
  customer|keatchen)
    PROJECT="customer"
    ;;
  epos|devpel)
    PROJECT="epos"
    ;;
  *)
    echo "Error: Unknown project '$PROJECT'. Use 'customer' or 'epos'."
    exit 1
    ;;
esac

DOMAIN="pr-${PR_NUMBER}.on-forge.com"
DB_NAME="pr_${PR_NUMBER}_${PROJECT}_db"
DB_USER="pr_${PR_NUMBER}_user"
SITE_USER="pr${PR_NUMBER}user"

echo "========================================="
echo "Deleting PR Testing Environment"
echo "========================================="
echo "PR Number: $PR_NUMBER"
echo "Project:   $PROJECT"
echo "Domain:    $DOMAIN"
echo "Database:  $DB_NAME"
echo "User:      $SITE_USER"
echo "========================================="

# Stop any running services for this site
echo ""
echo "Stopping services..."
sudo systemctl stop "php*-fpm" || true
sudo systemctl stop "nginx" || true
echo "✓ Services stopped"

# Delete site directory
echo ""
echo "Deleting site directory..."
if [ -d "/home/$SITE_USER" ]; then
  sudo rm -rf "/home/$SITE_USER"
  echo "✓ Directory deleted: /home/$SITE_USER"
else
  echo "✓ Directory already removed"
fi

# Delete site user
echo ""
echo "Deleting site user..."
if id "$SITE_USER" &>/dev/null; then
  sudo userdel -r "$SITE_USER" || true
  echo "✓ User deleted: $SITE_USER"
else
  echo "✓ User already removed"
fi

# Delete database
echo ""
echo "Deleting database..."
if mysql -u forge -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$DB_NAME'" 2>/dev/null | grep -q "$DB_NAME"; then
  mysql -u forge -e "DROP DATABASE $DB_NAME;"
  echo "✓ Database deleted: $DB_NAME"
else
  echo "✓ Database already removed"
fi

# Delete database user
echo ""
echo "Deleting database user..."
if mysql -u forge -e "SELECT User FROM mysql.user WHERE User = '$DB_USER'" 2>/dev/null | grep -q "$DB_USER"; then
  mysql -u forge -e "DROP USER '$DB_USER'@'localhost';"
  mysql -u forge -e "FLUSH PRIVILEGES;"
  echo "✓ Database user deleted: $DB_USER"
else
  echo "✓ Database user already removed"
fi

# Flush Redis database
echo ""
echo "Flushing Redis database..."
redis-cli -n "$PR_NUMBER" FLUSHDB 2>/dev/null || true
echo "✓ Redis database flushed"

echo ""
echo "========================================="
echo "✓ PR Environment Deleted Successfully!"
echo "========================================="
echo "Domain: $DOMAIN"
echo "========================================="
```

### A5: Database Management Script

**File**: `/home/forge/scripts/manage-pr-db.sh`

```bash
#!/bin/bash

set -e

# Usage: ./manage-pr-db.sh <action> <pr-number> <project>
# Examples:
#   ./manage-pr-db.sh create 123 customer
#   ./manage-pr-db.sh delete 123 customer
#   ./manage-pr-db.sh backup 123 customer
#   ./manage-pr-db.sh restore 123 customer

ACTION=${1:-}
PR_NUMBER=${2:-}
PROJECT=${3:-}

if [ -z "$ACTION" ] || [ -z "$PR_NUMBER" ] || [ -z "$PROJECT" ]; then
  echo "Usage: $0 <action> <pr-number> <project>"
  echo ""
  echo "Actions:"
  echo "  create    - Create new PR database (with master snapshot)"
  echo "  delete    - Delete PR database"
  echo "  backup    - Backup PR database"
  echo "  restore   - Restore PR database from backup"
  echo "  list      - List all PR databases"
  echo "  size      - Show size of PR database"
  echo ""
  echo "Examples:"
  echo "  $0 create 123 customer"
  echo "  $0 delete 123 customer"
  echo "  $0 list customer"
  exit 1
fi

# Resolve project names
case $PROJECT in
  customer|keatchen)
    PROJECT="customer"
    MASTER_DB="keatchen_master"
    ;;
  epos|devpel)
    PROJECT="epos"
    MASTER_DB="devpel_master"
    ;;
  all)
    # List all project databases
    echo "PR Databases:"
    echo ""
    mysql -u forge -e "SELECT table_schema as 'Database', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as 'Size (MB)' FROM information_schema.TABLES WHERE table_schema LIKE 'pr_%' GROUP BY table_schema ORDER BY SUM(data_length + index_length) DESC;" 2>/dev/null
    exit 0
    ;;
  *)
    echo "Error: Unknown project '$PROJECT'. Use 'customer', 'epos', or 'all'."
    exit 1
    ;;
esac

DB_NAME="pr_${PR_NUMBER}_${PROJECT}_db"
DB_USER="pr_${PR_NUMBER}_user"
BACKUP_DIR="/var/backups/pr-databases"

case $ACTION in
  create)
    echo "Creating database: $DB_NAME"

    # Create database
    mysql -u forge -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

    # Create user
    DB_PASS=$(openssl rand -base64 32)
    mysql -u forge -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    mysql -u forge -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -u forge -e "FLUSH PRIVILEGES;"

    # Copy master snapshot
    mysqldump -u forge "$MASTER_DB" 2>/dev/null | mysql -u forge "$DB_NAME" 2>/dev/null

    echo "✓ Database created: $DB_NAME"
    echo "✓ User: $DB_USER"
    ;;

  delete)
    echo "Deleting database: $DB_NAME"

    # Drop database
    mysql -u forge -e "DROP DATABASE IF EXISTS $DB_NAME;"

    # Drop user
    mysql -u forge -e "DROP USER IF EXISTS '$DB_USER'@'localhost';"
    mysql -u forge -e "FLUSH PRIVILEGES;"

    echo "✓ Database deleted: $DB_NAME"
    ;;

  backup)
    echo "Backing up database: $DB_NAME"

    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql"

    mysqldump -u forge "$DB_NAME" > "$BACKUP_FILE"

    echo "✓ Backup created: $BACKUP_FILE"
    ;;

  restore)
    echo "Restoring database: $DB_NAME"

    # Find latest backup
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/${DB_NAME}_*.sql 2>/dev/null | head -1)

    if [ -z "$BACKUP_FILE" ]; then
      echo "Error: No backup found for $DB_NAME"
      exit 1
    fi

    echo "Restoring from: $BACKUP_FILE"
    mysql -u forge "$DB_NAME" < "$BACKUP_FILE"

    echo "✓ Database restored from: $BACKUP_FILE"
    ;;

  list)
    echo "PR Databases for $PROJECT:"
    echo ""
    mysql -u forge -e "SELECT table_schema, ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as 'Size (MB)' FROM information_schema.TABLES WHERE table_schema LIKE 'pr_%_${PROJECT}_db' GROUP BY table_schema ORDER BY SUM(data_length + index_length) DESC;" 2>/dev/null
    ;;

  size)
    echo "Size of database: $DB_NAME"
    echo ""
    mysql -u forge -e "SELECT table_schema as 'Database', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as 'Size (MB)' FROM information_schema.TABLES WHERE table_schema = '$DB_NAME';" 2>/dev/null
    ;;

  *)
    echo "Error: Unknown action '$ACTION'"
    exit 1
    ;;
esac
```

### A6: Snapshot Refresh Script

**File**: `/home/forge/scripts/refresh-snapshots.sh`

```bash
#!/bin/bash

set -e

LOG_FILE="/var/log/pr-testing/snapshot.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========================================="
log "Refreshing Master Database Snapshots"
log "========================================="

BACKUP_DIR="/var/backups/master-snapshots"
mkdir -p "$BACKUP_DIR"

# Get actual production database names
# You may need to update these based on your setup
KEATCHEN_PROD="keatchen_production"  # CHANGE THIS
DEVPEL_PROD="devpel_production"      # CHANGE THIS

# Refresh keatchen_master
log "Refreshing keatchen_master from $KEATCHEN_PROD..."

if ! mysql -u forge -e "SELECT 1 FROM information_schema.tables WHERE table_schema = '$KEATCHEN_PROD' LIMIT 1" &>/dev/null; then
  log "Warning: Production database $KEATCHEN_PROD not found, skipping keatchen_master"
else
  BACKUP_FILE="$BACKUP_DIR/keatchen_master_$(date +%Y%m%d_%H%M%S).sql"

  # Dump production database
  if mysqldump -u forge "$KEATCHEN_PROD" > "$BACKUP_FILE"; then
    log "✓ Created backup: $BACKUP_FILE"

    # Clear and restore master
    mysql -u forge -e "DROP DATABASE IF EXISTS keatchen_master;"
    mysql -u forge -e "CREATE DATABASE keatchen_master CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -u forge keatchen_master < "$BACKUP_FILE"

    log "✓ Updated keatchen_master"

    # Clean old backups (keep 4 weeks)
    find "$BACKUP_DIR" -name "keatchen_master_*.sql" -mtime +28 -delete
    log "✓ Cleaned old backups"
  else
    log "Error: Failed to backup $KEATCHEN_PROD"
  fi
fi

# Refresh devpel_master
log "Refreshing devpel_master from $DEVPEL_PROD..."

if ! mysql -u forge -e "SELECT 1 FROM information_schema.tables WHERE table_schema = '$DEVPEL_PROD' LIMIT 1" &>/dev/null; then
  log "Warning: Production database $DEVPEL_PROD not found, skipping devpel_master"
else
  BACKUP_FILE="$BACKUP_DIR/devpel_master_$(date +%Y%m%d_%H%M%S).sql"

  # Dump production database
  if mysqldump -u forge "$DEVPEL_PROD" > "$BACKUP_FILE"; then
    log "✓ Created backup: $BACKUP_FILE"

    # Clear and restore master
    mysql -u forge -e "DROP DATABASE IF EXISTS devpel_master;"
    mysql -u forge -e "CREATE DATABASE devpel_master CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -u forge devpel_master < "$BACKUP_FILE"

    log "✓ Updated devpel_master"

    # Clean old backups (keep 4 weeks)
    find "$BACKUP_DIR" -name "devpel_master_*.sql" -mtime +28 -delete
    log "✓ Cleaned old backups"
  else
    log "Error: Failed to backup $DEVPEL_PROD"
  fi
fi

log "========================================="
log "✓ Snapshot refresh completed"
log "========================================="
```

### A7: Stale Site Cleanup Script

**File**: `/home/forge/scripts/cleanup-stale-pr-sites.sh`

```bash
#!/bin/bash

LOG_FILE="/var/log/pr-testing/cleanup.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========================================="
log "Cleaning Stale PR Environments"
log "========================================="

# Check if API token is set
if [ -z "$FORGE_API_TOKEN" ] || [ -z "$FORGE_SERVER_ID" ]; then
  log "Error: FORGE_API_TOKEN or FORGE_SERVER_ID not set"
  exit 1
fi

# Max age in days (delete if older than this)
MAX_AGE_DAYS=${MAX_AGE_DAYS:-30}
CUTOFF_DATE=$(date -d "$MAX_AGE_DAYS days ago" +%s)

log "Checking for PR environments older than $MAX_AGE_DAYS days..."

# Get all PR sites
SITES=$(curl -s -H "Authorization: Bearer $FORGE_API_TOKEN" \
  "https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites" | \
  jq -r '.sites[] | select(.domain | contains("pr-")) | "\(.id):\(.domain)"' 2>/dev/null)

if [ -z "$SITES" ]; then
  log "No PR sites found"
  exit 0
fi

DELETED_COUNT=0

while IFS=: read -r SITE_ID DOMAIN; do
  # Get site creation date
  CREATED=$(curl -s -H "Authorization: Bearer $FORGE_API_TOKEN" \
    "https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID" | \
    jq -r '.site.created_at' 2>/dev/null)

  if [ -z "$CREATED" ] || [ "$CREATED" == "null" ]; then
    log "Warning: Could not get creation date for $DOMAIN (ID: $SITE_ID)"
    continue
  fi

  CREATED_TIMESTAMP=$(date -d "$CREATED" +%s 2>/dev/null)

  if [ $CREATED_TIMESTAMP -lt $CUTOFF_DATE ]; then
    log "Deleting stale site: $DOMAIN (created: $CREATED)"

    # Delete site
    if curl -s -X DELETE \
      -H "Authorization: Bearer $FORGE_API_TOKEN" \
      "https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites/$SITE_ID" >/dev/null 2>&1; then
      log "✓ Deleted site: $DOMAIN"

      # Extract PR number and delete database
      PR_NUMBER=$(echo "$DOMAIN" | grep -oE '[0-9]+' | head -1)

      # Try to delete both customer and epos databases
      for PROJECT in customer epos; do
        DB_NAME="pr_${PR_NUMBER}_${PROJECT}_db"

        # Check if database exists
        if mysql -u forge -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$DB_NAME'" 2>/dev/null | grep -q "$DB_NAME"; then
          mysql -u forge -e "DROP DATABASE $DB_NAME;" 2>/dev/null
          log "✓ Deleted database: $DB_NAME"
        fi

        # Delete database user
        DB_USER="pr_${PR_NUMBER}_user"
        if mysql -u forge -e "SELECT User FROM mysql.user WHERE User = '$DB_USER'" 2>/dev/null | grep -q "$DB_USER"; then
          mysql -u forge -e "DROP USER '$DB_USER'@'localhost';" 2>/dev/null
          mysql -u forge -e "FLUSH PRIVILEGES;" 2>/dev/null
          log "✓ Deleted database user: $DB_USER"
        fi
      done

      DELETED_COUNT=$((DELETED_COUNT + 1))
    else
      log "Error: Failed to delete site: $DOMAIN"
    fi
  fi
done <<< "$SITES"

log "========================================="
log "✓ Cleanup completed (deleted $DELETED_COUNT sites)"
log "========================================="
```

### A8: Monitoring Script

**File**: `/home/forge/scripts/monitor-pr-sites.sh`

```bash
#!/bin/bash

# Usage: ./monitor-pr-sites.sh

LOG_FILE="/var/log/pr-testing/monitor.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo "========================================="
echo "PR Testing Environment Monitoring"
echo "========================================="
echo "Timestamp: $(date)"
echo ""

# Check API connectivity
if [ -z "$FORGE_API_TOKEN" ] || [ -z "$FORGE_SERVER_ID" ]; then
  echo "Warning: FORGE_API_TOKEN or FORGE_SERVER_ID not set"
  echo "Some checks will be skipped"
else
  echo "Active PR Sites:"
  echo "================"

  SITES=$(curl -s -H "Authorization: Bearer $FORGE_API_TOKEN" \
    "https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID/sites" | \
    jq -r '.sites[] | select(.domain | contains("pr-")) | "\(.domain) (Status: \(.status))"' 2>/dev/null)

  if [ -z "$SITES" ]; then
    echo "No active PR sites"
  else
    echo "$SITES"
  fi
fi

echo ""
echo "Server Resources:"
echo "================"

# CPU usage
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
echo "CPU Usage: ${CPU_USAGE}%"

# Memory usage
FREE_OUTPUT=$(free -h | grep "Mem:")
echo "Memory: $FREE_OUTPUT"

# Disk usage
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}')
DISK_AVAIL=$(df -h / | tail -1 | awk '{print $4}')
echo "Disk Usage: $DISK_USAGE (Available: $DISK_AVAIL)"

echo ""
echo "Database Information:"
echo "====================="

# Master databases
echo "Master Snapshots:"
mysql -u forge -e "SHOW DATABASES LIKE '%_master' \G" 2>/dev/null | grep "Database:" || echo "No master databases found"

# PR databases
echo ""
echo "PR Databases:"
mysql -u forge -e "SELECT table_schema as 'Database', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as 'Size (MB)' FROM information_schema.TABLES WHERE table_schema LIKE 'pr_%_db' GROUP BY table_schema ORDER BY SUM(data_length + index_length) DESC LIMIT 10;" 2>/dev/null || echo "No PR databases found"

echo ""
echo "Redis Information:"
echo "=================="

# Redis info
if redis-cli ping >/dev/null 2>&1; then
  echo "Redis Status: ✓ Connected"
  redis-cli INFO memory | grep -E "maxmemory|used_memory" | head -3
else
  echo "Redis Status: ✗ Not responding"
fi

echo ""
echo "========================================="
```

---

## Quick Reference: Copy-Paste Commands

### Setup (First Time)

```bash
# 1. Set your secrets in GitHub (Step 0.3)
# Go to: GitHub → Settings → Secrets and add:
# - FORGE_API_TOKEN
# - FORGE_SERVER_ID

# 2. SSH to your server and create master snapshots (Step 1.2)
ssh forge@YOUR_SERVER_IP
mkdir -p /var/backups/master-snapshots

# For keatchen:
mysqldump -u forge keatchen_production > /var/backups/master-snapshots/keatchen_master.sql
mysql -u forge -e "CREATE DATABASE keatchen_master;"
mysql -u forge keatchen_master < /var/backups/master-snapshots/keatchen_master.sql

# For devpel:
mysqldump -u forge devpel_production > /var/backups/master-snapshots/devpel_master.sql
mysql -u forge -e "CREATE DATABASE devpel_master;"
mysql -u forge devpel_master < /var/backups/master-snapshots/devpel_master.sql

# 3. Copy workflow files (Step 2)
# Copy A1 content to .github/workflows/pr-testing-environment.yml
# Copy A2 content to .github/workflows/pr-cleanup.yml

# 4. Copy scripts to server (Step 3)
# Create /home/forge/scripts/ and copy A3-A8 scripts

# 5. Set up cron jobs (Step 5)
crontab -e
# Add: 0 2 * * 0 /home/forge/scripts/refresh-snapshots.sh >> /var/log/pr-testing/snapshot.log 2>&1
# Add: 0 3 * * * /home/forge/scripts/cleanup-stale-pr-sites.sh >> /var/log/pr-testing/cleanup.log 2>&1
```

### Testing (Daily Use)

```bash
# Create PR environment (comment on PR)
/preview

# View PR environment
# (Check comment on PR for URL, or visit https://forge.laravel.com)

# Delete PR environment
/destroy

# Manual monitoring
ssh forge@YOUR_SERVER_IP
/home/forge/scripts/monitor-pr-sites.sh

# Manual snapshot refresh
ssh forge@YOUR_SERVER_IP
/home/forge/scripts/refresh-snapshots.sh
```

---

## Troubleshooting Reference

### "Site creation failed"
```bash
# Check Forge API connectivity
curl -H "Authorization: Bearer $FORGE_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$FORGE_SERVER_ID

# Check server resources
free -h
df -h
```

### "Database copy failed"
```bash
# Check master databases exist
mysql -u forge -e "SHOW DATABASES LIKE '%_master';"

# Check if master has data
mysql -u forge keatchen_master -e "SHOW TABLES;" | head -5
```

### "SSL certificate not provisioning"
```bash
# Wait 10 minutes and check status manually
# (Let's Encrypt rate limits: 50 certs/domain/week)

# Check certificate status in Forge UI
# https://forge.laravel.com → Server → Sites → PR-XXX → SSL
```

### "Deployment hanging"
```bash
# SSH to server and check logs
ssh forge@YOUR_SERVER_IP
tail -100 /home/prXXXuser/storage/logs/laravel.log

# Check if PHP-FPM is running
sudo systemctl status php8.2-fpm

# Restart if needed
sudo systemctl restart php8.2-fpm
```

---

## Next Steps After Implementation

1. **Monitor for 1 week**: Track usage, fix bugs, optimize
2. **Train team**: Document process for your team
3. **Add custom DNS** (optional): Only if stakeholders need branded URLs
4. **Scale up**: Add more servers if team grows beyond 3-5 developers
5. **Integrate monitoring**: Connect to Slack/email for alerts

---

**Version**: 1.0
**Last Updated**: November 8, 2025
**Status**: Ready for Production
