# Forge Setup Checklist - PR Testing Environment

**Implementation Timeline**: Day 1
**Skill Level**: Intermediate Laravel/DevOps
**Prerequisites**: Active Laravel Forge account, GitHub integration configured

---

## 🎯 **DNS Setup is Optional - Use on-forge.com Domains for Immediate Testing!**

**Start immediately with Forge's built-in `*.on-forge.com` domains - no DNS configuration needed!**

Custom DNS is only required if you need branded URLs for stakeholder demos.

---

## ⏱️ Quick Reference

| Phase | Duration | Can Skip If... |
|-------|----------|----------------|
| Phase 1: Server Prep | 45-90 min | Server already configured |
| Phase 2: Test Site with on-forge.com | 30-60 min | Never - REQUIRED |
| Phase 3: API Testing | 30-45 min | Never - REQUIRED |
| Optional: Custom DNS | 60-90 min | Skip unless you need branded URLs |

**Total Time**: 1-2 hours (using on-forge.com), 3-5 hours (with custom DNS)

---

## Phase 1: Forge Server Preparation (45-90 minutes)

### 1.1 Verify Server Resources

**⏰ Time**: 10 minutes
**⚠️ Critical**: Prevents resource exhaustion

- [ ] **Log into Laravel Forge** → Navigate to your server
- [ ] **Check current resources**:
  ```
  Current Server: _________________
  CPU Cores: _____ (Recommended: 4+)
  RAM: _____ GB (Recommended: 8GB+)
  Storage: _____ GB (Recommended: 100GB+)
  Current Sites: _____ (Note: Will increase)
  ```

- [ ] **Calculate capacity**:
  ```
  Expected PR sites: 10-20 concurrent
  Storage per site: ~500MB-1GB
  RAM per site: ~256-512MB
  Recommended buffer: 50%

  Minimum Requirements:
  ☐ 4 CPU cores
  ☐ 8GB RAM
  ☐ 100GB storage (or 50GB + regular cleanup)
  ```

**⚠️ If Resources Insufficient**:
- [ ] Upgrade server plan OR
- [ ] Create dedicated PR testing server

### 1.2 Verify Software Versions

**⏰ Time**: 5 minutes
**🎯 Goal**: Ensure compatibility

- [ ] **SSH into server**:
  ```bash
  ssh forge@your-server-ip
  ```

- [ ] **Check versions**:
  ```bash
  # PHP version (should be 8.1+)
  php -v
  # Output: PHP 8.1.x or 8.2.x

  # Nginx version
  nginx -v

  # MySQL version (should be 8.0+)
  mysql --version

  # Node.js version (should be 18+ or 20+)
  node --version

  # Redis (should be installed)
  redis-cli --version
  ```

- [ ] **Record versions**:
  ```
  PHP: _________________
  Nginx: _________________
  MySQL: _________________
  Node.js: _________________
  Redis: _________________
  ```

**❌ If Versions Wrong**:
- Update via Forge UI: Server → PHP → Install New Version
- Requires server reboot (schedule during low traffic)

### 1.3 Create Database Snapshots Directory

**⏰ Time**: 10 minutes
**🎯 Goal**: Store master database templates

- [ ] **SSH into server**:
  ```bash
  ssh forge@your-server-ip
  ```

- [ ] **Create snapshot directory**:
  ```bash
  # Create directory for database snapshots
  sudo mkdir -p /home/forge/db-snapshots

  # Set proper permissions
  sudo chown forge:forge /home/forge/db-snapshots
  sudo chmod 755 /home/forge/db-snapshots

  # Verify
  ls -la /home/forge/ | grep db-snapshots
  ```

- [ ] **Test write permissions**:
  ```bash
  # Create test file
  touch /home/forge/db-snapshots/test.txt

  # Verify
  ls -la /home/forge/db-snapshots/

  # Remove test file
  rm /home/forge/db-snapshots/test.txt
  ```

**✅ Success**: No permission errors when creating files

### 1.4 Set Up Redis Database Allocation

**⏰ Time**: 15 minutes
**🎯 Goal**: Isolate Redis databases per PR

