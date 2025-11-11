# Deployment Fix - Database Credentials

## Problem
Deployment failed with:
```
SQLSTATE[HY000] [1045] Access denied for user 'forge'@'localhost' (using password: YES)
```

## Cause
The Laravel `.env` file doesn't have the correct database password.

## Quick Fix (2 Minutes via Forge Dashboard)

### Step 1: Go to Forge
1. Open: https://forge.laravel.com/servers/986747/sites/2925742
2. Click the **"Environment"** tab

### Step 2: Update Database Credentials
Find these lines and update them:
```env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=forge
DB_USERNAME=forge
DB_PASSWORD=UVPfdFLCMpVW8XztQQDt
```

**Change**:
- `DB_DATABASE` → **forge**
- `DB_USERNAME` → **forge**
- `DB_PASSWORD` → **UVPfdFLCMpVW8XztQQDt**

### Step 3: Save & Deploy
1. Click **"Save Environment"** button
2. Go to **"App"** tab
3. Click **"Deploy Now"** button
4. Wait 2-3 minutes for deployment

### Step 4: Verify
```bash
curl -I http://159.65.213.130 -H "Host: pr-test-devpel.on-forge.com"
```

Should show: `HTTP/1.1 200 OK` with Laravel response

---

## Alternative: Via Script (If API Token Available)

```bash
cd /home/dev/project-analysis/laravel-forge-pr-testing

# Set your Forge API token
export FORGE_API_TOKEN="your-token-here"

# Run fix script
./scripts/fix-database-credentials.sh
```

---

## What Happened

### Timeline
1. ✅ Site created successfully via API
2. ✅ Database cloned from production (137 orders)
3. ✅ GitHub repository connected
4. ❌ Deployment failed: Wrong DB password in `.env`
5. ⏳ **Fix needed**: Update `.env` with correct password

### Why It Failed
- Default `.env` created by Forge has a generated password
- We're using the existing `forge` database with password `UVPfdFLCMpVW8XztQQDt`
- Laravel tried to connect during `php artisan package:discover`
- Connection failed → Deployment stopped

---

## Current Status

### ✅ Working
- Site structure created
- Web server (Nginx) running
- Database has 137 orders from production
- Saturday peak data transformed (16 orders on Nov 16)
- SSH access working

### ⏳ Needs Fix
- Update `.env` file with correct DB password
- Re-deploy to complete Laravel setup

---

## After Fix

Once `.env` is updated and redeployed:

### ✅ You'll Have
- Working Laravel application
- Access to 137 production orders
- Saturday peak data (16 orders, Nov 16, 2025)
- Driver screen with realistic data
- Test environment ready for PR testing

### 🧪 Test It
```bash
# View Laravel welcome page
curl http://159.65.213.130 -H "Host: pr-test-devpel.on-forge.com"

# Check database connection
ssh -i ~/.ssh/tall-stream-key forge@159.65.213.130 \
  "cd /home/forge/pr-test-devpel.on-forge.com && php artisan tinker --execute='DB::connection()->getPdo();'"

# View orders
ssh -i ~/.ssh/tall-stream-key forge@159.65.213.130 \
  "mysql -u forge -p'UVPfdFLCMpVW8XztQQDt' forge -e 'SELECT COUNT(*) FROM orders;'"
```

---

## Summary

**Problem**: Database credentials mismatch
**Solution**: Update `.env` via Forge dashboard
**Time**: 2 minutes
**Then**: Re-deploy and you're done!

---

**Next**: Go to Forge → Environment tab → Update DB credentials → Deploy
