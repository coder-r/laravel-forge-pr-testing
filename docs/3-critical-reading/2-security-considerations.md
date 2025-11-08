# Security Considerations - Laravel PR Testing Environment System

**Status**: 🔴 CRITICAL - READ BEFORE IMPLEMENTATION
**Last Updated**: 2025-11-07
**Audience**: Developers, DevOps, Security Team

---

## 🚨 Executive Summary

This document outlines critical security considerations for implementing an automated PR testing environment system using Laravel Forge. The system creates isolated test environments on-demand with production database snapshots for two Laravel applications (keatchen-customer-app and devpel-epos).

**Key Security Principles**:
- **Defense in Depth**: Multiple layers of security controls
- **Least Privilege**: Minimal permissions for all components
- **Isolation**: Complete separation between test environments
- **Secure by Default**: Security controls enabled from start
- **Audit Trail**: All actions logged and traceable

---

## 1. Site Isolation Security

### 1.1 Linux User Separation

**Requirement**: Each test environment MUST run under a separate Linux user to ensure complete filesystem isolation.

**Implementation**:
```bash
# Laravel Forge automatically creates isolated users per site
# Format: forge-pr-123, forge-pr-124, etc.

# Verify isolation
sudo ls -la /home/forge-pr-*/
# Each directory should be owned by different user

# File permissions should be:
# Directories: 755 (rwxr-xr-x)
# Files: 644 (rw-r--r--)
# Sensitive files: 600 (rw-------)
```

**Security Controls**:
- ✅ Each PR environment gets unique Linux user
- ✅ Home directories isolated: `/home/forge-pr-{PR_NUMBER}/`
- ✅ No shared filesystem access between environments
- ✅ Process isolation via user-level separation
- ✅ Forge manages user creation/deletion automatically

**Risks**:
- 🔴 **HIGH**: Shared `/tmp` directory - sanitize file uploads
- 🟡 **MEDIUM**: Shared `/var/log` - ensure log rotation
- 🟢 **LOW**: Memory-based attacks (mitigated by separate processes)

**Verification Checklist**:
```bash
# 1. Verify user isolation
ps aux | grep forge-pr-123
# Should only show processes for that PR

# 2. Check file ownership
stat /home/forge-pr-123/.env
# Owner should be forge-pr-123

# 3. Test cross-environment access (should fail)
sudo -u forge-pr-123 cat /home/forge-pr-124/.env
# Should return: Permission denied
```

---

## 2. Database Security

### 2.1 Database Isolation

**Context**: While databases don't contain PII, they do contain business logic, pricing data, and operational information that must be protected.

**Architecture**:
```
Production DB (Source)
    ↓ (scheduled snapshot)
Master Snapshot DB (weekend peaks)
    ↓ (on-demand clone)
PR-Specific DB (pr_123_keatchen)
```

**Security Controls**:
- ✅ Each PR gets completely isolated database
- ✅ Separate MySQL user per database
- ✅ No cross-database query privileges
- ✅ Databases named: `pr_{PR_NUMBER}_{APP_NAME}`
- ✅ Automatic cleanup on PR closure

**Database User Permissions**:
```sql
-- Each PR database user should have ONLY these privileges
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER
ON pr_123_keatchen.*
TO 'pr_123_keatchen'@'localhost'
IDENTIFIED BY 'STRONG_RANDOM_PASSWORD';

-- NEVER grant these privileges to test databases
-- GRANT SUPER, PROCESS, FILE, RELOAD, REPLICATION CLIENT
```

### 2.2 Snapshot Security

**Risks**:
- 🟡 **MEDIUM**: Master snapshot contains real production data
- 🟡 **MEDIUM**: Snapshots stored on same server as production
- 🟢 **LOW**: Snapshot timing reveals business patterns

**Mitigation**:
```bash
# 1. Encrypt snapshots at rest
# Add to Forge database backup configuration
--default-character-set=utf8mb4 \
--single-transaction \
--quick \
--lock-tables=false

# 2. Restrict snapshot access
chmod 600 /home/forge/database-snapshots/*.sql
chown forge:forge /home/forge/database-snapshots/*.sql

# 3. Rotate snapshots regularly
# Keep only last 7 days of snapshots
find /home/forge/database-snapshots/ -name "*.sql" -mtime +7 -delete
```

### 2.3 Connection Security