- [ ] **Check Redis configuration**:
  ```bash
  # Check Redis is running
  sudo systemctl status redis

  # Check available databases
  redis-cli CONFIG GET databases
  # Should show: "databases" "16" (or higher)
  ```

- [ ] **Plan Redis database allocation**:
  ```
  Database 0: Production site
  Database 1: Staging site (if exists)
  Database 2-15: Available for PR sites (14 databases)

  Strategy: Assign database (PR_NUMBER % 14) + 2

  Example:
  PR #123 → DB 2 + (123 % 14) = DB 3
  PR #456 → DB 2 + (456 % 14) = DB 12
  ```

- [ ] **Test Redis connection**:
  ```bash
  # Connect to database 2 (first PR database)
  redis-cli -n 2

  # Set test key
  SET test-key "PR testing"

  # Get test key
  GET test-key
  # Output: "PR testing"

  # Clean up
  DEL test-key

  # Exit
  exit
  ```

- [ ] **Document Redis allocation**:
  ```
  Redis Databases Available: 16
  Reserved for Production: 0-1
  Available for PRs: 2-15 (14 databases)
  Allocation Formula: (PR_NUMBER % 14) + 2
  ```

**❌ If Redis Not Installed**:
```bash
# Install via Forge UI
Server → Redis → Install Redis
# Wait 2-3 minutes for installation
```

### 1.5 Configure Storage Limits

**⏰ Time**: 10 minutes
**🎯 Goal**: Prevent storage exhaustion

- [ ] **Set up storage monitoring**:
  ```bash
  # Check current storage usage
  df -h

  # Record current usage
  # Output shows: Used / Available / Use%
  ```

- [ ] **Document storage limits**:
  ```
  Total Storage: _____ GB
  Current Usage: _____ GB
  Available: _____ GB

  Limit per PR site: 1GB (soft limit)
  Maximum concurrent PRs: _____ (based on available space)
  Cleanup threshold: 80% full
  ```

**🔔 Recommendation**: Set up storage alerts in Forge
- Server → Monitoring → Add Alert
- Condition: Disk usage > 80%

### 1.6 Prepare Forge Daemon

**⏰ Time**: 5 minutes
**🎯 Goal**: Ensure queue workers can handle PR deployments

- [ ] **Navigate to Server → Daemons**
- [ ] **Verify Laravel queue worker exists** (should already be configured)
- [ ] **Record daemon configuration**:
  ```
  Command: php artisan queue:work
  User: forge
  Directory: /home/forge/your-site
  Processes: _____ (Recommended: 3-5)
  ```

**✅ Phase 1 Complete When**:
- ✅ Server resources verified/upgraded
- ✅ Software versions compatible
- ✅ Database snapshots directory created
- ✅ Redis allocation planned and tested
- ✅ Storage limits documented
- ✅ Queue daemon verified

---

## Phase 2: First Test Site with on-forge.com (30-60 minutes)

**🎯 Using Forge's Built-In Domains - No DNS Required!**

### 2.1 Manual Site Creation with on-forge.com

**⏰ Time**: 20 minutes
**🎯 Goal**: Create test PR site using Forge's instant domains

- [ ] **Navigate to Forge** → Your Server → Sites
- [ ] **Click "New Site"**
- [ ] **Configure site**:
  ```
  Root Domain: pr-test-001-[your-server-slug].on-forge.com

  Note: Forge auto-generates the on-forge.com domain based on your server
  Example: pr-test-001-amazing-server-12345.on-forge.com

  Project Type: Laravel
  Web Directory: /public
  PHP Version: 8.1 (or 8.2)
  Create Database: Yes
  Database Name: pr_test_001
  Site Isolation: Yes (CRITICAL - Enable!)
  ```

- [ ] **Click "Add Site"**
- [ ] **Wait for site creation** (2-3 minutes)
- [ ] **Record site details**:
  ```
  Site ID: _________________
  Domain: pr-test-001-[server-slug].on-forge.com
  Full URL: https://pr-test-001-[server-slug].on-forge.com
  Database: pr_test_001
  Database User: pr_test_001
  Database Password: _________________ (copy from Forge)
  Created: _________________
  ```

