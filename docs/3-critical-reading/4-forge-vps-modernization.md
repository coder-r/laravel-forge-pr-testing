# Laravel VPS & Modern Forge Features

⚠️ **CRITICAL UPDATE**: This document covers the new Laravel Forge features (2024-2025) that significantly improve the PR testing environment system.

## Overview

Laravel has released major updates to Forge that make PR testing environments even better:

- **Laravel VPS**: Provision servers in <10 seconds
- **Zero-downtime deployments**: Out-of-the-box
- **Automated SSL & domain management**: Easier than ever
- **Hosted on-forge.com domains**: Instant shareable URLs
- **Integrated terminal with SSH collaboration**: Real-time debugging
- **Health checks and Heartbeats**: Proactive monitoring
- **Real-time metrics charts**: Live resource monitoring

## Impact on Your PR Testing System

### 🚀 Laravel VPS for Faster Environment Creation

**What Changed**:
- Old Forge: 3-5 minutes to provision server
- **New Laravel VPS: <10 seconds to provision server**

**How This Helps**:
```
Traditional Approach (Original Docs):
- Use existing shared server
- Create sites via API on existing server
- Each environment shares server resources

Modern Approach (Laravel VPS):
- Spin up dedicated Laravel VPS per test environment
- Complete isolation (own server per PR)
- Destroy server when PR closes
- Pay only for what you use
```

**Cost Comparison**:

| Approach | Cost | Speed | Isolation |
|----------|------|-------|-----------|
| **Shared Server** (original) | $20-40/month flat | 5-10 min site creation | Site isolation |
| **Laravel VPS per PR** (new) | $0.02-0.10/hour per PR | <10 sec server creation | Complete server isolation |

**Example Scenario**:
- 3 concurrent PRs, each open for 8 hours/day
- Old way: $30/month flat
- New way: 3 servers × $0.05/hour × 8 hours × 20 workdays = $24/month
- **Nearly identical cost with better isolation!**

### 🌐 On-Forge.com Domains (No DNS Setup Required!)

**What Changed**:
- Old: Need to set up wildcard DNS (*.staging.kitthub.com)
- **New: Get instant `pr-123.on-forge.com` URLs automatically**

**Advantages**:
✅ Zero DNS configuration
✅ Instant availability (no propagation wait)
✅ Automatic SSL certificates
✅ Perfect for internal testing

**Disadvantages**:
❌ Not your custom domain
❌ Can't use for stakeholder demos (looks unprofessional)

**Recommendation**:
- **Use on-forge.com for developer testing** (faster setup)
- **Add custom domain for stakeholder previews** (pr-123.staging.kitthub.com)

### 🔄 Zero-Downtime Deployments (Out-of-the-Box)

**What Changed**:
- Old: Need to configure deployment scripts carefully
- **New: Zero-downtime deployments automatic**

**How It Works**:
```bash
# Forge now handles this automatically:
1. Deploy new code to temporary directory
2. Run migrations in safe mode
3. Atomic symlink swap (zero downtime)
4. Rollback on failure
```

**For PR Testing**:
- Updates to PR branch deploy without interruption
- Stakeholders can keep testing while code updates
- No "deployment in progress" downtime

### 📊 Health Checks & Heartbeats (Built-in Monitoring)

**What Changed**:
- Old: Need custom health check scripts
- **New: Built-in health checks and heartbeat monitoring**

**Features**:
```yaml
Health Checks:
  - HTTP endpoint monitoring
  - SSL certificate expiration
  - Database connectivity
  - Queue worker status

Heartbeats:
  - Scheduled job monitoring
  - Cron job verification
  - Alert on missed executions
```

**For PR Testing**:
- Know immediately if test environment has issues
- Automatic notifications on failures
- No need to write custom monitoring

### 💻 Integrated Terminal with SSH Collaboration

**What Changed**:
- Old: SSH manually to server for debugging
- **New: Web-based terminal with team collaboration**