**Environment Configuration**:
```env
# .env for PR testing environment
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=pr_123_keatchen
DB_USERNAME=pr_123_keatchen
DB_PASSWORD=UNIQUE_RANDOM_PASSWORD_PER_PR

# CRITICAL: Never use production database credentials
# CRITICAL: Generate new password for each PR environment
```

**Password Generation**:
```bash
# Generate cryptographically secure password
openssl rand -base64 32

# Store in GitHub Secrets (one-time setup)
# Forge API will use this pattern to generate unique passwords
```

---

## 3. API Key Management

### 3.1 External Service APIs

**Critical**: All external services MUST use TEST/SANDBOX mode in PR environments.

**Services Requiring Test Mode**:
- Stripe (payment processing)
- Twilio (SMS/communications)
- SendGrid/Mailgun (email)
- Google Maps (geolocation)
- Any 3rd party integrations

**Environment Configuration**:
```env
# .env.testing (template for PR environments)

# Stripe - TEST MODE ONLY
STRIPE_KEY=pk_test_XXXXXXXXXX
STRIPE_SECRET=sk_test_XXXXXXXXXX
STRIPE_WEBHOOK_SECRET=whsec_test_XXXXXXXXXX

# Twilio - TEST MODE
TWILIO_SID=AC_TEST_XXXXXXXXXX
TWILIO_AUTH_TOKEN=test_XXXXXXXXXX
TWILIO_FROM_NUMBER=+15005550006

# Email - TEST MODE
MAIL_MAILER=log  # Log emails instead of sending
# Or use Mailtrap for testing
MAIL_HOST=smtp.mailtrap.io
MAIL_PORT=2525

# Google Maps - Development API Key (with restrictions)
GOOGLE_MAPS_API_KEY=AIza_DEV_XXXXXXXXXX

# CRITICAL: Never use production API keys in test environments
```

### 3.2 API Key Rotation

**Policy**: Test API keys should be rotated quarterly.

```bash
# Rotation checklist
# 1. Generate new test keys from service providers
# 2. Update GitHub Secrets
# 3. Update .env.testing template in repo
# 4. Destroy all active PR environments (force rebuild)
# 5. Document rotation in security log
```

### 3.3 API Key Storage

**GitHub Secrets** (recommended):
```yaml
# .github/workflows/pr-environment.yml
env:
  STRIPE_TEST_KEY: ${{ secrets.STRIPE_TEST_KEY }}
  STRIPE_TEST_SECRET: ${{ secrets.STRIPE_TEST_SECRET }}
  TWILIO_TEST_SID: ${{ secrets.TWILIO_TEST_SID }}
```

**Forge Environment Variables**:
```bash
# Store in Forge (encrypted at rest)
forge env:set pr-123-keatchen STRIPE_KEY pk_test_XXXXXXXXXX
forge env:set pr-123-keatchen STRIPE_SECRET sk_test_XXXXXXXXXX
```

**Never**:
- ❌ Commit API keys to repository (even test keys)
- ❌ Share API keys via Slack/email
- ❌ Use production keys in test environments
- ❌ Log API keys in application logs

---

## 4. Access Control for Test Environments

### 4.1 Authentication Methods

**Option 1: HTTP Basic Authentication** (Recommended)
```nginx
# Nginx configuration (managed by Forge)
location / {
    auth_basic "PR Testing Environment - Authorized Access Only";
    auth_basic_user_file /home/forge-pr-123/.htpasswd;

    try_files $uri $uri/ /index.php?$query_string;
}
```

**Generate htpasswd file**:
```bash
# Create password file
htpasswd -c /home/forge-pr-123/.htpasswd testuser

# Password should be stored in GitHub Secrets
# BASIC_AUTH_PASSWORD="strong_random_password"
```

**Option 2: IP Whitelist** (High Security)
```nginx
# Nginx configuration
location / {
    # Allow office IPs
    allow 203.0.113.0/24;  # Office network
    allow 198.51.100.50;    # VPN endpoint
    allow 192.0.2.100;      # Developer IP

    # Block all others
    deny all;

    try_files $uri $uri/ /index.php?$query_string;
}
```

**Option 3: Laravel Middleware** (Application Level)
```php
// app/Http/Middleware/TestEnvironmentAuth.php
namespace App\Http\Middleware;

class TestEnvironmentAuth
{
    public function handle($request, $next)
    {
        if (app()->environment('testing', 'pr-testing')) {
            $token = $request->header('X-Test-Token');

            if ($token !== config('app.test_access_token')) {
                abort(403, 'Unauthorized access to test environment');
            }
        }

        return $next($request);
    }
}
```