**✅ Success**: Site shows "Active" status in Forge

**💡 Benefits**:
- ✅ Works immediately - no DNS propagation wait
- ✅ SSL certificate auto-installed
- ✅ No DNS provider needed
- ✅ Perfect for testing and development

### 2.2 Enable Site Isolation

**⏰ Time**: 5 minutes
**⚠️ CRITICAL**: Prevents PR sites from affecting each other

- [ ] **Navigate to Site** → Settings
- [ ] **Verify "Site Isolation" is enabled**
  ```
  ☐ Site Isolation: ON

  What this does:
  - Separate PHP-FPM pool
  - Dedicated system user
  - Isolated file permissions
  - Cannot access other sites' files
  ```

- [ ] **If not enabled**:
  - Click "Enable Site Isolation"
  - Wait 2-3 minutes for configuration
  - Nginx will restart automatically

**⚠️ Warning**: Site isolation cannot be changed after site creation. If disabled, delete and recreate site.

### 2.3 Configure Environment Variables

**⏰ Time**: 10 minutes
**🎯 Goal**: Set up .env for test site

- [ ] **Navigate to Site** → Environment
- [ ] **Edit environment file**:
  ```env
  APP_NAME="PR Test Site"
  APP_ENV=staging
  APP_KEY=
  APP_DEBUG=true
  APP_URL=https://pr-test-001-[server-slug].on-forge.com

  LOG_CHANNEL=stack
  LOG_LEVEL=debug

  DB_CONNECTION=mysql
  DB_HOST=127.0.0.1
  DB_PORT=3306
  DB_DATABASE=pr_test_001
  DB_USERNAME=pr_test_001
  DB_PASSWORD=[PASTE FROM FORGE]

  BROADCAST_DRIVER=log
  CACHE_DRIVER=redis
  FILESYSTEM_DISK=local
  QUEUE_CONNECTION=redis
  SESSION_DRIVER=redis
  SESSION_LIFETIME=120

  REDIS_HOST=127.0.0.1
  REDIS_PASSWORD=null
  REDIS_PORT=6379
  REDIS_DB=2

  # PR-specific settings
  PR_NUMBER=test-001
  PR_BRANCH=test-branch
  PR_AUTHOR=test-user
  PR_TITLE="Test PR Site"
  ```

- [ ] **Click "Save"**
- [ ] **Generate APP_KEY**:
  ```bash
  # SSH into server
  ssh forge@your-server-ip

  # Navigate to site
  cd /home/forge/pr-test-001-[server-slug].on-forge.com

  # Generate key
  php artisan key:generate

  # Verify .env updated
  grep APP_KEY .env
  ```

### 2.4 Verify SSL Certificate (Auto-Installed!)

**⏰ Time**: 2 minutes
**🎯 Goal**: Confirm HTTPS is working

**✅ Good news**: on-forge.com domains come with SSL certificates pre-installed!

- [ ] **Verify SSL is active**:
  ```bash
  # Check certificate
  curl -I https://pr-test-001-[server-slug].on-forge.com
  # Should return: HTTP/2 200 (no SSL errors)

  # Visit in browser
  # URL: https://pr-test-001-[server-slug].on-forge.com
  # Should show padlock icon immediately
  ```

**✅ Success**: HTTPS works immediately - no waiting for DNS or certificate issuance!

### 2.5 Deploy Test Code

**⏰ Time**: 15 minutes
**🎯 Goal**: Deploy working Laravel application

- [ ] **Navigate to Site** → Git Repository
- [ ] **Connect GitHub repository**:
  ```
  Repository: your-github-username/your-laravel-repo
  Branch: main (or master)
  Deploy Key: Auto-generated by Forge
  ```

- [ ] **Click "Install Repository"**
- [ ] **Wait for initial deployment** (3-5 minutes)

