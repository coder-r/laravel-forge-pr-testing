# Architecture Design

⚠️ **CRITICAL**: Read this document completely before implementing. The decisions here affect everything else.

## System Overview

This document describes the complete architecture for automated PR testing environments using Laravel Forge.

## High-Level Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                         Developer                             │
│                  (Creates PR, comments "/preview")            │
└────────────────────────────┬─────────────────────────────────┘
                             │
                             ↓
┌──────────────────────────────────────────────────────────────┐
│                         GitHub                                │
│  ┌──────────────────┐           ┌──────────────────┐         │
│  │   Pull Request   │           │ GitHub Actions   │         │
│  │   #123           │──triggers→│  Workflow        │         │
│  └──────────────────┘           └────────┬─────────┘         │
└─────────────────────────────────────────┼───────────────────┘
                                           │
                                           │ API Calls
                                           ↓
┌──────────────────────────────────────────────────────────────┐
│                      Laravel Forge                            │
│                   (Orchestration Layer)                       │
│                                                               │
│  Forge API Operations:                                        │
│  1. Create isolated site                                      │
│  2. Create database                                          │
│  3. Configure environment variables                          │
│  4. Set up queue workers                                     │
│  5. Enable SSL certificate                                   │
│  6. Trigger deployment                                       │
└────────────────────────────┬──────────────────────────────────┘
                             │
                             ↓
┌──────────────────────────────────────────────────────────────┐
│                    Forge Server                               │
│                   (Compute Layer)                            │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Production Sites (Existing)                            │ │
│  │  ┌──────────────────┐  ┌──────────────────┐           │ │
│  │  │ app.kitthub.com  │  │ dev.kitthub.com  │           │ │
│  │  │ (customer-app)   │  │ (epos)           │           │ │
│  │  └──────────────────┘  └──────────────────┘           │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Test Environments (Dynamically Created)                │ │
│  │                                                          │ │
│  │  ┌─────────────────────────────────────┐               │ │
│  │  │ pr-123.staging.kitthub.com          │               │ │
│  │  │ - Isolated Linux user (pr123user)   │               │ │
│  │  │ - Database: pr_123_customer_db      │               │ │
│  │  │ - Redis DB: 123                     │               │ │
│  │  │ - Queue workers: dedicated          │               │ │
│  │  │ - SSL: Let's Encrypt                │               │ │
│  │  └─────────────────────────────────────┘               │ │
│  │                                                          │ │
│  │  ┌─────────────────────────────────────┐               │ │
│  │  │ pr-456.staging.kitthub.com          │               │ │
│  │  │ - Isolated Linux user (pr456user)   │               │ │
│  │  │ - Database: pr_456_epos_db          │               │ │
│  │  │ - Redis DB: 456                     │               │ │
│  │  │ - Queue workers: dedicated          │               │ │
│  │  │ - SSL: Let's Encrypt                │               │ │
│  │  └─────────────────────────────────────┘               │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Shared Resources                                        │ │
│  │  ┌──────────────────────────────────────┐              │ │
│  │  │ Master DB Snapshots                  │              │ │
│  │  │ - keatchen_master (refreshed weekly) │              │ │
│  │  │ - devpel_master (refreshed weekly)   │              │ │
│  │  └──────────────────────────────────────┘              │ │
│  │  ┌──────────────────────────────────────┐              │ │
│  │  │ Redis (shared instance)              │              │ │
│  │  │ - Database 0-99: available for envs  │              │ │
│  │  └──────────────────────────────────────┘              │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

## Component Architecture

### 1. GitHub Integration Layer

#### PR Trigger Mechanism

**Manual Trigger via Comment**:
- Developer comments `/preview` on PR
- GitHub webhook sends event to GitHub Actions
- Action validates: PR is open, user has permissions, no existing environment
- Action triggers Forge API automation

**Why Manual Trigger**:
- ✅ Prevents wasting resources on draft/WIP PRs
- ✅ Developer control over when to create environment
- ✅ Avoids unnecessary environments for minor PRs
- ✅ Reduces server load and costs

