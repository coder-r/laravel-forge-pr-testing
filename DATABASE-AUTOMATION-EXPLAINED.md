# 🔄 Database Automation Strategy - How It Works

**Question**: Will this run on a cron job and delete the previous DB that is there? How will this work?

**Answer**: Yes! Here's exactly how it works:

---

## 🎯 The Core Strategy

### Database Replacement (Not Append)
The system **replaces** the entire database on each refresh:

```
Test Database Before:  Old data from last week
                      ↓
Clone Production:     DROP all tables → Import fresh production dump
                      ↓
Test Database After:  Fresh production data from today
                      ↓
Transform:            Shift timestamps to Saturday 6pm peak
                      ↓
Final State:          Current production data + Saturday peak setup
```

**Key Point**: Each refresh gives you a **clean slate** with the latest production data.

---

## 🔄 Three Automation Options

### Option 1: Daily Automated Refresh (Recommended)
**When**: Every day at 3 AM
**What**: Replaces test database with fresh production data
**Who**: Cron job runs automatically

```bash
# Setup once
./scripts/setup-cron-jobs.sh

# Select: "1. Setup Daily Refresh (3 AM)"
# Or run directly:
./scripts/setup-cron-jobs.sh daily
```

**Cron Entry Created**:
```cron
0 3 * * * /home/dev/project-analysis/laravel-forge-pr-testing/scripts/cron-daily-db-refresh.sh
```

**What Happens Each Day**:
```
3:00 AM - Cron triggers
  ├─ 3:00-3:05 AM → Clone production database (overwrites test DB)
  ├─ 3:05-3:06 AM → Transform to Saturday peak (updates timestamps)
  ├─ 3:06 AM → Verify 102+ orders visible
  └─ Log saved to: /var/log/forge-pr-testing/db-refresh-YYYYMMDD.log
```

**Result**: Every morning, your test environment has yesterday's production data with Saturday peak setup.

---

### Option 2: PR-Triggered Refresh
**When**: When you open a new pull request
**What**: Creates fresh database for that specific PR
**Who**: GitHub Actions workflow

```yaml
# .github/workflows/pr-testing.yml
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  setup-database:
    runs-on: ubuntu-latest
    steps:
      - name: Clone Production Database
        run: ./scripts/cron-pr-triggered-refresh.sh ${{ github.event.pull_request.number }}
```

**What Happens on PR Open**:
```
PR #123 opened
  ├─ GitHub Actions triggers
  ├─ Create new site: pr-123-test.on-forge.com
  ├─ Clone production database
  ├─ Transform to Saturday peak
  └─ Comment PR with: "✅ Test environment ready: pr-123-test.on-forge.com"
```

---

### Option 3: Weekly Full Refresh
**When**: Every Sunday at 2 AM
**What**: Deep clean + fresh clone
**Who**: Cron job

```bash
# Setup
./scripts/setup-cron-jobs.sh weekly
```

**Cron Entry**:
```cron
0 2 * * 0 /home/dev/project-analysis/laravel-forge-pr-testing/scripts/cron-weekly-full-refresh.sh
```

**What Happens**:
```
Sunday 2:00 AM
  ├─ Clean up old backups (keep last 10)
  ├─ Delete old test sites (unused for 7+ days)
  ├─ Clone fresh production database
  ├─ Transform to Saturday peak
  └─ Generate weekly report
```

---

## 🗄️ How Database Replacement Works

### Technical Details

**Step 1: Production Dump (READ-ONLY)**
```bash
# SSH into production, create dump
ssh forge@18.135.39.222 << 'REMOTE'
mysqldump --single-transaction PROD_APP > /tmp/prod_dump.sql
REMOTE

# Copy to local
scp forge@18.135.39.222:/tmp/prod_dump.sql ./backups/
```
- ✅ No locks on production
- ✅ Production users unaffected
- ✅ Takes 2-5 minutes

**Step 2: Transfer to Test**
```bash
# Copy dump to test server
scp ./backups/prod_dump.sql forge@159.65.213.130:/tmp/
```

