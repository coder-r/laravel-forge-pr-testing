# Laravel Forge Capabilities

## Overview

Laravel Forge is a server management and application deployment service that provisions and manages servers on your cloud provider (DigitalOcean, Linode, AWS, etc.).

**Official Documentation**: https://forge.laravel.com/docs
**API Documentation**: https://forge.laravel.com/api-documentation

## Core Features for Our Use Case

### 1. Site Management

Forge's core capability is creating and managing "sites" - individual web applications on a server.

#### Site Creation
- **API Endpoint**: `POST /api/v1/servers/{serverId}/sites`
- **Parameters**:
  - `domain`: The domain/subdomain for the site
  - `project_type`: `php` (for Laravel) or `html`
  - `aliases`: Additional domains that point to this site
  - `directory`: Web root directory (default `/public`)
  - `isolated`: Enable site isolation (separate Linux user)
  - `php_version`: PHP version (e.g., `php82`, `php83`)

#### Key Features
- **Wildcard Subdomains**: Enable at site level to accept all subdomains
- **Site Isolation**: Each site runs under separate Linux user for security
- **Custom Nginx Config**: Modify nginx configuration for specific needs
- **Environment Variables**: Manage .env file through Forge interface or API

#### Wildcard Subdomain Support

**Important Discovery**: Forge supports wildcard subdomains!

**How it works**:
1. Create a site with "Allow Wildcard Sub-Domains" enabled
2. Set DNS wildcard record: `*.staging.kitthub.com` → Server IP
3. Configure SSL with DNS-01 validation (requires DNS provider API)
4. All subdomains (`pr-123.staging.kitthub.com`, `pr-456.staging.kitthub.com`) are handled by this site

**Limitations**:
- Wildcard subdomains enabled at the **site level** (not per domain)
- All apex domains on the site share the wildcard setting
- SSL certificates require DNS-01 validation for wildcards

**For our use case**: We'll create individual sites per PR (not use wildcard feature), because:
- We need complete isolation per environment
- We need unique databases per environment
- We need separate environment variables per environment

### 2. Site Isolation

**New Feature** (added ~2025): Sites can be isolated with separate Linux users.

**Benefits**:
- Security: One site can't access another site's files
- Resource isolation: Easier to track resource usage per site
- Permission separation: Better security posture

**How to enable**:
- Check "Use Website Isolation" when creating site
- Or via API: `isolated: true` parameter

**Recommendation**: Enable for all PR test environments.

### 3. Database Management

Forge can create and manage databases programmatically.

#### Database Operations
- **Create Database**: `POST /api/v1/servers/{serverId}/databases`
- **Create Database User**: `POST /api/v1/servers/{serverId}/database-users`
- **Grant Access**: Link database user to specific databases

#### Database Types Supported
- MySQL (default)
- PostgreSQL
- MariaDB

#### For Our Use Case
- Each PR environment gets unique database
- Database created via API on environment setup
- Database copied from master snapshot
- Database deleted on environment teardown

### 4. Deployment Automation

Forge integrates with Git providers (GitHub, GitLab, Bitbucket).

#### Deployment Features
- **Quick Deploy**: Enable auto-deploy on git push
- **Deployment Script**: Customize deployment commands
- **Deployment History**: Track all deployments
- **Manual Deploy**: Trigger deployments via API or interface

#### API Endpoints
- **Enable Quick Deploy**: `POST /api/v1/servers/{serverId}/sites/{siteId}/deployment`
- **Trigger Deploy**: `POST /api/v1/servers/{serverId}/sites/{siteId}/deployment/deploy`
- **Get Deploy Log**: `GET /api/v1/servers/{serverId}/sites/{siteId}/deployment/log`

#### Deployment Script Example
```bash
cd /home/forge/pr-123.staging.kitthub.com
git pull origin $FORGE_SITE_BRANCH
$FORGE_COMPOSER install --no-interaction --prefer-dist --optimize-autoloader
( flock -w 10 9 || exit 1
    echo 'Restarting FPM...'; sudo -S service $FORGE_PHP_FPM reload ) 9>/tmp/fpmlock
if [ -f artisan ]; then
    $FORGE_PHP artisan migrate --force
    $FORGE_PHP artisan queue:restart
    $FORGE_PHP artisan config:cache
    $FORGE_PHP artisan route:cache
    $FORGE_PHP artisan view:cache
fi
```

### 5. SSL Certificate Management

Forge automates SSL certificate creation and renewal.

