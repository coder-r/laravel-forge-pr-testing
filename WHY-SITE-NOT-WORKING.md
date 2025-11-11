# Why Site Not Working - Complete Diagnosis

**Issue**: https://pr-test-devpel.on-forge.com doesn't load
**Root Causes**: TWO separate issues

---

## Issue #1: DNS Not Resolving ❌

**Problem**: Domain doesn't exist in DNS
```bash
$ nslookup pr-test-devpel.on-forge.com
Server can't find pr-test-devpel.on-forge.com: NXDOMAIN
```

**Cause**: SSL certificate failed, so Forge never activated the `.on-forge.com` subdomain

**Impact**: Can't access via domain name at all

---

## Issue #2: Laravel App Not Deployed ❌

**Problem**: Showing Forge default page instead of Laravel app

**Evidence**:
```bash
$ ls /home/prdevpel/pr-test-devpel.on-forge.com/public/
index.html  ← Forge default (currently showing)
# Missing: index.php (Laravel entry point)
```

**Cause**: Deployment failed multiple times:
1. First: Wrong database password
2. Second: Wrong database (PROD_APP vs keatchen)
3. Third: Memory limit (512MB too low)
4. Fourth: Still incomplete

**Impact**: Seeing Forge landing page, not your Laravel application

---

## ✅ Complete Fix (5 Minutes)

### Step 1: Fix Storage Permissions (In Forge)

1. Go to: https://forge.laravel.com/servers/986747/sites/2925742
2. Click **"Commands"** tab (or SSH tab)
3. Run this command:
```bash
chmod -R 775 /home/prdevpel/pr-test-devpel.on-forge.com/storage
chmod -R 775 /home/prdevpel/pr-test-devpel.on-forge.com/bootstrap/cache
chown -R prdevpel:prdevpel /home/prdevpel/pr-test-devpel.on-forge.com/storage
chown -R prdevpel:prdevpel /home/prdevpel/pr-test-devpel.on-forge.com/bootstrap/cache
```

### Step 2: Update Deploy Script (Critical!)

1. Click **"App"** tab
2. Scroll to **"Deploy Script"**
3. Replace with this (from deploy-script.txt):

```bash
echo "Starting deployment..."
cd /home/prdevpel/pr-test-devpel.on-forge.com

git pull origin main
echo "✓ Git pull completed"

# Composer
php -d memory_limit=2048M /usr/local/bin/composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev
echo "✓ Composer completed"

# NPM
npm ci
npm run build
echo "✓ Assets built"

# Fix permissions FIRST
chmod -R 775 storage bootstrap/cache
echo "✓ Permissions fixed"

# Clear caches
php -d memory_limit=2048M artisan cache:clear
php -d memory_limit=2048M artisan config:clear
php -d memory_limit=2048M artisan view:clear
echo "✓ Caches cleared"

# Cache config
php -d memory_limit=2048M artisan config:cache
echo "✓ Config cached"

# Migrations
php -d memory_limit=2048M artisan migrate --force
echo "✓ Migrations completed"

# Reload PHP
( flock -w 10 9 || exit 1
    echo 'Restarting FPM...'; sudo -S service php8.3-fpm reload ) 9>/tmp/fpmlock

echo "✅ Deployment completed!"
```

4. Click **"Update Deploy Script"**

### Step 3: Deploy

1. Click **"Deploy Now"**
2. Watch deployment logs
3. Wait 2-3 minutes

### Step 4: Fix SSL (So Domain Works)

1. Click **"SSL"** tab
2. Delete failed certificate
3. Request new LetsEncrypt certificate
4. Wait 2-3 minutes

---

## 🧪 Verification After Fix

### Test 1: Site Loads (via IP)
```bash
curl http://159.65.213.130 -H "Host: pr-test-devpel.on-forge.com"
# Should show Laravel app, not Forge page
```

### Test 2: Laravel Works
```bash
curl http://159.65.213.130/admin/login -H "Host: pr-test-devpel.on-forge.com"
# Should show login form
```

### Test 3: Database Connected
```bash
curl http://159.65.213.130/api/health -H "Host: pr-test-devpel.on-forge.com"
# Should return database status
```

### Test 4: Domain Works (after SSL)
```bash
curl https://pr-test-devpel.on-forge.com
# Should work once SSL succeeds
```

---

## 📊 Current State Summary

| Component | Status | Fix Needed |
|-----------|--------|------------|
| DNS Resolution | ❌ Not working | Install SSL certificate |
| Site Files | ✅ Deployed | None |
| Database | ✅ Working (77,909 orders) | None |
| Laravel App | ❌ Not loading | Redeploy with permissions fix |
| Storage Permissions | ❌ Denied | chmod 775 storage/ |
| PHP Memory | ✅ Fixed in script | None |
| Web Server | ✅ Running | None |

---

## 💡 Why This Happened

### Timeline:
1. ✅ Site created via API
2. ✅ Code deployed from GitHub
3. ❌ First deploy failed (wrong DB password)
4. ❌ Second deploy failed (wrong database)
5. ❌ Third deploy failed (memory limit)
6. ❌ Fourth deploy failed (permissions)
7. ⏳ Fifth deploy needed (with all fixes)

**Current State**: Stuck showing Forge default page because Laravel setup never completed.

---

## 🎯 Root Cause

**The deploy script keeps failing**, so:
- Laravel's index.php never gets activated
- Forge's default index.html shows instead
- Database is fine (77,909 orders ready)
- Just need one successful deployment!

---

## ✅ Solution Summary

**Two issues, two fixes**:

1. **DNS not resolving**:
   - Fix SSL certificate
   - Domain will activate automatically

2. **Laravel not loading**:
   - Fix storage permissions
   - Redeploy with correct script
   - Application will work

**Time**: 5 minutes total
**Then**: Site fully operational!

---

**Next**: Follow Steps 1-4 above in Forge dashboard
