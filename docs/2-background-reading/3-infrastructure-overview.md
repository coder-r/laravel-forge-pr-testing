# Infrastructure Overview

## Current Projects

### 1. keatchen-customer-app

**Purpose**: Customer-facing ordering application

**Production URL**: https://app.kitthub.com/

**Technology Stack**:
- Framework: Laravel (version TBD - check composer.json)
- PHP: 8.x
- Database: MySQL or PostgreSQL (<5GB)
- Queue: Laravel Horizon with Redis
- Cache: Redis
- External APIs: Payment processing (Stripe/similar)

**Hosting**: Laravel Forge (existing setup)

**Git Repository**: GitHub (private repository)
- Current deployment: Automated via Forge on push to `main` branch
- Deployment script: Custom Forge deployment script

**Environment Management**:
- Using Forge environment variables
- Environment variables managed through Forge interface

**Key Dependencies**:
- Queue workers for background job processing
- External payment API integrations
- Redis for caching and sessions

### 2. devpel-epos

**Purpose**: EPOS (Electronic Point of Sale) system

**Production URL**: https://dev.kitthub.com/admin/login/validate2/rameez/takeaway786ttt/select-order

**Technology Stack**:
- Framework: Laravel (version TBD - check composer.json)
- PHP: 8.x
- Database: MySQL or PostgreSQL (<5GB)
- Queue: Laravel Horizon with Redis
- Cache: Redis
- External APIs: Payment processing

**Hosting**: Laravel Forge (existing setup)

**Git Repository**: GitHub (private repository)
- Current deployment: Automated via Forge on push
- Deployment script: Custom Forge deployment script

**Environment Management**:
- Using Forge environment variables
- Separate from keatchen-customer-app

**Key Dependencies**:
- Queue workers for order processing
- External payment API integrations
- Redis for caching and sessions

## Project Independence

**Critical Fact**: These projects are **completely independent**:
- ✅ Separate codebases
- ✅ Separate databases (no shared data)
- ✅ Separate deployments
- ✅ Separate environment variables
- ✅ Can be deployed/tested independently

**Implication for PR Testing**: We can use the **same infrastructure pattern** for both projects, just duplicate the setup.

## Current Deployment Workflow

### Existing Forge Setup

Both projects currently use:
1. GitHub repository integration
2. Automated deployment on push to main branch
3. Custom deployment scripts in Forge
4. Environment variable management via Forge interface

### Deployment Process (Current)

```
Developer commits to main branch
   ↓
GitHub webhook triggers Forge
   ↓
Forge runs deployment script:
   - git pull
   - composer install
   - npm run build (if needed)
   - php artisan migrate --force
   - php artisan config:cache
   - php artisan route:cache
   - php artisan queue:restart
   ↓
Production updated
```

## Database Overview

### Size and Growth

**Current State**:
- Both databases: <5GB each
- Growth rate: Stable (small restaurant business)
- Total data: ~10GB for both projects combined

**Peak Times**:
- Busiest: Weekend evenings (Friday/Saturday 6pm-10pm)
- Orders: Highest volume during these times
- Realistic test data: Best captured on Sunday morning (post-peak)

**Database Structure** (typical for restaurant apps):
- Orders and order items
- Customers and addresses
- Menu items and categories
- Payment transactions
- User accounts
- Settings and configurations

### Database Replication Feasibility

**Excellent for replication**:
- ✅ Small size (<5GB) means quick replication
- ✅ No PII concerns mentioned
- ✅ Realistic data available from weekend peaks
- ✅ Snapshot strategy is simple and fast

**Estimated Replication Time**:
- Master snapshot creation: ~3-5 minutes
- Per-environment clone: ~2-3 minutes
- Total per PR: <10 minutes including deployment

## Current Forge Configuration

### Server Details (To Be Confirmed)

Need to gather from Forge:
- Server size (CPU, RAM, storage)
- Server location (region)
- PHP version installed
- Database version (MySQL 8.0 / PostgreSQL 15?)
- Redis version
- Node.js version
- Current resource utilization

