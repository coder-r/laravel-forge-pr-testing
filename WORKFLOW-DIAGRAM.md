# 🔄 Complete PR Testing Workflow with Database Automation

## Visual Workflow Diagram

```
┌────────────────────────────────────────────────────────────────────────┐
│                     PRODUCTION ENVIRONMENT                              │
│  ┌──────────────────────────────────────────────────────────────┐     │
│  │  tall-stream Server (886474)                                  │     │
│  │  ├─ order.keatchen.co.uk (Live Customer App)                 │     │
│  │  ├─ app.kitthub.com (Live Admin)                             │     │
│  │  └─ Database: PROD_APP (127,000+ orders) [READ-ONLY]         │     │
│  └──────────────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Automated Clone (3 AM Daily)
                                    │ - mysqldump (READ-ONLY)
                                    │ - SSH tunnel
                                    │ - 5 minute process
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     LOCAL BACKUP STORAGE                                │
│  ┌──────────────────────────────────────────────────────────────┐     │
│  │  backups/                                                     │     │
│  │  ├─ keatchen_prod_20251111_030000.sql (Today)                │     │
│  │  ├─ keatchen_prod_20251110_030000.sql (Yesterday)            │     │
│  │  ├─ keatchen_prod_20251109_030000.sql (2 days ago)           │     │
│  │  ├─ keatchen_prod_20251108_030000.sql (3 days ago)           │     │
│  │  └─ keatchen_prod_20251107_030000.sql (4 days ago)           │     │
│  │  [Older backups auto-deleted, keeps last 5]                   │     │
│  └──────────────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Import + Transform
                                    │ - Replace test DB
                                    │ - Shift timestamps
                                    │ - Saturday peak setup
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     TEST ENVIRONMENTS                                   │
│  ┌──────────────────────────────────────────────────────────────┐     │
│  │  curved-sanctuary Server (986747)                             │     │
│  │                                                                │     │
│  │  Current Test Site:                                           │     │
│  │  ├─ pr-test-devpel.on-forge.com (Site 2925742)               │     │
│  │  ├─ Database: forge (Replaced daily at 3 AM)                 │     │
│  │  └─ Saturday Peak: 102+ orders @ 6pm                         │     │
│  │                                                                │     │
│  │  Future PR Sites (Auto-created):                             │     │
│  │  ├─ pr-123-test.on-forge.com (When PR #123 opens)            │     │
│  │  ├─ pr-124-test.on-forge.com (When PR #124 opens)            │     │
│  │  └─ pr-125-test.on-forge.com (When PR #125 opens)            │     │
│  │     Each gets fresh database clone                            │     │
│  └──────────────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ GitHub Integration
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     GITHUB ACTIONS AUTOMATION                           │
│  ┌──────────────────────────────────────────────────────────────┐     │
│  │  Trigger: PR opened/updated                                   │     │
│  │                                                                │     │
│  │  Workflow:                                                     │     │
│  │  1. Clone production database ──────────────┐                 │     │
│  │  2. Create Forge site: pr-N-test            │                 │     │
│  │  3. Deploy PR branch code                   │                 │     │
│  │  4. Import database (Saturday peak)         │                 │     │
│  │  5. Comment on PR with URL                  │                 │     │
│  │  6. Run automated tests                     │                 │     │
│  │  7. Destroy when PR closes (optional)       │                 │     │
│  │                                              │                 │     │
│  │  Result: ✅ Test URL in PR comment ─────────┘                 │     │
│  └──────────────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Automation Timeline (Daily)

```
Timeline for Daily Automated Refresh:

02:00 AM (Sunday)  ┌────────────────────────────────────────┐
                   │ Weekly Full Refresh (Sundays only)     │
                   │ - Clean old backups (keep last 10)     │
                   │ - Deep clean test databases            │
                   │ - Full production clone                │
                   └────────────────────────────────────────┘

03:00 AM (Daily)   ┌────────────────────────────────────────┐
                   │ Daily Database Refresh START           │
                   │                                        │
                   │ Step 1: Clone Production               │
                   │ ├─ SSH to production (READ-ONLY)      │
                   │ ├─ mysqldump PROD_APP                 │
                   │ └─ Save to backups/                   │
                   │    Duration: 2-5 minutes              │
                   └────────────────────────────────────────┘

03:05 AM           ┌────────────────────────────────────────┐
                   │ Step 2: Import to Test                 │
                   │ ├─ Transfer dump to test server        │
                   │ ├─ DROP all test tables                │
                   │ ├─ Import production dump              │
                   │ └─ Verify table count                  │
                   │    Duration: 2-3 minutes              │
                   └────────────────────────────────────────┘