#### Certificate Types
- **Let's Encrypt**: Free, auto-renewing
- **Custom Certificate**: Upload your own
- **Cloudflare**: If using Cloudflare as proxy

#### Wildcard SSL Requirements
- Must use DNS-01 validation
- Requires DNS provider API credentials
- Supported providers: Cloudflare, DigitalOcean, Route53, etc.

#### API Endpoints
- **Create Let's Encrypt Cert**: `POST /api/v1/servers/{serverId}/sites/{siteId}/certificates/letsencrypt`
- **Activate Certificate**: `POST /api/v1/servers/{serverId}/sites/{siteId}/certificates/{certId}/activate`

### 6. Queue Workers (Laravel Horizon)

Forge can manage Laravel queue workers.

#### Worker Configuration
- **Create Worker**: `POST /api/v1/servers/{serverId}/sites/{siteId}/workers`
- **Parameters**:
  - `connection`: Queue connection (e.g., `redis`)
  - `queue`: Queue name (e.g., `default,high`)
  - `processes`: Number of worker processes
  - `timeout`: Job timeout in seconds
  - `sleep`: Seconds to sleep when no jobs
  - `daemon`: Run as daemon (true)

#### For Our Use Case
Each PR environment needs its own queue workers configured to use isolated Redis database.

### 7. Scheduled Jobs (Cron)

Forge manages Laravel's task scheduler.

#### Configuration
- Automatically creates cron entry: `* * * * * php artisan schedule:run`
- Per-site scheduler
- Enable/disable via API

### 8. Environment Variable Management

Forge provides secure environment variable storage.

#### Features
- Edit .env file through web interface
- Update via API: `PUT /api/v1/servers/{serverId}/sites/{siteId}/env`
- Encrypted storage
- Version history

#### For Our Use Case
Each PR environment needs unique .env configuration:
- Database credentials
- Queue connection
- Redis database number
- API keys (test mode)
- App URL

### 9. Server Management

While we're using existing servers, Forge can also provision new servers.

#### Server Features
- Multiple PHP versions
- Redis, Memcached
- MySQL, PostgreSQL, MariaDB
- UFW firewall
- Automatic security updates
- Monitoring and metrics

### 10. Webhooks

Forge can send webhooks on deployment events.

#### Webhook Events
- Deployment started
- Deployment completed
- Deployment failed

#### For Our Use Case
Can integrate webhooks to notify when PR environment is ready.

## Forge API

### Authentication

```bash
Authorization: Bearer YOUR_FORGE_API_TOKEN
Content-Type: application/json
Accept: application/json
```

### Rate Limits

- **60 requests per minute** per API token
- Returns `429 Too Many Requests` if exceeded
- Includes `Retry-After` header

### Example API Calls

#### Create Site
```bash
curl -X POST https://forge.laravel.com/api/v1/servers/123456/sites \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "pr-789.staging.kitthub.com",
    "project_type": "php",
    "directory": "/public",
    "isolated": true,
    "php_version": "php82"
  }'
```

#### Create Database
```bash
curl -X POST https://forge.laravel.com/api/v1/servers/123456/databases \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "pr_789_db",
    "user": "pr_789_user",
    "password": "secure_password_here"
  }'
```

#### Deploy Site
```bash
curl -X POST https://forge.laravel.com/api/v1/servers/123456/sites/789012/deployment/deploy \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "branch": "feature/new-checkout"
  }'
```