### 4.2 Recommended Approach

**Layered Security** (Defense in Depth):
```nginx
# Layer 1: IP whitelist for known office/VPN
allow 203.0.113.0/24;

# Layer 2: Basic Auth for developers working remotely
auth_basic "PR Testing Environment";
auth_basic_user_file /home/forge-pr-123/.htpasswd;

# Layer 3: Application-level middleware
# (checks token in Laravel)
```

### 4.3 Access Control Checklist

- [ ] HTTP Basic Auth enabled on all PR sites
- [ ] Strong password (min 20 chars, random)
- [ ] Password stored in GitHub Secrets
- [ ] IP whitelist configured for office network
- [ ] `robots.txt` configured to block search engines
- [ ] No links from production to test environments
- [ ] Test environments use non-obvious subdomains

**robots.txt Configuration**:
```
# /public/robots.txt for PR environments
User-agent: *
Disallow: /
```

---

## 5. SSL Certificate Security

### 5.1 Certificate Management

**Requirement**: All test environments MUST use HTTPS (no exceptions).

**Options**:
1. **Let's Encrypt** (Recommended)
   - Free SSL certificates
   - Auto-renewal via Forge
   - Wildcard certificates for `*.pr-testing.example.com`

2. **Cloudflare SSL** (Alternative)
   - Free SSL via Cloudflare
   - Additional DDoS protection
   - Better for high-traffic testing

**Implementation**:
```bash
# Let's Encrypt via Forge API
curl -X POST https://forge.laravel.com/api/v1/servers/{server_id}/sites/{site_id}/certificates/letsencrypt \
  -H "Authorization: Bearer $FORGE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domains": ["pr-123.pr-testing.example.com"]
  }'
```

### 5.2 Wildcard Certificates

**Setup Wildcard SSL** (One-time):
```bash
# DNS Challenge for Let's Encrypt wildcard
# Add TXT record: _acme-challenge.pr-testing.example.com

# Forge will auto-provision certificates for:
# pr-*.pr-testing.example.com
```

**Benefits**:
- ✅ No certificate provisioning per PR
- ✅ Faster environment creation (no cert wait)
- ✅ No rate limiting issues from Let's Encrypt
- ✅ Consistent SSL across all test environments

### 5.3 Certificate Renewal

**Automated Renewal**:
```bash
# Forge handles renewal automatically
# Verify renewal schedule
forge certificate:list --server-id={server_id}

# Check certificate expiry
openssl s_client -connect pr-123.pr-testing.example.com:443 -servername pr-123.pr-testing.example.com < /dev/null 2>/dev/null | openssl x509 -noout -dates
```

**Monitoring**:
- Set up alerts for certificates expiring in <30 days
- Monitor Forge renewal logs
- Test certificate validity in CI/CD pipeline

---

## 6. Environment Variable Security

### 6.1 Secure Storage

**.env File Protection**:
```bash
# File permissions (CRITICAL)
chmod 600 /home/forge-pr-123/.env
chown forge-pr-123:forge-pr-123 /home/forge-pr-123/.env

# Verify no world-readable permissions
ls -la /home/forge-pr-123/.env
# Should show: -rw------- (600)
```

**Git Protection**:
```gitignore
# .gitignore (verify these entries exist)
.env
.env.*
!.env.example
.env.backup
.env.testing.local
```

### 6.2 Sensitive Variables

**Classification**:
```env
# HIGH RISK (rotate regularly, never log)
DB_PASSWORD=XXXXXXXXXX
FORGE_API_TOKEN=XXXXXXXXXX
STRIPE_SECRET=sk_test_XXXXXXXXXX

# MEDIUM RISK (rotate quarterly)
REDIS_PASSWORD=XXXXXXXXXX
SESSION_ENCRYPTION_KEY=XXXXXXXXXX
JWT_SECRET=XXXXXXXXXX

# LOW RISK (can be logged in debug mode)
APP_NAME="PR Testing"
APP_ENV=pr-testing
LOG_LEVEL=debug
```

### 6.3 Environment Variable Injection