**Alternative Commands**:
- `/preview` - Create test environment
- `/destroy` - Destroy test environment (manual cleanup)
- `/update` - Redeploy environment with latest code

#### GitHub Actions Workflow

```yaml
name: PR Testing Environment

on:
  issue_comment:
    types: [created]

jobs:
  create-environment:
    if: github.event.issue.pull_request && contains(github.event.comment.body, '/preview')
    runs-on: ubuntu-latest
    steps:
      - name: Get PR info
      - name: Check if environment exists
      - name: Create Forge site
      - name: Create database
      - name: Copy database snapshot
      - name: Configure environment
      - name: Deploy code
      - name: Wait for deployment
      - name: Post comment with URL

  destroy-environment:
    if: github.event.issue.pull_request && contains(github.event.comment.body, '/destroy')
    runs-on: ubuntu-latest
    steps:
      - name: Get PR info
      - name: Delete Forge site
      - name: Delete database
      - name: Post confirmation comment
```

### 2. Forge Orchestration Layer

#### Site Creation Workflow

**Step-by-Step Process**:

1. **Validate PR Number**
   - Ensure PR exists and is open
   - Check for existing environment
   - Generate unique identifiers

2. **Create Isolated Site**
   ```bash
   POST /api/v1/servers/{serverId}/sites
   {
     "domain": "pr-{PR_NUMBER}.staging.kitthub.com",
     "project_type": "php",
     "directory": "/public",
     "isolated": true,
     "php_version": "php82"
   }
   ```

3. **Create Database**
   ```bash
   POST /api/v1/servers/{serverId}/databases
   {
     "name": "pr_{PR_NUMBER}_{PROJECT}_db",
     "user": "pr_{PR_NUMBER}_user",
     "password": "{GENERATED_SECURE_PASSWORD}"
   }
   ```

4. **Copy Database Snapshot**
   ```bash
   # Via SSH to server
   mysqldump {MASTER_DB} | mysql pr_{PR_NUMBER}_{PROJECT}_db
   ```

5. **Configure Environment Variables**
   ```bash
   PUT /api/v1/servers/{serverId}/sites/{siteId}/env
   {
     "APP_NAME": "PR-{PR_NUMBER} Testing",
     "APP_URL": "https://pr-{PR_NUMBER}.staging.kitthub.com",
     "DB_DATABASE": "pr_{PR_NUMBER}_{PROJECT}_db",
     "DB_USERNAME": "pr_{PR_NUMBER}_user",
     "DB_PASSWORD": "{PASSWORD}",
     "REDIS_DB": "{PR_NUMBER}",
     # ... etc
   }
   ```

6. **Connect Git Repository**
   ```bash
   POST /api/v1/servers/{serverId}/sites/{siteId}/git
   {
     "provider": "github",
     "repository": "{OWNER}/{REPO}",
     "branch": "{PR_BRANCH}"
   }
   ```

7. **Create Queue Workers**
   ```bash
   POST /api/v1/servers/{serverId}/sites/{siteId}/workers
   {
     "connection": "redis",
     "queue": "default",
     "processes": 1,
     "timeout": 60
   }
   ```

8. **Install SSL Certificate**
   ```bash
   POST /api/v1/servers/{serverId}/sites/{siteId}/certificates/letsencrypt
   {
     "domains": ["pr-{PR_NUMBER}.staging.kitthub.com"]
   }
   ```

9. **Trigger Deployment**
   ```bash
   POST /api/v1/servers/{serverId}/sites/{siteId}/deployment/deploy
   ```

10. **Wait for Ready** (health check polling)

### 3. Server Infrastructure Layer

#### Resource Allocation

**Server Specifications**:
- CPU: 4 cores (shared among all sites)
- RAM: 8 GB (2-3 GB for production, 4-5 GB for test environments)
- Storage: 100 GB SSD
- Network: 1 Gbps

**Resource Allocation Per Environment**:
- RAM: ~500 MB per test environment
- CPU: Shared, minimal per environment
- Storage: ~5.5 GB (5GB database + 500MB code)
- Redis: Separate database number per environment

**Max Concurrent Environments**:
- Theoretical: 8-10 on 8GB server
- Practical: 3-5 (to maintain performance)
- Target: 1-3 (requirement)

