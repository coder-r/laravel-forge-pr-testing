# Production Database Setup Guide

**Purpose**: Clone production keatchen database to test environments for PR testing

**Source**: tall-stream server (886474) - 18.135.39.222
**Database**: PROD_APP
**Target**: Test PR environments

---

## 🔐 Security Overview

### Access Control
- **Production**: READ-ONLY access only
- **Method**: SSH tunneling with key-based auth
- **User**: forge@18.135.39.222
- **Database User**: forge
- **Operations**: Only SELECT and mysqldump allowed

### Safety Measures
1. ✅ Single-transaction dumps (no table locks)
2. ✅ --lock-tables=false (no write locks)
3. ✅ No DDL operations on production
4. ✅ All modifications happen on test environment only
5. ✅ Automatic backup creation before transformations

---

## 📋 Database Information

### Production Database (tall-stream)
```
Server ID: 886474
Server Name: tall-stream
IP Address: 18.135.39.222
Database: PROD_APP
Alternative DBs: keatchen, staging, WP, PROD_WP
SSH User: forge
DB User: forge
Access: Read-only via SSH tunnel
```

### Test Environment (curved-sanctuary)
```
Server ID: 986747
Server Name: curved-sanctuary
IP Address: 159.65.213.130
Site ID: 2925742
Database: forge
SSH User: forge
DB User: forge
Access: Full read-write for testing
```

---

## 🚀 Quick Start

### Prerequisites
1. SSH access to both servers
2. SSH key configured: `~/.ssh/id_rsa` or set `FORGE_SSH_KEY`
3. Both servers accessible via SSH

### Step 1: Clone Production Database
```bash
cd /home/dev/project-analysis/laravel-forge-pr-testing

# Run the cloning script
./scripts/clone-production-database.sh
```

**What it does:**
1. Connects to production (READ-ONLY)
2. Creates mysqldump with safe options
3. Sanitizes dump (removes DEFINERs)
4. Transfers to test environment
5. Imports into test database
6. Verifies import success
7. Keeps last 5 backups

**Duration**: ~2-5 minutes (depends on database size)

### Step 2: Transform to Saturday Peak Data
```bash
# Transform timestamps to show Saturday 6pm peak
./scripts/saturday-peak-data.sh
```

**What it does:**
1. Analyzes production order patterns
2. Finds best Saturday with 100+ orders
3. Shifts timestamps to target Saturday 6pm
4. Creates backup of original timestamps
5. Verifies driver screen will show 102+ orders
6. Creates restore script for rollback

**Duration**: ~30 seconds

---

## 📊 Database Schema (Key Tables)

### Orders Table
```sql
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    status VARCHAR(50),
    total DECIMAL(10,2),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    delivery_time TIMESTAMP,
    driver_id BIGINT,
    -- ... other columns
);
```

### Key Statuses
- `pending` - New order
- `confirmed` - Restaurant confirmed
- `preparing` - Being prepared
- `ready` - Ready for pickup
- `out_for_delivery` - Driver en route
- `delivered` - Completed
- `cancelled` - Cancelled

### Driver Screen Query
```sql
-- Orders visible to drivers (Saturday 5pm-8pm)
SELECT *
FROM orders
WHERE DATE(created_at) = '2025-11-09'
  AND HOUR(created_at) BETWEEN 17 AND 20
  AND status IN ('ready', 'out_for_delivery')
ORDER BY delivery_time ASC;
```

---

## 🔄 Database Cloning Workflow