**Secure Injection via Forge**:
```php
// GitHub Action -> Forge API
$envVariables = [
    'APP_ENV' => 'pr-testing',
    'APP_DEBUG' => 'true',
    'APP_URL' => "https://pr-{$prNumber}.pr-testing.example.com",
    'DB_DATABASE' => "pr_{$prNumber}_{$appName}",
    'DB_USERNAME' => "pr_{$prNumber}_{$appName}",
    'DB_PASSWORD' => $this->generateSecurePassword(),

    // From GitHub Secrets
    'STRIPE_KEY' => $githubSecrets['STRIPE_TEST_KEY'],
    'STRIPE_SECRET' => $githubSecrets['STRIPE_TEST_SECRET'],
];

// Update via Forge API
$forge->updateEnvironmentFile($serverId, $siteId, $envVariables);
```

**Validation**:
```php
// app/Providers/AppServiceProvider.php
public function boot()
{
    if (app()->environment('pr-testing')) {
        // Verify NO production credentials
        $productionKeys = [
            'sk_live_',  // Stripe production
            'AC[a-z0-9]{32}',  // Twilio production
        ];

        foreach (config()->all() as $key => $value) {
            if (is_string($value)) {
                foreach ($productionKeys as $pattern) {
                    if (preg_match("/$pattern/", $value)) {
                        throw new \Exception("SECURITY: Production credentials detected in PR environment: $key");
                    }
                }
            }
        }
    }
}
```

---

## 7. GitHub Webhook Security

### 7.1 Webhook Signature Verification

**Critical**: Always verify GitHub webhook signatures to prevent spoofing attacks.

**Implementation**:
```php
// app/Http/Controllers/WebhookController.php
namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class GitHubWebhookController extends Controller
{
    public function handle(Request $request)
    {
        // 1. Verify signature
        if (!$this->verifySignature($request)) {
            Log::warning('Invalid GitHub webhook signature', [
                'ip' => $request->ip(),
                'headers' => $request->headers->all(),
            ]);
            abort(403, 'Invalid signature');
        }

        // 2. Verify event type
        $event = $request->header('X-GitHub-Event');
        if (!in_array($event, ['pull_request', 'pull_request_review'])) {
            return response()->json(['message' => 'Event not handled'], 200);
        }

        // 3. Process webhook
        $payload = $request->json()->all();

        return $this->processWebhook($event, $payload);
    }

    private function verifySignature(Request $request): bool
    {
        $signature = $request->header('X-Hub-Signature-256');

        if (!$signature) {
            return false;
        }

        $secret = config('services.github.webhook_secret');
        $payload = $request->getContent();

        $expectedSignature = 'sha256=' . hash_hmac('sha256', $payload, $secret);

        return hash_equals($expectedSignature, $signature);
    }
}
```

### 7.2 Webhook Configuration

**GitHub Repository Settings**:
```
Settings → Webhooks → Add webhook

Payload URL: https://api.example.com/webhooks/github
Content type: application/json
Secret: [STORE IN GITHUB SECRETS - WEBHOOK_SECRET]

Events:
✅ Pull requests
✅ Pull request reviews
❌ Everything else (not needed)

Active: ✅
SSL verification: ✅ Enable (CRITICAL)
```

**Webhook Secret Generation**:
```bash
# Generate strong webhook secret (one-time)
openssl rand -hex 32

# Store in:
# 1. GitHub Repository Secrets (GITHUB_WEBHOOK_SECRET)
# 2. Laravel .env (GITHUB_WEBHOOK_SECRET)
```

### 7.3 Rate Limiting

**Prevent Abuse**:
```php
// routes/api.php
Route::post('/webhooks/github', [GitHubWebhookController::class, 'handle'])
    ->middleware(['throttle:10,1']); // 10 requests per minute

// config/app.php - Rate limiting for webhooks
'webhooks' => [
    'max_requests' => 10,
    'decay_seconds' => 60,
    'by_ip' => true,
],
```

### 7.4 Webhook IP Whitelist

**GitHub Webhook IPs** (verify current list):
```nginx
# Nginx configuration
location /webhooks/github {
    # GitHub webhook IPs (verify at https://api.github.com/meta)
    allow 140.82.112.0/20;
    allow 143.55.64.0/20;
    allow 185.199.108.0/22;
    allow 192.30.252.0/22;

    deny all;

    try_files $uri $uri/ /index.php?$query_string;
}
```