#### Site Isolation

**Why Site Isolation is Critical**:

Each test environment runs under a separate Linux user account:

```
Production Sites:
/home/forge/app.kitthub.com/
/home/forge/dev.kitthub.com/

Test Environments:
/home/pr123user/pr-123.staging.kitthub.com/
/home/pr456user/pr-456.staging.kitthub.com/
/home/pr789user/pr-789.staging.kitthub.com/
```

**Benefits**:
- ✅ File system isolation (one site can't access another's files)
- ✅ Process isolation (separate PHP-FPM pools)
- ✅ Security (bugs in one environment don't affect others)
- ✅ Resource tracking (easier to monitor per-environment usage)

#### Database Architecture

**Master Snapshots** (refreshed weekly on Sunday):
```
keatchen_master (production replica)
   ↓ (copied weekly from production)
devpel_master (production replica)
```

**Per-Environment Databases**:
```
pr_123_customer_db (cloned from keatchen_master)
pr_456_epos_db (cloned from devpel_master)
pr_789_customer_db (cloned from keatchen_master)
```

**Database Isolation**:
- Each environment has completely separate database
- No shared tables or connections
- Safe for destructive testing
- Can be dropped without affecting other environments

#### Redis Architecture

**Shared Redis Instance** with separate databases:

```
Redis (port 6379)
├── DB 0: Production cache (customer-app)
├── DB 1: Production sessions (customer-app)
├── DB 2: Production cache (epos)
├── DB 3: Production sessions (epos)
├── DB 100: Master snapshots metadata
├── DB 123: PR-123 test environment (cache + sessions)
├── DB 456: PR-456 test environment (cache + sessions)
└── DB 789: PR-789 test environment (cache + sessions)
```

**Why Separate Databases**:
- ✅ Isolation: Test environments don't interfere with production
- ✅ Cleanup: Easy to flush a test environment's data
- ✅ Monitoring: Can track per-environment Redis usage
- ✅ Queues: Separate queue channels prevent job conflicts

### 4. DNS and SSL Layer

#### Wildcard DNS Configuration

**DNS Record Required**:
```
Type: A
Name: *.staging.kitthub.com
Value: {FORGE_SERVER_IP}
TTL: 3600
```

**How It Works**:
1. Any subdomain under `staging.kitthub.com` resolves to Forge server
2. `pr-123.staging.kitthub.com` → Forge server IP
3. `pr-456.staging.kitthub.com` → Forge server IP
4. Nginx on server routes to correct site based on domain name

**Important**: This is just DNS. Each site is still created individually in Forge with its own Nginx configuration.

#### SSL Certificate Strategy

**Option 1: Let's Encrypt Per Site** (Recommended)
- Each test environment gets own SSL certificate
- Automatic issuance via Forge API
- Auto-renewal handled by Forge
- Rate limit: 50 certificates per domain per week (plenty for 1-3 concurrent environments)

**Option 2: Wildcard SSL** (Complex, Not Recommended for Initial Implementation)
- Single certificate for `*.staging.kitthub.com`
- Requires DNS-01 validation
- Requires DNS provider API credentials
- More complex setup

**Recommendation**: Use Option 1 (per-site certificates) for simplicity.

### 5. Deployment Automation

#### Deployment Script Template

Each test environment uses a custom deployment script:

```bash
#!/bin/bash

# Standard Laravel Forge deployment script
cd /home/pr{PR_NUMBER}user/pr-{PR_NUMBER}.staging.kitthub.com

git pull origin {PR_BRANCH}

$FORGE_COMPOSER install --no-interaction --prefer-dist --optimize-autoloader

# Database migrations (safe in isolated environment)
if [ -f artisan ]; then
    $FORGE_PHP artisan migrate --force
fi

# Clear and cache configuration
$FORGE_PHP artisan config:cache
$FORGE_PHP artisan route:cache
$FORGE_PHP artisan view:cache

# Restart queue workers
$FORGE_PHP artisan queue:restart

# Restart PHP-FPM for this site
( flock -w 10 9 || exit 1
    echo 'Restarting FPM...'; sudo -S service $FORGE_PHP_FPM reload ) 9>/tmp/fpmlock

echo "Deployment complete at $(date)"
```

#### Continuous Deployment

Once environment is created, subsequent commits to the PR branch automatically trigger deployments:

```
Developer pushes to PR branch
   ↓
GitHub webhook to Forge
   ↓
Forge runs deployment script
   ↓
Environment updated automatically
```

### 6. Cleanup and Lifecycle Management

#### Auto-Cleanup Triggers

**Cleanup Scenarios**:

1. **PR Merged**
   - GitHub webhook detects PR merged
   - GitHub Action calls Forge API to delete site
   - Database dropped
   - Cleanup confirmed

2. **PR Closed** (without merge)
   - Same process as merged

3. **Manual Cleanup**
   - Developer comments `/destroy` on PR
   - Immediate cleanup triggered

4. **Scheduled Cleanup** (future enhancement)
   - Weekly job checks for stale environments
   - Environments older than 30 days auto-deleted
   - Notification sent before deletion

#### Cleanup Process

```bash
1. Delete Site:
   DELETE /api/v1/servers/{serverId}/sites/{siteId}

2. Delete Database:
   DELETE /api/v1/servers/{serverId}/databases/{dbId}

3. Flush Redis Database:
   redis-cli -n {PR_NUMBER} FLUSHDB

4. Post Confirmation:
   Comment on PR: "✅ Test environment destroyed"
```

## Data Flow Diagrams

### Environment Creation Flow

```
PR Comment "/preview"
   ↓
[GitHub Actions]
   ↓
Extract PR number & branch name
   ↓
Check if environment exists
   ↓ (if not exists)
[Call Forge API]
   ↓
Create site with isolated user
   ↓
Create unique database
   ↓
[SSH to Server]
   ↓
Copy master DB snapshot → new DB
   ↓
[Forge API]
   ↓
Upload environment variables
   ↓
Connect Git repository (PR branch)
   ↓
Configure queue workers
   ↓
Create SSL certificate
   ↓
Trigger deployment
   ↓
[Wait for deployment]
   ↓
Poll deployment status (max 10 minutes)
   ↓
[Post Comment on PR]
   ↓
"✅ Environment ready: pr-123.staging.kitthub.com"
```

### Database Snapshot Flow

```
[Weekly Cron Job - Sunday 2 AM]
   ↓
Check production databases
   ↓
Create dumps:
   mysqldump production_customer > /tmp/customer.sql
   mysqldump production_epos > /tmp/epos.sql
   ↓
Import to master snapshots:
   mysql keatchen_master < /tmp/customer.sql
   mysql devpel_master < /tmp/epos.sql
   ↓
Clean up temp files
   ↓
Log completion
```

### Environment Update Flow

```
Developer pushes new commit to PR branch
   ↓
GitHub webhook to Forge
   ↓
Forge detects branch change
   ↓
Runs deployment script:
   - git pull
   - composer install
   - migrate
   - cache clear
   - queue restart
   ↓
Environment updated
   ↓
(Optional) Post comment: "♻️ Environment updated"
```

## Scalability Considerations

### Current Capacity (1-3 Environments)

**Resource Usage**:
- RAM: 1.5-2.5 GB for test environments
- Storage: 15-20 GB
- CPU: Minimal impact
- Cost: $0-10/month additional

### Future Scaling (4-10 Environments)

**If team grows**:
- Upgrade server to 16 GB RAM ($60-80/month)
- Add storage as needed
- Consider separate test server

### Very Large Scale (10+ Environments)

**If significant growth**:
- Separate test server (dedicated)
- Database server separation
- Consider Kubernetes (but requires significant DevOps investment)

**Not needed for current requirements** (1-3 developers, 1-3 environments)

## Monitoring and Observability

### Health Checks

**Per-Environment Health Check**:
```
GET https://pr-123.staging.kitthub.com/health

Response:
{
  "status": "healthy",
  "database": "connected",
  "redis": "connected",
  "queue": "running",
  "disk_space": "45GB available"
}
```

### Metrics to Track

**Server-Level**:
- CPU usage
- RAM usage
- Disk space
- Active sites count

**Environment-Level**:
- Creation time
- Deployment success rate
- Database size
- Queue job processing rate

### Alerting

**Critical Alerts** (via GitHub comment or email):
- Environment creation failed
- Deployment failed
- Server resource exhaustion (>90% RAM)
- SSL certificate issuance failed

## Security Architecture

See [2-security-considerations.md](./2-security-considerations.md) for detailed security design.

**Key Security Principles**:
1. Site isolation (separate Linux users)
2. Database isolation (no shared data)
3. API key separation (test mode for external services)
4. Access control (basic auth on test environments)
5. Automatic cleanup (no abandoned environments)

## Failure Modes and Recovery

### Common Failures

**1. Site Creation Fails**
- **Cause**: Forge API error, server full, DNS issues
- **Recovery**: Retry with exponential backoff, alert developer

**2. Database Copy Fails**
- **Cause**: Master snapshot missing, disk space, connection timeout
- **Recovery**: Regenerate master snapshot, cleanup and retry

**3. SSL Certificate Fails**
- **Cause**: Rate limit, DNS not propagated, Let's Encrypt down
- **Recovery**: Wait and retry, fallback to HTTP temporarily (not ideal)

**4. Deployment Fails**
- **Cause**: Composer error, migration failure, code error
- **Recovery**: Post error message on PR, developer fixes and redeploys

**5. Cleanup Fails**
- **Cause**: Site already deleted, database locked, API error
- **Recovery**: Log error, schedule retry, manual cleanup if needed

### Circuit Breaker Pattern

**Prevent Cascade Failures**:
```python
if failed_attempts >= 3:
    pause_automation(duration="30 minutes")
    notify_admin("PR testing automation paused due to repeated failures")
```

## Technology Stack Summary

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Orchestration** | GitHub Actions | Trigger automation, call APIs |
| **Infrastructure** | Laravel Forge | Server management, deployments |
| **Compute** | Cloud VPS (DigitalOcean/Linode) | Host applications |
| **Web Server** | Nginx | Reverse proxy, SSL termination |
| **Application** | Laravel 10/11 + PHP 8.2 | Application framework |
| **Database** | MySQL 8.0 | Data storage |
| **Cache/Queue** | Redis 7.x | Caching, sessions, job queues |
| **SSL** | Let's Encrypt | Free SSL certificates |
| **DNS** | Cloudflare/AWS Route53/etc | Domain management |
| **Version Control** | GitHub | Code repository |

## Decision Log

### Key Architectural Decisions

**Decision 1: Per-Site Approach vs Wildcard Site**
- **Choice**: Create individual isolated sites per PR
- **Rationale**: Complete isolation, separate databases, easier cleanup
- **Trade-off**: More API calls, slightly more complex

**Decision 2: Shared Server vs Dedicated Test Server**
- **Choice**: Start with shared server
- **Rationale**: Cost-effective for 1-3 environments, easy to scale later
- **Trade-off**: Risk of resource contention (acceptable for small team)

**Decision 3: Manual Trigger vs Auto-Create**
- **Choice**: Manual trigger via `/preview` comment
- **Rationale**: Developer control, no wasted resources on draft PRs
- **Trade-off**: Requires extra step (acceptable)

**Decision 4: Real Data vs Synthetic Data**
- **Choice**: Real data from weekend peak snapshots
- **Rationale**: More realistic testing, catch real-world issues
- **Trade-off**: Requires snapshot maintenance (acceptable, automated)

**Decision 5: Let's Encrypt Per-Site vs Wildcard SSL**
- **Choice**: Let's Encrypt per-site
- **Rationale**: Simpler, automatic via Forge, well within rate limits
- **Trade-off**: 50 cert/week limit (not a concern for 1-3 environments)

## Next Steps

After understanding this architecture:

1. **Critical**: Read [2-security-considerations.md](./2-security-considerations.md)
2. **Critical**: Read [3-database-strategy.md](./3-database-strategy.md)
3. **Implementation**: Start with [../4-implementation/1-forge-setup-checklist.md](../4-implementation/1-forge-setup-checklist.md)
