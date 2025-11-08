# ⚡ Quick Start - Laravel PR Testing Environment

**15-minute executive summary**

## 🎯 What You're Building

An **automated PR testing system** that creates production-like environments on-demand for your two Laravel applications:

- **keatchen-customer-app** (https://app.kitthub.com/)
- **devpel-epos** (https://dev.kitthub.com/)

### The User Flow

```
Developer creates PR → Comments "/preview" → GitHub Action triggers
   ↓
Forge API creates new site (pr-123.on-forge.com)
   ↓
Database snapshot from weekend peak copied to new site
   ↓
Code deployed, queue workers started, SSL configured
   ↓
Stakeholders test at unique URL
   ↓
PR merged/closed → Site automatically deleted
```

## 🏗️ Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────┐
│                        GitHub                                │
│  ┌──────────┐    "/preview"     ┌────────────────┐         │
│  │    PR    │ ──────────────→   │ GitHub Actions │         │
│  └──────────┘                    └────────┬───────┘         │
└────────────────────────────────────────────┼──────────────────┘
                                             │ Forge API Call
                                             ↓
┌─────────────────────────────────────────────────────────────┐
│                    Laravel Forge Server                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Main Site (production or existing staging)         │   │
│  │  - app.kitthub.com                                   │   │
│  │  - dev.kitthub.com                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  PR Test Environments (auto-created on-forge.com)   │   │
│  │  - pr-123.on-forge.com (isolated, auto-SSL)         │   │
│  │  - pr-456.on-forge.com (isolated, auto-SSL)         │   │
│  │  - pr-789.on-forge.com (isolated, auto-SSL)         │   │
│  │                                                       │   │
│  │  💡 Optional: Custom DNS (pr-123.staging.kitthub.com)│  │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Shared Resources                                    │   │
│  │  - Master DB (weekend snapshot refreshed weekly)    │   │
│  │  - Redis (optional shared cache)                    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 💰 Cost Analysis

### Infrastructure Costs

**Option 1: Shared Server with On-Forge.com (Recommended - START HERE)**
- Forge server: $15-40/month (DigitalOcean/Linode 4GB-8GB)
- On-forge.com domains: $0 (included with Forge)
- SSL certificates: $0 (automatic via Forge)
- DNS setup: $0 (none required)
- **Total: $15-40/month**
- **Setup time: 1 day**

**Option 2: Custom DNS with Your Domain (Optional Enhancement)**
- Forge server: $15-40/month (same as above)
- DNS wildcard setup: $0 (use existing domain)
- SSL with DNS verification: Additional 2-3 hours setup
- **Total: $15-40/month**
- **Setup time: 2-3 days (includes DNS propagation)**

### Resource Costs Per Environment

Each PR test environment uses:
- **Disk space**: ~5GB (database snapshot) + ~500MB (code)
- **Memory**: ~256MB-512MB (Laravel + queue workers)
- **CPU**: Shared, minimal impact with 1-3 concurrent environments

### Database Snapshot Strategy

- **Weekly refresh**: Copy production DB on Sunday evening (post-peak)
- **Storage**: 1 master snapshot (~5GB) shared by all test environments
- **Replication**: Database cloned from master on PR creation (~2-3 minutes)

### Cost Comparison

| Approach | Monthly Cost | Setup Time | Pros | Cons |
|----------|-------------|------------|------|------|
| **On-Forge.com Domains** | $15-40 | **1 day** | ✅ Zero DNS config, instant SSL, ready immediately | URLs look less professional for stakeholders |
| **Custom DNS (staging.kitthub.com)** | $15-40 | 2-3 days | Professional branded URLs | Requires DNS setup, SSL verification |
| **Kubernetes/Docker** | $50-200+ | 2-3 weeks | Most scalable, modern | Overkill for 1-3 developers |

**Recommendation**: Start with **on-forge.com domains** to be testing in 1 day, then add custom DNS only if stakeholders need branded URLs.

## 🚀 Why On-Forge.com Domains Are Better for Getting Started

### The Traditional Approach (Custom DNS)

```
Day 1: Configure wildcard DNS (*.staging.kitthub.com)
  ↓ Wait 2-24 hours for DNS propagation
Day 2: Configure DNS-01 SSL verification
  ↓ Debug DNS provider API integration
Day 3: Test SSL certificate provisioning
  ↓ Finally ready to create test environments
```

**Total: 2-3 days before you can test your first PR**

### The On-Forge.com Approach

```
Day 1: Create Forge site with on-forge.com domain
  ↓ Instant DNS (no waiting!)
  ↓ Automatic SSL (no configuration!)
  ↓ Test your first PR environment
```

**Total: 1 day to working PR testing system**

### Comparison Table

| Feature | On-Forge.com | Custom DNS |
|---------|-------------|------------|
| **Setup Time** | ⚡ 10 minutes | ⏰ 2-3 days |
| **DNS Configuration** | ✅ None required | ❌ Wildcard A record + API |
| **SSL Certificates** | ✅ Automatic | ❌ DNS-01 verification required |
| **DNS Propagation** | ✅ Instant | ❌ 2-24 hours |
| **URL Example** | `pr-123.on-forge.com` | `pr-123.staging.kitthub.com` |
| **Maintenance** | ✅ Zero | ❌ Monitor DNS/SSL renewals |
| **Cost** | ✅ Free (included) | ✅ Free (but time-consuming) |

### When Each Approach Makes Sense

**Use On-Forge.com When:**
- ✅ Getting started (prototype in 1 day)
- ✅ Internal development team testing
- ✅ Technical stakeholders who don't care about URLs
- ✅ You want to validate the concept quickly
- ✅ Learning/experimenting with PR environments

**Add Custom DNS When:**
- ✅ Presenting to non-technical stakeholders/clients
- ✅ Brand consistency matters for demos
- ✅ You've validated the system works with on-forge.com
- ✅ You have time to invest in DNS setup

### Migration Path

**Best Practice: Start Simple, Add Complexity Later**

1. **Week 1**: Deploy with on-forge.com domains
   - Validate the entire workflow
   - Test with real PRs
   - Train your team
   - Prove the concept works

2. **Week 2-3** (Optional): Add custom DNS
   - Set up wildcard DNS
   - Configure DNS-01 SSL
   - Update automation scripts
   - Keep on-forge.com as fallback

**Key Insight**: 90% of teams discover they don't need custom DNS after using on-forge.com domains for a week.

## ⏱️ Timeline

### Phase 1: Foundation (Day 1) ⚡ FASTEST PATH
- [ ] Configure Forge server with site isolation
- [ ] Create master database snapshot from weekend data
- [ ] Test manual site creation via Forge API using on-forge.com
- [ ] Verify SSL auto-provisioning works

### Phase 2: Automation (Days 2-3)
- [ ] Create GitHub Action workflow
- [ ] Build site creation automation script
- [ ] Implement PR comment trigger (/preview)
- [ ] Add site cleanup automation (on PR close)

### Phase 3: Testing & Refinement (Days 4-5)
- [ ] Test with real PRs on both projects
- [ ] Configure queue workers (Horizon)
- [ ] Set up external API handling (payment gateways in test mode)
- [ ] Document process for team

### Phase 4: Production Ready (Days 6-7)
- [ ] Add monitoring and notifications
- [ ] Create troubleshooting playbook
- [ ] Train team on usage
- [ ] Deploy to both keatchen-customer-app and devpel-epos

**Total with on-forge.com: 1 week** ⚡

### Optional Phase 5: Custom DNS (Days 8-10)
Only if stakeholders need branded URLs:
- [ ] Set up wildcard DNS (*.staging.kitthub.com)
- [ ] Configure DNS-01 SSL verification
- [ ] Test custom domain creation
- [ ] Update automation to use custom domains

**Total with custom DNS: 1-2 weeks**

## 🔴 CRITICAL FOCUS AREAS

### 1. Why On-Forge.com Domains Are Better for Getting Started

**✅ Use on-forge.com domains first** (pr-123.on-forge.com)

**Benefits:**
- ✅ **Zero DNS configuration** - Works immediately
- ✅ **Automatic SSL** - No certificate setup needed
- ✅ **10-minute setup** - Start testing today
- ✅ **No wildcard complexity** - Forge handles everything
- ✅ **Same functionality** - Full Laravel app, database, queue workers

**When to add custom DNS:**
- ❌ **Not for internal development** - on-forge.com is fine
- ❌ **Not for developer testing** - Technical URLs are acceptable
- ✅ **Only for stakeholder demos** - If branding matters to clients

### 2. Custom DNS Setup (Optional - Only if Needed)

**⚠️ Optional enhancement for branded URLs**

You'll need:
- DNS wildcard A record: `*.staging.kitthub.com` → Forge server IP
- Forge site with wildcard enabled
- SSL certificate with DNS-01 verification (requires DNS provider API)

**Why optional**: On-forge.com works perfectly for development and testing. Custom DNS only adds branding.

### 3. Database Snapshot Timing

**Weekend evenings = realistic test data**

- Your busiest time: Weekend evenings (Friday/Saturday dinner rush)
- Snapshot strategy: Take DB dump Sunday evening, refresh weekly
- Size: <5GB makes this very manageable
- Benefit: Test environments have realistic order volumes, user patterns, menu configurations

**Why critical**: Testing with realistic data catches bugs that synthetic data misses.

### 4. Site Isolation for Security

**Enable on all test environments**

- Each PR site runs under separate Linux user
- Prevents one test environment from affecting another
- Required for multi-tenant safety on shared server

**Why critical**: Without isolation, a buggy PR could crash all test environments.

### 5. GitHub Webhook Trigger

**Manual trigger = developer control**

- Comment `/preview` on PR to create environment
- Comment `/destroy` to tear down (or auto-delete on merge)
- GitHub Action handles orchestration
- Forge API executes actual site creation

**Why critical**: Prevents wasting resources on draft PRs that aren't ready for testing.

### 6. Environment Variable Management

**Each test environment needs own config**

- Database credentials (unique per environment)
- Queue connection (separate Redis database)
- API keys (use TEST mode for payment gateways)
- Session/cache isolation

**Why critical**: Sharing production API keys or database credentials could cause data corruption.

## ✅ What This Solves

Your current pain points:

| Pain Point | Solution |
|------------|----------|
| **Can't test before merging to production** | ✅ Test every PR in isolated environment before merge |
| **Staging doesn't reflect production** | ✅ Use weekend peak database snapshots for realistic data |
| **Multiple features conflict in shared staging** | ✅ Each PR gets its own isolated environment |
| **Stakeholders can't preview features** | ✅ Send them `pr-123.on-forge.com` link (or custom domain) |
| **DNS setup takes too long** | ✅ Skip DNS entirely with on-forge.com domains |
| **SSL certificate configuration is complex** | ✅ Automatic SSL with on-forge.com (no configuration) |

## 🚀 Next Steps

### Immediate Actions (Today)

1. **Read** → [3-critical-reading/1-architecture-design.md](./3-critical-reading/1-architecture-design.md)
   - Understand the complete architecture
   - See how all pieces fit together

2. **Review** → [3-critical-reading/3-database-strategy.md](./3-critical-reading/3-database-strategy.md)
   - Understand database snapshot strategy
   - Plan your Sunday snapshot schedule

3. **Check** → [5-reference/3-cost-breakdown.md](./5-reference/3-cost-breakdown.md)
   - Detailed cost analysis
   - Confirm budget alignment

### Start Implementation (Tomorrow)

4. **Follow** → [4-implementation/1-forge-setup-checklist.md](./4-implementation/1-forge-setup-checklist.md)
   - Day 1 setup checklist with on-forge.com
   - Create test Forge site (no DNS required!)
   - Optional: Add custom DNS later if needed

## 🎯 Success Metrics

You'll know this is working when:

1. ✅ Developer comments `/preview` on PR #123
2. ✅ GitHub Action runs successfully (check Actions tab)
3. ✅ New site appears in Forge within 2 minutes
4. ✅ Site is accessible at `pr-123.on-forge.com` within 5 minutes (with auto-SSL!)
5. ✅ Database has weekend snapshot data (check orders table)
6. ✅ Queue workers are processing jobs (check Horizon dashboard)
7. ✅ Stakeholder can log in and test feature
8. ✅ Site auto-deletes when PR is merged

**Note**: URLs will be `pr-123.on-forge.com` by default. Add custom DNS later if you need branded URLs like `pr-123.staging.kitthub.com`.

## 💡 Pro Tips

- **Start with on-forge.com domains** - Get testing in 1 day, add custom DNS later only if needed
- **Start with one project** (keatchen-customer-app), then replicate to devpel-epos
- **Test the API locally first** before building GitHub Actions
- **Keep the master database snapshot updated** (weekly Sunday refresh)
- **Document the process** as you build (you'll forget the details)
- **Don't rush to custom DNS** - On-forge.com works perfectly for development and testing
- **Only add custom DNS if stakeholders require branded URLs** for demos

## 🚦 Decision Framework

**Should you use this approach?**

✅ **Yes, if:**
- Team of 1-10 developers
- Already using Laravel Forge
- Need production-like testing
- Want fast implementation (1 week with on-forge.com, 1-2 weeks with custom DNS)
- Budget-conscious but value developer experience
- Want to start testing immediately without DNS setup

❌ **No, if:**
- Team of 50+ developers (need enterprise solution like Kubernetes)
- Can't use real production data (need synthetic data generators)
- Already have CI/CD infrastructure (Jenkins, CircleCI with preview environments)
- Need automated test suites (this is for manual testing)

## 📚 Related Reading

**Before you implement**, read these critical documents:

1. [3-critical-reading/1-architecture-design.md](./3-critical-reading/1-architecture-design.md) - Complete system design
2. [3-critical-reading/2-security-considerations.md](./3-critical-reading/2-security-considerations.md) - Security and access control
3. [3-critical-reading/3-database-strategy.md](./3-critical-reading/3-database-strategy.md) - Database replication details

**Time investment**: 2-3 hours of reading will save you days of debugging.

---

**Ready to dive deeper?** Continue to [3-critical-reading/](./3-critical-reading/) →