### Full Workflow Diagram
```
┌─────────────────────────────────────────────────────────┐
│ Production Server (tall-stream)                         │
│ ┌─────────────────────────────────────────────────┐    │
│ │ PROD_APP Database (READ-ONLY)                   │    │
│ │ - 100,000+ orders                               │    │
│ │ - Historical data from 2023                     │    │
│ │ - Real customer data                            │    │
│ └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                      │
                      │ SSH Tunnel
                      │ mysqldump --single-transaction
                      │ (READ-ONLY, no locks)
                      ▼
┌─────────────────────────────────────────────────────────┐
│ Local Backup Storage                                    │
│ ┌─────────────────────────────────────────────────┐    │
│ │ backups/keatchen_prod_YYYYMMDD_HHMMSS.sql      │    │
│ │ - Sanitized (DEFINERs removed)                 │    │
│ │ - Compressed                                    │    │
│ │ - Last 5 backups kept                          │    │
│ └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                      │
                      │ SCP Transfer
                      │ Import via mysql CLI
                      ▼
┌─────────────────────────────────────────────────────────┐
│ Test Server (curved-sanctuary)                          │
│ ┌─────────────────────────────────────────────────┐    │
│ │ forge Database                                  │    │
│ │ - Full production data copy                     │    │
│ │ - Timestamps transformed                        │    │
│ │ - Saturday peak: 102 orders                     │    │
│ └─────────────────────────────────────────────────┘    │
│                                                         │
│ ┌─────────────────────────────────────────────────┐    │
│ │ Driver App: http://159.65.213.130/driver       │    │
│ │ Shows: 102 orders from Saturday 6pm             │    │
│ └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

---

## 🛠️ Advanced Operations

### Manual Database Dump
```bash
# SSH into production
ssh forge@18.135.39.222

# Create dump (READ-ONLY)
mysqldump \
    --single-transaction \
    --quick \
    --lock-tables=false \
    -u forge \
    -p'fXcAINwUflS64JVWQYC5' \
    PROD_APP \
    > /tmp/manual_dump.sql

# Exit and copy locally
exit
scp forge@18.135.39.222:/tmp/manual_dump.sql ./backups/
```

### Manual Import to Test
```bash
# Copy to test server
scp ./backups/manual_dump.sql forge@159.65.213.130:/tmp/

# SSH into test server
ssh forge@159.65.213.130

# Import
mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge < /tmp/manual_dump.sql

# Verify
mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge -e "SHOW TABLES; SELECT COUNT(*) FROM orders;"
```

### Restore Original Timestamps
```bash
# If you need to undo Saturday transformation
./scripts/restore-original-timestamps.sh
```

### Check Database Size
```bash
# Production
ssh forge@18.135.39.222 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' -e 'SELECT table_schema AS Database_name, ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS Size_MB FROM information_schema.tables WHERE table_schema = \"PROD_APP\" GROUP BY table_schema;'"

# Test
ssh forge@159.65.213.130 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' -e 'SELECT table_schema AS Database_name, ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS Size_MB FROM information_schema.tables WHERE table_schema = \"forge\" GROUP BY table_schema;'"
```

---

## 🎯 Saturday Peak Data Testing

### Goal
Show driver screen with exactly 102 orders from Saturday 6pm peak time.

### How It Works
1. **Find Best Saturday**: Query production for Saturday with 100+ orders
2. **Calculate Time Shift**: Determine days/hours to move timestamps
3. **Transform Orders**: Update created_at/updated_at timestamps
4. **Verify Count**: Confirm driver screen shows correct orders

### Target Configuration
```bash
TARGET_SATURDAY="2025-11-09"  # Next Saturday
TARGET_TIME="18:00:00"        # 6pm peak
ORDERS_TO_SHOW=102            # Expected on driver screen
TIME_WINDOW="17:00-20:00"     # 3-hour peak window
```

### Verification Query
```sql
-- Check driver screen data
SELECT
    DATE(created_at) as date,
    HOUR(created_at) as hour,
    COUNT(*) as orders,
    COUNT(CASE WHEN status = 'ready' THEN 1 END) as ready_orders,
    COUNT(CASE WHEN status = 'out_for_delivery' THEN 1 END) as delivering
FROM orders
WHERE DATE(created_at) = '2025-11-09'
  AND HOUR(created_at) BETWEEN 17 AND 20
