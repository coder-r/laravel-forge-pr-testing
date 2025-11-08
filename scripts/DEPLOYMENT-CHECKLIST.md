# Production Deployment Checklist

Use this checklist to ensure all steps are completed before, during, and after deployment.

## Pre-Deployment (Day Before)

### Preparation
- [ ] Review `IMPLEMENTATION-SUMMARY.md` - understand the 6 phases
- [ ] Read `README-IMPLEMENTATION.md` - understand options and troubleshooting
- [ ] Backup current state/data from existing servers (if any)
- [ ] Notify stakeholders about maintenance window
- [ ] Ensure 30-40 minutes of uninterrupted time

### Configuration
- [ ] Get Forge API token from https://forge.laravel.com/account/api-tokens
- [ ] Copy `example-deployment.env` to `.env.deployment`
- [ ] Set `FORGE_API_TOKEN` in `.env.deployment`
- [ ] Review `FORGE_API_URL` (should be default)
- [ ] Set `MAX_PROVISIONING_WAIT=3600` (1 hour - safe for DigitalOcean)
- [ ] Save `.env.deployment` securely (add to .gitignore)

### System Requirements
- [ ] Install required tools:
  ```bash
  sudo apt-get update
  sudo apt-get install curl jq ssh
  ```
- [ ] Verify installation:
  ```bash
  which curl jq ssh
  ```
- [ ] Test SSH access to existing servers (if any)

### Test Run
- [ ] Run script in dry-run mode:
  ```bash
  ./scripts/implement-complete-system.sh --config .env.deployment --dry-run --verbose
  ```
- [ ] Review output - ensure all resources would be created
- [ ] Check for any errors or warnings
- [ ] Estimate actual deployment time

## Deployment Day (Phase Execution)

### Phase 1: Validate API Access (30 seconds)
- [ ] Start deployment at agreed time
- [ ] Monitor Phase 1 output
- [ ] Verify API token is working:
  ```bash
  cat logs/implementation-*.log | grep "API authentication"
  ```
- [ ] Confirm existing servers are listed

### Phase 2: Create Production VPS (10-20 minutes)
- [ ] Monitor progress bar
- [ ] Check ETA calculations
- [ ] Watch for:
  - [ ] keatchen-customer-app VPS created
  - [ ] devpel-epos VPS created
  - [ ] Both servers reach "active" status
  - [ ] Firewall rules configured
- [ ] If timeout occurs:
  ```bash
  MAX_PROVISIONING_WAIT=7200 ./scripts/implement-complete-system.sh --phase 2
  ```

### Phase 3: Create Sites (5 minutes)
- [ ] Monitor site creation
- [ ] Verify:
  - [ ] keatchen-customer-app.on-forge.com created
  - [ ] devpel-epos.on-forge.com created
  - [ ] Databases created (PostgreSQL & MySQL)
  - [ ] SSL certificates installed
- [ ] Check log for any warnings

### Phase 4: Database Snapshots (5 minutes)
- [ ] Monitor snapshot creation
- [ ] Check:
  - [ ] SSH connections established
  - [ ] Database dumps created
  - [ ] Files saved to backups/
  - [ ] Cron jobs configured
- [ ] Verify backup files:
  ```bash
  ls -lh backups/*.sql
  ```

### Phase 5: Test PR Environment (5-10 minutes)
- [ ] Monitor test server creation
- [ ] Verify:
  - [ ] pr-test-environment VPS created
  - [ ] Test site created
  - [ ] Test database created
- [ ] Note test server IP address

### Phase 6: Monitoring Setup (2 minutes)
- [ ] Monitor final configuration
- [ ] Verify:
  - [ ] Health checks configured
  - [ ] Alerts configured
  - [ ] Daily summaries enabled

## Post-Deployment

### Immediate (First 5 minutes)
- [ ] Review final report:
  ```bash
  cat logs/implementation-report.txt
  ```
- [ ] Check for any FAILED phases
- [ ] Note server IDs and IP addresses
- [ ] Note site IDs from logs

