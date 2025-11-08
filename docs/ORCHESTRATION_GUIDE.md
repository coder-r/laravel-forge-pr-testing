# PR Testing System Orchestration Guide

Complete Forge API orchestration for automated PR testing environments.

## Overview

The orchestration script (`scripts/orchestrate-pr-system.sh`) automates the complete lifecycle of PR testing environments:

- Creates VPS servers on cloud providers
- Configures sites with SSL certificates
- Sets up databases and clones from master
- Deploys code from GitHub branches
- Validates health and connectivity
- Manages rollback on failure

## 15-Step Orchestration Pipeline

### 1. Create VPS Server
```
POST /servers
```
- Creates server with specified cloud provider
- Idempotent: checks if server already exists
- Adds to rollback stack for cleanup on failure

### 2. Wait for VPS Provisioning
```
GET /servers/{id}
```
- Polls server status until `active`
- Configurable timeout (default: 3600s)
- Extractable server IP address

### 3. Create Site with Domain
```
POST /servers/{id}/sites
```
- Creates Laravel site
- Assigns `pr-{NUMBER}-{PROJECT}.on-forge.com` domain
- Returns site ID for subsequent operations

### 4. Create Database
```
POST /servers/{id}/databases
```
- Creates database named `pr_{NUMBER}`
- Returns database ID
- Added to rollback stack

### 5. Create Database User
```
POST /servers/{id}/database-users
```
- Creates user `pr_{NUMBER}_user`
- Generates secure password (openssl rand -base64 32)
- Saves credentials to state file

### 6. Grant Database Access
```
POST /servers/{id}/database-users/{user_id}/databases
```
- Grants user access to specific database
- Enables user to connect

### 7. Clone Database from Master
- SSH into master server
- `mysqldump` database from master
- Import dump into PR database
- Skips gracefully if master not found

### 8. Install Git Repository Connection
```
POST /servers/{id}/sites/{id}/git-projects
```
- Connects GitHub repository
- Sets branch for deployment
- Requires GitHub SSH key in Forge

### 9. Update Environment Variables
```
POST /servers/{id}/sites/{id}/env
```
- Sets testing environment: `APP_ENV=testing`
- Configures for testing: `CACHE_DRIVER=array`
- Sets queue driver: `QUEUE_DRIVER=sync`

### 10. Create Queue Workers
```
POST /servers/{id}/workers
```
- Creates background job worker
- Non-critical: continues if fails

### 11. Obtain SSL Certificate
```
POST /servers/{id}/ssl-certificates
```
- Requests Let's Encrypt certificate
- Automatic renewal
- Non-critical: continues if fails

### 12. Deploy Code
```
POST /servers/{id}/sites/{id}/deployment/deploy
```
- Triggers deployment of GitHub branch
- Returns deployment ID for polling

### 13. Wait for Deployment Completion
```
GET /servers/{id}/sites/{id}/deployments/{id}
```
- Polls deployment status
- Timeout: 1800 seconds (default)
- Confirms code deployment success

### 14. Run Health Checks
```
GET /servers/{id}/sites/{id}
```
- Verifies site status
- Retries up to 5 times
- Ensures site is operational

### 15. Verify Connectivity
- HTTP/HTTPS connectivity test
- Confirms site responds to requests
- 10 attempts with 10-second intervals

## Quick Start

### Prerequisites

```bash
# Set environment variables
export FORGE_API_TOKEN="your-laravel-forge-api-token"
export PROVIDER="digitalocean"  # or aws, linode, vultr, hetzner
export REGION="nyc3"
export SIZE="s-2vcpu-4gb"
```

### Basic Usage

```bash
# Create PR testing environment
./scripts/orchestrate-pr-system.sh \
  --pr-number 123 \
  --project-name "my-app" \
  --github-branch "feature/new-feature"
```

### Full Configuration

```bash
./scripts/orchestrate-pr-system.sh \
  --pr-number 456 \
  --project-name "laravel-app" \
  --github-branch "bugfix/issue-789" \
  --provider "digitalocean" \
  --region "sfo3" \
  --size "s-4vcpu-8gb" \
  --github-repository "company/laravel-app" \
  --github-ssh-key-id "12345" \
  --log-dir "./logs"
```

## Output

On success, the script outputs the PR URL and server details for accessing the testing environment.

## Error Handling

### Automatic Rollback

If any critical step fails, the script automatically rolls back:

1. Deletes created server
2. Deletes created database
3. Logs all rollback actions
4. Exits with error code

### Graceful Degradation

Non-critical steps continue on failure:

- Database cloning
- Environment variables
- Queue workers
- SSL certificate
- Health checks
- Connectivity tests

These failures are logged but don't prevent orchestration completion.

## Configuration

### Environment Variables

```bash
# Required
export FORGE_API_TOKEN="your-api-token"

# Optional (with defaults)
export FORGE_API_URL="https://forge.laravel.com/api/v1"
export PROVIDER="digitalocean"
export REGION="nyc3"
export SIZE="s-2vcpu-4gb"
export MAX_PROVISIONING_WAIT="3600"
export MAX_DEPLOYMENT_WAIT="1800"
```

## State and Resume

The script saves state to: `logs/.pr-orchestration-state`

Contains:
- PR number and project name
- Server and site IDs
- Database information
- PR URL and credentials

## Troubleshooting

### Server Creation Fails
- Verify FORGE_API_TOKEN is valid
- Check cloud provider limits
- Ensure region is valid

### Provisioning Timeout
- Check cloud provider dashboard
- Increase MAX_PROVISIONING_WAIT
- Check Forge notifications

### Deployment Fails
- Check GitHub branch exists
- Verify SSH key has GitHub access
- Check deployment log via API

## Integration with CI/CD

### GitHub Actions

```yaml
- name: Orchestrate PR Environment
  env:
    FORGE_API_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
  run: |
    ./scripts/orchestrate-pr-system.sh \
      --pr-number ${{ github.event.pull_request.number }} \
      --project-name "my-app" \
      --github-branch "${{ github.head_ref }}"
```

## Performance

Typical orchestration times:
- Server provisioning: 3-5 minutes
- Site configuration: 30-60 seconds
- Code deployment: 2-5 minutes
- Total: 7-14 minutes

## Security

1. Never commit API token
2. Database passwords generated securely
3. Restrict state file access: `chmod 600`
4. Ensure SSH keys in Forge
5. Firewall rules created automatically

## API Rate Limits

- 30 requests/minute - General endpoints
- 10 requests/minute - Server creation
- 5 requests/minute - Deployment

Script respects these limits with built-in delays.

## See Also

- [create-vps-environment.sh](./create-vps-environment.sh) - Individual VPS creation
- [health-check.sh](./health-check.sh) - Post-deployment health validation
- [Laravel Forge API Docs](https://forge.laravel.com/api-documentation)
