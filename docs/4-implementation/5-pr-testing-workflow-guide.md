# GitHub Actions PR Testing Workflow Guide

**Production-ready workflow for automated PR testing environments**

---

## Table of Contents

1. [Quick Setup](#quick-setup)
2. [Workflow Overview](#workflow-overview)
3. [Configuration](#configuration)
4. [Usage Guide](#usage-guide)
5. [Security Best Practices](#security-best-practices)
6. [Troubleshooting](#troubleshooting)
7. [API Reference](#api-reference)

---

## Quick Setup

### Step 1: Add GitHub Secrets

Navigate to: **Settings → Secrets and Variables → Actions → Repository Secrets**

Add these secrets:

```
FORGE_API_TOKEN: your_forge_api_token
FORGE_SERVER_ID: your_forge_server_id
```

**Where to find these:**
- **FORGE_API_TOKEN**: https://forge.laravel.com/user/profile#/api → Create new token
- **FORGE_SERVER_ID**: https://forge.laravel.com/servers → Click your server → ID in URL

### Step 2: Create Workflow File

File: `.github/workflows/pr-testing.yml`

(Already included in this repository)

### Step 3: Test the Workflow

1. Open any PR
2. Comment: `/preview`
3. Watch GitHub Actions tab
4. Get environment URL in PR comment

**That's it! Takes ~5-10 minutes to deploy.**

---

## Workflow Overview

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Developer Comments in PR                                    │
│  "/preview" | "/update" | "/destroy"                       │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  route-command Job                                          │
│  - Parse comment                                            │
│  - Validate permissions                                     │
│  - Route to appropriate job                                │
└──────────────────────────┬──────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ↓                  ↓                  ↓
   ┌─────────┐       ┌─────────┐       ┌─────────┐
   │ CREATE  │       │ UPDATE  │       │DESTROY  │
   │ ENVIRON │       │ENVIRON  │       │ENVIRON  │
   │   MENT  │       │   MENT  │       │   MENT  │
   └────┬────┘       └────┬────┘       └────┬────┘
        │                 │                 │
        ↓                 ↓                 ↓
   Forge API Calls (Parallel Execution)
        │
        ↓
   PR Comment with Test URL
```

### Job Breakdown

#### 1. route-command (Always Runs)

**Purpose**: Parse the PR comment and route to correct job

**Steps**:
- Validate commenter has push permissions
- Parse command from comment body
- Extract PR details (number, SHA, branch)
- Add reaction to comment
- Deny permission if needed

**Output**:
- `command`: create, update, destroy, or none
- `pr_number`: PR number
- `pr_sha`: Commit SHA
- `project`: customer-app or epos
- `proceed`: true/false

#### 2. create-environment

**Purpose**: Create new test environment on Forge

**Steps**:
1. Check for existing environment
2. Create site via Forge API (isolated user)
3. Wait for site installation
4. Configure git repository
5. Deploy PR branch code
6. Set environment variables
7. Clone database snapshot
8. Enable SSL (automatic on on-forge.com)
9. Start queue workers
10. Post PR comment with test URL

**Duration**: 5-10 minutes

#### 3. update-environment

**Purpose**: Redeploy code without recreating site

**Steps**:
1. Find existing site by PR number
2. Trigger deployment from latest PR code
3. Update PR comment

**Duration**: 2-3 minutes

**Use Case**: When you push new commits to the PR after environment is created

#### 4. destroy-environment

**Purpose**: Delete test environment

**Steps**:
1. Find site by PR number
2. Delete via Forge API
3. Post cleanup comment
4. Remove preview-environment label

**Duration**: <1 minute

#### 5. auto-cleanup-on-pr-close

**Purpose**: Automatically delete environment when PR closes

**Triggers**: PR closed (merged or rejected)

**Steps**:
1. Find site by PR number
2. Delete via Forge API
3. Post cleanup comment

---

## Configuration

### Environment Variables

Defined at top of workflow:

```yaml
env:
  FORGE_API_BASE_URL: https://forge.laravel.com/api/v1
  DEPLOYMENT_TIMEOUT: 600  # 10 minutes
  LOG_RETENTION: 30  # days
```

**Customize as needed:**
- Increase `DEPLOYMENT_TIMEOUT` if database cloning takes longer
- Adjust `LOG_RETENTION` for how long to keep GitHub logs

### Secrets Configuration

#### Required Secrets

| Secret | Value | Where to Get |
|--------|-------|-------------|
| `FORGE_API_TOKEN` | Your Forge API token | https://forge.laravel.com/user/profile → API |
| `FORGE_SERVER_ID` | Your Forge server ID | https://forge.laravel.com/servers → Click server |

#### How to Create Token

1. Go to: https://forge.laravel.com/user/profile#/api
2. Click "Create API Token"
3. Copy token immediately (not shown again)
4. Add to GitHub Secrets as `FORGE_API_TOKEN`

#### How to Get Server ID

1. Go to: https://forge.laravel.com/servers
2. Click your server name
3. URL will be: `https://forge.laravel.com/servers/{SERVER_ID}/`
4. Copy that number to GitHub Secrets as `FORGE_SERVER_ID`

### Permissions

Workflow uses minimal required permissions:

```yaml
permissions:
  contents: read
  pull-requests: write
```

- `contents: read` - Read code to deploy
- `pull-requests: write` - Post comments to PR

---

## Usage Guide

### Command: /preview

**Create new test environment for this PR**

```
Comment on PR: /preview
```

**What happens:**
1. GitHub Action validates your permissions
2. Creates new site: `pr-{NUMBER}.on-forge.com`
3. Deploys your PR branch code
4. Clones database snapshot
5. Posts comment with test URL
6. Takes 5-10 minutes total

**Response in PR comment:**
```
✅ Testing environment created successfully!

Test URL: https://pr-123.on-forge.com
Site ID: 12345
```

**When to use:**
- First time testing a PR
- Want fresh environment from scratch

### Command: /update

**Redeploy code to existing environment**

```
Comment on PR: /update
```

**What happens:**
1. Finds your existing test environment
2. Pulls latest code from your PR branch
3. Runs deployment script
4. Tests site available in ~2 minutes

**When to use:**
- You pushed new commits to PR after environment created
- Want faster redeployment (doesn't recreate database)
- Testing code changes without full setup

### Command: /destroy

**Delete test environment manually**

```
Comment on PR: /destroy
```

**What happens:**
1. Finds test environment
2. Deletes site and all data
3. Posts cleanup confirmation

**When to use:**
- Want to free up resources
- Testing complete, ready to merge
- Environment has issues and you want fresh one

### Automatic Cleanup

**When PR is closed (merged or rejected)**

Test environment is automatically deleted:
- All data cleaned up
- Resources freed
- Confirmation posted in PR comment

**No action needed** - happens automatically

---

## Security Best Practices

### 1. Secrets Management

**DO:**
- ✅ Store tokens in GitHub Secrets (encrypted)
- ✅ Rotate tokens regularly
- ✅ Use minimal permission tokens
- ✅ Keep tokens out of logs
- ✅ Review secret access in Settings

**DON'T:**
- ❌ Commit tokens to repository
- ❌ Share tokens in chat or email
- ❌ Use same token for multiple services
- ❌ Print tokens in workflow logs

### 2. Permissions

**Commenter Validation**:
```yaml
# Workflow validates that commenter has push access
if: github.event.issue.pull_request &&
    (starts with comment "/preview" ...)
```

Only users with push permissions can trigger commands.

**Verify who has access:**
- Settings → Collaborators
- Only add developers who need it

### 3. Environment Isolation

**Each test environment is isolated:**
- Separate Linux user (`prXXXuser`)
- Separate database (`pr_XXX_database`)
- Separate Redis database
- Separate queue workers

**One PR's code cannot affect another:**
- No shared database
- No shared cache
- No shared resources

### 4. Database Snapshot Security

**Master snapshot should contain NO:**
- ❌ Real customer data
- ❌ Real payment info
- ❌ Real API keys
- ❌ Sensitive credentials

**Master snapshot should contain:**
- ✅ Production database structure
- ✅ Test customer records
- ✅ Realistic order volumes
- ✅ Test data only

**Refresh weekly:**
- Sunday evening from sanitized backup
- Not from live production
- Review contents before use

### 5. API Token Permissions

When creating token at https://forge.laravel.com/user/profile#/api:

**Required permissions only:**
- Site management (create/delete)
- Database management (optional)
- SSL certificates

**Never give:**
- ❌ Server management (reboot, manage users)
- ❌ SSH access
- ❌ Full server control

### 6. Rate Limiting

Forge API rate limit: **60 requests per minute**

Workflow is designed to stay well under:
- create-environment: ~15 requests
- update-environment: ~5 requests
- destroy-environment: ~5 requests

Safe for multiple concurrent PRs.

---

## Troubleshooting

### Site Creation Fails

**Error**: `Failed to create site. Response: ...`

**Solutions**:
1. Check Forge API token is correct
2. Check server ID is correct
3. Check server has available resources
4. Verify rate limit not exceeded

**Debug**:
```bash
# Test Forge API manually
curl -X GET https://forge.laravel.com/api/v1/servers/SERVER_ID/sites \
  -H "Authorization: Bearer TOKEN" \
  -H "Accept: application/json"
```

### Site Installation Timeout

**Error**: `Timeout waiting for site installation`

**Solutions**:
1. Increase `DEPLOYMENT_TIMEOUT` (currently 600s = 10 min)
2. Check Forge server resources (CPU, RAM, disk)
3. Check GitHub Actions runner isn't throttled
4. Try again (temporary Forge API delays)

**Debug**:
Check Forge dashboard → Your Server → Activity Log

### Database Clone Fails

**Error**: Database operations timing out

**Solutions**:
1. Check master snapshot exists and is accessible
2. Verify database user has permissions
3. If snapshot is large (>5GB), increase timeout
4. Check server disk space

**Debug**:
```bash
# SSH to server and check
# List databases
mysql -u forge -p 'password' -e "SHOW DATABASES;"

# Check master snapshot
mysqldump -u forge -p 'password' pr_master_customer \
  --single-transaction --quick | wc -c
```

### SSL Certificate Not Provisioning

**Error**: Site is accessible at HTTP but not HTTPS

**Solutions**:
1. Wait 5-10 minutes (Let's Encrypt can be slow)
2. Check domain is accessible (ping pr-123.on-forge.com)
3. Verify Forge can reach your server
4. Check Forge logs for certificate errors

**Debug**:
```bash
# Check Forge certificate status
curl -X GET https://forge.laravel.com/api/v1/servers/SERVER_ID/sites/SITE_ID/certificates \
  -H "Authorization: Bearer TOKEN"
```

### PR Comment Permission Denied

**Error**: `Permission denied. You need push access...`

**Solutions**:
1. User is not collaborator on repo
2. User doesn't have push permissions
3. Repository might be private/restricted

**Fix**:
- Add user as collaborator: Settings → Collaborators → Add
- Make sure they have "Write" or "Admin" role

### Queue Workers Not Starting

**Error**: Horizon shows no workers

**Solutions**:
1. Check site deployment completed successfully
2. Verify queue configuration in `.env`
3. Check Laravel Horizon is installed
4. Verify Redis connection

**Debug**:
```bash
# SSH to site and check
cd /home/forge/pr-123.on-forge.com
php artisan queue:work --help
php artisan horizon:list
```

### Code Not Deployed from PR Branch

**Error**: Site shows old/wrong code

**Solutions**:
1. Check deployment script in Forge
2. Verify branch name is correct (case-sensitive)
3. Make sure PR branch exists on origin
4. Try `/update` command to redeploy

**Debug**:
```bash
# SSH to site and verify
cd /home/forge/pr-123.on-forge.com
git status
git branch -a
git log --oneline -5
```

---

## API Reference

### Forge API Endpoints Used

#### Create Site

```bash
POST /api/v1/servers/{serverId}/sites

{
  "domain": "pr-123.on-forge.com",
  "project_type": "php",
  "directory": "/public",
  "isolated": true,
  "php_version": "php82"
}
```

#### Get Site

```bash
GET /api/v1/servers/{serverId}/sites/{siteId}
```

#### Configure Git

```bash
POST /api/v1/servers/{serverId}/sites/{siteId}/git

{
  "provider": "github",
  "repository": "owner/repo",
  "branch": "main"
}
```

#### Update Deployment Script

```bash
PUT /api/v1/servers/{serverId}/sites/{siteId}/deployment-script

{
  "content": "#!/bin/bash\nset -e\ncd /home/forge/pr-123.on-forge.com\n..."
}
```

#### Trigger Deployment

```bash
POST /api/v1/servers/{serverId}/sites/{siteId}/deployment/request
```

#### Add Environment Variable

```bash
POST /api/v1/servers/{serverId}/sites/{siteId}/environment-variables

{
  "name": "APP_ENV",
  "value": "testing"
}
```

#### Create SSL Certificate

```bash
POST /api/v1/servers/{serverId}/sites/{siteId}/certificates

{
  "type": "letsencrypt"
}
```

#### Create Queue Worker

```bash
POST /api/v1/servers/{serverId}/workers

{
  "connection": "redis",
  "queue": "default",
  "timeout": 60,
  "sleep": 3,
  "processes": 2,
  "site_id": {siteId}
}
```

#### Delete Site

```bash
DELETE /api/v1/servers/{serverId}/sites/{siteId}
```

### Full Forge API Documentation

See: https://forge.laravel.com/api-documentation

---

## Advanced Configuration

### Custom PHP Version

Edit the site creation step:

```yaml
- name: Create Forge Site via API
  env:
    PHP_VERSION: php83  # Change this
  run: |
    curl -X POST ...
      -d '{
        "php_version": "${{ env.PHP_VERSION }}"
      }'
```

### Database Cloning Script

For production, create dedicated script:

**File**: `scripts/clone-db.sh`

```bash
#!/bin/bash
set -e

SOURCE_DB=$1
TARGET_DB=$2

echo "Cloning $SOURCE_DB → $TARGET_DB"

mysqldump -u forge -p"${DB_PASSWORD}" \
  --single-transaction --quick \
  "${SOURCE_DB}" | \
mysql -u forge -p"${DB_PASSWORD}" "${TARGET_DB}"

echo "Database clone complete"
```

Call from workflow:

```yaml
- name: Clone Database Snapshot
  env:
    DB_PASSWORD: ${{ secrets.FORGE_DB_PASSWORD }}
  run: |
    chmod +x scripts/clone-db.sh
    ./scripts/clone-db.sh pr_master_customer pr_${{ needs.route-command.outputs.pr_number }}_customer
```

### Multiple Projects

If using different projects (customer-app, epos):

```yaml
- name: Setup Project-Specific Config
  env:
    PROJECT: ${{ needs.route-command.outputs.project }}
  run: |
    if [ "$PROJECT" = "epos" ]; then
      echo "MASTER_DB=pr_master_epos" >> $GITHUB_ENV
    else
      echo "MASTER_DB=pr_master_customer" >> $GITHUB_ENV
    fi
```

### Conditional Steps

Skip steps based on conditions:

```yaml
- name: Enable Queue Workers
  if: github.event.repository.name == 'keatchen-customer-app'
  run: |
    # Only for customer app
```

---

## Monitoring & Logs

### View Workflow Logs

1. Go to PR → **Checks** tab
2. Click workflow name
3. Expand job for details
4. View logs for each step

### GitHub Actions Insights

1. Go to repository → **Actions** tab
2. See all workflow runs
3. Click run for details
4. View timing and status

### Forge Activity Log

1. Go to https://forge.laravel.com/servers/YOUR_SERVER
2. Check **Activity Log** for API calls
3. See deployment status and errors

---

## Cost Estimation

### Per Environment

| Resource | Cost | Notes |
|----------|------|-------|
| Disk space | Minimal | ~5GB per environment (temporary) |
| Database | Free | Uses existing server PostgreSQL |
| Queue workers | Free | Uses existing Redis |
| SSL | Free | Automatic Let's Encrypt |
| Total | **Free** | Uses existing server resources |

### Server Costs

| Provider | Monthly Cost | Capacity |
|----------|------------|----------|
| DigitalOcean 4GB | $20 | ~5 concurrent environments |
| Linode 4GB | $20 | ~5 concurrent environments |
| AWS t3.medium | ~$30 | ~3 concurrent environments |

### Timeline Cost

For **one PR per day** with **1 concurrent environment**:

- Server: $20/month
- Bandwidth: Minimal
- **Total: ~$20/month**

---

## Next Steps

1. ✅ Add GitHub Secrets (5 minutes)
2. ✅ Commit workflow file to `.github/workflows/` (already done)
3. ✅ Test with `/preview` command (5 minutes)
4. ✅ Share with team (5 minutes)

**Total setup time: 15 minutes**

---

## Support & Resources

- **Forge Documentation**: https://forge.laravel.com/docs
- **Forge API Docs**: https://forge.laravel.com/api-documentation
- **GitHub Actions**: https://docs.github.com/en/actions
- **Let's Encrypt**: https://letsencrypt.org/

---

**Last Updated**: January 2025
**Workflow Version**: 1.0.0
**Status**: Production Ready