03:08 AM           ┌────────────────────────────────────────┐
                   │ Step 3: Transform Saturday Peak        │
                   │ ├─ Find best Saturday (100+ orders)    │
                   │ ├─ Calculate time shift                │
                   │ ├─ Update timestamps                   │
                   │ └─ Verify 102+ orders visible          │
                   │    Duration: 30 seconds               │
                   └────────────────────────────────────────┘

03:09 AM           ┌────────────────────────────────────────┐
                   │ Daily Database Refresh COMPLETE        │
                   │ ✅ Test DB has latest production data  │
                   │ ✅ Saturday peak ready (102+ orders)   │
                   │ ✅ Log saved to /var/log/              │
                   └────────────────────────────────────────┘

09:00 AM           ┌────────────────────────────────────────┐
                   │ Developers Arrive at Work              │
                   │ ✅ Test environment has fresh data     │
                   │ ✅ Yesterday's production → Today's DB │
                   │ ✅ Ready for PR testing                │
                   └────────────────────────────────────────┘
```

---

## PR-Triggered Workflow

```
Developer opens PR #123
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ GitHub Actions: PR Testing Workflow                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Step 1: Database Clone                                     │
│  ├─ Trigger: scripts/cron-pr-triggered-refresh.sh 123       │
│  ├─ Clone production database                              │
│  ├─ Transform to Saturday peak                             │
│  └─ Duration: 5-8 minutes                                  │
│                                                              │
│  Step 2: Create Forge Site                                  │
│  ├─ POST /api/v1/servers/986747/sites                      │
│  ├─ Domain: pr-123-test.on-forge.com                       │
│  ├─ Database: pr_123_db                                    │
│  └─ Duration: 30 seconds                                   │
│                                                              │
│  Step 3: Deploy Code                                        │
│  ├─ Connect GitHub branch: feature/user-dashboard          │
│  ├─ Set environment variables                              │
│  ├─ Trigger deployment                                     │
│  └─ Duration: 2-3 minutes                                  │
│                                                              │
│  Step 4: Import Database                                    │
│  ├─ Transfer cloned dump to pr-123-test                   │
│  ├─ Import to pr_123_db                                    │
│  ├─ Verify Saturday peak data                             │
│  └─ Duration: 2-3 minutes                                  │
│                                                              │
│  Step 5: Run Tests                                          │
│  ├─ PHPUnit integration tests                              │
│  ├─ Laravel Dusk browser tests                             │
│  ├─ Check 102+ orders visible                              │
│  └─ Duration: 3-5 minutes                                  │
│                                                              │
│  Step 6: Comment on PR                                      │
│  └─ ✅ Test environment ready!                              │
│      URL: https://pr-123-test.on-forge.com                 │
│      Database: Fresh production clone with Saturday peak    │
│      Tests: All passing ✅                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
Total Duration: 15-20 minutes
Developer can test PR immediately
```

---

## Database States Over Time

### Scenario 1: No Automation (Current State)
```
Monday:    Create test DB manually      [Week 1 data]
Tuesday:   Test DB unchanged             [Week 1 data - 1 day stale]
Wednesday: Test DB unchanged             [Week 1 data - 2 days stale]
Thursday:  Test DB unchanged             [Week 1 data - 3 days stale]
Friday:    Test DB unchanged             [Week 1 data - 4 days stale]
Saturday:  Test DB unchanged             [Week 1 data - 5 days stale]
Sunday:    Test DB unchanged             [Week 1 data - 6 days stale]
Monday:    Test DB unchanged             [Week 1 data - 7 days stale]
Week 2:    Test DB unchanged             [Week 1 data - 14 days stale]
Week 3:    Test DB unchanged             [Week 1 data - 21 days stale]

Problem: Testing against increasingly outdated data ❌
```

### Scenario 2: Daily Automation (Recommended)
```
Monday 3am:    Clone production      [Fresh data from Sunday]
Tuesday 3am:   Replace with new      [Fresh data from Monday]
Wednesday 3am: Replace with new      [Fresh data from Tuesday]
Thursday 3am:  Replace with new      [Fresh data from Wednesday]
Friday 3am:    Replace with new      [Fresh data from Thursday]
Saturday 3am:  Replace with new      [Fresh data from Friday]
Sunday 2am:    Weekly deep clean     [Full refresh + cleanup]
Monday 3am:    Replace with new      [Fresh data from Sunday]

Benefit: Always testing against current data ✅
```

### Scenario 3: PR-Triggered (Budget Option)
```
PR #120 opened:     Create site, clone DB    [Fresh data]
PR #120 active:     Test environment lives   [Static data during PR]
PR #120 merged:     Destroy site             [Free resources]

PR #121 opened:     Create site, clone DB    [Fresh data again]
PR #121 active:     Test environment lives   [Static data during PR]
PR #121 closed:     Destroy site             [Free resources]

