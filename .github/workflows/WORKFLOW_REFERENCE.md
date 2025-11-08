# PR Testing Workflow Reference

**Comprehensive reference for the `pr-testing.yml` GitHub Actions workflow**

---

## Table of Contents

1. [Workflow Architecture](#workflow-architecture)
2. [Configuration](#configuration)
3. [Secrets Setup](#secrets-setup)
4. [Troubleshooting](#troubleshooting)
5. [Advanced Usage](#advanced-usage)
6. [API Rate Limits](#api-rate-limits)
7. [Performance Optimization](#performance-optimization)

---

## Workflow Architecture

### High-Level Flow

```
GitHub PR Comment (/preview, /update, /destroy)
         │
         ↓
┌──────────────────────────────────────┐
│   route-command Job                  │
│   - Parse comment                    │
│   - Validate permissions             │
│   - Extract PR details               │
└──────────────┬───────────────────────┘
               │
    ┌──────────┼──────────┐
    │          │          │
    ↓          ↓          ↓
┌────────┐ ┌───────┐ ┌──────────┐
│ Create │ │Update │ │ Destroy  │
│   Env  │ │ Env   │ │   Env    │
└────────┘ └───────┘ └──────────┘
```

### Job Dependencies

```
route-command (always runs)
├── Parses command
├── Validates permissions
└── Outputs: command, pr_number, project, proceed
    │
    ├→ IF command=create: create-environment
    ├→ IF command=update: update-environment
    └→ IF command=destroy: destroy-environment

auto-cleanup-on-pr-close (parallel)
├── Triggers on PR close event
└── Deletes environment automatically
```

### Concurrency Control

```yaml
concurrency:
  group: pr-testing-${{ github.event.issue.number || github.event.pull_request.number }}
  cancel-in-progress: true
```

**Effect**:
- Only one workflow runs per PR
- New run cancels previous incomplete run
- Prevents race conditions

---

## Configuration

### Workflow Triggers

```yaml
on:
  issue_comment:
    types: [created, edited]
  pull_request:
    types: [closed]
```

**Triggers**:
- `issue_comment created` - PR comment `/preview`, `/update`, `/destroy`
- `issue_comment edited` - Edit comment with command
- `pull_request closed` - PR merged or rejected → auto-cleanup

### Environment Variables

```yaml
env:
  FORGE_API_BASE_URL: https://forge.laravel.com/api/v1
  DEPLOYMENT_TIMEOUT: 600  # 10 minutes
  LOG_RETENTION: 30  # days
```

**Customization**:

```yaml
# For slow servers, increase timeout
env:
  DEPLOYMENT_TIMEOUT: 900  # 15 minutes

# For faster servers, decrease timeout
env:
  DEPLOYMENT_TIMEOUT: 300  # 5 minutes
```

### Permissions

```yaml
permissions:
  contents: read           # Read code to deploy
  pull-requests: write     # Post comments to PR
```

**Why minimal?**
- ✅ Security best practice
- ✅ Least privilege principle
- ✅ Only needs what's required

---

## Secrets Setup

### Step 1: Create Forge API Token

```bash
# 1. Go to: https://forge.laravel.com/user/profile#/api
# 2. Click "Create API Token"
# 3. Name: "GitHub PR Testing"
# 4. Copy token (you won't see it again!)
# 5. Save as FORGE_API_TOKEN
```

### Step 2: Get Server ID

```bash
# 1. Go to: https://forge.laravel.com/servers
# 2. Click your server
# 3. URL becomes: https://forge.laravel.com/servers/12345/...
# 4. ID is: 12345
# 5. Save as FORGE_SERVER_ID
```

### Step 3: Add to GitHub

```bash
# Settings → Secrets and variables → Actions → New repository secret
# Name: FORGE_API_TOKEN
# Value: your_token_here

# Settings → Secrets and variables → Actions → New repository secret
# Name: FORGE_SERVER_ID
# Value: 12345
```

### Verify Secrets

```bash
# List secrets (doesn't show values, just confirms they exist)
curl -X GET https://api.github.com/repos/OWNER/REPO/actions/secrets \
  -H "Authorization: Bearer YOUR_GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json"

# Expected output shows:
# - FORGE_API_TOKEN
# - FORGE_SERVER_ID
```

### Rotate Secrets (Quarterly)

```bash
# 1. Generate new Forge API token
# 2. Test with curl:
curl -X GET https://forge.laravel.com/api/v1/servers/SERVER_ID \
  -H "Authorization: Bearer NEW_TOKEN" \
  -H "Accept: application/json"

# 3. If successful, update GitHub secret
# 4. Delete old token from Forge dashboard
```

---

## Troubleshooting

### Common Issues & Solutions

#### 1. "Permission denied" Error

**Error Message**:
```
Permission denied. You need push access to use PR testing environments.
```

**Cause**: User doesn't have push access to repository

**Fix**:
```bash
# 1. Go to: Settings → Collaborators
# 2. Add user or verify existing
# 3. Ensure role is "Write" or higher
# 4. Try command again
```

#### 2. "Failed to create site" Error

**Error Message**:
```
Failed to create site. Response: {"message": "Unauthorized"}
```

**Cause**: Invalid or expired API token

**Fix**:
```bash
# 1. Check token at: https://forge.laravel.com/user/profile#/api
# 2. Generate new token if expired
# 3. Update GitHub secret: FORGE_API_TOKEN
# 4. Try again
```

#### 3. "Site not found" Error

**Error Message**:
```
Site not found. Run /preview command to create environment first.
```

**Cause**: Using `/update` or `/destroy` without existing environment

**Fix**:
```bash
# 1. Comment /preview first to create environment
# 2. Wait 5-10 minutes for creation
# 3. Then use /update or /destroy
```

#### 4. Timeout Waiting for Site Installation

**Error Message**:
```
Timeout waiting for site installation
```

**Cause**: Site taking longer than expected to install

**Possible Reasons**:
- Server under heavy load
- Forge API slow
- Insufficient disk space

**Fix**:
```yaml
# Increase timeout in workflow:
env:
  DEPLOYMENT_TIMEOUT: 900  # 15 minutes instead of 10

# Or:
# 1. SSH to server, check resources:
df -h  # Check disk space
free -h  # Check memory
# 2. Delete old test environments if full
# 3. Try again
```

#### 5. HTTPS Not Working (HTTP only)

**Symptom**: Site accessible at HTTP but not HTTPS

**Cause**: Let's Encrypt certificate not provisioned yet

**Fix**:
```bash
# 1. Wait 5-10 minutes (Let's Encrypt can be slow)
# 2. Check Forge dashboard → Your site → SSL tab
# 3. If error shown, may need manual intervention
# 4. Worst case: comment /destroy, run /preview again
```

#### 6. Code Not Deployed Correctly

**Symptom**: Site shows wrong/old code

**Cause**: Wrong branch deployed, or deployment failed

**Debug**:
```bash
# SSH to site and check
ssh user@server "cd /home/forge/pr-123.on-forge.com && git log --oneline -5"

# Should show your PR branch commits
# If not, check:
# 1. GitHub Secrets FORGE_API_TOKEN is correct
# 2. Deployment script in Forge is correct
# 3. Branch name is correct (case-sensitive)
```

#### 7. Database Not Cloned

**Symptom**: Site works but database is empty

**Cause**: Master snapshot doesn't exist or permissions wrong

**Debug**:
```bash
# SSH to server and check
ssh user@server "mysql -u forge -p'password' -e 'SHOW DATABASES;'"

# Should show:
# - pr_master_customer
# - pr_master_epos

# If missing, create from backup:
# 1. Take production backup (sanitized)
# 2. Upload to server
# 3. Restore as pr_master_customer
```

#### 8. Workflow Runs But Doesn't Complete

**Symptom**: Workflow shows as still running after 30+ minutes

**Cause**: Stuck job or GitHub Actions outage

**Fix**:
```bash
# 1. Cancel run: Actions → workflow run → "Cancel workflow"
# 2. Try command again
# 3. Check GitHub Status: https://www.githubstatus.com/
# 4. If problem persists, open GitHub issue
```

#### 9. Site Creates But Comments Don't Post

**Symptom**: Environment created but PR comment missing

**Cause**: GitHub Actions permission issue

**Fix**:
```yaml
# Check workflow permissions in YAML:
permissions:
  contents: read
  pull-requests: write  # Must have this!

# If missing, add and push
```

#### 10. API Rate Limit Exceeded

**Symptom**: Workflow fails with rate limit error

**Cause**: Too many API calls (>60/min to Forge)

**Note**: Workflow is designed to stay well under limit, only happens with 30+ concurrent environments

**Fix**:
```bash
# 1. Wait 1 minute (rate limit resets)
# 2. Try again
# 3. For persistent issues, contact Forge support
```

### Debugging Commands

#### View Workflow Logs

```bash
# 1. Go to PR → Checks tab
# 2. Click "Details" next to workflow
# 3. Expand each job to see logs
# 4. Look for "ERROR" or "FAIL" messages
```

#### Test Forge API Manually

```bash
# Get your server info
curl -X GET https://forge.laravel.com/api/v1/servers/YOUR_SERVER_ID \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json" | jq .

# List all sites on server
curl -X GET https://forge.laravel.com/api/v1/servers/YOUR_SERVER_ID/sites \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json" | jq .

# Get specific site
curl -X GET https://forge.laravel.com/api/v1/servers/YOUR_SERVER_ID/sites/SITE_ID \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json" | jq .
```

#### Check Forge Activity Log

```bash
# 1. Go to: https://forge.laravel.com/servers/YOUR_SERVER
# 2. Scroll down to "Activity Log"
# 3. See all API calls and their results
```

#### SSH to Test Site

```bash
# Find site path and user
cd /home/forge/pr-123.on-forge.com

# Check git status
git log --oneline -10
git status
git branch -a

# Check Laravel installation
php artisan --version
php artisan env

# Check if migrations ran
php artisan migrate:status

# View logs if errors
tail -f storage/logs/laravel.log
```

---

## Advanced Usage

### Custom Deployment Script

Edit the workflow to use custom deployment:

```yaml
- name: Deploy Code to PR Branch
  env:
    FORGE_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
    SERVER_ID: ${{ secrets.FORGE_SERVER_ID }}
    SITE_ID: ${{ steps.create_site.outputs.site_id }}
  run: |
    curl -X PUT "${FORGE_API_BASE_URL}/servers/${SERVER_ID}/sites/${SITE_ID}/deployment-script" \
      -H "Authorization: Bearer ${FORGE_TOKEN}" \
      -H "Content-Type: application/json" \
      -d @- <<'DEPLOY_SCRIPT'
    {
      "content": "#!/bin/bash\nset -e\ncd /home/forge/pr-${{ needs.route-command.outputs.pr_number }}.on-forge.com\ngit fetch origin ${{ github.head_ref }}\ngit reset --hard origin/${{ github.head_ref }}\ncomposer install --no-interaction --prefer-dist\nnpm ci\nnpm run build\nphp artisan migrate --force\nphp artisan cache:clear\nphp artisan config:clear\nphp artisan optimize:clear"
    }
    DEPLOY_SCRIPT
```

### Multiple Projects

If managing different Laravel projects:

```yaml
- name: Determine Configuration
  id: config
  env:
    PROJECT: ${{ needs.route-command.outputs.project }}
  run: |
    if [ "$PROJECT" = "epos" ]; then
      echo "db_prefix=pr_epos_" >> $GITHUB_ENV
      echo "php_version=php83" >> $GITHUB_ENV
      echo "workers=4" >> $GITHUB_ENV
    else
      echo "db_prefix=pr_customer_" >> $GITHUB_ENV
      echo "php_version=php82" >> $GITHUB_ENV
      echo "workers=2" >> $GITHUB_ENV
    fi
```

### Slack Notifications

Add Slack alerts:

```yaml
- name: Notify Slack
  if: failure()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    text: 'PR Testing Workflow Failed'
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
    fields: repo,message,commit,author
```

### Custom Domain Support

Modify for custom domains (requires DNS setup):

```yaml
env:
  USE_CUSTOM_DOMAIN: false  # Set to true if using custom DNS

- name: Create Forge Site via API
  run: |
    if [ "$USE_CUSTOM_DOMAIN" = "true" ]; then
      DOMAIN="pr-${{ needs.route-command.outputs.pr_number }}.staging.kitthub.com"
    else
      DOMAIN="pr-${{ needs.route-command.outputs.pr_number }}.on-forge.com"
    fi
```

---

## API Rate Limits

### Forge API Limits

- **Rate Limit**: 60 requests per minute per token
- **Burst Limit**: None
- **Backoff**: Implement exponential backoff

### Workflow API Usage

| Operation | Requests | Duration |
|-----------|----------|----------|
| Create | ~15 | 5-10 min |
| Update | ~5 | 2-3 min |
| Destroy | ~3 | <1 min |
| Check status | 1 | <10 sec |

**Total for typical day**: ~50 requests (well under limit)

### If Rate Limited

```bash
# Check remaining requests
curl -I https://forge.laravel.com/api/v1/servers/YOUR_SERVER \
  -H "Authorization: Bearer YOUR_TOKEN" | grep -i "x-ratelimit"

# If getting 429 error:
# 1. Wait 60 seconds
# 2. Retry with exponential backoff
# 3. For persistent issues, contact Forge support
```

---

## Performance Optimization

### Site Creation Speed (Target: 5-10 min)

**Bottlenecks in order**:

1. **Database clone** (~3-5 min) - Largest bottleneck
   - Optimize: Use smaller snapshot
   - Or: Copy only essential tables
   - Or: Create test data on-the-fly instead

2. **Site installation** (~1-2 min) - Forge process
   - Optimize: Pre-create blank sites and clone instead
   - Limited: Not much can optimize here

3. **Composer install** (~1 min) - Dependency installation
   - Optimize: Use `composer install --no-dev` for tests
   - Or: Pre-cache dependencies

4. **SSL provisioning** (~0-5 min) - Let's Encrypt
   - Optimize: Use on-forge.com (automatic)
   - Or: Pre-generate certificates

### Deployment Speed Optimization

**Current**: 2-3 minutes

**To improve**:

```yaml
# Skip unnecessary steps
- name: Deploy Code
  run: |
    # Fast deployment without migrations
    git fetch && git reset --hard origin/branch
    # Skip: composer install (use cached)
    # Skip: npm run build (if not needed)
    # Skip: php artisan migrate (if not needed for tests)
    php artisan cache:clear  # Must do
```

### Concurrent Environment Handling

**Recommended limits** (per server):
- **2GB server**: 1 concurrent environment
- **4GB server**: 2-3 concurrent environments
- **8GB server**: 4-5 concurrent environments

**Check current usage**:

```bash
# SSH to server
free -h  # Memory
df -h    # Disk space

# List all sites
curl -X GET https://forge.laravel.com/api/v1/servers/YOUR_SERVER/sites \
  -H "Authorization: Bearer YOUR_TOKEN" | jq '.sites | length'
```

---

## Maintenance Tasks

### Weekly

```bash
# Refresh master database snapshot
# 1. Take backup from production (sanitized)
# 2. Upload to server as pr_master_customer, pr_master_epos
# 3. Verify with test /preview
```

### Monthly

```bash
# Review workflow performance
# 1. Check GitHub Actions log
# 2. Note average deployment times
# 3. Look for errors/timeouts
# 4. Clean up orphaned test sites (if any)
```

### Quarterly

```bash
# Security review
# 1. Rotate Forge API token
# 2. Verify collaborators still have access
# 3. Check no secrets leaked in logs
# 4. Review database snapshot (no sensitive data)
```

---

## Support & Resources

- **Forge Documentation**: https://forge.laravel.com/docs
- **Forge API Docs**: https://forge.laravel.com/api-documentation
- **GitHub Actions**: https://docs.github.com/en/actions
- **Let's Encrypt**: https://letsencrypt.org/how-it-works

---

**Workflow Version**: 1.0.0
**Status**: Production Ready
**Last Updated**: January 2025