- [ ] **Configure deployment script**:
  ```bash
  cd /home/forge/pr-test-001-[server-slug].on-forge.com

  git pull origin $FORGE_SITE_BRANCH

  $FORGE_COMPOSER install --no-interaction --prefer-dist --optimize-autoloader --no-dev

  ( flock -w 10 9 || exit 1
      echo 'Restarting FPM...'; sudo -S service $FORGE_PHP_FPM reload ) 9>/tmp/fpmlock

  if [ -f artisan ]; then
      $FORGE_PHP artisan migrate --force
      $FORGE_PHP artisan config:cache
      $FORGE_PHP artisan route:cache
      $FORGE_PHP artisan view:cache
      $FORGE_PHP artisan queue:restart
  fi
  ```

- [ ] **Click "Save"**
- [ ] **Click "Deploy Now"**
- [ ] **Monitor deployment** (Site → Deployments)

### 2.6 Initialize Database

**⏰ Time**: 10 minutes
**🎯 Goal**: Seed database with test data

- [ ] **SSH into server**:
  ```bash
  ssh forge@your-server-ip
  cd /home/forge/pr-test-001-[server-slug].on-forge.com
  ```

- [ ] **Run migrations**:
  ```bash
  php artisan migrate:fresh --seed

  # Or if you have specific seeder
  php artisan migrate:fresh
  php artisan db:seed --class=TestDataSeeder
  ```

- [ ] **Verify database**:
  ```bash
  # Connect to database
  mysql -u pr_test_001 -p pr_test_001
  # Enter password from .env

  # Check tables
  SHOW TABLES;

  # Check user count (example)
  SELECT COUNT(*) FROM users;

  # Exit
  exit
  ```

- [ ] **Create database snapshot**:
  ```bash
  # Dump database to snapshot
  mysqldump -u pr_test_001 -p pr_test_001 > /home/forge/db-snapshots/master-snapshot.sql

  # Verify snapshot created
  ls -lh /home/forge/db-snapshots/

  # Test snapshot can be restored
  mysql -u pr_test_001 -p pr_test_001 < /home/forge/db-snapshots/master-snapshot.sql
  ```

**✅ Success**: Database snapshot created and tested

### 2.7 Verify Site Functionality

**⏰ Time**: 10 minutes
**🎯 Goal**: Ensure all site features work

- [ ] **Test HTTP access**:
  ```bash
  curl -I https://pr-test-001-[server-slug].on-forge.com
  # Should return: HTTP/2 200
  ```

- [ ] **Test in browser**:
  ```
  URL: https://pr-test-001-[server-slug].on-forge.com

  ☐ Site loads without errors
  ☐ SSL certificate valid (padlock icon)
  ☐ No "Not Secure" warnings
  ☐ Homepage displays correctly
  ☐ Login page works
  ☐ Database queries execute
  ☐ Assets load (CSS, JS, images)
  ```

- [ ] **Check Laravel logs**:
  ```bash
  # SSH into server
  cd /home/forge/pr-test-001-[server-slug].on-forge.com

  # Check for errors
  tail -50 storage/logs/laravel.log

  # Should not show critical errors
  ```

- [ ] **Test Redis connection**:
  ```bash
  # SSH into server
  cd /home/forge/pr-test-001-[server-slug].on-forge.com

  # Test Redis via artisan
  php artisan tinker

  # In tinker:
  Redis::set('test-key', 'test-value');
  Redis::get('test-key');
  # Should return: "test-value"

  exit
  ```

- [ ] **Test queue worker**:
  ```bash
  # Dispatch test job
  php artisan tinker

  # In tinker:
  dispatch(function() {
      Log::info('Test job executed');
  });

  exit

  # Check logs
  tail -10 storage/logs/laravel.log
  # Should show: "Test job executed"
  ```

- [ ] **Run test suite** (if available):
  ```bash
  php artisan test
  # Or
  ./vendor/bin/phpunit
  ```

**📋 Test Checklist**:
```
✅ Site accessible via HTTPS
✅ SSL certificate valid
✅ Homepage loads correctly
✅ Database queries work
✅ Redis caching works
✅ Queue jobs execute
✅ Logs show no errors
✅ Tests pass (if applicable)
```