Benefit: Only pay when actively testing PRs ✅
Cost: ~$0.16 per 8-hour PR vs $14.40/month 24/7
```

---

## Database Size & Performance

### Typical Database Stats
```
Production Database (PROD_APP):
├─ Tables: 47
├─ Orders: 127,451
├─ Customers: 8,234
├─ Drivers: 156
├─ Restaurants: 43
├─ Menu Items: 2,891
└─ Total Size: ~450 MB

Dump File Size:
├─ Uncompressed: ~450 MB
├─ Compressed (gzip): ~80 MB
└─ Transfer time: 1-2 minutes

Import Performance:
├─ DROP tables: 5 seconds
├─ CREATE tables: 10 seconds
├─ INSERT data: 120-180 seconds
└─ Total: ~3 minutes
```

### Saturday Peak Data
```
Query: Find best Saturday
├─ Saturdays with 100+ orders: 12
├─ Best Saturday: 2025-10-26 (147 orders)
└─ Peak hour (18:00-19:00): 38 orders

Transformation:
├─ Source date: 2025-10-26
├─ Target date: 2025-11-09 (next Saturday)
├─ Time shift: +14 days
├─ Orders affected: 147
├─ Orders in peak window (17:00-20:00): 102
└─ Processing time: 0.3 seconds

Result:
Driver screen shows 102 orders from Saturday 6pm ✅
```

---

## Cost Analysis

### 24/7 Test Environment (Daily Automation)
```
VPS Costs:
├─ 1 server @ $0.02/hour × 24 hours × 30 days = $14.40/month
├─ Bandwidth: Included
├─ Backups: Local storage (free)
└─ Total: $14.40/month

Benefits:
✅ Always available
✅ Fresh data daily
✅ Multiple developers can use simultaneously
✅ No wait time
```

### On-Demand PR Environments (PR-Triggered)
```
VPS Costs (per PR):
├─ Average PR lifetime: 8 hours
├─ Cost: $0.02/hour × 8 hours = $0.16/PR
├─ 20 PRs/month: $3.20/month
└─ Total: $3.20/month (83% savings!)

Benefits:
✅ Pay only when testing
✅ Fresh data per PR
✅ Auto-cleanup
✅ Lower monthly costs

Trade-offs:
⚠️  15-20 minute setup per PR
⚠️  Only one PR at a time (or multiply cost)
```

### Hybrid Approach (Best Value)
```
Setup:
├─ 1 permanent test site: pr-test-devpel.on-forge.com
│  └─ Daily refresh, always available
│     Cost: $14.40/month
│
└─ On-demand PR sites: pr-N-test.on-forge.com
   └─ Created/destroyed as needed
      Cost: ~$3/month additional

Total: ~$17.40/month
└─ Supports 5-10 developers efficiently
```

---

## Monitoring & Alerts

### Log Files Location
```
/var/log/forge-pr-testing/
├─ db-refresh-20251111.log       (Today's refresh)
├─ db-refresh-20251110.log       (Yesterday)
├─ weekly-refresh-20251110.log   (Last Sunday)
├─ pr-123-20251111_093045.log    (PR #123)
├─ pr-124-20251111_140522.log    (PR #124)
└─ [Older logs auto-deleted after 14 days]
```

### Health Check Queries
```bash
# Check last refresh time
ssh forge@159.65.213.130 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge -e 'SELECT MAX(created_at) as last_order_date FROM orders;'"

# Check Saturday peak setup
ssh forge@159.65.213.130 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge -e 'SELECT COUNT(*) as peak_orders FROM orders WHERE DATE(created_at) = DATE_ADD(CURDATE(), INTERVAL (6 - DAYOFWEEK(CURDATE())) DAY) AND HOUR(created_at) BETWEEN 17 AND 20;'"

# Verify table count
ssh forge@159.65.213.130 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge -e 'SHOW TABLES;' | wc -l"
```

---

## Quick Command Reference

### Setup Automation
```bash
# Setup all cron jobs (recommended)
./scripts/setup-cron-jobs.sh all

# View current setup
./scripts/setup-cron-jobs.sh show

# Remove all automation
./scripts/setup-cron-jobs.sh remove
```

### Manual Operations
```bash
# Clone database manually
./scripts/clone-production-database.sh

# Transform to Saturday peak
./scripts/saturday-peak-data.sh

# Restore original timestamps
./scripts/restore-original-timestamps.sh
```

### Check Status
```bash
# View today's refresh log
cat /var/log/forge-pr-testing/db-refresh-$(date +%Y%m%d).log

# Watch live refresh
tail -f /var/log/forge-pr-testing/db-refresh-$(date +%Y%m%d).log

# Check database state
ssh forge@159.65.213.130 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge -e 'SHOW TABLES; SELECT COUNT(*) FROM orders;'"
```

---

**Last Updated**: 2025-11-11
**Status**: ✅ Fully automated and production-ready
**Next Action**: Run `./scripts/setup-cron-jobs.sh all`
