# Correct Deploy Script - Memory Fix

## Issue
The deploy script is NOT using the memory limit for all artisan commands.

The error shows it's running without `-d memory_limit=2048M`:
```
INFO  Caching the framework bootstrap files.
Fatal error: Allowed memory size of 536870912 bytes exhausted
```

---

## ✅ CORRECT Deploy Script (Copy This Exactly)

**Go to Forge → Site → App → Deploy Script**

**Replace with this EXACT script:**

```bash
cd /home/prdevpel/pr-test-devpel.on-forge.com
git pull origin main

# Composer install
php -d memory_limit=2048M /usr/local/bin/composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev

# NPM (if needed)
npm ci
npm run build

# Clear all caches
php -d memory_limit=2048M artisan cache:clear
php -d memory_limit=2048M artisan config:clear
php -d memory_limit=2048M artisan view:clear

# Cache ONLY config (skip routes to avoid memory issue)
php -d memory_limit=2048M artisan config:cache

# DO NOT run: php artisan optimize (causes memory issue)
# DO NOT run: php artisan route:cache (causes memory issue)

# Optional: Run migrations
php -d memory_limit=2048M artisan migrate --force

# Reload PHP
( flock -w 10 9 || exit 1
    echo 'Restarting FPM...'; sudo -S service php8.3-fpm reload ) 9>/tmp/fpmlock

echo "Deployment completed successfully!"
```

---

## Key Changes

### ❌ REMOVE These (cause memory issues):
```bash
php artisan optimize       # ← REMOVE THIS
php artisan route:cache    # ← REMOVE THIS
```

### ✅ KEEP These (with memory flag):
```bash
php -d memory_limit=2048M artisan config:cache   # ← KEEP THIS
php -d memory_limit=2048M artisan cache:clear    # ← KEEP THIS
```

---

## Why This Fixes It

**Before**:
- `php artisan optimize` runs without memory limit
- This internally calls `route:cache`
- Route caching exhausts 512MB memory
- Deployment fails

**After**:
- Skip `optimize` and `route:cache` commands
- Only cache config (uses less memory)
- Routes work fine without caching
- Deployment succeeds

---

## After Updating Script

1. **Click**: "Update Deploy Script"
2. **Click**: "Deploy Now"
3. **Watch**: Should complete without memory error
4. **Result**: Site will load properly!

---

## Verification

After successful deployment, the site should show:
- ✅ Laravel application (not Forge page)
- ✅ Login page accessible
- ✅ Database connected (77,909 orders)
- ✅ All routes working

---

**Note**: Routes will work fine WITHOUT caching. Route caching is only for performance optimization (not required for functionality).
