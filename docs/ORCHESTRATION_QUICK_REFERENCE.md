# Orchestration Quick Reference

## Command Template

```bash
./scripts/orchestrate-pr-system.sh \
  --pr-number {PR_NUMBER} \
  --project-name {PROJECT_NAME} \
  --github-branch {GITHUB_BRANCH}
```

## Minimal Example

```bash
export FORGE_API_TOKEN="your-token-here"

./scripts/orchestrate-pr-system.sh \
  --pr-number 123 \
  --project-name "my-app" \
  --github-branch "feature/my-feature"
```

## Full Example with All Options

```bash
export FORGE_API_TOKEN="your-token-here"
export PROVIDER="digitalocean"
export REGION="nyc3"
export SIZE="s-2vcpu-4gb"
export GITHUB_REPOSITORY="company/laravel-app"
export GITHUB_SSH_KEY_ID="12345"

./scripts/orchestrate-pr-system.sh \
  --pr-number 456 \
  --project-name "laravel-app" \
  --github-branch "bugfix/issue-789" \
  --provider "digitalocean" \
  --region "sfo3" \
  --size "s-4vcpu-8gb" \
  --log-dir "/var/log/forge"
```

## Environment Variables

### Required
- `FORGE_API_TOKEN` - Your Laravel Forge API token

### Optional with Defaults
- `FORGE_API_URL` - Default: `https://forge.laravel.com/api/v1`
- `PROVIDER` - Default: `digitalocean` (aws, linode, vultr, hetzner)
- `REGION` - Default: `nyc3`
- `SIZE` - Default: `s-2vcpu-4gb`
- `LOG_DIR` - Default: `./logs`

### Timeouts
- `MAX_PROVISIONING_WAIT` - Default: 3600s (1 hour)
- `MAX_DEPLOYMENT_WAIT` - Default: 1800s (30 minutes)
- `RETRY_INTERVAL` - Default: 10s
- `HEALTH_CHECK_RETRIES` - Default: 5

## Command Line Arguments

| Flag | Purpose | Example |
|------|---------|---------|
| `--pr-number` | PR number (required) | `--pr-number 123` |
| `--project-name` | Project name (required) | `--project-name my-app` |
| `--github-branch` | GitHub branch (required) | `--github-branch feature/x` |
| `--provider` | Cloud provider | `--provider aws` |
| `--region` | Server region | `--region sfo3` |
| `--size` | Server size | `--size s-4vcpu-8gb` |
| `--github-repository` | Repository owner/repo | `--github-repository company/app` |
| `--github-ssh-key-id` | SSH key ID in Forge | `--github-ssh-key-id 12345` |
| `--log-dir` | Log directory | `--log-dir /var/log/forge` |
| `--help` | Show help | `--help` |

## Typical Execution Flow

```
1. Parse arguments
2. Check requirements (curl, jq, FORGE_API_TOKEN)
3. Validate inputs (PR number, project name, branch)
4. Create VPS server
5. Wait for provisioning (3-5 min)
6. Create site and database
7. Create database user
8. Grant database access
9. Clone database from master
10. Connect Git repository
11. Update environment variables
12. Create queue workers
13. Request SSL certificate
14. Deploy code
15. Wait for deployment (2-5 min)
16. Run health checks
17. Verify connectivity
18. Output success with PR URL
```

## Output Success Indicators

```bash
✓ VPS server created with ID: 12345
✓ Server is active and ready for configuration
✓ Site created with URL: https://pr-123-my-app.on-forge.com
✓ Database created: pr_123 (ID: 11111)
✓ Database user created: pr_123_user
✓ Database user access granted
✓ Git repository installed
✓ Environment variables updated
✓ Queue worker created
✓ SSL certificate installation initiated
✓ Deployment initiated
✓ Deployment completed successfully
✓ Site is healthy and ready
✓ HTTP connectivity verified
```

## Accessing PR Environment

Once orchestration succeeds:

### Via Browser
```
https://pr-{NUMBER}-{PROJECT}.on-forge.com
```

Example:
```
https://pr-123-my-app.on-forge.com
```

### Via SSH
```bash
# Extract server IP from state file
source logs/.pr-orchestration-state

# SSH into server
ssh root@$SERVER_IP
```

### Using Forge Dashboard
1. Log into Forge: https://forge.laravel.com
2. Select server: `pr-{NUMBER}-{PROJECT}`
3. Browse sites, databases, deployments

## State File Location

After orchestration:

```bash
logs/.pr-orchestration-state
```

Contains:
- `SERVER_ID` - Server identifier
- `SITE_ID` - Site identifier
- `DATABASE_ID` - Database identifier
- `PR_URL` - Complete PR test URL
- `DB_USER` - Database username
- `DB_PASSWORD` - Database password
- `TIMESTAMP` - Orchestration timestamp

## Log Locations

```
logs/orchestrate-pr-YYYYMMDD_HHMMSS.log
```

Follow logs in real-time:

```bash
tail -f logs/orchestrate-pr-*.log
```

## Common Cloud Provider Regions

### DigitalOcean
- `nyc1`, `nyc3` - New York
- `sfo2`, `sfo3` - San Francisco
- `lon1` - London
- `tor1` - Toronto
- `ams3` - Amsterdam
- `fra1` - Frankfurt

### AWS
- `us-east-1` - N. Virginia
- `us-west-2` - Oregon
- `eu-west-1` - Ireland
- `ap-southeast-1` - Singapore