**Step 3: Import (Replaces All Data)**
```bash
# Import on test server
ssh forge@159.65.213.130 << 'REMOTE'
# This DROPS all tables and recreates from dump
mysql forge < /tmp/prod_dump.sql
REMOTE
```

**What Import Does**:
```sql
-- Dump file starts with:
DROP TABLE IF EXISTS `orders`;
DROP TABLE IF EXISTS `customers`;
DROP TABLE IF EXISTS `drivers`;
-- ... (drops ALL tables)

-- Then recreates:
CREATE TABLE `orders` (...);
CREATE TABLE `customers` (...);
-- ... (creates all tables)

-- Then inserts:
INSERT INTO `orders` VALUES (...);
-- ... (inserts all data)
```

**Result**: Test database is completely **replaced** with production data.

---

## 📊 Database States Over Time

### Without Automation
```
Day 1:  Clone production → Test DB has data from Day 1
Day 7:  Test DB still has stale data from Day 1 (1 week old)
Day 30: Test DB has very old data (1 month old)
❌ Problem: Testing against outdated data
```

### With Daily Automation
```
Day 1:  Clone production → Test DB has data from Day 1
Day 2:  3 AM refresh → Test DB has data from Day 2 (fresh)
Day 3:  3 AM refresh → Test DB has data from Day 3 (fresh)
Day 7:  3 AM refresh → Test DB has data from Day 7 (fresh)
✅ Benefit: Always testing against current data
```

---

## 🔐 Safety & Backups

### Production is Never Modified
```
┌─────────────────────────────────────┐
│ Production Database                 │
│ - READ-ONLY access                 │
│ - No DROP, DELETE, UPDATE          │
│ - Only SELECT and mysqldump        │
│ - Zero risk                        │
└─────────────────────────────────────┘
         │ READ-ONLY
         │ mysqldump
         ▼
┌─────────────────────────────────────┐
│ Local Backup Files                  │
│ - backups/keatchen_prod_*.sql      │
│ - Keep last 5-10 dumps             │
│ - Can restore test anytime         │
└─────────────────────────────────────┘
         │ COPY
         │ scp + import
         ▼
┌─────────────────────────────────────┐
│ Test Database (Replaceable)         │
│ - Full read-write access           │
│ - Can be destroyed anytime         │
│ - Recreated from backup            │
│ - No production impact             │
└─────────────────────────────────────┘
```

### Backup Strategy
```bash
# Automatic backups before each operation
backups/
├── keatchen_prod_20251111_030000.sql      (Today 3 AM)
├── keatchen_prod_20251110_030000.sql      (Yesterday)
├── keatchen_prod_20251109_030000.sql      (2 days ago)
├── keatchen_prod_20251108_030000.sql      (3 days ago)
└── keatchen_prod_20251107_030000.sql      (4 days ago)

# Older backups automatically deleted (keep last 5)
```

### Rollback Options
```bash
# Option 1: Restore from backup
mysql forge < backups/keatchen_prod_20251110_030000.sql

# Option 2: Re-run clone (gets latest production)
./scripts/clone-production-database.sh

# Option 3: Restore original timestamps only
./scripts/restore-original-timestamps.sh
```

---

## ⚙️ Setup Instructions

### Quick Setup (All Options)
```bash
cd /home/dev/project-analysis/laravel-forge-pr-testing

# Interactive menu
./scripts/setup-cron-jobs.sh

# Or setup all at once
./scripts/setup-cron-jobs.sh all
```

### Manual Setup (Individual Options)
```bash
# Daily refresh only
./scripts/setup-cron-jobs.sh daily

# Weekly refresh only
./scripts/setup-cron-jobs.sh weekly

# PR-triggered only
./scripts/setup-cron-jobs.sh pr
```

### Verify Setup
```bash
# Show current cron jobs
./scripts/setup-cron-jobs.sh show

# Or use crontab directly
crontab -l | grep forge-pr-testing
```