### Verification (10 minutes)
- [ ] Test HTTPS connectivity:
  ```bash
  curl -I https://keatchen-customer-app.on-forge.com
  curl -I https://devpel-epos.on-forge.com
  ```
- [ ] SSH to each server and verify:
  ```bash
  ssh root@<ip-address>
  ls -la /home/forge
  cat .env | grep APP_KEY
  ```
- [ ] Check Forge dashboard:
  - [ ] All servers shown as "active"
  - [ ] All sites showing green status
  - [ ] Firewall rules visible
  - [ ] SSL certificates valid

### Configuration (30 minutes)
- [ ] **keatchen-customer-app:**
  - [ ] SSH to server
  - [ ] Edit `/home/forge/keatchen-customer-app/.env`
  - [ ] Set database credentials
  - [ ] Set APP_KEY if not auto-generated
  - [ ] Set other environment variables
  - [ ] Run migrations: `php artisan migrate`
  - [ ] Run seeders if needed: `php artisan db:seed`

- [ ] **devpel-epos:**
  - [ ] SSH to server
  - [ ] Edit `/home/forge/devpel-epos/.env`
  - [ ] Set database credentials
  - [ ] Set APP_KEY if not auto-generated
  - [ ] Set other environment variables
  - [ ] Run migrations: `php artisan migrate`
  - [ ] Run seeders if needed: `php artisan db:seed`

### Git Integration (15 minutes)
- [ ] From Forge dashboard, for each site:
  - [ ] Add repository URL (GitHub/GitLab)
  - [ ] Add SSH keys if needed
  - [ ] Install repository
  - [ ] Test automatic deployment

- [ ] Verify code deployed:
  - [ ] SSH to each server
  - [ ] Check /home/forge/<app>/ has latest code
  - [ ] Verify `.env` file exists
  - [ ] Check storage/ has correct permissions

### Testing (20 minutes)
- [ ] **Basic Connectivity:**
  - [ ] Visit https://keatchen-customer-app.on-forge.com
  - [ ] Visit https://devpel-epos.on-forge.com
  - [ ] Verify no SSL warnings
  - [ ] Check application loads

- [ ] **Database:**
  - [ ] SSH to each server
  - [ ] Test database connectivity:
    ```bash
    mysql -u root -p<password> -e "SHOW DATABASES;"
    psql -U postgres -l
    ```
  - [ ] Verify migrations ran
  - [ ] Check if data exists

- [ ] **Application Functions:**
  - [ ] Test login (if applicable)
  - [ ] Test database queries
  - [ ] Check error logs: `tail -f /home/forge/<app>/storage/logs/laravel.log`

### Monitoring Setup (10 minutes)
- [ ] Go to Forge dashboard
- [ ] For each server:
  - [ ] Enable monitoring
  - [ ] Set email alerts
  - [ ] Test alert email
  - [ ] Review health check graph
- [ ] Setup Slack notifications (optional)

### Backup Verification (5 minutes)
- [ ] Verify database snapshots created:
  ```bash
  ls -lh backups/
  du -sh backups/
  ```
- [ ] Test snapshot restoration (on test server):
  ```bash
  ssh root@<test-ip>
  mysql -u root -p<password> < /path/to/snapshot.sql
  ```
- [ ] Verify cron jobs created:
  ```bash
  ssh root@<production-ip> "crontab -l"
  ```

## Troubleshooting During Deployment

### If Timeout on VPS Creation
```bash
# Check status manually
curl -H "Authorization: Bearer $FORGE_API_TOKEN" \
  https://forge.laravel.com/api/v1/servers | jq '.servers'

# Resume with longer timeout
MAX_PROVISIONING_WAIT=7200 ./scripts/implement-complete-system.sh --phase 2
```

### If API Call Fails
```bash
# Verify token is valid
curl -H "Authorization: Bearer $FORGE_API_TOKEN" \
  https://forge.laravel.com/api/v1/user

# Check rate limits
curl -I -H "Authorization: Bearer $FORGE_API_TOKEN" \
  https://forge.laravel.com/api/v1/servers
# Look for X-RateLimit-* headers
```