### Linode
- `us-east` - Newark
- `us-west` - Fremont
- `eu-west` - London
- `ap-south` - Singapore

## Server Sizes

### DigitalOcean (monthly pricing)
- `s-1vcpu-1gb` - $5
- `s-2vcpu-2gb` - $12
- `s-2vcpu-4gb` - $18 (recommended)
- `s-4vcpu-8gb` - $36
- `s-6vcpu-16gb` - $72

## Success Criteria

Orchestration is successful when:

1. Server is provisioned and active
2. Site responds to HTTP requests
3. Database is accessible
4. Code is deployed from GitHub
5. SSL certificate is installed
6. PR URL is accessible

## Failure Recovery

If orchestration fails:

1. **Check logs:**
   ```bash
   tail -100 logs/orchestrate-pr-*.log
   ```

2. **Review state:**
   ```bash
   cat logs/.pr-orchestration-state
   ```

3. **Manual cleanup (if needed):**
   ```bash
   # Delete server via Forge API
   curl -X DELETE \
     -H "Authorization: Bearer $FORGE_API_TOKEN" \
     https://forge.laravel.com/api/v1/servers/{SERVER_ID}
   ```

4. **Retry orchestration:**
   ```bash
   ./scripts/orchestrate-pr-system.sh \
     --pr-number {PR_NUMBER} \
     --project-name {PROJECT_NAME} \
     --github-branch {GITHUB_BRANCH}
   ```

## Parallel Execution

Run multiple PR environments concurrently:

```bash
#!/bin/bash
for pr in 100 101 102 103; do
    ./scripts/orchestrate-pr-system.sh \
      --pr-number "$pr" \
      --project-name "my-app" \
      --github-branch "feature/pr-$pr" &
done

wait
echo "All PR environments ready"
```

## CI/CD Integration

### GitHub Actions

```yaml
name: PR Testing Environment

on:
  pull_request:
    types: [opened]

env:
  FORGE_API_TOKEN: ${{ secrets.FORGE_API_TOKEN }}

jobs:
  orchestrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Create PR Testing Environment
        run: |
          ./scripts/orchestrate-pr-system.sh \
            --pr-number ${{ github.event.pull_request.number }} \
            --project-name "my-app" \
            --github-branch "${{ github.head_ref }}"
```

## Monitoring

```bash
# Watch all logs
watch -n 5 'tail logs/orchestrate-pr-*.log | tail -20'

# Count servers
curl -s -H "Authorization: Bearer $FORGE_API_TOKEN" \
  https://forge.laravel.com/api/v1/servers | jq '.servers | length'

# List PR servers
curl -s -H "Authorization: Bearer $FORGE_API_TOKEN" \
  https://forge.laravel.com/api/v1/servers | \
  jq '.servers[] | select(.name | startswith("pr-")) | {id, name, status}'
```

## API Endpoints Used

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/servers` | Create VPS |
| GET | `/servers/{id}` | Check status |
| POST | `/servers/{id}/sites` | Create site |
| POST | `/servers/{id}/databases` | Create database |
| POST | `/servers/{id}/database-users` | Create user |
| POST | `/servers/{id}/database-users/{id}/databases` | Grant access |
| POST | `/servers/{id}/sites/{id}/git-projects` | Connect Git |
| POST | `/servers/{id}/sites/{id}/env` | Environment vars |
| POST | `/servers/{id}/workers` | Create worker |
| POST | `/servers/{id}/ssl-certificates` | Request SSL |
| POST | `/servers/{id}/sites/{id}/deployment/deploy` | Deploy |
| GET | `/servers/{id}/sites/{id}/deployments/{id}` | Check deployment |
| GET | `/servers/{id}/sites/{id}` | Check site |

## Cleanup Commands

### Delete Single PR Environment

```bash
source logs/.pr-orchestration-state

curl -X DELETE \
  -H "Authorization: Bearer $FORGE_API_TOKEN" \
  https://forge.laravel.com/api/v1/servers/$SERVER_ID

echo "Server $SERVER_ID deleted"
```

### Delete All PR Servers

```bash
curl -s -H "Authorization: Bearer $FORGE_API_TOKEN" \
  https://forge.laravel.com/api/v1/servers | \
  jq -r '.servers[] | select(.name | startswith("pr-")) | .id' | \
  while read id; do
    curl -X DELETE \
      -H "Authorization: Bearer $FORGE_API_TOKEN" \
      https://forge.laravel.com/api/v1/servers/$id
    echo "Deleted server: $id"
  done
```

## Troubleshooting Checklist

- [ ] FORGE_API_TOKEN is valid
- [ ] curl and jq are installed
- [ ] PR number is unique
- [ ] Project name is valid (no special chars)
- [ ] GitHub branch exists
- [ ] Cloud provider has available resources
- [ ] SSH key is configured in Forge
- [ ] GitHub repository is accessible
- [ ] DNS can resolve on-forge.com domains

## Performance Expectations

| Step | Typical Time |
|------|--------------|
| VPS Provisioning | 3-5 min |
| Configuration | 1-2 min |
| Deployment | 2-5 min |
| Health Checks | 1-2 min |
| **Total** | **7-14 min** |

## Documentation References

- [orchestrate-pr-system.sh](../scripts/orchestrate-pr-system.sh) - Full script
- [ORCHESTRATION_GUIDE.md](./ORCHESTRATION_GUIDE.md) - Complete guide
- [Laravel Forge API](https://forge.laravel.com/api-documentation)
- [Forge Documentation](https://forge.laravel.com/docs)