**Dynamic IP Verification**:
```php
private function verifyGitHubIP(Request $request): bool
{
    $requestIP = $request->ip();

    // Fetch current GitHub IP ranges
    $response = Http::get('https://api.github.com/meta');
    $githubIPs = $response->json()['hooks'] ?? [];

    foreach ($githubIPs as $cidr) {
        if ($this->ipInRange($requestIP, $cidr)) {
            return true;
        }
    }

    return false;
}
```

---

## 8. Forge API Token Security

### 8.1 Token Management

**Critical**: Forge API tokens have FULL server access - treat as root credentials.

**Token Permissions**:
```
Forge API Token Permissions:
✅ Server management
✅ Site management
✅ Database management
✅ SSL certificate management
✅ Environment variable management
❌ Billing access (not needed)
❌ Team management (not needed)
```

**Storage Locations**:
```yaml
# GitHub Repository Secrets (REQUIRED)
FORGE_API_TOKEN: token_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Never store in:
❌ .env file in repository
❌ Hardcoded in PHP files
❌ Git commit history
❌ Slack messages
❌ Email
❌ Documentation
```

### 8.2 Token Rotation

**Policy**: Rotate Forge API tokens every 90 days.

```bash
# Rotation process:
# 1. Generate new token in Forge dashboard
# 2. Update GitHub Secret immediately
# 3. Test new token with API call
# 4. Revoke old token in Forge dashboard
# 5. Document rotation in security log

# Test token validity
curl -H "Authorization: Bearer $FORGE_API_TOKEN" \
     -H "Accept: application/json" \
     https://forge.laravel.com/api/v1/user
```

### 8.3 Token Usage Monitoring

**Audit Logging**:
```php
// Log all Forge API calls
use Illuminate\Support\Facades\Log;

class ForgeApiClient
{
    public function makeRequest($method, $endpoint, $data = [])
    {
        Log::info('Forge API Request', [
            'method' => $method,
            'endpoint' => $endpoint,
            'timestamp' => now(),
            'user' => auth()->user()?->email ?? 'system',
            'ip' => request()->ip(),
        ]);

        // Make API request
        $response = Http::withToken($this->token)
            ->$method("https://forge.laravel.com/api/v1/{$endpoint}", $data);

        Log::info('Forge API Response', [
            'status' => $response->status(),
            'success' => $response->successful(),
        ]);

        return $response;
    }
}
```

**Alert on Suspicious Activity**:
- Multiple failed API calls
- API calls from unexpected IPs
- High-frequency API calls (>100/hour)
- Calls outside business hours

### 8.4 Least Privilege

**GitHub Action Permissions**:
```yaml
# .github/workflows/pr-environment.yml
permissions:
  contents: read
  pull-requests: write
  issues: write
  # No admin, packages, or security events access needed
```

**Forge API Scoped Requests**:
```php
// Only request minimum necessary data
$forge->getSite($serverId, $siteId); // ✅ Specific
$forge->getAllServers(); // ❌ Too broad, avoid if possible
```

---

## 9. Cleanup Security

### 9.1 Automated Cleanup Triggers

**Prevent Environment Sprawl**:

**Trigger 1: PR Closed**
```yaml
# GitHub Action workflow
on:
  pull_request:
    types: [closed]

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - name: Delete PR environment
        run: |
          # 1. Delete site via Forge API
          # 2. Drop database
          # 3. Remove Linux user
          # 4. Delete SSL certificate
          # 5. Update DNS records
```

**Trigger 2: Abandoned PRs** (Stale for >7 days)
```bash
# Cron job on main app server
0 2 * * * /usr/local/bin/cleanup-abandoned-pr-environments.sh
```

```bash
#!/bin/bash
# cleanup-abandoned-pr-environments.sh

# Find PR environments older than 7 days
STALE_SITES=$(forge site:list --server-id={server_id} --format=json | \
  jq -r '.[] | select(.name | test("pr-[0-9]+")) | select(.created_at < (now - 604800)) | .id')

for SITE_ID in $STALE_SITES; do
  echo "Cleaning up stale site: $SITE_ID"

  # Check if PR still open on GitHub
  PR_NUMBER=$(echo $SITE_ID | grep -oP 'pr-\K[0-9]+')
  PR_STATE=$(gh pr view $PR_NUMBER --json state --jq .state)

  if [ "$PR_STATE" != "OPEN" ]; then
    # Delete site
    forge site:delete $SITE_ID --force

    # Drop database
    forge database:delete "pr_${PR_NUMBER}_*" --force

    # Log cleanup
    echo "$(date): Cleaned up PR $PR_NUMBER" >> /var/log/pr-cleanup.log
  fi
done
```

