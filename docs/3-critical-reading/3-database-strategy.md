# Database Replication Strategy for PR Testing Environments

## Executive Summary

This document outlines the database replication strategy for the dual Laravel application PR testing system. The strategy leverages **weekly master snapshots** taken after peak traffic periods to provide realistic test data while maintaining database isolation and performance.

**Key Facts:**
- Two databases: `keatchen` (<5GB) and `devpel` (<5GB)
- Total data volume: <10GB (highly manageable)
- Peak traffic: Weekend evenings (Friday/Saturday)
- Snapshot timing: Sunday morning (post-peak)
- Replication method: mysqldump/pg_dump for portability
- Isolation: Separate databases per PR environment

---

## Table of Contents

1. [Master Snapshot Strategy](#master-snapshot-strategy)
2. [Database Cloning Process](#database-cloning-process)
3. [Database Isolation Architecture](#database-isolation-architecture)
4. [Performance Considerations](#performance-considerations)
5. [Data Anonymization](#data-anonymization)
6. [Database Cleanup](#database-cleanup)
7. [Backup and Recovery](#backup-and-recovery)
8. [Handling Database Migrations](#handling-database-migrations)
9. [Redis Database Isolation](#redis-database-isolation)
10. [Automation Scripts](#automation-scripts)

---

## Master Snapshot Strategy

### Overview

Master snapshots are **weekly refreshes** of production data taken on **Sunday mornings** after the busiest traffic period (Friday/Saturday evenings). This ensures test environments have the most realistic and recent data patterns.

### Snapshot Schedule

```
┌─────────────┬─────────────────────────────────────┐
│ Day         │ Activity                            │
├─────────────┼─────────────────────────────────────┤
│ Fri-Sat     │ Peak traffic (realistic data gen)   │
│ Sunday 4 AM │ Automated snapshot creation         │
│ Mon-Sat     │ Snapshots used for PR environments  │
└─────────────┴─────────────────────────────────────┘
```

### Master Snapshot Naming Convention

```
keatchen_master    # Master snapshot for keatchen database
devpel_master      # Master snapshot for devpel database
```

### Storage Location

```bash
# Recommended snapshot storage structure
/var/lib/mysql-snapshots/
├── keatchen_master.sql.gz
├── keatchen_master.sql.gz.md5
├── devpel_master.sql.gz
├── devpel_master.sql.gz.md5
└── metadata.json  # Snapshot metadata (timestamp, size, version)
```

### Snapshot Metadata

```json
{
  "keatchen": {
    "snapshot_date": "2025-11-07T04:00:00Z",
    "size_bytes": 3221225472,
    "size_human": "3.0GB",
    "mysql_version": "8.0.35",
    "record_count": 1250000,
    "checksum": "a1b2c3d4e5f6..."
  },
  "devpel": {
    "snapshot_date": "2025-11-07T04:00:00Z",
    "size_bytes": 4294967296,
    "size_human": "4.0GB",
    "mysql_version": "8.0.35",
    "record_count": 1800000,
    "checksum": "f6e5d4c3b2a1..."
  }
}
```

### Retention Policy

- **Current master**: Always available
- **Previous 4 weeks**: Archived for rollback capability
- **Older snapshots**: Deleted to conserve space

```bash
/var/lib/mysql-snapshots/
├── current/
│   ├── keatchen_master.sql.gz
│   └── devpel_master.sql.gz
└── archive/
    ├── 2025-10-31/
    ├── 2025-10-24/
    ├── 2025-10-17/
    └── 2025-10-10/
```

---

## Database Cloning Process

### MySQL Approach

#### 1. Create Master Snapshot (mysqldump)

```bash
#!/bin/bash
# Fast mysqldump with compression and optimizations

DB_NAME="$1"
OUTPUT_FILE="/var/lib/mysql-snapshots/current/${DB_NAME}_master.sql.gz"

mysqldump \
  --host=production-db-host \
  --user=snapshot_user \
  --password="${DB_PASSWORD}" \
  --single-transaction \
  --quick \
  --compress \
  --routines \
  --triggers \
  --events \
  --skip-lock-tables \
  "${DB_NAME}" | gzip -9 > "${OUTPUT_FILE}"

# Generate checksum
md5sum "${OUTPUT_FILE}" > "${OUTPUT_FILE}.md5"
```

**Performance:** ~2-3 minutes per 5GB database with gzip compression

#### 2. Clone to Test Environment (mysql import)

```bash
#!/bin/bash
# Fast database cloning from master snapshot

MASTER_DB="$1"      # e.g., keatchen
TARGET_DB="$2"      # e.g., pr_123_keatchen_db
SNAPSHOT_FILE="/var/lib/mysql-snapshots/current/${MASTER_DB}_master.sql.gz"

# Create target database
mysql -h test-db-host -u admin -p"${DB_PASSWORD}" \
  -e "CREATE DATABASE IF NOT EXISTS \`${TARGET_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Import snapshot
gunzip -c "${SNAPSHOT_FILE}" | mysql \
  -h test-db-host \
  -u admin \
  -p"${DB_PASSWORD}" \
  "${TARGET_DB}"

echo "✅ Cloned ${MASTER_DB} → ${TARGET_DB}"
```

**Performance:** ~1-2 minutes to import 5GB database

### PostgreSQL Approach

#### 1. Create Master Snapshot (pg_dump)

```bash
#!/bin/bash
# PostgreSQL snapshot creation

DB_NAME="$1"
OUTPUT_FILE="/var/lib/pg-snapshots/current/${DB_NAME}_master.sql.gz"

PGPASSWORD="${DB_PASSWORD}" pg_dump \
  --host=production-db-host \
  --username=snapshot_user \
  --format=custom \
  --compress=9 \
  --no-owner \
  --no-acl \
  --verbose \
  "${DB_NAME}" > "${OUTPUT_FILE%.gz}"

gzip -9 "${OUTPUT_FILE%.gz}"
md5sum "${OUTPUT_FILE}" > "${OUTPUT_FILE}.md5"
```

#### 2. Clone to Test Environment (pg_restore)

```bash
#!/bin/bash
# PostgreSQL database cloning

MASTER_DB="$1"
TARGET_DB="$2"
SNAPSHOT_FILE="/var/lib/pg-snapshots/current/${MASTER_DB}_master.sql.gz"

# Create target database
PGPASSWORD="${DB_PASSWORD}" psql \
  -h test-db-host \
  -U admin \
  -c "CREATE DATABASE \"${TARGET_DB}\" WITH ENCODING='UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8';"

# Import snapshot
gunzip -c "${SNAPSHOT_FILE}" | PGPASSWORD="${DB_PASSWORD}" pg_restore \
  --host=test-db-host \
  --username=admin \
  --dbname="${TARGET_DB}" \
  --no-owner \
  --no-acl \
  --verbose

echo "✅ Cloned ${MASTER_DB} → ${TARGET_DB}"
```

---

## Database Isolation Architecture

### Naming Convention

```
Production Databases:
  - keatchen
  - devpel

Master Snapshots:
  - keatchen_master
  - devpel_master

PR Environment Databases:
  - pr_{PR_NUMBER}_{PROJECT}_db

Examples:
  - pr_123_keatchen_db
  - pr_123_devpel_db
  - pr_456_keatchen_db
  - pr_456_devpel_db
```

### Isolation Benefits

| Aspect | Benefit |
|--------|---------|
| **Data integrity** | Each PR has its own database; no cross-contamination |
| **Parallel testing** | Multiple PRs can run tests simultaneously |
| **Destructive tests** | Safe to truncate tables or test migrations |
| **Independent lifecycles** | Databases created/destroyed with environments |

### Database User Permissions

```sql
-- Create isolated user per PR environment
CREATE USER 'pr_123_user'@'%' IDENTIFIED BY 'random_generated_password';

-- Grant permissions only to PR-specific databases
GRANT ALL PRIVILEGES ON `pr_123_keatchen_db`.* TO 'pr_123_user'@'%';
GRANT ALL PRIVILEGES ON `pr_123_devpel_db`.* TO 'pr_123_user'@'%';

FLUSH PRIVILEGES;
```

### Connection Pooling

```ini
# MySQL connection limits per PR environment
max_connections = 50  # Per PR environment
wait_timeout = 3600   # 1 hour idle timeout
interactive_timeout = 3600
```

---

## Performance Considerations

### Why <5GB is Optimal

```
┌────────────────────┬──────────────────────────────────┐
│ Operation          │ Time (5GB database)              │
├────────────────────┼──────────────────────────────────┤
│ mysqldump          │ 2-3 minutes (with compression)   │
│ mysql import       │ 1-2 minutes                      │
│ Database creation  │ <5 seconds                       │
│ Total clone time   │ 3-5 minutes per PR               │
└────────────────────┴──────────────────────────────────┘
```

### Optimization Strategies

#### 1. Snapshot Compression

```bash
# Compression comparison for 5GB database
├── Uncompressed: 5.0 GB
├── gzip -9:      1.2 GB (76% reduction)
└── zstd:         1.0 GB (80% reduction, faster)

# Recommended: gzip -9 (best compatibility)
```

#### 2. Parallel Database Operations

```bash
# Clone both databases simultaneously
clone_database "keatchen" "pr_123_keatchen_db" &
clone_database "devpel" "pr_123_devpel_db" &
wait

# Total time: 3-5 minutes (not 6-10 minutes)
```

#### 3. Storage Optimization

```bash
# Use tmpfs for fast imports (optional)
mount -t tmpfs -o size=6G tmpfs /tmp/db-import

# Import from tmpfs (RAM disk)
cp /var/lib/mysql-snapshots/current/keatchen_master.sql.gz /tmp/db-import/
gunzip -c /tmp/db-import/keatchen_master.sql.gz | mysql pr_123_keatchen_db
```

#### 4. Index Rebuild

```sql
-- After import, rebuild indexes for optimal performance
ANALYZE TABLE table_name;
OPTIMIZE TABLE table_name;
```

### Network Considerations

```
Database Server Location Options:

Option 1: Same host as Docker containers
  ✅ Pros: Zero network latency, fast imports
  ❌ Cons: Resource sharing with containers

Option 2: Dedicated database server
  ✅ Pros: Isolated resources, better scaling
  ❌ Cons: Network transfer time (~30s for 5GB)

Recommendation: Same host for <5GB databases
```

---

## Data Anonymization

### Current Status

**Not required** for internal PR testing environments with proper access control.

### When Anonymization is Needed

- External contractor access
- Compliance requirements (GDPR, HIPAA)
- Public demo environments
- Third-party integrations

### Future Anonymization Strategy

```sql
-- Example anonymization script (if needed in future)

-- Anonymize user emails
UPDATE users SET
  email = CONCAT('user_', id, '@test.local'),
  password = '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'; -- "password"

-- Anonymize phone numbers
UPDATE users SET
  phone = CONCAT('+1555', LPAD(id, 7, '0'));

-- Anonymize addresses
UPDATE addresses SET
  street = CONCAT('Test Street ', id),
  city = 'Test City',
  postal_code = CONCAT('12345-', LPAD(id % 9999, 4, '0'));

-- Keep referential integrity intact
-- Keep realistic data patterns (dates, counts, relationships)
```

### Anonymization Tools

```bash
# If needed in future, consider:
- mysql-anonymizer (Python)
- PostgreSQL Anonymizer extension
- Custom Laravel seeders with Faker
```

---

## Database Cleanup

### Automatic Cleanup on Environment Destruction

```bash
#!/bin/bash
# cleanup_pr_databases.sh
# Called when PR environment is destroyed

PR_NUMBER="$1"

echo "🗑️  Cleaning up databases for PR #${PR_NUMBER}..."

# MySQL cleanup
for PROJECT in keatchen devpel; do
  DB_NAME="pr_${PR_NUMBER}_${PROJECT}_db"
  USER_NAME="pr_${PR_NUMBER}_user"

  mysql -h test-db-host -u admin -p"${ADMIN_PASSWORD}" <<EOF
    DROP DATABASE IF EXISTS \`${DB_NAME}\`;
    DROP USER IF EXISTS '${USER_NAME}'@'%';
    FLUSH PRIVILEGES;
EOF

  echo "  ✅ Dropped ${DB_NAME}"
done

echo "✅ Database cleanup complete for PR #${PR_NUMBER}"
```

### Orphaned Database Detection

```bash
#!/bin/bash
# find_orphaned_databases.sh
# Finds databases for PRs that no longer exist

echo "🔍 Scanning for orphaned databases..."

# Get list of active PRs
ACTIVE_PRS=$(gh pr list --repo owner/repo --json number --jq '.[].number')

# Get all pr_* databases
DATABASES=$(mysql -h test-db-host -u admin -p"${ADMIN_PASSWORD}" -N -e "SHOW DATABASES LIKE 'pr_%';")

for DB in $DATABASES; do
  # Extract PR number from database name
  PR_NUM=$(echo "$DB" | grep -oP 'pr_\K[0-9]+')

  # Check if PR exists
  if ! echo "$ACTIVE_PRS" | grep -q "^${PR_NUM}$"; then
    echo "  ⚠️  Orphaned: ${DB} (PR #${PR_NUM} not found)"

    # Optional: Auto-cleanup after confirmation
    # mysql -h test-db-host -u admin -p"${ADMIN_PASSWORD}" -e "DROP DATABASE \`${DB}\`;"
  fi
done

echo "✅ Scan complete"
```

### Cleanup Schedule

```cron
# Crontab for database maintenance

# Daily orphaned database cleanup (3 AM)
0 3 * * * /usr/local/bin/cleanup_orphaned_databases.sh

# Weekly snapshot archive rotation (Sunday 5 AM)
0 5 * * 0 /usr/local/bin/rotate_snapshot_archives.sh

# Monthly disk space check (1st of month, 6 AM)
0 6 1 * * /usr/local/bin/check_database_disk_space.sh
```

---

## Backup and Recovery

### Three-Tier Backup Strategy

```
┌─────────────────┬──────────────────┬────────────────────┐
│ Tier            │ Retention        │ Purpose            │
├─────────────────┼──────────────────┼────────────────────┤
│ Master Snapshot │ Current + 4 wks  │ PR cloning         │
│ Production DB   │ 30 days          │ Disaster recovery  │
│ Offsite Backup  │ 1 year           │ Long-term archive  │
└─────────────────┴──────────────────┴────────────────────┘
```

### Recovery Scenarios

#### Scenario 1: Corrupted Master Snapshot

```bash
# Rollback to previous week's snapshot
cp /var/lib/mysql-snapshots/archive/2025-10-31/keatchen_master.sql.gz \
   /var/lib/mysql-snapshots/current/keatchen_master.sql.gz

# Update metadata
./update_snapshot_metadata.sh --rollback --date=2025-10-31
```

#### Scenario 2: Test Database Corruption

```bash
# Simply re-clone from master snapshot
./clone_database.sh keatchen pr_123_keatchen_db

# No data loss (test data is disposable)
```

#### Scenario 3: Production Database Failure

```bash
# Restore from production backups (not master snapshots)
# Master snapshots are NOT production backups!

# Use production backup system
./restore_production_db.sh --date=2025-11-06 --database=keatchen
```

### Backup Verification

```bash
#!/bin/bash
# verify_snapshots.sh
# Daily snapshot integrity check

for SNAPSHOT in /var/lib/mysql-snapshots/current/*.sql.gz; do
  echo "🔍 Verifying: $(basename $SNAPSHOT)"

  # Checksum verification
  if md5sum -c "${SNAPSHOT}.md5"; then
    echo "  ✅ Checksum valid"
  else
    echo "  ❌ CHECKSUM MISMATCH!"
    exit 1
  fi

  # Test decompression
  if gunzip -t "$SNAPSHOT"; then
    echo "  ✅ Decompression successful"
  else
    echo "  ❌ CORRUPTION DETECTED!"
    exit 1
  fi

  # Test import to temporary database
  TEMP_DB="snapshot_verify_$(date +%s)"
  mysql -e "CREATE DATABASE ${TEMP_DB};"

  if gunzip -c "$SNAPSHOT" | mysql "${TEMP_DB}"; then
    echo "  ✅ Import test successful"
    mysql -e "DROP DATABASE ${TEMP_DB};"
  else
    echo "  ❌ IMPORT FAILED!"
    mysql -e "DROP DATABASE IF EXISTS ${TEMP_DB};"
    exit 1
  fi
done

echo "✅ All snapshots verified successfully"
```

---

## Handling Database Migrations

### Migration Strategy in Test Environments

```
┌────────────────────────────────────────────────────────┐
│ Master Snapshot (Sunday)                               │
│   ↓                                                    │
│ Clone to PR Environment                                │
│   ↓                                                    │
│ Run PR's Migrations (php artisan migrate)              │
│   ↓                                                    │
│ Test Against Migrated Schema                           │
└────────────────────────────────────────────────────────┘
```

### Migration Workflow

#### 1. Fresh Clone Always Starts from Master

```bash
# PR environment creation
clone_database "keatchen" "pr_123_keatchen_db"

# Master snapshot is at production schema version
# Example: production is at migration 2025_11_01_000000
```

#### 2. Apply PR's Migrations

```bash
# Inside PR environment container
cd /var/www/keatchen
php artisan migrate --force

# This runs any NEW migrations in the PR branch
# Example: PR adds migration 2025_11_05_000000
```

#### 3. Test With Updated Schema

```bash
# Run tests against migrated database
php artisan test
```

### Migration Rollback Testing

```bash
#!/bin/bash
# test_migration_rollback.sh
# Tests migration rollback capability

PR_NUMBER="$1"
PROJECT="$2"

DB_NAME="pr_${PR_NUMBER}_${PROJECT}_db"

echo "Testing migration rollback for PR #${PR_NUMBER}..."

# 1. Clone fresh database
./clone_database.sh "${PROJECT}" "${DB_NAME}"

# 2. Apply migrations
docker exec "pr-${PR_NUMBER}-${PROJECT}" php artisan migrate --force

# 3. Test rollback
docker exec "pr-${PR_NUMBER}-${PROJECT}" php artisan migrate:rollback --force

# 4. Re-apply migrations
docker exec "pr-${PR_NUMBER}-${PROJECT}" php artisan migrate --force

# 5. Verify data integrity
docker exec "pr-${PR_NUMBER}-${PROJECT}" php artisan test --filter=MigrationTest

echo "✅ Migration rollback test complete"
```

### Handling Breaking Migrations

```bash
# If PR migration breaks on master snapshot schema

# Option 1: Clone from production (latest schema)
# Production should already have base migrations run
./clone_from_production.sh keatchen pr_123_keatchen_db

# Option 2: Re-create master snapshot (if prod schema changed)
./create_master_snapshot.sh keatchen

# Option 3: Manual migration repair
docker exec pr-123-keatchen mysql pr_123_keatchen_db \
  -e "DELETE FROM migrations WHERE migration = 'problematic_migration';"
```

### Migration Best Practices

```php
// In PR migrations, always check for existing state

public function up()
{
    // ✅ Good: Check before creating
    if (!Schema::hasTable('new_table')) {
        Schema::create('new_table', function (Blueprint $table) {
            $table->id();
            // ...
        });
    }

    // ✅ Good: Check before adding column
    if (!Schema::hasColumn('users', 'new_column')) {
        Schema::table('users', function (Blueprint $table) {
            $table->string('new_column')->nullable();
        });
    }
}

public function down()
{
    // ✅ Good: Safe rollback
    Schema::dropIfExists('new_table');

    if (Schema::hasColumn('users', 'new_column')) {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('new_column');
        });
    }
}
```

---

## Redis Database Isolation

### Redis Database Number Assignment

Redis supports 16 databases (0-15) by default. Assign unique database numbers per PR environment.

```
┌─────────────────┬──────────────────┬──────────────────┐
│ Redis DB        │ Purpose          │ PR Environment   │
├─────────────────┼──────────────────┼──────────────────┤
│ 0               │ Production       │ -                │
│ 1               │ Staging          │ -                │
│ 2-15            │ PR Environments  │ pr_123, pr_456   │
└─────────────────┴──────────────────┴──────────────────┘
```

### Dynamic Redis DB Assignment

```bash
#!/bin/bash
# assign_redis_db.sh
# Assigns unique Redis database number to PR

PR_NUMBER="$1"

# Calculate Redis DB number (2-15 for PRs)
# Use modulo to wrap around if > 14 PRs active
REDIS_DB=$((2 + (PR_NUMBER % 14)))

echo "PR #${PR_NUMBER} → Redis DB ${REDIS_DB}"
echo "${REDIS_DB}" > "/var/lib/pr-environments/pr_${PR_NUMBER}/redis_db.txt"
```

### Laravel Redis Configuration

```php
// config/database.php
// Dynamically set Redis database per environment

'redis' => [
    'client' => env('REDIS_CLIENT', 'phpredis'),

    'default' => [
        'host' => env('REDIS_HOST', '127.0.0.1'),
        'password' => env('REDIS_PASSWORD', null),
        'port' => env('REDIS_PORT', 6379),
        'database' => env('REDIS_DB', 0), // Set dynamically per PR
    ],

    'cache' => [
        'host' => env('REDIS_HOST', '127.0.0.1'),
        'password' => env('REDIS_PASSWORD', null),
        'port' => env('REDIS_PORT', 6379),
        'database' => env('REDIS_CACHE_DB', 1),
    ],
],
```

### Environment Variable Injection

```bash
# In PR environment creation script

PR_NUMBER="$1"
REDIS_DB=$((2 + (PR_NUMBER % 14)))

# Add to .env file
cat >> "/var/www/${PROJECT}/.env" <<EOF
REDIS_DB=${REDIS_DB}
REDIS_CACHE_DB=${REDIS_DB}
EOF
```

### Redis Cleanup

```bash
#!/bin/bash
# cleanup_redis_db.sh
# Flush Redis database for PR environment

PR_NUMBER="$1"
REDIS_DB_FILE="/var/lib/pr-environments/pr_${PR_NUMBER}/redis_db.txt"

if [ -f "$REDIS_DB_FILE" ]; then
  REDIS_DB=$(cat "$REDIS_DB_FILE")

  echo "🗑️  Flushing Redis DB ${REDIS_DB} for PR #${PR_NUMBER}..."

  redis-cli -h redis-host -n "${REDIS_DB}" FLUSHDB

  echo "✅ Redis DB ${REDIS_DB} flushed"
  rm "$REDIS_DB_FILE"
else
  echo "⚠️  No Redis DB assignment found for PR #${PR_NUMBER}"
fi
```

### Redis Isolation Benefits

- **Cache isolation**: Each PR has independent cache
- **Session isolation**: No session leakage between PRs
- **Queue isolation**: Job queues don't interfere
- **Fast cleanup**: FLUSHDB instead of selective key deletion

---

## Automation Scripts

### 1. Create Master Snapshots (Sunday Morning)

```bash
#!/bin/bash
# /usr/local/bin/create_master_snapshots.sh
# Cron: 0 4 * * 0 (Sunday 4 AM)

set -euo pipefail

SNAPSHOT_DIR="/var/lib/mysql-snapshots"
CURRENT_DIR="${SNAPSHOT_DIR}/current"
ARCHIVE_DIR="${SNAPSHOT_DIR}/archive/$(date +%Y-%m-%d)"

# Database credentials
DB_HOST="production-db-host"
DB_USER="snapshot_user"
DB_PASS="${MYSQL_SNAPSHOT_PASSWORD}"

# Databases to snapshot
DATABASES=("keatchen" "devpel")

echo "📸 Creating master snapshots - $(date)"

# Create directories
mkdir -p "${CURRENT_DIR}" "${ARCHIVE_DIR}"

# Archive previous snapshots
if [ -f "${CURRENT_DIR}/keatchen_master.sql.gz" ]; then
  echo "📦 Archiving previous snapshots..."
  cp -p "${CURRENT_DIR}"/*.sql.gz* "${ARCHIVE_DIR}/"
fi

# Create new snapshots
for DB in "${DATABASES[@]}"; do
  echo "📸 Snapshotting: ${DB}"

  OUTPUT_FILE="${CURRENT_DIR}/${DB}_master.sql.gz"
  TEMP_FILE="${CURRENT_DIR}/${DB}_master.sql.gz.tmp"

  # Create snapshot
  mysqldump \
    --host="${DB_HOST}" \
    --user="${DB_USER}" \
    --password="${DB_PASS}" \
    --single-transaction \
    --quick \
    --compress \
    --routines \
    --triggers \
    --events \
    --skip-lock-tables \
    "${DB}" | gzip -9 > "${TEMP_FILE}"

  # Generate checksum
  md5sum "${TEMP_FILE}" > "${TEMP_FILE}.md5"

  # Atomic move
  mv "${TEMP_FILE}" "${OUTPUT_FILE}"
  mv "${TEMP_FILE}.md5" "${OUTPUT_FILE}.md5"

  # Get stats
  SIZE=$(stat -f%z "${OUTPUT_FILE}" 2>/dev/null || stat -c%s "${OUTPUT_FILE}")
  SIZE_MB=$((SIZE / 1024 / 1024))

  echo "  ✅ ${DB}: ${SIZE_MB} MB"
done

# Update metadata
cat > "${CURRENT_DIR}/metadata.json" <<EOF
{
  "snapshot_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "databases": {
$(for DB in "${DATABASES[@]}"; do
  FILE="${CURRENT_DIR}/${DB}_master.sql.gz"
  SIZE=$(stat -f%z "${FILE}" 2>/dev/null || stat -c%s "${FILE}")
  CHECKSUM=$(cut -d' ' -f1 "${FILE}.md5")
  cat <<INNER
    "${DB}": {
      "size_bytes": ${SIZE},
      "size_human": "$((SIZE / 1024 / 1024)) MB",
      "checksum": "${CHECKSUM}"
    }$([ "${DB}" = "${DATABASES[-1]}" ] && echo "" || echo ",")
INNER
done)
  }
}
EOF

# Cleanup old archives (keep 4 weeks)
echo "🧹 Cleaning old archives..."
find "${SNAPSHOT_DIR}/archive" -type d -mtime +28 -exec rm -rf {} +

# Verify snapshots
echo "🔍 Verifying snapshots..."
for DB in "${DATABASES[@]}"; do
  FILE="${CURRENT_DIR}/${DB}_master.sql.gz"

  if md5sum -c "${FILE}.md5" >/dev/null 2>&1; then
    echo "  ✅ ${DB}: Checksum valid"
  else
    echo "  ❌ ${DB}: CHECKSUM FAILED!"
    exit 1
  fi
done

echo "✅ Master snapshot creation complete - $(date)"

# Send notification (optional)
# curl -X POST https://slack-webhook-url \
#   -d '{"text": "✅ Database master snapshots created successfully"}'
```

### 2. Clone Database to PR Environment

```bash
#!/bin/bash
# /usr/local/bin/clone_database.sh
# Usage: clone_database.sh <source_db> <target_db>

set -euo pipefail

SOURCE_DB="$1"  # e.g., keatchen
TARGET_DB="$2"  # e.g., pr_123_keatchen_db

SNAPSHOT_DIR="/var/lib/mysql-snapshots/current"
SNAPSHOT_FILE="${SNAPSHOT_DIR}/${SOURCE_DB}_master.sql.gz"

DB_HOST="test-db-host"
DB_USER="admin"
DB_PASS="${MYSQL_ADMIN_PASSWORD}"

echo "🔄 Cloning ${SOURCE_DB} → ${TARGET_DB}"

# Verify snapshot exists
if [ ! -f "${SNAPSHOT_FILE}" ]; then
  echo "❌ Snapshot not found: ${SNAPSHOT_FILE}"
  exit 1
fi

# Verify checksum
if ! md5sum -c "${SNAPSHOT_FILE}.md5" >/dev/null 2>&1; then
  echo "❌ Snapshot checksum verification failed!"
  exit 1
fi

# Create target database
echo "📝 Creating database: ${TARGET_DB}"
mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" <<EOF
CREATE DATABASE IF NOT EXISTS \`${TARGET_DB}\`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
EOF

# Import snapshot
echo "📥 Importing snapshot..."
START_TIME=$(date +%s)

gunzip -c "${SNAPSHOT_FILE}" | mysql \
  -h "${DB_HOST}" \
  -u "${DB_USER}" \
  -p"${DB_PASS}" \
  "${TARGET_DB}"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "✅ Clone complete in ${DURATION}s: ${SOURCE_DB} → ${TARGET_DB}"
```

### 3. Cleanup PR Databases

```bash
#!/bin/bash
# /usr/local/bin/cleanup_pr_databases.sh
# Usage: cleanup_pr_databases.sh <pr_number>

set -euo pipefail

PR_NUMBER="$1"

DB_HOST="test-db-host"
DB_USER="admin"
DB_PASS="${MYSQL_ADMIN_PASSWORD}"

REDIS_HOST="redis-host"

PROJECTS=("keatchen" "devpel")

echo "🗑️  Cleaning up PR #${PR_NUMBER} databases..."

# MySQL cleanup
for PROJECT in "${PROJECTS[@]}"; do
  DB_NAME="pr_${PR_NUMBER}_${PROJECT}_db"
  USER_NAME="pr_${PR_NUMBER}_user"

  echo "  🗑️  Dropping: ${DB_NAME}"

  mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" <<EOF
DROP DATABASE IF EXISTS \`${DB_NAME}\`;
DROP USER IF EXISTS '${USER_NAME}'@'%';
FLUSH PRIVILEGES;
EOF

  echo "    ✅ Dropped ${DB_NAME}"
done

# Redis cleanup
REDIS_DB_FILE="/var/lib/pr-environments/pr_${PR_NUMBER}/redis_db.txt"

if [ -f "${REDIS_DB_FILE}" ]; then
  REDIS_DB=$(cat "${REDIS_DB_FILE}")
  echo "  🗑️  Flushing Redis DB ${REDIS_DB}"

  redis-cli -h "${REDIS_HOST}" -n "${REDIS_DB}" FLUSHDB
  rm "${REDIS_DB_FILE}"

  echo "    ✅ Flushed Redis DB ${REDIS_DB}"
fi

echo "✅ Cleanup complete for PR #${PR_NUMBER}"
```

### 4. Find Orphaned Databases

```bash
#!/bin/bash
# /usr/local/bin/find_orphaned_databases.sh
# Cron: 0 3 * * * (Daily at 3 AM)

set -euo pipefail

DB_HOST="test-db-host"
DB_USER="admin"
DB_PASS="${MYSQL_ADMIN_PASSWORD}"

GITHUB_REPO="owner/repo"

echo "🔍 Scanning for orphaned databases..."

# Get list of active PRs
ACTIVE_PRS=$(gh pr list --repo "${GITHUB_REPO}" --json number --jq '.[].number' | sort -n)

# Get all pr_* databases
DATABASES=$(mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" -N -e "SHOW DATABASES LIKE 'pr_%';" | sort)

ORPHANED_COUNT=0

for DB in ${DATABASES}; do
  # Extract PR number from database name
  PR_NUM=$(echo "${DB}" | grep -oP 'pr_\K[0-9]+' | head -1)

  if [ -z "${PR_NUM}" ]; then
    continue
  fi

  # Check if PR exists
  if ! echo "${ACTIVE_PRS}" | grep -q "^${PR_NUM}$"; then
    echo "  ⚠️  Orphaned: ${DB} (PR #${PR_NUM} not found)"
    ORPHANED_COUNT=$((ORPHANED_COUNT + 1))

    # Auto-cleanup after 7 days
    DB_AGE=$(mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" -N -e \
      "SELECT DATEDIFF(NOW(), CREATE_TIME) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '${DB}';")

    if [ "${DB_AGE}" -gt 7 ]; then
      echo "    🗑️  Auto-deleting (${DB_AGE} days old)"
      mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" -e "DROP DATABASE \`${DB}\`;"
      echo "    ✅ Deleted ${DB}"
    else
      echo "    ⏳ Keeping (${DB_AGE} days old, < 7 day threshold)"
    fi
  fi
done

echo "✅ Scan complete - Found ${ORPHANED_COUNT} orphaned databases"

# Send notification if orphaned databases found
if [ ${ORPHANED_COUNT} -gt 0 ]; then
  # curl -X POST https://slack-webhook-url \
  #   -d "{\"text\": \"⚠️ Found ${ORPHANED_COUNT} orphaned PR databases\"}"
  :
fi
```

### 5. Complete PR Environment Setup

```bash
#!/bin/bash
# /usr/local/bin/setup_pr_environment.sh
# Usage: setup_pr_environment.sh <pr_number>

set -euo pipefail

PR_NUMBER="$1"

echo "🚀 Setting up PR #${PR_NUMBER} environment..."

# 1. Clone databases
for PROJECT in keatchen devpel; do
  echo "📦 Cloning ${PROJECT} database..."
  /usr/local/bin/clone_database.sh "${PROJECT}" "pr_${PR_NUMBER}_${PROJECT}_db"
done

# 2. Create database user
echo "👤 Creating database user..."
DB_USER="pr_${PR_NUMBER}_user"
DB_PASS=$(openssl rand -base64 32)

mysql -h test-db-host -u admin -p"${MYSQL_ADMIN_PASSWORD}" <<EOF
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`pr_${PR_NUMBER}_keatchen_db\`.* TO '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`pr_${PR_NUMBER}_devpel_db\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF

# 3. Assign Redis DB
REDIS_DB=$((2 + (PR_NUMBER % 14)))
mkdir -p "/var/lib/pr-environments/pr_${PR_NUMBER}"
echo "${REDIS_DB}" > "/var/lib/pr-environments/pr_${PR_NUMBER}/redis_db.txt"

# 4. Store credentials
cat > "/var/lib/pr-environments/pr_${PR_NUMBER}/db_credentials.env" <<EOF
DB_HOST=test-db-host
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASS}
REDIS_DB=${REDIS_DB}
EOF

chmod 600 "/var/lib/pr-environments/pr_${PR_NUMBER}/db_credentials.env"

echo "✅ PR #${PR_NUMBER} environment ready"
echo ""
echo "Database Credentials:"
echo "  User: ${DB_USER}"
echo "  Databases: pr_${PR_NUMBER}_keatchen_db, pr_${PR_NUMBER}_devpel_db"
echo "  Redis DB: ${REDIS_DB}"
```

---

## Performance Benchmarks

### Expected Timings (5GB database)

```
Operation                          | Time (MySQL) | Time (PostgreSQL)
-----------------------------------|--------------|------------------
Create master snapshot (dump)      | 2-3 min      | 2-3 min
Clone to test environment (import) | 1-2 min      | 1-2 min
Create database user               | <1 sec       | <1 sec
Run Laravel migrations             | 10-30 sec    | 10-30 sec
Total PR environment setup         | 3-6 min      | 3-6 min

Parallel operations (both DBs):    | 3-6 min      | 3-6 min
```

### Scalability

```
Concurrent PR Environments | Storage Required | Database Load
---------------------------|------------------|---------------
1 PR                       | 10 GB           | Low
5 PRs                      | 50 GB           | Medium
10 PRs                     | 100 GB          | High
20 PRs                     | 200 GB          | Very High

Recommendation: 10 concurrent PRs maximum
Storage recommendation: 500 GB (master + 20 PRs + archives)
```

---

## Troubleshooting

### Issue: Snapshot creation fails

```bash
# Check disk space
df -h /var/lib/mysql-snapshots

# Check database connection
mysql -h production-db-host -u snapshot_user -p -e "SHOW DATABASES;"

# Check permissions
ls -la /var/lib/mysql-snapshots/current/

# Manual snapshot test
mysqldump --host=production-db-host --user=snapshot_user -p keatchen | head -100
```

### Issue: Clone import fails

```bash
# Verify snapshot integrity
md5sum -c /var/lib/mysql-snapshots/current/keatchen_master.sql.gz.md5

# Test decompression
gunzip -t /var/lib/mysql-snapshots/current/keatchen_master.sql.gz

# Check target database connection
mysql -h test-db-host -u admin -p -e "SHOW DATABASES;"

# Check MySQL error log
tail -100 /var/log/mysql/error.log
```

### Issue: Orphaned databases not cleaned up

```bash
# Manual cleanup
./cleanup_pr_databases.sh 123

# List all pr_* databases
mysql -h test-db-host -u admin -p -e "SHOW DATABASES LIKE 'pr_%';"

# Force drop database
mysql -h test-db-host -u admin -p -e "DROP DATABASE IF EXISTS \`pr_123_keatchen_db\`;"
```

### Issue: Redis database conflicts

```bash
# Check Redis database assignment
cat /var/lib/pr-environments/pr_123/redis_db.txt

# List keys in Redis DB
redis-cli -n 2 KEYS '*'

# Manually flush Redis DB
redis-cli -n 2 FLUSHDB

# Reassign Redis DB
./assign_redis_db.sh 123
```

---

## Security Considerations

### Snapshot Storage Permissions

```bash
# Restrict snapshot directory access
chown -R mysql:mysql /var/lib/mysql-snapshots
chmod 700 /var/lib/mysql-snapshots
chmod 600 /var/lib/mysql-snapshots/current/*.sql.gz
```

### Database User Isolation

```sql
-- PR users should NOT have:
- GRANT OPTION
- CREATE USER
- SUPER
- FILE
- PROCESS
- RELOAD

-- PR users SHOULD have:
- SELECT, INSERT, UPDATE, DELETE on pr_*_db
- CREATE, DROP, INDEX on pr_*_db
- REFERENCES, ALTER on pr_*_db
```

### Credential Management

```bash
# Store credentials securely
# Option 1: Environment variables (systemd)
# Option 2: HashiCorp Vault
# Option 3: AWS Secrets Manager

# Never commit credentials to git
echo "db_credentials.env" >> .gitignore
```

### Network Security

```
Recommended firewall rules:

Production DB:
  - Allow: Snapshot script server (Sunday 4 AM only)
  - Deny: All other access

Test DB:
  - Allow: PR environment containers
  - Deny: External access
```

---

## Summary

### Key Points

✅ **Weekly snapshots** (Sunday morning) provide realistic test data
✅ **<5GB databases** = fast 3-6 minute cloning
✅ **Isolated databases** per PR prevent cross-contamination
✅ **Automatic cleanup** removes orphaned databases
✅ **Migration testing** works seamlessly with snapshot baseline
✅ **Redis isolation** via database numbers (2-15)

### Quick Reference Commands

```bash
# Create master snapshots
/usr/local/bin/create_master_snapshots.sh

# Setup PR environment
/usr/local/bin/setup_pr_environment.sh 123

# Clone single database
/usr/local/bin/clone_database.sh keatchen pr_123_keatchen_db

# Cleanup PR environment
/usr/local/bin/cleanup_pr_databases.sh 123

# Find orphaned databases
/usr/local/bin/find_orphaned_databases.sh
```

### Next Steps

1. ✅ Deploy snapshot creation script to production server
2. ✅ Configure Sunday 4 AM cron job
3. ✅ Test database cloning workflow
4. ✅ Integrate with GitHub Actions PR automation
5. ✅ Set up monitoring and alerts
6. ✅ Document in team wiki

---

**Document Version:** 1.0
**Last Updated:** 2025-11-07
**Author:** DevOps Team
**Review Date:** 2025-12-01