**✅ Phase 2 Complete When**:
- ✅ Test site created with on-forge.com domain
- ✅ Site accessible immediately (no DNS wait!)
- ✅ Site isolation enabled
- ✅ SSL certificate working (pre-installed!)
- ✅ Database migrated and seeded
- ✅ Database snapshot created
- ✅ All functionality verified
- ✅ No errors in logs

---

## Phase 3: API Testing (30-45 minutes)

### 3.1 Get Forge API Token

**⏰ Time**: 5 minutes
**⚠️ Critical**: Required for automation

- [ ] **Log into Laravel Forge**
- [ ] **Navigate to**: Account → API → API Tokens
- [ ] **Click "Create New Token"**
- [ ] **Name token**: "PR Testing Automation"
- [ ] **Copy token** (shown only once!)
- [ ] **Store securely**:
  ```
  Token: _________________________________
  Created: _________________
  Expires: Never (revoke manually if compromised)
  ```

- [ ] **Test token validity**:
  ```bash
  curl -s https://forge.laravel.com/api/v1/servers \
    -H "Authorization: Bearer YOUR_TOKEN_HERE" \
    -H "Accept: application/json"

  # Should return JSON list of servers
  ```

**⚠️ Security**:
- Never commit token to git
- Store in environment variables
- Revoke if exposed

### 3.2 Test API Calls Locally

**⏰ Time**: 15 minutes
**🎯 Goal**: Verify API access and operations

#### Test 1: List Servers

- [ ] **Run command**:
  ```bash
  export FORGE_TOKEN="your_token_here"

  curl -s https://forge.laravel.com/api/v1/servers \
    -H "Authorization: Bearer $FORGE_TOKEN" \
    -H "Accept: application/json" \
    | jq '.'
  ```

- [ ] **Expected output**:
  ```json
  {
    "servers": [
      {
        "id": 12345,
        "name": "your-server",
        "ip_address": "xxx.xxx.xxx.xxx",
        ...
      }
    ]
  }
  ```

- [ ] **Record server ID**: `_________________`

#### Test 2: List Sites

- [ ] **Run command**:
  ```bash
  export SERVER_ID="12345"  # From previous step

  curl -s https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites \
    -H "Authorization: Bearer $FORGE_TOKEN" \
    -H "Accept: application/json" \
    | jq '.'
  ```

- [ ] **Verify**: Should show `pr-test-001-[server-slug].on-forge.com` in list

#### Test 3: Get Site Details

- [ ] **Find site ID from previous response**
- [ ] **Run command**:
  ```bash
  export SITE_ID="67890"  # Your test site ID

  curl -s https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$SITE_ID \
    -H "Authorization: Bearer $FORGE_TOKEN" \
    -H "Accept: application/json" \
    | jq '.'
  ```

- [ ] **Record site ID**: `_________________`

### 3.3 Create Site via API with on-forge.com

**⏰ Time**: 8 minutes
**🎯 Goal**: Automate site creation (SSL included!)

- [ ] **Prepare API request**:
  ```bash
  curl -X POST https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites \
    -H "Authorization: Bearer $FORGE_TOKEN" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d '{
      "domain": "pr-test-002-[server-slug].on-forge.com",
      "project_type": "php",
      "directory": "/public",
      "php_version": "php81",
      "isolated": true,
      "username": "pr_test_002",
      "database": "pr_test_002"
    }' | jq '.'
  ```

**💡 Note**: Replace `[server-slug]` with your actual server slug from the first test site

- [ ] **Expected response**:
  ```json
  {
    "site": {
      "id": 99999,
      "name": "pr-test-002-[server-slug].on-forge.com",
      "status": "installing",
      ...
    }
  }
  ```

- [ ] **Wait for site creation** (2-3 minutes)
- [ ] **Check site status**:
  ```bash
  export NEW_SITE_ID="99999"  # From response above

  curl -s https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$NEW_SITE_ID \
    -H "Authorization: Bearer $FORGE_TOKEN" \
    -H "Accept: application/json" \
    | jq '.site.status'

  # Should return: "installed"
  ```

- [ ] **Verify in Forge UI**: Site appears in dashboard
- [ ] **Test site access**: Visit `https://pr-test-002-[server-slug].on-forge.com`
  - Should show Nginx default page (no code deployed yet)
  - **SSL works immediately** - no certificate installation needed!

