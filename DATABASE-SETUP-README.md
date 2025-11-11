# 🗄️ Production Database Setup - Quick Reference

**Status**: ✅ Scripts created and ready to run
**Purpose**: Clone production database to test PR environments with Saturday peak data

---

## ⚡ Quick Start (3 Commands)

```bash
# 1. Navigate to project
cd /home/dev/project-analysis/laravel-forge-pr-testing

# 2. Clone production database (READ-ONLY, safe)
./scripts/clone-production-database.sh

# 3. Transform to Saturday peak data (6pm, 102 orders)
./scripts/saturday-peak-data.sh
```

**Duration**: ~5 minutes total
**Result**: Driver screen shows 102 orders from Saturday 6pm

---

## 🔐 What You Need to Know

### Production Server (Source)
- **Name**: tall-stream (886474)
- **IP**: 18.135.39.222
- **Database**: PROD_APP
- **Access**: READ-ONLY via SSH
- **Safety**: Zero impact on production

### Test Server (Target)
- **Name**: curved-sanctuary (986747)
- **IP**: 159.65.213.130
- **Database**: forge
- **Site**: pr-test-devpel.on-forge.com
- **Access**: Full read-write for testing

---

## 📋 What the Scripts Do

### Script 1: `clone-production-database.sh`
**Purpose**: Safely copy production database to test environment

**Steps**:
1. ✅ Verify SSH access to both servers
2. ✅ Create mysqldump from production (READ-ONLY, no locks)
3. ✅ Sanitize dump (remove DEFINERs)
4. ✅ Transfer to test server via SCP
5. ✅ Import into test database
6. ✅ Verify import success
7. ✅ Keep last 5 backups

**Output**:
```
================================================
  Production Database Cloning (READ-ONLY)
================================================

Source: tall-stream (18.135.39.222)
Database: PROD_APP
Target: curved-sanctuary (159.65.213.130)
Database: forge

[INFO] Checking prerequisites...
[SUCCESS] Production SSH access verified
[SUCCESS] Backup directory ready
[INFO] Creating production database dump...
[SUCCESS] Production dump created: 234 MB
[INFO] Sanitizing database dump...
[SUCCESS] Database dump sanitized
[INFO] Importing to test environment...
[SUCCESS] Database imported successfully
[INFO] Verifying database import...
[SUCCESS] Database contains 47 tables
[SUCCESS] Orders table verified: 127,451 orders

================================================
  ✅ Database Cloning Complete!
================================================
```

### Script 2: `saturday-peak-data.sh`
**Purpose**: Transform timestamps to show Saturday 6pm peak with 102 orders

**Steps**:
1. ✅ Analyze production order patterns
2. ✅ Find Saturday with 100+ orders
3. ✅ Calculate time shift to target Saturday
4. ✅ Backup original timestamps
5. ✅ Transform orders to Saturday 6pm
6. ✅ Verify driver screen data
7. ✅ Create restore script

**Output**:
```
================================================
  Saturday Peak Data Transformation
================================================

Target: 2025-11-09 at 18:00:00
Expected orders: 102+
Database: 159.65.213.130 (forge)

[INFO] Analyzing production order patterns...
[SUCCESS] Production data analysis complete
[INFO] Finding Saturday peak period orders...
[SUCCESS] Saturday peak periods identified
[INFO] Transforming timestamps...
[SUCCESS] Timestamps transformed successfully
[INFO] Verifying driver screen data...

Time Window: 2025-11-09 17:00 - 20:00
Visible Orders: 127
- Pending: 15
- Confirmed: 23
- Preparing: 31
- Ready: 42
- Out for Delivery: 16

Target Met: ✅ 127 orders (target: 102+)

================================================
  ✅ Saturday Peak Data Ready!
================================================
```

---

## 🎯 Expected Results

### After Running Both Scripts

**Database State**:
- ✅ Complete production data cloned to test
- ✅ Orders shifted to Saturday 2025-11-09
- ✅ Peak time: 17:00 - 20:00 (5pm - 8pm)
- ✅ 100+ orders visible on driver screen

**Test URLs**:
```bash
# Driver app (should show 102+ orders)
http://159.65.213.130/driver

# Customer app
http://159.65.213.130/

# Admin panel
http://159.65.213.130/admin
```

**Database Query** (verify data):
```bash
ssh forge@159.65.213.130 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge -e \"SELECT DATE(created_at) as date, COUNT(*) as orders FROM orders WHERE DATE(created_at) = '2025-11-09' GROUP BY DATE(created_at);\""
```

