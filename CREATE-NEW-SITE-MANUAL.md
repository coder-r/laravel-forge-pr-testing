# Create New Clean Site - Manual Steps (10 Minutes)

**Why**: The old site (pr-test-devpel) has failed deployments. Starting fresh is cleaner!

**Result**: Working site with all fixes applied from the start

---

## ✅ Step-by-Step Guide

### Step 1: Create New Site (2 minutes)

1. Go to: https://forge.laravel.com/servers/986747 (curved-sanctuary)
2. Click **"New Site"** button
3. Fill in the form:

```
Domain: pr-clean-test.on-forge.com
Project Type: PHP/Laravel
Web Directory: /public
Isolated: ✓ Yes (creates dedicated user)
Username: prclean
PHP Version: 8.3 ⭐ (NOT 8.4!)
```

4. Click **"Add Site"**
5. Wait 30 seconds

**Note the Site ID** (you'll need it)

---

### Step 2: Connect GitHub (1 minute)

1. On the new site page, click **"Git Repository"** tab
2. Fill in:

```
Source Control: GitHub
Repository: coder-r/devpelEPOS
Branch: main
☐ Install Composer Dependencies (UNCHECK - we'll do this in deploy script)
```

3. Click **"Install Repository"**
4. Wait 30 seconds

---

### Step 3: Set Environment Variables (2 minutes)

1. Click **"Environment"** tab
2. Replace EVERYTHING with this:

```env
APP_NAME=DevPelEPOS
APP_ENV=production
APP_KEY=base64:YOUR_KEY_HERE_GENERATE_NEW
APP_DEBUG=false
APP_URL=http://pr-clean-test.on-forge.com

LOG_CHANNEL=stack
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=forge
DB_USERNAME=forge
DB_PASSWORD=UVPfdFLCMpVW8XztQQDt

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DRIVER=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120
```

3. Click **"Save Environment"**

---

### Step 4: Update Deploy Script (3 minutes)

1. Click **"App"** tab
2. Scroll to **"Deploy Script"**
3. Replace with this (from deploy-script.txt):

```bash
echo "Starting deployment..."
cd $FORGE_SITE_PATH

git pull origin $FORGE_SITE_BRANCH
echo "✓ Git pull completed"

# Composer with 2GB memory
php -d memory_limit=2048M $FORGE_COMPOSER install --no-interaction --prefer-dist --optimize-autoloader --no-dev
echo "✓ Composer completed"

# NPM
npm ci
npm run build
echo "✓ Assets built"

# Fix permissions
chmod -R 775 storage bootstrap/cache
echo "✓ Permissions fixed"

# Clear caches
php -d memory_limit=2048M artisan cache:clear
php -d memory_limit=2048M artisan config:clear
php -d memory_limit=2048M artisan view:clear
echo "✓ Caches cleared"

# Cache config only (skip routes - memory issue)
php -d memory_limit=2048M artisan config:cache
echo "✓ Config cached"

# Migrations
php -d memory_limit=2048M artisan migrate --force
echo "✓ Migrations completed"

# Reload PHP
( flock -w 10 9 || exit 1
    echo "Restarting FPM..."; sudo -S service $FORGE_PHP_FPM reload ) 9>/tmp/fpmlock

echo "✅ Deployment completed!"
```

4. Click **"Update Deploy Script"**

---

### Step 5: Deploy Application (2 minutes)

1. Still in **"App"** tab
2. Click **"Deploy Now"** button
3. Watch deployment logs
4. Should complete successfully with all ✓ marks

**Expected output**:
```
Starting deployment...
✓ Git pull completed
✓ Composer completed
✓ Assets built
✓ Permissions fixed
✓ Caches cleared
✓ Config cached
✓ Migrations completed
✅ Deployment completed!
```

---

### Step 6: Import Database (3 minutes)

**Via SSH** (I'll do this part):

```bash
# Using existing keatchen dump
scp -i ~/.ssh/tall-stream-key \
  /home/dev/project-analysis/laravel-forge-pr-testing/backups/keatchen_devpel_*.sql \
  forge@159.65.213.130:/tmp/clean_import.sql

# Import
ssh -i ~/.ssh/tall-stream-key forge@159.65.213.130 \
  "mysql -u forge -p'UVPfdFLCMpVW8XztQQDt' forge < /tmp/clean_import.sql"

# Verify
ssh -i ~/.ssh/tall-stream-key forge@159.65.213.130 \
  "mysql -u forge -p'UVPfdFLCMpVW8XztQQDt' forge -e 'SELECT COUNT(*) FROM orders;'"
# Should show: 77909
```

---

### Step 7: Test Site (1 minute)

1. Get the site IP from Forge (should be same: 159.65.213.130)
2. Add to /etc/hosts:
```bash
echo "159.65.213.130 pr-clean-test.on-forge.com" | sudo tee -a /etc/hosts
```

3. Visit:
```
http://pr-clean-test.on-forge.com
```

Should show: Laravel application ✅

---

### Step 8: Optional - Install SSL

1. Click **"SSL"** tab
2. Click **"LetsEncrypt"**
3. Domain: `pr-clean-test.on-forge.com`
4. Click **"Obtain Certificate"**
5. Wait 2-3 minutes

Then domain will work without /etc/hosts!

---

## 🎯 What's Different This Time

### Lessons Applied ✅

1. **PHP 8.3** (not 8.4) - Compatible from start
2. **Correct database** (forge with keatchen data) - No wrong import
3. **2GB memory** - No memory errors
4. **Skip route cache** - Avoid memory issue
5. **Fix permissions** - In deploy script
6. **Correct password** - From the beginning
7. **Debug logging** - See what's happening

### Clean Start ✅

- No failed deployments in history
- No wrong database imports
- No SSL failures to clean up
- Fresh slate with all fixes

---

## 📊 Expected Timeline

```
Step 1: Create site           (2 min)
Step 2: Connect GitHub         (1 min)
Step 3: Environment vars       (2 min)
Step 4: Deploy script          (3 min)
Step 5: Deploy                 (2 min)
Step 6: Import database        (3 min)
Step 7: Test                   (1 min)
Step 8: SSL (optional)         (3 min)

Total: 10-15 minutes for fully working site!
```

---

## ✅ Checklist

Before starting:
- [ ] Delete old site (pr-test-devpel) or keep for reference
- [ ] Have deploy-script.txt ready to copy
- [ ] Have keatchen database dump ready (206 MB)
- [ ] Know the database password: UVPfdFLCMpVW8XztQQDt

During setup:
- [ ] Step 1: Create site (PHP 8.3!)
- [ ] Step 2: Connect GitHub
- [ ] Step 3: Set environment (correct DB password!)
- [ ] Step 4: Update deploy script (2GB memory!)
- [ ] Step 5: Deploy
- [ ] Step 6: Import database
- [ ] Step 7: Test site
- [ ] Step 8: SSL (optional)

After setup:
- [ ] Site loads in browser
- [ ] Laravel app showing (not Forge page)
- [ ] Database connected (77,909 orders)
- [ ] Ready for testing

---

## 🚀 Ready to Start?

**I can help with**:
- Step 6: Database import (via SSH)
- Step 7: Testing and verification
- Troubleshooting if anything fails

**You need to do**:
- Steps 1-5: In Forge dashboard (I can't access API token)

---

**Want me to walk you through it step by step?** Or would you like to do Steps 1-5 and then I'll handle the database import?

Let me know when you're ready to start! 🎉