**✅ Benefits**: on-forge.com domains come with SSL pre-configured!

### 3.4 Delete Site via API

**⏰ Time**: 5 minutes
**🎯 Goal**: Test cleanup automation

- [ ] **Delete site and database**:
  ```bash
  # Delete site
  curl -X DELETE https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$NEW_SITE_ID \
    -H "Authorization: Bearer $FORGE_TOKEN" \
    -H "Accept: application/json"

  # Response: 200 OK (no body)
  ```

- [ ] **Wait 30 seconds**, then verify deletion:
  ```bash
  # Try to get deleted site
  curl -s https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$NEW_SITE_ID \
    -H "Authorization: Bearer $FORGE_TOKEN" \
    -H "Accept: application/json"

  # Should return 404 error
  ```

- [ ] **Verify in Forge UI**: Site no longer appears
- [ ] **Verify URL**: `pr-test-002-[server-slug].on-forge.com` should show Nginx 404

### 3.5 Document API Rate Limits

**⏰ Time**: 5 minutes
**📋 Important**: Prevent hitting rate limits

- [ ] **Record rate limit information**:
  ```
  Forge API Rate Limits:
  - 30 requests per minute per IP
  - 1000 requests per hour per account

  Recommendations:
  - Add 2-second delay between API calls
  - Batch operations when possible
  - Cache server/site IDs locally
  - Monitor X-RateLimit-Remaining header
  ```

- [ ] **Test rate limit headers**:
  ```bash
  curl -I https://forge.laravel.com/api/v1/servers/$SERVER_ID \
    -H "Authorization: Bearer $FORGE_TOKEN" \
    -H "Accept: application/json"

  # Look for headers:
  # X-RateLimit-Limit: 30
  # X-RateLimit-Remaining: 29
  ```

**✅ Phase 3 Complete When**:
- ✅ API token obtained and tested
- ✅ Can list servers and sites via API
- ✅ Successfully created site via API (with on-forge.com domain)
- ✅ SSL works immediately (no manual installation!)
- ✅ Successfully deleted site via API
- ✅ Rate limits documented
- ✅ All API calls logged for reference

---

## Optional Phase 4: Custom DNS Setup (60-90 minutes)

**⚠️ ONLY DO THIS IF**: You need branded URLs like `pr-123.staging.kitthub.com` for stakeholder demos

**Skip this if**: on-forge.com domains work for your team (recommended for most cases)

### 4.1 Add Wildcard DNS Record

**⏰ Time**: 15 minutes

- [ ] **Log into DNS provider** (Cloudflare, Route53, Namecheap, etc.)
- [ ] **Navigate to DNS management** for `kitthub.com`
- [ ] **Add wildcard A record**:
  ```
  Type: A
  Name: *.staging
  Value: [YOUR_FORGE_SERVER_IP]
  TTL: 300 (5 minutes) - for testing, increase to 3600 later
  Proxy: Disabled (if using Cloudflare)
  ```

### 4.2 Test DNS Propagation

**⏰ Time**: 15-45 minutes (includes waiting)

- [ ] **Test wildcard resolution**:
  ```bash
  dig pr-123.staging.kitthub.com
  # Should return your server IP
  ```

### 4.3 Create Test Site with Custom Domain

**⏰ Time**: 20 minutes

- [ ] Create site: `pr-custom-001.staging.kitthub.com`
- [ ] Install SSL certificate (LetsEncrypt)
- [ ] Wait for SSL issuance (2-5 minutes)
- [ ] Test HTTPS access

### 4.4 Update GitHub Actions for Custom Domains

**⏰ Time**: 10 minutes

- [ ] Update workflow to use custom domain pattern
- [ ] Configure DNS suffix in environment variables

**✅ Phase 4 Complete When**:
- ✅ Wildcard DNS working
- ✅ Custom domain sites accessible
- ✅ SSL certificates issuing correctly

---

## 🎯 Final Verification Checklist

### Overall System Check

- [ ] **Server Preparation**:
  - [ ] Resources adequate (CPU, RAM, storage)
  - [ ] Software versions compatible
  - [ ] Database snapshots directory created
  - [ ] Redis databases allocated