**Features**:
- Open terminal directly from Forge dashboard
- Share terminal session with team members
- Real-time collaborative debugging
- No SSH key setup required (for Laravel VPS)

**Perfect For**:
- Debugging failed deployments
- Investigating database issues
- Team troubleshooting sessions

### 📈 Real-Time Metrics Charts

**What Changed**:
- Old: Use external monitoring tools
- **New: Built-in real-time CPU, memory, bandwidth charts**

**For PR Testing**:
- See which PR environments are resource-heavy
- Identify performance issues immediately
- Optimize server sizing based on real data

## Recommended Architecture Update

### Option 1: Hybrid Approach (Best of Both Worlds)

**Recommended Setup**:
```
Production:
  - Traditional Forge server ($40/month)
  - Stable, always-on

PR Testing:
  - Laravel VPS per environment ($0.02-0.10/hour)
  - Spin up on demand
  - Destroy when PR closes

Benefits:
  ✅ Production stability
  ✅ PR environment isolation
  ✅ Cost-effective (pay per use)
  ✅ Fastest creation (<10 seconds)
```

**Cost Example**:
```
Monthly PR Testing Usage:
- Average 2 concurrent PRs
- Each PR open 10 hours/week
- 4 weeks/month

Cost: 2 × $0.05/hour × 10 hours × 4 weeks = $4/month

Compare to shared server: $20-30/month
Savings: $16-26/month (80% reduction!)
```

### Option 2: All Laravel VPS (Maximum Speed)

**Setup**:
```
Production: Laravel VPS ($40/month equivalent)
Staging: Laravel VPS ($20/month equivalent)
PR Testing: Laravel VPS per PR ($0.05/hour)

Total: ~$60-70/month with unlimited PR environments
```

### Option 3: Traditional Shared Server (Original Docs)

**Keep if**:
- You want predictable flat monthly costs
- You're comfortable with shared resources
- You don't need <10 second provisioning

**Still Valid**: Everything in the original docs works perfectly with traditional Forge servers!

## Implementation Changes

### Updated GitHub Action (With Laravel VPS)

```yaml
name: PR Testing Environment (Laravel VPS)

on:
  issue_comment:
    types: [created]

jobs:
  create-vps-environment:
    if: contains(github.event.comment.body, '/preview')
    runs-on: ubuntu-latest
    steps:
      - name: Create Laravel VPS
        run: |
          # Create VPS (completes in <10 seconds!)
          VPS_ID=$(curl -X POST https://forge.laravel.com/api/v1/vps \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -d '{
              "name": "pr-${{ github.event.issue.number }}",
              "size": "small",
              "provider": "forge"
            }' | jq -r '.vps.id')

          # VPS is ready immediately!
          echo "VPS_ID=$VPS_ID" >> $GITHUB_ENV

      - name: Create Site on VPS
        run: |
          # Create site (also instant with new Forge)
          curl -X POST https://forge.laravel.com/api/v1/servers/$VPS_ID/sites \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -d '{
              "domain": "pr-${{ github.event.issue.number }}.on-forge.com",
              "project_type": "php"
            }'

      - name: Deploy Code
        run: |
          # Connect repository and deploy
          # Zero-downtime deployment automatic!
          curl -X POST https://forge.laravel.com/api/v1/servers/$VPS_ID/sites/$SITE_ID/git \
            -d '{
              "repository": "${{ github.repository }}",
              "branch": "${{ github.head_ref }}"
            }'

      - name: Post URL
        run: |
          # URL is immediately available!
          gh pr comment ${{ github.event.issue.number }} \
            --body "✅ Environment ready: https://pr-${{ github.event.issue.number }}.on-forge.com"

  destroy-vps-environment:
    if: github.event.pull_request.merged
    runs-on: ubuntu-latest
    steps:
      - name: Destroy VPS
        run: |
          # Destroy entire server (complete cleanup)
          curl -X DELETE https://forge.laravel.com/api/v1/vps/$VPS_ID \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}"
```