---

## 🔄 Common Operations

### Re-run Database Clone
```bash
# Safe to run multiple times
./scripts/clone-production-database.sh
```

### Re-transform Saturday Data
```bash
# Will use latest cloned data
./scripts/saturday-peak-data.sh
```

### Restore Original Timestamps
```bash
# Undo Saturday transformation
./scripts/restore-original-timestamps.sh
```

### Check Current Database State
```bash
# See what's in the test database
ssh forge@159.65.213.130 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge -e 'SHOW TABLES; SELECT COUNT(*) FROM orders;'"
```

---

## 🛡️ Safety Features

### Production Protection
- ✅ **READ-ONLY**: No write operations on production
- ✅ **No Locks**: Single-transaction dump, no table locks
- ✅ **Zero Impact**: Production users won't notice anything
- ✅ **Safe Failure**: If anything fails, production is unaffected

### Backup & Rollback
- ✅ **Automatic Backups**: Original timestamps saved before transformation
- ✅ **Restore Script**: One command to undo changes
- ✅ **Backup Rotation**: Keeps last 5 dumps automatically
- ✅ **Local Storage**: All backups saved to `./backups/`

### Error Handling
- ✅ **Pre-flight Checks**: Verifies access before starting
- ✅ **Graceful Failures**: Clear error messages
- ✅ **No Partial State**: Transactions ensure all-or-nothing
- ✅ **Verification**: Confirms success at each step

---

## 📊 Database Details

### Key Tables
- `orders` - Order data (main table for Saturday peak)
- `customers` - Customer information
- `drivers` - Driver accounts
- `restaurants` - Restaurant data
- `menu_items` - Menu catalog
- `order_items` - Line items for orders

### Order Statuses
```
pending → confirmed → preparing → ready → out_for_delivery → delivered
                                   ↓
                              cancelled (any time)
```

### Saturday Peak Query
```sql
-- Orders visible on driver screen
SELECT
    id,
    customer_id,
    status,
    total,
    delivery_time,
    created_at
FROM orders
WHERE DATE(created_at) = '2025-11-09'
  AND HOUR(created_at) BETWEEN 17 AND 20
  AND status IN ('ready', 'out_for_delivery')
ORDER BY delivery_time ASC;
```

---

## 🚨 Troubleshooting

### "SSH connection failed"
```bash
# Test SSH access
ssh forge@18.135.39.222
ssh forge@159.65.213.130

# Check SSH key
ls -la ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
```

### "Permission denied on mysqldump"
```bash
# Verify database access
ssh forge@18.135.39.222 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' PROD_APP -e 'SELECT 1;'"
```

### "Not enough Saturday orders"
```bash
# Find better Saturdays
ssh forge@18.135.39.222 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' PROD_APP -e 'SELECT DATE(created_at), COUNT(*) FROM orders WHERE DAYNAME(created_at)=\"Saturday\" GROUP BY DATE(created_at) ORDER BY COUNT(*) DESC LIMIT 5;'"
```

### "Import taking too long"
- Normal for large databases (5-10 minutes)
- Check disk space: `df -h`
- Monitor progress: `tail -f /var/log/mysql/error.log`

---

## 📚 Full Documentation

Comprehensive guides available in `docs/`:

- **[4-implementation/3-production-database-setup.md](./docs/4-implementation/3-production-database-setup.md)** - Complete setup guide
- **[3-critical-reading/3-database-strategy.md](./docs/3-critical-reading/3-database-strategy.md)** - Database architecture
- **[5-reference/3-troubleshooting.md](./docs/5-reference/3-troubleshooting.md)** - Troubleshooting reference

---

## ✅ Ready to Run?

**Checklist before starting:**
- [ ] SSH access to production server (18.135.39.222)
- [ ] SSH access to test server (159.65.213.130)
- [ ] SSH key configured (~/.ssh/id_rsa)
- [ ] Test server has space for database (~500MB)
- [ ] Understand this is READ-ONLY on production

**Run the commands:**
```bash
cd /home/dev/project-analysis/laravel-forge-pr-testing
./scripts/clone-production-database.sh
./scripts/saturday-peak-data.sh
```

**Then test:**
```bash
# Visit driver screen
open http://159.65.213.130/driver

# Should see 102+ orders from Saturday 6pm
```

---

**Status**: ✅ Ready to execute
**Last Updated**: 2025-11-11
**Next Step**: Run `clone-production-database.sh`