- [ ] **on-forge.com Site Creation**:
  - [ ] Test site created with on-forge.com domain
  - [ ] Site accessible immediately (no DNS wait!)
  - [ ] Site isolation enabled
  - [ ] SSL certificate working (pre-installed!)
  - [ ] Database migrated and seeded
  - [ ] All features work correctly

- [ ] **API Access**:
  - [ ] API token obtained and secured
  - [ ] Can create sites via API with on-forge.com domains
  - [ ] Can delete sites via API
  - [ ] Rate limits understood

- [ ] **Optional Custom DNS** (skip if using on-forge.com):
  - [ ] Wildcard DNS configured
  - [ ] Custom domain sites working
  - [ ] SSL certificates issuing

### Ready for Automation?

**✅ You're ready to proceed if**:
- All checkboxes above are complete
- Test site with on-forge.com domain fully functional
- API calls work reliably
- No errors in Forge logs
- (Optional) Custom DNS resolving if configured

**⏭️ Next Steps**:
1. Review: `2-github-actions-setup.md`
2. Build: API wrapper class
3. Create: GitHub Actions workflow
4. Test: First automated PR site

---

## 🆘 Troubleshooting Guide

### on-forge.com Issues

| Problem | Check | Solution |
|---------|-------|----------|
| Site not accessible | Site status in Forge | Verify site shows "Active" status |
| SSL not working | Check URL format | Ensure using https:// not http:// |
| Wrong domain pattern | Server slug | Use correct server slug from first site |
| 404 errors | Deployment status | Check if code deployed successfully |

### Custom DNS Issues (Optional)

| Problem | Check | Solution |
|---------|-------|----------|
| DNS not resolving | `dig pr-test.staging.kitthub.com` | Wait 15-60 minutes for propagation |
| Wrong IP returned | DNS record value | Update A record to correct server IP |
| Intermittent results | Global propagation | Check dnschecker.org, wait longer |
| SSL fails for wildcard | Cloudflare proxy | Disable orange cloud, use DNS-only |

### Forge Site Issues

| Problem | Check | Solution |
|---------|-------|----------|
| Site creation hangs | Server resources | Check CPU/RAM/storage availability |
| Database creation fails | MySQL limits | Increase max_connections in MySQL |
| SSL certificate fails | DNS propagation | Wait for DNS, try LetsEncrypt again |
| Site isolation not working | Forge version | Update Forge agent: `sudo forge-update` |
| Deployment fails | Git credentials | Regenerate deploy key in Forge |

### API Issues

| Problem | Check | Solution |
|---------|-------|----------|
| 401 Unauthorized | Token validity | Regenerate API token |
| 429 Rate Limited | Request frequency | Add delays between calls (2+ seconds) |
| 422 Validation Error | Request payload | Check JSON syntax and required fields |
| Site creation timeout | Server load | Wait 5 minutes, check status endpoint |

### Common Error Messages

**"Database already exists"**
- Solution: Use unique database name per PR
- Implement: `pr_${PR_NUMBER}_${TIMESTAMP}`

**"Domain already exists"**
- Solution: Clean up old PR sites first or use different server slug
- Check: `curl -s .../sites | jq '.sites[] | .name'`

**"Insufficient server resources"**
- Solution: Delete old PR sites or upgrade server
- Monitor: `df -h` and `free -m`

**"SSL certificate failed"** (custom domains only)
- Solution: Check DNS first with `dig +short [domain]`
- Wait: 15 minutes after DNS changes
- Note: on-forge.com domains don't have this issue!

---

## 📊 Performance Benchmarks

### Expected Timings with on-forge.com

| Operation | Time | Notes |
|-----------|------|-------|
| Site creation (manual) | 2-3 min | Via Forge UI |
| Site creation (API) | 2-3 min | Same as manual |
| SSL availability | 0 min | Pre-installed! |
| Database migration | 1-5 min | Depends on complexity |
| Site deletion | 30 sec | Via API |
| Full PR site setup | 5-8 min | End-to-end automation (faster with on-forge.com!) |