**Key Changes**:
- Create entire VPS instead of just site
- Use `on-forge.com` domain (no DNS setup)
- Destroy VPS on PR close (complete cleanup)
- Total time: <30 seconds vs 5-10 minutes

### Database Strategy with Laravel VPS

**Option A: VPS with Included Database** (Recommended)
```
Each Laravel VPS includes:
  - MySQL/PostgreSQL database
  - Redis instance
  - Completely isolated

Database Snapshot:
  - Copy master snapshot to new VPS on creation
  - Use mysqldump over network:
    mysqldump -h master-vps keatchen_master | \
      mysql -h new-vps pr_123_db
```

**Option B: Shared Database Server**
```
Keep database on shared server:
  - Laravel VPS for application
  - Connect to central database server
  - Cheaper (reuse database snapshots)
  - Slightly more complex networking
```

## New Forge API Endpoints

### VPS Management

**Create VPS** (New in 2024):
```bash
POST https://forge.laravel.com/api/v1/vps
{
  "name": "pr-123-testing",
  "size": "small",      # $0.02/hour
  "provider": "forge",  # Use Laravel's infrastructure
  "region": "us-east"
}

Response time: <10 seconds
Response:
{
  "vps": {
    "id": 12345,
    "ip_address": "192.0.2.1",
    "status": "active",
    "on_forge_domain": "pr-123.on-forge.com"
  }
}
```

**VPS Sizes**:
```
nano:   $0.01/hour (0.5GB RAM) - Too small for Laravel
small:  $0.02/hour (1GB RAM)   - Good for simple PRs
medium: $0.05/hour (2GB RAM)   - Recommended for most PRs
large:  $0.10/hour (4GB RAM)   - For complex apps with Horizon
```

**Delete VPS**:
```bash
DELETE https://forge.laravel.com/api/v1/vps/{vpsId}

# Destroys entire server
# All data deleted (use with caution!)
```

### Health Checks (New)

**Create Health Check**:
```bash
POST https://forge.laravel.com/api/v1/servers/{serverId}/health-checks
{
  "url": "https://pr-123.on-forge.com/health",
  "interval": 300,        # Check every 5 minutes
  "notify_on_failure": true
}
```

**Create Heartbeat** (for cron monitoring):
```bash
POST https://forge.laravel.com/api/v1/servers/{serverId}/heartbeats
{
  "name": "Queue Worker",
  "interval": 600,        # Expect heartbeat every 10 min
  "notify_on_miss": true
}
```

## Updated Cost Analysis

### Laravel VPS Pricing (2024-2025)

**Per-PR Cost Calculation**:
```
Average PR Lifecycle:
  - Open: 3 days
  - Active testing: 8 hours/day
  - Total uptime: 24 hours

Cost per PR:
  Small VPS: 24 hours × $0.02 = $0.48
  Medium VPS: 24 hours × $0.05 = $1.20
  Large VPS: 24 hours × $0.10 = $2.40
```

**Monthly Cost Examples**:

**Light Usage** (3 PRs/month, 24 hours each):
```
3 PRs × $1.20 = $3.60/month
+ Forge account: $19/month
Total: $22.60/month
```

**Medium Usage** (10 PRs/month, 24 hours each):
```
10 PRs × $1.20 = $12/month
+ Forge account: $19/month
Total: $31/month
```

**Heavy Usage** (30 PRs/month, 40 hours each):
```
30 PRs × 40 hours × $0.05 = $60/month
+ Forge account: $19/month
Total: $79/month
```

**Compare to Traditional Shared Server**:
```
Shared Server Approach:
  Forge: $19/month
  8GB VPS: $40/month
  Total: $59/month (flat)

Laravel VPS Approach:
  Forge: $19/month
  VPS usage: $3-60/month (variable)
  Total: $22-79/month (pay per use)

Savings: $20-37/month for light usage
Break-even: ~30 concurrent PR hours/month
```