### 9.2 Data Sanitization

**Critical**: Ensure data cannot be recovered after cleanup.

```bash
# Secure database deletion
mysql -e "DROP DATABASE pr_123_keatchen;"
mysql -e "DROP USER 'pr_123_keatchen'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Secure file deletion (if needed)
shred -vfz -n 5 /home/forge-pr-123/.env
rm -rf /home/forge-pr-123

# Verify deletion
ls /home/forge-pr-123  # Should return "No such file or directory"
mysql -e "SHOW DATABASES LIKE 'pr_123_%';"  # Should return empty set
```

### 9.3 Cleanup Verification

**Post-Cleanup Checklist**:
```bash
# 1. Site removed from Forge
forge site:list --server-id={server_id} | grep pr-123
# Should return: No results

# 2. Database dropped
mysql -e "SHOW DATABASES LIKE 'pr_123_%';"
# Should return: Empty set

# 3. Linux user removed
id forge-pr-123
# Should return: no such user

# 4. SSL certificate deleted
certbot certificates | grep pr-123
# Should return: No results

# 5. DNS record removed
dig pr-123.pr-testing.example.com
# Should return: NXDOMAIN
```

### 9.4 Cleanup Audit Trail

**Logging**:
```php
// Log all cleanup operations
Log::channel('security')->info('PR Environment Cleanup', [
    'pr_number' => $prNumber,
    'site_id' => $siteId,
    'database' => $databaseName,
    'triggered_by' => 'pr_closed',
    'timestamp' => now(),
    'duration_seconds' => $cleanupDuration,
    'success' => true,
]);
```

---

## 10. Network Security Considerations

### 10.1 Firewall Configuration

**Server-Level Firewall** (UFW on Ubuntu):
```bash
# Default deny incoming
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (from specific IPs only)
ufw allow from 203.0.113.0/24 to any port 22

# Allow HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Allow MySQL (localhost only)
ufw allow from 127.0.0.1 to any port 3306

# Enable firewall
ufw enable

# Verify rules
ufw status verbose
```

### 10.2 Database Network Access

**MySQL Binding**:
```ini
# /etc/mysql/mysql.conf.d/mysqld.cnf

# CRITICAL: Only bind to localhost
bind-address = 127.0.0.1

# Never use:
# bind-address = 0.0.0.0  ❌ Exposes to internet
```

**Verify MySQL Access**:
```bash
# Should only show localhost
netstat -tuln | grep 3306
# Expected: tcp 0 0 127.0.0.1:3306 0.0.0.0:* LISTEN

# Test remote connection (should fail)
mysql -h {PUBLIC_IP} -u root -p
# Expected: ERROR 2003 (HY000): Can't connect to MySQL server
```

### 10.3 Redis Security

**Redis Configuration**:
```conf
# /etc/redis/redis.conf

# Bind to localhost only
bind 127.0.0.1

# Require password
requirepass STRONG_RANDOM_PASSWORD

# Disable dangerous commands
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command KEYS ""
rename-command CONFIG ""

# Enable protected mode
protected-mode yes
```

### 10.4 Outbound Network Security

**Restrict Outbound Connections**:
```bash
# Allow only necessary outbound connections
# 1. Package repositories (apt)
# 2. GitHub (git clone)
# 3. Composer (dependencies)
# 4. NPM (frontend dependencies)
# 5. External APIs (Stripe, etc)

# Block all other outbound (optional, strict)
iptables -A OUTPUT -o eth0 -d github.com -j ACCEPT
iptables -A OUTPUT -o eth0 -d api.stripe.com -j ACCEPT
# ... add other whitelisted domains
iptables -A OUTPUT -o eth0 -j DROP
```

### 10.5 DDoS Protection

**Rate Limiting** (Nginx):
```nginx
# /etc/nginx/nginx.conf

http {
    # Define rate limit zones
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=api:10m rate=5r/s;

    # Connection limits
    limit_conn_zone $binary_remote_addr zone=addr:10m;

    server {
        # Apply rate limits
        location / {
            limit_req zone=general burst=20 nodelay;
            limit_conn addr 10;
        }

        location /api/ {
            limit_req zone=api burst=10 nodelay;
            limit_conn addr 5;
        }
    }
}
```