#### Delete Site
```bash
curl -X DELETE https://forge.laravel.com/api/v1/servers/123456/sites/789012 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Forge Limitations

### What Forge Cannot Do

1. **No Built-in PR Integration**
   - Forge doesn't automatically create sites on PR creation
   - We must build this automation ourselves

2. **No Site Cloning**
   - Can't clone an existing site with all configuration
   - Must create each site from scratch via API

3. **No Database Cloning**
   - Must manually copy database from master snapshot
   - No built-in database snapshot/restore

4. **No Auto-Cleanup**
   - Sites don't auto-delete
   - We must build cleanup automation

5. **No Cost Management**
   - No built-in warnings for resource usage
   - Must monitor server resources separately

6. **API Rate Limits**
   - 60 requests/minute could be a constraint with many PRs
   - Must implement rate limiting and queuing

### Workarounds for Limitations

1. **PR Integration**: Build with GitHub Actions + Forge API
2. **Site Cloning**: Create template configuration, apply to each new site
3. **Database Cloning**: Use `mysqldump` + `mysql` commands via SSH
4. **Auto-Cleanup**: GitHub Action on PR close/merge to call delete API
5. **Cost Management**: External monitoring tools (CloudWatch, Datadog)
6. **Rate Limits**: Implement queue for site creation/deletion

## Recommended Forge Configuration

### Server Setup

**Server Specifications** (for 1-3 concurrent environments):
- CPU: 2-4 cores
- RAM: 4-8 GB
- Storage: 50-100 GB SSD
- Provider: DigitalOcean, Linode, or Hetzner (best value)

**Estimated Cost**: $20-40/month

**Server Configuration**:
- PHP 8.2 or 8.3 (match production)
- MySQL 8.0 or PostgreSQL 15 (match production)
- Redis 7.x
- Node.js 20.x (for asset compilation)
- Let's Encrypt SSL

### Site Configuration Template

For each PR environment:

```json
{
  "domain": "pr-{PR_NUMBER}.staging.kitthub.com",
  "project_type": "php",
  "directory": "/public",
  "isolated": true,
  "php_version": "php82",
  "aliases": []
}
```

### Database Configuration Template

For each PR environment:

```json
{
  "name": "pr_{PR_NUMBER}_db",
  "user": "pr_{PR_NUMBER}_user",
  "password": "{GENERATED_PASSWORD}"
}
```

### Environment Variables Template

```env
APP_NAME="PR-{PR_NUMBER} Testing"
APP_ENV=staging
APP_KEY=base64:...
APP_DEBUG=true
APP_URL=https://pr-{PR_NUMBER}.staging.kitthub.com

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=pr_{PR_NUMBER}_db
DB_USERNAME=pr_{PR_NUMBER}_user
DB_PASSWORD={GENERATED_PASSWORD}

QUEUE_CONNECTION=redis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379
REDIS_DB={PR_NUMBER}

# Use test mode for external APIs
STRIPE_KEY=pk_test_...
STRIPE_SECRET=sk_test_...
PAYMENT_GATEWAY_MODE=test

SESSION_DRIVER=redis
SESSION_DATABASE={PR_NUMBER}
CACHE_DATABASE={PR_NUMBER}
```

## New Features (2025)

### Site Isolation Improvements

Sites created after October 2025 have enhanced domain and SSL management:
- Per-domain SSL certificates (not shared)
- Better wildcard subdomain handling
- Improved security isolation

**Recommendation**: Create fresh sites using new system (not legacy).

### API Enhancements

Recent API improvements:
- Better error messages
- Webhook support for deployment events
- Improved rate limiting transparency

## Integration Strategy for Our Use Case

### Phase 1: Manual Testing
1. Manually create test site via Forge interface
2. Configure database, environment variables
3. Deploy code manually
4. Verify everything works
5. Manually delete site

### Phase 2: API Automation
1. Create site via API
2. Create database via API
3. Copy database from snapshot via SSH
4. Update environment variables via API
5. Trigger deployment via API
6. Verify via health check endpoint
7. Delete site via API when PR closes

### Phase 3: GitHub Integration
1. GitHub Action triggers on PR comment `/preview`
2. Action calls Forge API to create environment
3. Action waits for environment to be ready
4. Action posts comment with URL
5. On PR close, Action calls Forge API to delete

## Comparison with Alternatives

### Forge vs Laravel Vapor
- **Vapor**: Serverless, more expensive, auto-scaling
- **Forge**: Traditional servers, cheaper for small team
- **Winner for us**: Forge (already using it, cost-effective)

### Forge vs Custom Docker/Kubernetes
- **Docker/K8s**: More flexible, steeper learning curve
- **Forge**: Easier, Laravel-optimized, faster setup
- **Winner for us**: Forge (1-2 week timeline, small team)

### Forge vs Heroku Review Apps
- **Heroku**: Built-in PR environments, more expensive
- **Forge**: More control, better value
- **Winner for us**: Forge (cost-flexible but prefer value)

## Further Reading

1. **Official Docs**: https://forge.laravel.com/docs
2. **API Docs**: https://forge.laravel.com/api-documentation
3. **Community**: https://laracasts.com/discuss/channels/forge
4. **Site Isolation**: https://stackoverflow.com/questions/66741475/what-does-website-isolation-user-isolation-do-laravel-forge
5. **Wildcard Subdomains**: https://mattstauffer.com/blog/laravel-forge-wildcard-subdomains/

## Next Steps

Now that you understand Forge's capabilities:

1. **Read**: [3-infrastructure-overview.md](./3-infrastructure-overview.md) - Your current setup
2. **Then**: Move to [3-critical-reading/1-architecture-design.md](../3-critical-reading/1-architecture-design.md)