### If SSH Fails During Phase 4
```bash
# Wait for server to finish booting
sleep 300

# Try resuming
./scripts/implement-complete-system.sh --phase 4 --verbose

# Or manually SSH
ssh -o StrictHostKeyChecking=no root@<ip-address>
```

### If Site Creation Fails
```bash
# Check Forge dashboard for errors
# Verify PHP version available on server
ssh root@<ip-address> "php -v"

# Try resuming Phase 3
./scripts/implement-complete-system.sh --phase 3 --verbose
```

## Rollback Procedure (If Needed)

### If Critical Issues Found
1. [ ] Document issue and time
2. [ ] Note which servers are affected
3. [ ] Check logs for error details: `cat logs/implementation-*.log`
4. [ ] Contact Forge support if API error

### Manual Cleanup
If you need to delete everything and start over:

```bash
# From Forge dashboard:
1. Delete sites
2. Delete databases
3. Delete servers

# Locally:
rm -rf logs/ .implementation-state/ backups/

# Start over:
./scripts/implement-complete-system.sh
```

## Post-Deployment Checklist

### Day 1 (After Deployment)
- [ ] Monitor error logs for any issues
- [ ] Check all applications are functioning
- [ ] Verify backups are working
- [ ] Test failover procedures
- [ ] Document any issues found

### Week 1 (After Deployment)
- [ ] Review performance metrics
- [ ] Check alert system is working
- [ ] Monitor CPU/memory/disk usage
- [ ] Verify automated backups run
- [ ] Document any improvements needed

### Month 1 (After Deployment)
- [ ] Review Forge dashboard dashboard
- [ ] Test disaster recovery procedures
- [ ] Optimize resource allocation if needed
- [ ] Plan for scaling if needed
- [ ] Update documentation

## Important Files & Locations

### Local
```
scripts/
├── implement-complete-system.sh     (MAIN SCRIPT)
├── README-IMPLEMENTATION.md         (Full documentation)
├── example-deployment.env           (Config template)
└── IMPLEMENTATION-SUMMARY.md        (Overview)

logs/                               (Created during deployment)
├── implementation-YYYYMMDD_HHMMSS.log
└── implementation-report.txt

.implementation-state/              (Created during deployment)
├── phase-1.state
├── phase-2.state
└── ...phase-6.state

backups/                            (Created during Phase 4)
├── keatchen-customer-app-postgres-*.sql
└── devpel-epos-mysql-*.sql
```

### On Servers
```
/home/forge/keatchen-customer-app/
├── .env
├── public/
├── storage/
└── logs/
  └── laravel.log

/home/forge/devpel-epos/
├── .env
├── public/
├── storage/
└── logs/
  └── laravel.log

/root/
├── backup-database.sh           (Cron script)
└── backups/                     (Remote backups)
  ├── database-YYYYMMDD.sql
  └── ...
```

## Contact Information

### Support
- **Forge**: https://forge.laravel.com
- **Forge API**: https://forge.laravel.com/api-documentation
- **Logs**: Check local `logs/` directory

### Emergency
If deployment fails:
1. Check logs: `tail -50 logs/implementation-*.log`
2. Review this checklist for the failed phase
3. Attempt to resume: `./scripts/implement-complete-system.sh --phase N`
4. If still stuck, use Forge dashboard to clean up and restart

## Sign-Off

- [ ] Deployment completed successfully
- [ ] All applications verified working
- [ ] Backups confirmed
- [ ] Monitoring active
- [ ] Team notified

**Deployment Date**: _______________
**Deployed By**: ___________________
**Status**: [ ] Success [ ] Partial [ ] Rolled Back

**Notes**:
```
_________________________________________________________________

_________________________________________________________________

_________________________________________________________________
```

---

**Last Updated**: November 8, 2025
**Version**: 1.0.0
**For**: emphermal-llaravel-app