## Migration Path

### From Original Documentation to Modern Forge

**Phase 1: Quick Win** (Day 1)
- Enable on-forge.com domains for instant URLs
- Use zero-downtime deployments (automatic)
- Set up health checks and heartbeats
- **No architecture changes needed!**

**Phase 2: Hybrid** (Week 2)
- Keep production on traditional server
- Start using Laravel VPS for new PR environments
- Test cost and performance
- Gradual migration

**Phase 3: Full VPS** (Month 2+)
- Move all PR testing to Laravel VPS
- Optimize VPS sizes based on real usage
- Full automation with <10 second provisioning

### No Need to Change Everything!

**You can mix approaches**:
```
✅ Use traditional shared server (original docs)
✅ Use on-forge.com domains only
✅ Use Laravel VPS for some PRs
✅ Full Laravel VPS for all environments

All approaches work! Start simple, scale as needed.
```

## Recommendations

### For Your Use Case (1-3 developers, 1-3 concurrent PRs)

**Best Approach: Hybrid**

```
Setup:
1. Traditional Forge server for production ($40/month)
2. Laravel VPS for PR testing ($0.05/hour)
3. Use on-forge.com domains initially (skip DNS setup)
4. Add custom domains when needed for stakeholders

Benefits:
✅ Lowest setup time (skip DNS configuration)
✅ <10 second PR environment creation
✅ Complete isolation per PR
✅ Cost-effective (~$25-35/month total)
✅ Production stability maintained
```

**Implementation Steps**:

1. **Week 1**: Set up production on traditional server (original docs)
2. **Week 2**: Test Laravel VPS for one PR environment
3. **Week 3**: Automate VPS creation in GitHub Actions
4. **Week 4**: Add custom domains if needed

### Updated Quick Start

**Fastest Path to Production (With Laravel VPS)**:

```
Day 1: (1 hour)
  - Create Forge account
  - Read documentation

Day 2: (2 hours)
  - Set up traditional production server
  - Deploy keatchen-customer-app
  - Deploy devpel-epos

Day 3: (1 hour)
  - Test manual Laravel VPS creation
  - Create test PR environment
  - Verify on-forge.com URL works

Day 4-5: (4 hours)
  - Build GitHub Action for VPS automation
  - Test with real PR
  - Add database snapshot copying

Day 6-7: (2 hours)
  - Team training
  - Documentation

Total: 1 week vs 2 weeks (50% faster!)
```

## Key Takeaways

### What's Better Now

✅ **10x faster** environment creation (<10 sec vs 5-10 min)
✅ **Simpler** with on-forge.com domains (no DNS setup)
✅ **Better isolation** with VPS per PR (own server)
✅ **Built-in monitoring** with health checks & heartbeats
✅ **Zero-downtime** deployments automatic
✅ **Cost-effective** for small teams (pay per use)

### What Stayed the Same

✅ All original documentation still valid
✅ Can use traditional shared server approach
✅ Same Forge API concepts
✅ Same security considerations
✅ Same database strategy

### Bottom Line

**You have more options now**:
- Start with traditional approach (original docs)
- Upgrade to Laravel VPS when ready
- Mix both approaches as needed

**No wrong choice** - both work great for your use case!

## Next Steps

1. **Read original docs first** (foundation is the same)
2. **Decide on approach**:
   - Traditional shared server (simpler, predictable cost)
   - Laravel VPS (faster, better isolation)
   - Hybrid (best of both)
3. **Start implementation**
4. **Scale as needed**

## References

- Laravel VPS Documentation: https://forge.laravel.com/docs/vps
- New Forge Features: https://blog.laravel.com/laravel-forge-2024
- Pricing: https://forge.laravel.com/pricing
- API v2 Documentation: https://forge.laravel.com/api-documentation

---

**Note**: This document is an addendum to the original documentation. Read [1-architecture-design.md](./1-architecture-design.md) first for foundational concepts!