### Remove All Automation
```bash
# Remove all cron jobs
./scripts/setup-cron-jobs.sh remove
```

---

## 📈 Resource Usage

### Daily Refresh
- **Runtime**: 5-8 minutes
- **Bandwidth**: ~200-500 MB (database transfer)
- **Disk**: ~500 MB per backup (rotated automatically)
- **CPU**: Low (runs at 3 AM off-peak)

### Cost Estimate
```
Daily refresh:
- VPS running: $0.02/hour × 24 hours = $0.48/day
- Database transfer: Included in hosting
- Backups: Local storage (free)

Monthly: $14.40 for 24/7 test environment

Alternative (on-demand):
- Create VPS when PR opens: $0.02/hour
- Destroy after PR merges: $0.16 per 8-hour PR
- 20 PRs/month: ~$3.20/month
```

---

## 🎯 Recommended Setup

### For Active Development Teams
```bash
# Daily refresh + PR-triggered + weekly cleanup
./scripts/setup-cron-jobs.sh all
```

**Benefits**:
- ✅ Test environment always has fresh data
- ✅ Each PR gets isolated database
- ✅ Weekly cleanup prevents clutter
- ✅ Fully automated

### For Small Teams / Budget
```bash
# PR-triggered only (no daily refresh)
./scripts/setup-cron-jobs.sh pr
```

**Benefits**:
- ✅ Only refresh when needed (PR opened)
- ✅ Lower VPS costs (destroy after PR)
- ✅ Still fully automated
- ✅ Fresh data for each PR

---

## 📊 Monitoring & Logs

### Log Files
```bash
# Daily refresh logs
/var/log/forge-pr-testing/db-refresh-YYYYMMDD.log

# Weekly refresh logs
/var/log/forge-pr-testing/weekly-refresh-YYYYMMDD.log

# PR-specific logs
/var/log/forge-pr-testing/pr-123-YYYYMMDD_HHMMSS.log
```

### Check Last Refresh
```bash
# View today's log
cat /var/log/forge-pr-testing/db-refresh-$(date +%Y%m%d).log

# View recent refreshes
ls -lh /var/log/forge-pr-testing/

# Watch live (during refresh)
tail -f /var/log/forge-pr-testing/db-refresh-$(date +%Y%m%d).log
```

### Email Notifications (Optional)
```bash
# Add to cron for email on failure
0 3 * * * /path/to/cron-daily-db-refresh.sh || echo "Database refresh failed" | mail -s "PR Test DB Refresh Failed" admin@example.com
```

---

## ❓ FAQ

### Q: Will this affect production?
**A**: No. Production database is accessed READ-ONLY. No writes, no locks, zero impact.

### Q: What if the test database is in use during refresh?
**A**: Scheduled at 3 AM (off-peak). If needed, adjust cron time: `crontab -e`

### Q: Can I manually trigger a refresh?
**A**: Yes! Just run: `./scripts/clone-production-database.sh`

### Q: How do I know if automation is working?
**A**: Check logs: `ls /var/log/forge-pr-testing/`

### Q: Can I change the Saturday date?
**A**: Yes! Edit `saturday-peak-data.sh`, change `TARGET_SATURDAY` variable.

### Q: What if I want more than 102 orders?
**A**: Edit `saturday-peak-data.sh`, change `ORDERS_TO_SHOW` variable.

---

## ✅ Summary

**How Database Automation Works**:
1. ✅ **Production cloned** daily/on-demand (READ-ONLY, safe)
2. ✅ **Test DB replaced** completely (not appended)
3. ✅ **Saturday peak setup** automatically
4. ✅ **Backups kept** for rollback (last 5-10)
5. ✅ **Logs generated** for monitoring

**Recommended Setup**:
```bash
./scripts/setup-cron-jobs.sh all
```

**Next Steps**:
1. Run setup script above
2. Check logs tomorrow morning: `/var/log/forge-pr-testing/`
3. Test driver screen: `http://159.65.213.130/driver`

---

**Last Updated**: 2025-11-11
**Status**: ✅ Ready for production use