### Sites Currently Configured

1. **keatchen-customer-app** production site
   - Domain: app.kitthub.com
   - Repository: Connected to GitHub
   - Deployment: Automated
   - SSL: Active (Let's Encrypt)
   - Queue workers: Configured

2. **devpel-epos** production site
   - Domain: dev.kitthub.com
   - Repository: Connected to GitHub
   - Deployment: Automated
   - SSL: Active (Let's Encrypt)
   - Queue workers: Configured

### DNS Configuration (Current)

**Existing DNS Records**:
- `app.kitthub.com` → Forge server IP (A record)
- `dev.kitthub.com` → Forge server IP (A record)

**Need to Add**:
- `*.staging.kitthub.com` → Forge server IP (A record)

This wildcard record will allow us to create any subdomain under `staging.kitthub.com` dynamically.

## External Service Integrations

### Payment Processing

Both projects integrate with payment gateways (likely Stripe or similar).

**For Testing**:
- Need TEST API keys configured in test environments
- Ensure payment gateway supports test mode
- Document test credit cards / payment methods

### Email Services

Both projects likely send transactional emails.

**For Testing**:
- Consider using Mailtrap or similar for test environments
- Prevent test environments from sending real customer emails
- Configure separate email settings per environment

### Other Integrations (To Verify)

Potential integrations to check:
- SMS notifications (Twilio?)
- Delivery tracking systems
- POS hardware integrations (for EPOS)
- Analytics (Google Analytics, Mixpanel?)
- Error tracking (Sentry, Bugsnag?)

## Resource Usage Patterns

### Peak Load Characteristics

**Weekend Evening Peak** (Friday/Saturday 6pm-10pm):
- Highest order volume
- Most concurrent users
- Maximum queue job processing
- Peak database queries

**Why This Matters**:
- Database snapshots from this period contain realistic peak data
- Test environments can simulate real-world load scenarios
- Helps catch performance issues before production

### Typical Resource Usage (To Be Measured)

Need to gather:
- Average CPU usage during peak
- Average RAM usage during peak
- Database query performance metrics
- Queue job processing rates
- Redis memory usage

## Proposed Testing Infrastructure

### Option 1: Shared Server (Recommended)

**Use existing production server** or provision new dedicated test server:

```
┌─────────────────────────────────────────────────┐
│           Forge Server (4-8GB RAM)               │
├─────────────────────────────────────────────────┤
│ Production Sites:                                │
│  - app.kitthub.com (keatchen-customer-app)      │
│  - dev.kitthub.com (devpel-epos)                │
├─────────────────────────────────────────────────┤
│ Test Environments (Isolated):                    │
│  - pr-123.staging.kitthub.com (isolated user)   │
│  - pr-456.staging.kitthub.com (isolated user)   │
│  - pr-789.staging.kitthub.com (isolated user)   │
├─────────────────────────────────────────────────┤
│ Shared Resources:                                │
│  - Master DB Snapshots (keatchen_master)        │
│  - Master DB Snapshots (devpel_master)          │
│  - Redis (separate DB per environment)          │
└─────────────────────────────────────────────────┘
```

**Pros**:
- Cost-effective ($20-40/month for dedicated test server)
- Simple architecture
- Leverages existing Forge knowledge
- Suitable for 1-3 concurrent environments

**Cons**:
- Resource contention if too many concurrent PRs
- Shared server means one site issue could affect others (mitigated by site isolation)

### Option 2: Separate Server Per Project

```
┌──────────────────────────┐  ┌──────────────────────────┐
│  Forge Server 1          │  │  Forge Server 2          │
│  (keatchen-customer-app) │  │  (devpel-epos)          │
├──────────────────────────┤  ├──────────────────────────┤
│ Production:              │  │ Production:              │
│  - app.kitthub.com       │  │  - dev.kitthub.com       │
├──────────────────────────┤  ├──────────────────────────┤
│ Test:                    │  │ Test:                    │
│  - pr-*.app.staging...   │  │  - pr-*.dev.staging...   │
└──────────────────────────┘  └──────────────────────────┘
```

**Pros**:
- Complete isolation between projects
- No resource contention between projects
- Easier to debug issues

**Cons**:
- Double the cost ($40-80/month)
- More complex management
- Overkill for small team

**Recommendation**: Start with Option 1 (shared server), scale to Option 2 if needed.

## Network Architecture

### Current Setup

```
Internet
   ↓
DNS (kitthub.com)
   ↓
Forge Server (DigitalOcean/Linode/AWS)
   ↓
Nginx (reverse proxy)
   ↓
PHP-FPM (Laravel applications)
   ↓
MySQL/PostgreSQL (databases)
Redis (cache/queues)
```

### Proposed Addition for Testing

```
Internet
   ↓
DNS (*.staging.kitthub.com wildcard)
   ↓
Forge Server
   ↓
Nginx (handles all pr-*.staging.kitthub.com)
   ↓
Isolated Sites:
   - /home/pr123user/pr-123.staging.kitthub.com
   - /home/pr456user/pr-456.staging.kitthub.com
   - /home/pr789user/pr-789.staging.kitthub.com
```

Each site:
- Runs under separate Linux user (site isolation)
- Has own PHP-FPM pool
- Has own database
- Uses separate Redis database number

## Security Considerations

### Current Production Security

Assumed production security measures:
- SSL/TLS certificates (Let's Encrypt)
- Firewall (UFW configured by Forge)
- SSH key authentication
- Automatic security updates
- Private GitHub repositories

### Additional Security for Test Environments

Need to add:
- Basic authentication for test environments (prevent public access)
- Separate API keys (use TEST mode for payments)
- Environment isolation (site isolation feature)
- Automatic cleanup (prevent abandoned test environments)

## Monitoring and Logging

### Current Monitoring (To Be Confirmed)

Check if already using:
- Forge monitoring (basic server metrics)
- Application monitoring (Sentry, Bugsnag?)
- Log aggregation (Papertrail, Loggly?)
- Uptime monitoring (Oh Dear, Pingdom?)

### Recommended for Test Environments

Minimal monitoring:
- Health check endpoint per environment
- Deployment success/failure notifications
- Resource usage alerts (if server overwhelmed)
- Automatic cleanup verification

## Backup Strategy

### Production Backups (Current)

Assumed:
- Database backups (Forge built-in or manual)
- Code in GitHub (version controlled)
- Environment variables documented

### Test Environment Backups

Not needed:
- Test environments are ephemeral
- Can be recreated from scratch
- Database comes from production snapshots

## Cost Estimation

### Current Infrastructure Costs

Approximate (to be confirmed):
- Forge account: $13-19/month
- Server hosting: $20-80/month (depending on size)
- Domain registration: $10-15/year
- Total: ~$35-100/month

### Additional Costs for PR Testing

**Shared Server Approach**:
- Upgrade server size (if needed): +$10-20/month
- Additional disk space: $0-10/month
- Total additional: $10-30/month

**Dedicated Test Server**:
- Additional server: $20-40/month
- Additional disk space: $0-10/month
- Total additional: $20-50/month

**GitHub Actions** (if using free tier):
- 2,000 minutes/month free
- Estimated usage: ~500 minutes/month (well within limits)
- Cost: $0

**Total New Cost**: $10-50/month (flexible, as stated in requirements)

## Migration Path

### Minimal Disruption Approach

1. **Add wildcard DNS** (no downtime, just DNS addition)
2. **Create test sites on same server** (no impact on production)
3. **Test automation with real PRs** (production unaffected)
4. **Roll out to team** (gradual adoption)

No production downtime required!

## Next Steps

Now that you understand the current infrastructure:

1. **Critical**: Read [3-critical-reading/1-architecture-design.md](../3-critical-reading/1-architecture-design.md)
2. **Critical**: Read [3-critical-reading/3-database-strategy.md](../3-critical-reading/3-database-strategy.md)
3. **Then**: Start implementation with [4-implementation/1-forge-setup-checklist.md](../4-implementation/1-forge-setup-checklist.md)