GROUP BY DATE(created_at), HOUR(created_at)
ORDER BY hour;
```

---

## 🔍 Troubleshooting

### Issue: SSH Connection Failed
```bash
# Test SSH access
ssh -v forge@18.135.39.222

# Check SSH key
ls -la ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa

# Test with specific key
ssh -i ~/.ssh/id_rsa forge@18.135.39.222
```

### Issue: mysqldump Permission Denied
```bash
# Test database access
ssh forge@18.135.39.222 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' PROD_APP -e 'SELECT COUNT(*) FROM orders;'"

# Check grants
ssh forge@18.135.39.222 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' -e 'SHOW GRANTS;'"
```

### Issue: Import Failed
```bash
# Check dump file
head -20 ./backups/keatchen_prod_*.sql
tail -20 ./backups/keatchen_prod_*.sql

# Test import locally first
mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge < ./backups/keatchen_prod_*.sql 2>&1 | tee import.log
```

### Issue: Not Enough Saturday Orders
```bash
# Check production for better Saturdays
ssh forge@18.135.39.222 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' PROD_APP -e 'SELECT DATE(created_at), COUNT(*) FROM orders WHERE DAYNAME(created_at) = \"Saturday\" GROUP BY DATE(created_at) ORDER BY COUNT(*) DESC LIMIT 10;'"
```

---

## 📈 Performance Considerations

### Dump Performance
- **Time**: ~2-5 minutes for typical database
- **Size**: 50-500MB compressed
- **Network**: ~1-2 minutes transfer time
- **Impact**: Zero impact on production (no locks)

### Import Performance
- **Time**: ~3-10 minutes depending on size
- **Resources**: Temporary high CPU/disk I/O on test server
- **Downtime**: Test site may be slow during import

### Optimization Tips
1. Run during off-peak hours (early morning)
2. Use `--quick` flag for large tables
3. Consider `--compress` for slow connections
4. Increase `innodb_buffer_pool_size` on test server

---

## 🔄 Automation Options

### Scheduled Daily Clone
```bash
# Add to crontab
0 3 * * * /home/dev/project-analysis/laravel-forge-pr-testing/scripts/clone-production-database.sh >> /var/log/db-clone.log 2>&1
```

### GitHub Actions Integration
```yaml
- name: Clone Production Database
  run: |
    ./scripts/clone-production-database.sh
    ./scripts/saturday-peak-data.sh
```

### API-Triggered Clone
```bash
# Via Forge API (future enhancement)
curl -X POST https://forge.laravel.com/api/v1/servers/986747/database-import \
  -H "Authorization: Bearer $FORGE_TOKEN" \
  -d '{"source_server": 886474, "database": "PROD_APP"}'
```

---

## 📚 Related Documentation

- [Forge API Reference](../5-reference/1-forge-api-endpoints.md)
- [Database Strategy](../3-critical-reading/3-database-strategy.md)
- [Testing Workflow](../4-implementation/2-testing-workflow.md)
- [Troubleshooting Guide](../5-reference/3-troubleshooting.md)

---

## ✅ Checklist

**Before Running Scripts:**
- [ ] SSH key configured and accessible
- [ ] Access verified to production server
- [ ] Access verified to test server
- [ ] Backup directory exists and has space
- [ ] Test environment database is empty or backed up

**After Cloning:**
- [ ] Verify table count matches production
- [ ] Check orders table has data
- [ ] Run Saturday transformation
- [ ] Verify driver screen shows correct data
- [ ] Document any issues encountered

**Production Safety:**
- [ ] Confirmed READ-ONLY access only
- [ ] No DDL operations on production
- [ ] No UPDATE/DELETE on production
- [ ] All modifications on test only
- [ ] Backups exist before transformations

---

**Last Updated**: 2025-11-11
**Maintainer**: DevOps Team
**Status**: ✅ Production Ready