### Expected Timings with Custom DNS

| Operation | Time | Notes |
|-----------|------|-------|
| DNS propagation | 5-60 min | Varies by provider |
| Site creation | 2-3 min | Via API |
| SSL issuance | 2-5 min | LetsEncrypt |
| Full PR site setup | 10-15 min | Includes DNS wait time |

### Resource Usage Per Site

```
Disk Space: 300-500 MB (with dependencies)
RAM: 128-256 MB (idle), 512 MB (active)
Database: 50-200 MB (depends on seed data)
Redis: 10-50 MB (session + cache)
```

---

## 📝 Documentation Template

**Save this information for your project**:

```markdown
# PR Testing Environment - Configuration

## Domain Strategy
- Using on-forge.com: Yes ✅ (recommended)
- Domain Pattern: pr-[number]-[server-slug].on-forge.com
- Server Slug: _________________
- Benefits: Instant SSL, no DNS setup, works immediately

## Custom DNS (Optional)
- Using Custom Domains: Yes/No
- Provider: _________________ (if applicable)
- Wildcard Record: *.staging.kitthub.com (if applicable)
- Server IP: _________________ (if applicable)

## Forge Server
- Server ID: _________________
- Server Name: _________________
- Server Slug: _________________ (for on-forge.com domains)
- IP Address: _________________
- PHP Version: _________________
- MySQL Version: _________________
- Redis Databases: 2-15 (PRs)

## API Access
- Token Created: _________________
- Token Name: PR Testing Automation
- Stored In: GitHub Secrets (FORGE_TOKEN)
- Rate Limit: 30/min, 1000/hour

## Test Sites Created (on-forge.com)
1. pr-test-001-[server-slug].on-forge.com
   - Site ID: _________________
   - Database: pr_test_001
   - Created: _________________
   - SSL: Pre-installed ✅
   - Status: Active ✅

2. pr-test-002-[server-slug].on-forge.com
   - Site ID: _________________
   - Database: pr_test_002
   - Created: _________________
   - SSL: Pre-installed ✅
   - Status: Deleted (API test) ✅

## Next Steps
- [ ] Create GitHub Actions workflow
- [ ] Build Forge API wrapper class
- [ ] Implement PR site creation automation
- [ ] Set up automatic cleanup job
- [ ] Configure environment variables
- [ ] Test end-to-end flow
```

---

## ✅ Success Criteria

**You've successfully completed Forge setup when**:

1. ✅ **on-forge.com works**: Test site accessible at pr-test-001-[server-slug].on-forge.com
2. ✅ **Server ready**: Resources adequate, software up-to-date, directories created
3. ✅ **Manual site works**: Test site fully functional with SSL (pre-installed!), database, Redis
4. ✅ **API tested**: Can create and delete sites via API calls with on-forge.com domains
5. ✅ **Documentation complete**: All configuration values recorded (especially server slug)
6. ✅ **Troubleshooting tested**: Know how to fix common issues

**Time to completion**: 1-2 hours (using on-forge.com), 3-5 hours (with custom DNS)

---

## 🎓 What You've Accomplished

After completing this checklist, you have:

- ✅ Used Forge's on-forge.com domains for instant site deployment (no DNS setup needed!)
- ✅ Prepared Forge server for hosting multiple isolated sites
- ✅ Manually created and verified a test PR site with instant SSL
- ✅ Tested all critical site features (SSL pre-installed, database, Redis, deployment)
- ✅ Obtained and tested Forge API access
- ✅ Successfully created and deleted sites via API with on-forge.com domains
- ✅ Documented all configuration values (especially server slug)
- ✅ Learned troubleshooting techniques
- ✅ (Optional) Configured custom DNS if needed for branded URLs

**You're now ready to build the automation layer!**

**🚀 Key Benefit**: By using on-forge.com domains, you've saved 30-60 minutes of DNS setup and eliminated DNS propagation wait times!

---

**⏭️ Next Document**: [2-github-actions-setup.md](./2-github-actions-setup.md)
**📖 Back to**: [0-README-START-HERE.md](../0-README-START-HERE.md)