**Cloudflare DDoS Protection** (Recommended):
```
Enable Cloudflare for:
✅ DDoS protection
✅ Rate limiting
✅ WAF (Web Application Firewall)
✅ Bot protection
✅ SSL termination
```

### 10.6 Network Monitoring

**Monitor Suspicious Activity**:
```bash
# Install fail2ban
apt-get install fail2ban

# Configure for Nginx
# /etc/fail2ban/jail.local
[nginx-http-auth]
enabled = true
port    = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 3600

[nginx-limit-req]
enabled = true
port    = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
findtime = 60
bantime = 3600
```

---

## 11. Compliance & Audit Requirements

### 11.1 Logging Requirements

**Essential Logs**:
```php
// config/logging.php
'channels' => [
    'security' => [
        'driver' => 'daily',
        'path' => storage_path('logs/security.log'),
        'level' => 'info',
        'days' => 90, // Retain for 90 days
    ],

    'audit' => [
        'driver' => 'daily',
        'path' => storage_path('logs/audit.log'),
        'level' => 'info',
        'days' => 365, // Retain for 1 year
    ],
];
```

**Events to Log**:
- ✅ PR environment creation/deletion
- ✅ Database snapshot creation
- ✅ Forge API calls
- ✅ Webhook received/processed
- ✅ Authentication failures
- ✅ SSL certificate changes
- ✅ Environment variable updates
- ✅ Access denied events

### 11.2 Security Checklist

