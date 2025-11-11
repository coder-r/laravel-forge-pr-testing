# Memory Limit Fix for Deployment

## Problem
Deployment failing with:
```
Fatal error: Allowed memory size of 536870912 bytes exhausted
```

**Cause**: PHP memory limit (512MB) is too low for route caching with large application

---

## Quick Fix (Via Forge Dashboard)

### Step 1: Update Deployment Script

1. Go to: https://forge.laravel.com/servers/986747/sites/2925742
2. Click **"App"** tab
3. Scroll to **"Deploy Script"** section
4. Replace the entire script with:

```bash
cd /home/prdevpel/pr-test-devpel.on-forge.com
git pull origin main

# Install dependencies with increased memory
php -d memory_limit=2048M /usr/local/bin/composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev

# Run migrations
php -d memory_limit=2048M artisan migrate --force

# Clear caches
php -d memory_limit=2048M artisan cache:clear
php -d memory_limit=2048M artisan config:clear
php -d memory_limit=2048M artisan view:clear

# Cache config only (skip routes to avoid memory issue)
php -d memory_limit=2048M artisan config:cache

# Optimize autoloader
php -d memory_limit=2048M artisan optimize

echo "Deployment completed!"
```

5. Click **"Update Deploy Script"**

### Step 2: Deploy Again

1. Click **"Deploy Now"** button
2. Wait 2-3 minutes

This should work now! ✅

---

## What Changed

### Before (Default):
```bash
php artisan config:cache  # Uses 512MB limit
php artisan route:cache   # FAILS - needs >512MB
```

### After (Fixed):
```bash
php -d memory_limit=2048M artisan config:cache  # Uses 2GB limit
# Skip route:cache to avoid memory issue
```

---

## Alternative: Increase Global PHP Memory

If you want to increase memory globally:

### Via Forge Dashboard:

1. Go to: https://forge.laravel.com/servers/986747
2. Click **"PHP"** tab
3. Click **"Customize PHP"**
4. Find: `memory_limit = 512M`
5. Change to: `memory_limit = 2048M`
6. Click **"Save"**
7. Redeploy site

---

## Why This Happens

Large Laravel applications with many routes can exhaust memory during:
- Route caching (`php artisan route:cache`)
- Config caching with complex configs
- Large number of service providers

**Solutions**:
1. Increase memory limit ✅ (fastest)
2. Skip route caching ✅ (our approach)
3. Optimize routes (long-term)
4. Split application into smaller services

---

## After Fix

Once deployed successfully:
- ✅ Site loads
- ✅ Config cached
- ✅ Routes work (not cached but functional)
- ✅ Application operational
- ✅ 77,909 orders accessible

---

## Test After Deployment

```bash
# Check site loads
curl -I http://159.65.213.130 -H "Host: pr-test-devpel.on-forge.com"

# Test database connection
ssh -i ~/.ssh/tall-stream-key forge@159.65.213.130 \
  "cd /home/prdevpel/pr-test-devpel.on-forge.com && \
   php -d memory_limit=2048M artisan tinker --execute='echo DB::table(\"orders\")->count();'"

# Should show: 77909
```

---

## Summary

**Problem**: 512MB memory not enough for route caching
**Solution**: Use 2GB memory for artisan commands + skip route cache
**Time**: 2 minutes to update script
**Result**: Deployment succeeds ✅

---

**Next**: Update deploy script in Forge → Deploy Now → Success! 🎉