**Pre-Launch Checklist**:
- [ ] Firewall configured (UFW enabled)
- [ ] Database bound to localhost only
- [ ] SSL certificates provisioned (Let's Encrypt)
- [ ] HTTP Basic Auth enabled
- [ ] GitHub webhook signature verification enabled
- [ ] Forge API token stored in GitHub Secrets
- [ ] All external APIs in TEST mode
- [ ] Cleanup automation tested
- [ ] Log retention configured (90 days)
- [ ] fail2ban installed and configured
- [ ] Rate limiting enabled (Nginx + Laravel)
- [ ] robots.txt blocks search engines

**Per-PR Checklist**:
- [ ] Unique Linux user created
- [ ] Isolated database provisioned
- [ ] Strong random passwords generated
- [ ] Environment variables injected securely
- [ ] SSL certificate valid
- [ ] Basic Auth credentials set
- [ ] API keys verified (TEST mode only)
- [ ] Cleanup trigger configured

### 11.3 Incident Response

**Security Incident Process**:
1. **Detect**: Monitor logs for suspicious activity
2. **Contain**: Disable affected PR environment immediately
3. **Investigate**: Review logs, identify root cause
4. **Remediate**: Fix vulnerability, update code
5. **Document**: Write post-mortem, update procedures
6. **Prevent**: Implement additional controls

**Emergency Contacts**:
```
Security Lead: security@example.com
DevOps Team: devops@example.com
On-Call: +1-555-0123
```

---

## 12. Security Best Practices Summary

### 12.1 DO's ✅

- ✅ Use HTTPS for all test environments
- ✅ Enable HTTP Basic Auth or IP whitelist
- ✅ Store secrets in GitHub Secrets
- ✅ Use TEST mode for all external APIs
- ✅ Rotate API tokens every 90 days
- ✅ Verify GitHub webhook signatures
- ✅ Implement automated cleanup (7 days)
- ✅ Log all security events
- ✅ Use separate Linux users per PR
- ✅ Isolate databases completely
- ✅ Bind MySQL to localhost only
- ✅ Enable firewall (UFW)
- ✅ Monitor logs regularly
- ✅ Test backups and recovery

### 12.2 DON'Ts ❌

- ❌ Never commit secrets to Git
- ❌ Never use production API keys in test
- ❌ Never disable SSL verification
- ❌ Never share Forge API tokens
- ❌ Never allow public database access
- ❌ Never skip webhook signature verification
- ❌ Never leave abandoned environments
- ❌ Never log sensitive data (passwords, tokens)
- ❌ Never use weak passwords
- ❌ Never disable firewall
- ❌ Never expose test environments to search engines
- ❌ Never share .env files via email/Slack

---

## 13. Security Testing

### 13.1 Penetration Testing Checklist

**Before Launch**:
```bash
# 1. Test site isolation
sudo -u forge-pr-123 cat /home/forge-pr-124/.env
# Expected: Permission denied

# 2. Test database isolation
mysql -u pr_123_keatchen -p -e "SHOW DATABASES;"
# Expected: Only see pr_123_keatchen database

# 3. Test authentication
curl -I https://pr-123.pr-testing.example.com
# Expected: 401 Unauthorized (Basic Auth required)

# 4. Test webhook signature
curl -X POST https://api.example.com/webhooks/github \
  -H "Content-Type: application/json" \
  -d '{"action":"opened"}'
# Expected: 403 Forbidden (no signature)

# 5. Test SSL
sslscan pr-123.pr-testing.example.com
# Expected: TLS 1.2+, strong ciphers only

# 6. Test firewall
nmap -p 3306 {PUBLIC_IP}
# Expected: filtered (port closed)

# 7. Test rate limiting
ab -n 1000 -c 10 https://pr-123.pr-testing.example.com/
# Expected: 429 Too Many Requests after threshold
```

### 13.2 Security Scanning

**Automated Scans**:
```yaml
# .github/workflows/security-scan.yml
name: Security Scan

on:
  schedule:
    - cron: '0 2 * * 1' # Weekly on Monday 2am

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      # Dependency vulnerability scan
      - name: Composer Audit
        run: composer audit

      # Static analysis security scan
      - name: PHPStan Security
        run: vendor/bin/phpstan analyse --level=max

      # Secrets detection
      - name: TruffleHog
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
```

---

## 14. Emergency Procedures

### 14.1 Security Breach Response

**If API Keys Compromised**:
```bash
# 1. Immediately rotate compromised keys
# 2. Revoke old keys in service provider
# 3. Update GitHub Secrets
# 4. Force destroy ALL PR environments
# 5. Rebuild environments with new keys
# 6. Review logs for unauthorized usage
# 7. Document incident

# Emergency key rotation script
./scripts/emergency-key-rotation.sh
```

### 14.2 Unauthorized Access

**If Test Environment Accessed**:
```bash
# 1. Check access logs
tail -f /var/log/nginx/access.log | grep pr-123

# 2. Immediately destroy environment
forge site:delete {site_id} --force

# 3. Drop database
mysql -e "DROP DATABASE pr_123_*;"

# 4. Review webhook logs for tampering
# 5. Check Forge API logs for unauthorized calls
# 6. Reset all authentication credentials
# 7. Investigate root cause
```

---

## 15. Conclusion

### 15.1 Security Posture Summary

**Current Risk Level**: 🟡 MEDIUM (with proper implementation)

**Critical Controls**:
1. Site isolation via separate Linux users
2. Database isolation per PR
3. TEST-only external API keys
4. Access control (Basic Auth + IP whitelist)
5. HTTPS everywhere
6. GitHub webhook verification
7. Secure Forge API token management
8. Automated cleanup (7-day TTL)
9. Comprehensive logging and monitoring

**Residual Risks**:
- 🟡 Production data in snapshots (mitigated by no PII)
- 🟡 Shared server infrastructure (mitigated by isolation)
- 🟢 Test environment exposure (mitigated by access control)

### 15.2 Next Steps

**Before Implementation**:
1. Review this document with security team
2. Complete security checklist
3. Set up monitoring and alerting
4. Configure automated cleanup
5. Test incident response procedures
6. Train team on security protocols

**Ongoing**:
- Monthly security audits
- Quarterly API token rotation
- Weekly log review
- Continuous monitoring
- Annual penetration testing

---

## 16. References & Resources

**Documentation**:
- [Laravel Forge Security](https://forge.laravel.com/docs/1.0/security.html)
- [GitHub Webhook Security](https://docs.github.com/en/webhooks-and-events/webhooks/securing-your-webhooks)
- [Let's Encrypt Best Practices](https://letsencrypt.org/docs/)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)

**Security Tools**:
- fail2ban: https://www.fail2ban.org/
- UFW: https://help.ubuntu.com/community/UFW
- Composer Audit: https://getcomposer.org/doc/03-cli.md#audit
- TruffleHog: https://github.com/trufflesecurity/trufflehog

**Emergency Contacts**:
- Security Team: security@example.com
- DevOps Team: devops@example.com
- On-Call: +1-555-0123

---

**Document Version**: 1.0
**Last Reviewed**: 2025-11-07
**Next Review**: 2025-12-07
**Owner**: Security Team / DevOps Lead
