# End-to-End Deployment Workflow Guide

⚡ **Quick Reference**: This guide shows exactly how to use the PR testing environment system day-to-day.

**Audience**: Developers and stakeholders using the PR testing environment system

**Time to Read**: 10 minutes

## Table of Contents

1. [Developer Workflow](#developer-workflow)
2. [Stakeholder Workflow](#stakeholder-workflow)
3. [Testing Checklist](#testing-checklist)
4. [Troubleshooting Guide](#troubleshooting-guide)
5. [Best Practices](#best-practices)
6. [Quick Reference Commands](#quick-reference-commands)

---

## Developer Workflow

### Step-by-Step Guide

#### Step 1: Create Feature Branch

```bash
# Create and switch to new feature branch
git checkout -b feature/add-payment-gateway

# Make your changes
# ... code, code, code ...

# Commit your work
git add .
git commit -m "Add Stripe payment gateway integration"

# Push to GitHub
git push origin feature/add-payment-gateway
```

#### Step 2: Open Pull Request

1. **Go to GitHub repository**
2. **Click "New Pull Request"**
3. **Select your feature branch**
4. **Fill in PR details**:
   ```
   Title: Add Stripe payment gateway integration

   Description:
   - Implemented Stripe checkout flow
   - Added payment webhooks
   - Updated order processing

   Testing needed:
   - Test checkout flow
   - Verify webhook handling
   - Check refund process
   ```
5. **Click "Create Pull Request"**

#### Step 3: Request Test Environment

**In the PR, add a comment**:

```
/preview
```

**What happens next**:

```
You comment "/preview"
   ↓
GitHub Actions detects comment (within 10 seconds)
   ↓
System validates: PR is open, you have permissions
   ↓
Creates isolated test environment (5-10 minutes)
   ↓
Bot posts comment with details
```

#### Step 4: Wait for Environment (5-10 minutes)

**While waiting**, the system is:

1. ✅ Creating isolated Linux user account
2. ✅ Creating new database
3. ✅ Copying production data snapshot
4. ✅ Setting up environment variables
5. ✅ Installing SSL certificate
6. ✅ Deploying your code
7. ✅ Starting queue workers

**Progress tracking**: Check the GitHub Actions tab to see progress

#### Step 5: Receive Notification

**Bot posts comment on your PR**:

```
✅ Test environment ready!

🔗 URL: https://pr-123.staging.kitthub.com
🔐 Basic Auth: username / password (if configured)
🗄️ Database: Snapshot from 2024-11-03
⏱️ Created: 2024-11-07 10:23 AM
🔄 Auto-deploys: Yes (on push to feature branch)

Test away! 🚀
```

#### Step 6: Access Test Environment

**Visit the URL**:

```
https://pr-123.staging.kitthub.com
```

**If basic auth is configured**:
- Username: `staging`
- Password: `[provided by team]`

**First-time access checklist**:
- [ ] Site loads correctly
- [ ] Can log in with test credentials
- [ ] Database has realistic data
- [ ] Your new feature is visible

#### Step 7: Test Your Feature

**Manual Testing**:

1. **Happy Path Testing**
   - Test the main feature functionality
   - Verify everything works as expected
   - Check UI/UX looks correct

2. **Error Handling**
   - Test edge cases
   - Try invalid inputs
   - Verify error messages

3. **Integration Testing**
   - Test interactions with other features
   - Verify database changes
   - Check queue jobs process correctly

4. **Cross-Browser Testing** (if needed)
   - Chrome
   - Firefox
   - Safari
   - Mobile browsers

**Example Testing Checklist** (payment gateway):
```
Testing Checklist: Payment Gateway
- [ ] Load checkout page
- [ ] Enter test card details
- [ ] Submit payment
- [ ] Verify order created in database
- [ ] Check payment confirmation email sent
- [ ] Test refund process
- [ ] Verify webhook handling
- [ ] Check error handling for declined cards
```

#### Step 8: Push Updates (Auto-Deploys)

**Make changes and push**:

```bash
# Fix issues found during testing
git add .
git commit -m "Fix webhook signature validation"
git push origin feature/add-payment-gateway
```

**Automatic deployment happens**:

```
GitHub detects push to your branch
   ↓
Webhook triggers Forge deployment
   ↓
Your test environment updates automatically (2-3 minutes)
   ↓
(Optional) Bot posts: "♻️ Environment updated"
```

**No need to recreate environment** - it updates automatically!

#### Step 9: Get Stakeholder Feedback

**Share the URL with stakeholders**:

```
Hi @product-manager,

Feature is ready for review: https://pr-123.staging.kitthub.com

Test account:
- Email: test@example.com
- Password: test123

Please test:
1. Checkout flow with test card (4242 4242 4242 4242)
2. Order confirmation email
3. Refund process in admin panel

Let me know if you spot any issues!
```

**Stakeholders can test at their convenience** without technical setup.

#### Step 10: Merge PR (Auto-Cleanup)

**When ready to merge**:

1. **Address all feedback**
2. **Get PR approval**
3. **Click "Merge Pull Request"**

**Automatic cleanup happens**:

```
PR merged to main
   ↓
GitHub webhook detects merge
   ↓
Cleanup automation triggers
   ↓
Test environment deleted (site + database + SSL)
   ↓
Bot posts: "✅ Environment cleaned up"
```

**Resources freed automatically** - no manual cleanup needed!

---

## Stakeholder Workflow

### For Product Managers, Business Owners, QA Team

#### Step 1: Receive Preview URL

**Developer shares**:
```
"Feature ready for review: https://pr-123.staging.kitthub.com"
```

#### Step 2: Access Environment

**Click the URL**:
- May need basic auth credentials (ask developer)
- Site looks identical to production
- Uses realistic production data

#### Step 3: Test Feature

**What to test**:

1. **Functionality**
   - Does the feature work as expected?
   - Are there any bugs or issues?
   - Does it match requirements?

2. **User Experience**
   - Is it intuitive?
   - Are there any confusing elements?
   - Does it look good on mobile?

3. **Business Logic**
   - Does it solve the business problem?
   - Are there edge cases not covered?
   - Does it integrate well with existing features?

#### Step 4: Provide Feedback

**Comment on GitHub PR** or **message developer**:

```
Tested the payment gateway feature:

✅ Works great:
- Checkout flow is smooth
- Confirmation emails look good

⚠️ Issues found:
- Refund button is hard to find (too small)
- Error message when card declined is unclear
- Mobile layout is a bit cramped

💡 Suggestions:
- Add loading spinner during payment processing
- Show order total more prominently
```

#### Step 5: Re-Test After Changes

**Developer fixes issues and pushes updates**:
- Environment updates automatically
- Test again to verify fixes
- Approve when satisfied

#### Step 6: Approve for Production

**When everything looks good**:
```
✅ Approved! Ready for production.

All issues addressed. Feature works perfectly.
```

**Developer merges to production** - environment cleans up automatically.

---

## Testing Checklist

### Verify System Works Correctly

Use this checklist after initial setup or when troubleshooting:

#### ✅ Environment Creation

- [ ] **Comment `/preview` on test PR**
- [ ] **GitHub Actions workflow starts within 30 seconds**
- [ ] **Environment creates in under 10 minutes**
- [ ] **Bot posts success comment with URL**
- [ ] **URL resolves correctly** (DNS propagated)

**Expected**: Success comment appears in PR:
```
✅ Test environment ready!
🔗 URL: https://pr-123.staging.kitthub.com
```

#### ✅ Database Setup

- [ ] **Can access database** (via site or direct connection)
- [ ] **Database has realistic data** (recent snapshot)
- [ ] **All tables present** (matches production schema)
- [ ] **Foreign keys intact** (referential integrity)
- [ ] **Data volume reasonable** (similar to production)

**Test query** (if direct access):
```sql
SELECT COUNT(*) FROM orders;
SELECT COUNT(*) FROM users;
-- Should show realistic numbers
```

#### ✅ Queue Workers

- [ ] **Queue workers running** (check Horizon dashboard)
- [ ] **Jobs processing** (test a background job)
- [ ] **No job failures** (check failed jobs queue)
- [ ] **Redis connection working** (check cache)

**Test**: Trigger a background job (e.g., send email, process order)
- **Expected**: Job processes successfully within 30 seconds

#### ✅ SSL Certificate

- [ ] **Site loads over HTTPS** (no browser warnings)
- [ ] **Certificate is valid** (not self-signed)
- [ ] **Certificate covers domain** (matches pr-*.staging.kitthub.com)
- [ ] **Auto-redirect from HTTP** (if configured)

**Check**: Visit `https://pr-123.staging.kitthub.com`
- **Expected**: Green padlock in browser, no certificate warnings

#### ✅ Application Functionality

- [ ] **Can log in** (authentication works)
- [ ] **Can create data** (forms submit)
- [ ] **Can view data** (lists load)
- [ ] **Can update data** (edits save)
- [ ] **Can delete data** (deletions work)

**Test user account**:
```
Email: test@example.com
Password: test123
```

#### ✅ Auto-Deploy on Push

- [ ] **Push new commit to PR branch**
- [ ] **Deployment triggers automatically** (within 2 minutes)
- [ ] **Changes appear on site** (code updates)
- [ ] **No deployment errors** (check logs)

**Test**: Make trivial change (e.g., update text), push, verify update appears

#### ✅ Environment Cleanup

- [ ] **Merge or close PR**
- [ ] **Cleanup workflow triggers** (within 2 minutes)
- [ ] **Site deleted** (URL returns 404)
- [ ] **Database deleted** (no longer in database list)
- [ ] **Bot posts cleanup confirmation**

**Expected**: Success comment appears:
```
✅ Environment cleaned up successfully
```

---

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue 1: Environment Creation Takes Too Long (>15 minutes)

**Symptoms**:
- Comment `/preview` posted
- GitHub Action running for 15+ minutes
- No success comment from bot

**Possible Causes**:
1. Database snapshot copy is slow (>5GB database)
2. Forge API is slow/timing out
3. SSL certificate issuance delayed
4. Server resources exhausted

**Solutions**:

```bash
# Check GitHub Actions logs
1. Go to PR → Actions tab
2. Find "PR Testing Environment" workflow
3. Check logs for errors

# Common fixes:
- Wait longer (SSL can take 5-10 minutes)
- Check Forge dashboard for site status
- Verify server has enough disk space
- Check DNS has propagated (dig pr-123.staging.kitthub.com)
```

**Manual intervention**:
```bash
# If stuck, destroy and recreate
Comment on PR: /destroy
Wait 2 minutes
Comment on PR: /preview
```

#### Issue 2: Deployment Fails

**Symptoms**:
- Environment created but site shows error
- "500 Internal Server Error" or similar
- Deployment log shows failures

**Possible Causes**:
1. Composer dependency error
2. Database migration failure
3. Environment variable missing
4. Code syntax error

**Solutions**:

```bash
# Check Forge deployment logs
1. Log into Laravel Forge
2. Navigate to test site (pr-123.staging.kitthub.com)
3. View deployment log

# Common errors:

# Composer error:
# Fix: Update composer.json, push again

# Migration error:
# Fix: Fix migration file, push again

# Environment variable missing:
# Fix: Add to .env in Forge dashboard

# Disk space:
# Fix: Clean up old environments, increase storage
```

**Quick fix**:
```bash
# Re-trigger deployment
Comment on PR: /update

# Or SSH to server and manually deploy:
ssh forge@your-server-ip
cd /home/pr123user/pr-123.staging.kitthub.com
./deploy.sh
```

#### Issue 3: Database Connection Errors

**Symptoms**:
- "SQLSTATE[HY000] [1045] Access denied"
- "Could not connect to database"
- Site loads but can't access data

**Possible Causes**:
1. Database credentials wrong in .env
2. Database not created
3. Database user permissions wrong
4. MySQL server down

**Solutions**:

```bash
# Verify database exists
1. Log into Forge
2. Go to Databases tab
3. Look for pr_123_[project]_db

# Check environment variables
1. Go to site in Forge
2. Click "Environment"
3. Verify DB_DATABASE, DB_USERNAME, DB_PASSWORD

# Test database connection
ssh forge@your-server-ip
mysql -u pr_123_user -p pr_123_[project]_db
# Should connect successfully

# If database missing:
# Re-run environment creation
Comment on PR: /destroy
Comment on PR: /preview
```

#### Issue 4: SSL Certificate Issues

**Symptoms**:
- Browser shows "Not Secure" or certificate warning
- Site loads over HTTP but not HTTPS
- Certificate error in browser

**Possible Causes**:
1. Let's Encrypt issuance failed
2. DNS not propagated yet
3. Rate limit hit (50 certs/week)
4. Forge couldn't verify domain ownership

**Solutions**:

```bash
# Check DNS propagation
dig pr-123.staging.kitthub.com
# Should return server IP

# Wait and retry (DNS can take 5-10 minutes)

# Check Forge certificate status
1. Log into Forge
2. Go to site → SSL
3. Check certificate status

# Retry certificate issuance
# In Forge dashboard:
1. Go to site → SSL
2. Click "Obtain Certificate"
3. Use Let's Encrypt
4. Enter domain: pr-123.staging.kitthub.com

# Fallback: Use HTTP temporarily
# (Not ideal but works for testing)
Access via: http://pr-123.staging.kitthub.com
```

#### Issue 5: Queue Workers Not Running

**Symptoms**:
- Background jobs not processing
- Emails not sending
- Jobs stuck in "pending" state
- Horizon dashboard shows "Inactive"

**Possible Causes**:
1. Queue workers not started
2. Redis connection error
3. Redis database conflict
4. Worker crashed

**Solutions**:

```bash
# Check Horizon dashboard
Visit: https://pr-123.staging.kitthub.com/horizon
# Should show active workers

# Restart queue workers
ssh forge@your-server-ip
sudo -u pr123user php /home/pr123user/pr-123.staging.kitthub.com/artisan queue:restart

# Check Redis connection
redis-cli -n 123 PING
# Should return PONG

# Check worker status in Forge
1. Go to site → Workers
2. Verify worker is "Active"
3. If not, click "Restart"

# Check logs
tail -f /home/pr123user/pr-123.staging.kitthub.com/storage/logs/laravel.log
# Look for Redis or queue errors
```

#### Issue 6: Site Shows Old Code (Not Updating)

**Symptoms**:
- Pushed new commits but changes don't appear
- Site still shows old version
- Deployment shows success but no changes

**Possible Causes**:
1. Browser cache
2. Laravel cache not cleared
3. OPcache not refreshed
4. Deployment didn't actually run

**Solutions**:

```bash
# Clear browser cache
Ctrl+Shift+R (hard refresh)
Or open in incognito/private mode

# Clear Laravel caches
ssh forge@your-server-ip
sudo -u pr123user php /home/pr123user/pr-123.staging.kitthub.com/artisan cache:clear
sudo -u pr123user php /home/pr123user/pr-123.staging.kitthub.com/artisan config:clear
sudo -u pr123user php /home/pr123user/pr-123.staging.kitthub.com/artisan view:clear

# Restart PHP-FPM
sudo service php8.2-fpm restart

# Force deployment
Comment on PR: /update

# Verify code is latest
ssh forge@your-server-ip
cd /home/pr123user/pr-123.staging.kitthub.com
git log -1
# Should show your latest commit
```

#### Issue 7: Environment Won't Clean Up

**Symptoms**:
- PR merged but environment still exists
- Commented `/destroy` but site still accessible
- Cleanup workflow failed

**Possible Causes**:
1. GitHub webhook not triggered
2. Forge API error during deletion
3. Database locked (active connections)
4. Workflow permissions issue

**Solutions**:

```bash
# Manual cleanup via GitHub Actions
1. Go to repository → Actions
2. Find "PR Testing Environment Cleanup" workflow
3. Click "Run workflow"
4. Enter PR number
5. Click "Run"

# Manual cleanup via Forge
1. Log into Forge
2. Find site: pr-123.staging.kitthub.com
3. Click "Delete Site"
4. Go to Databases → Delete pr_123_[project]_db

# Manual cleanup via CLI
forge delete-site pr-123.staging.kitthub.com
forge delete-database pr_123_customer_db
```

---

## Best Practices

### When to Create Test Environments

**✅ Create environments for**:

1. **Feature branches** that need testing before merge
2. **Bug fixes** that require production data to reproduce
3. **Stakeholder reviews** before production deployment
4. **Integration testing** with external APIs
5. **Performance testing** with realistic data volumes

**❌ Don't create environments for**:

1. **Draft PRs** not ready for testing
2. **Typo fixes** or minor changes
3. **Documentation updates** (no code changes)
4. **Work in progress** (use your local environment)
5. **Just to see if it builds** (use GitHub Actions status)

### How to Test Effectively

**1. Test with Production-Like Behavior**:
```
✅ Use realistic workflows (how users actually use the app)
✅ Test with production data volumes
✅ Try edge cases and error scenarios
✅ Test on multiple devices/browsers if relevant
```

**2. Test the Right Things**:
```
✅ Focus on your changes
✅ Verify integration points
✅ Check for regressions in related features
✅ Test error handling
❌ Don't test unrelated parts of the app
```

**3. Document Your Testing**:
```
Add comment to PR with testing notes:

Tested:
- ✅ Checkout flow works
- ✅ Payment confirmation email sent
- ✅ Order appears in admin panel
- ⚠️ Refund button placement could be better

Tested on:
- Chrome 120 (desktop)
- Safari iOS 17
- Test data: 3 orders, 2 refunds
```

### Communication with Stakeholders

**1. Set Clear Expectations**:
```
When sharing preview URL:

"Feature ready for review: https://pr-123.staging.kitthub.com

📋 What to test:
1. Create order with test card (4242 4242 4242 4242)
2. Verify order confirmation email
3. Test refund in admin panel

⏰ Available: Until Friday (when PR merges)

🔐 Login: test@example.com / test123
```

**2. Guide Non-Technical Users**:
```
Provide step-by-step instructions:

1. Visit: https://pr-123.staging.kitthub.com
2. Log in with: test@example.com / test123
3. Go to "Checkout"
4. Use test card: 4242 4242 4242 4242
5. Check your email for confirmation
6. Let me know if anything looks wrong!
```

**3. Make Feedback Easy**:
```
"Please test and let me know:
✅ What works well
⚠️ What could be improved
🐛 Any bugs you find

No need to be technical - just describe what you see!"
```

### Cleanup Etiquette

**1. Clean Up When Done**:
```
✅ Merge PRs promptly when approved
✅ Close abandoned PRs (auto-cleanup triggers)
✅ Use /destroy if testing is complete early
❌ Don't leave old environments running indefinitely
```

**2. Resource Awareness**:
```
Remember:
- Maximum 3 concurrent environments work well
- Each environment uses ~500MB RAM + 5GB storage
- Old environments waste resources
- Be a good teammate - clean up when done
```

**3. When to Keep Environments Longer**:
```
✅ Active stakeholder review in progress
✅ Waiting for feedback from multiple people
✅ Multi-day testing required

Still, maximum 1-2 weeks. After that, destroy and recreate if needed.
```

### Cost Optimization

**1. Efficient Environment Usage**:
```
✅ Create environment only when ready to test
✅ Merge PRs promptly when approved
✅ Don't create environment for every commit (it auto-updates)
✅ Reuse environment across multiple testing iterations
```

**2. Batch Testing**:
```
If you have multiple small features:
✅ Test multiple changes in one environment
✅ Create one PR with all related changes
❌ Don't create separate environment for every tiny change
```

**3. Resource Sharing**:
```
✅ Coordinate with team on concurrent environments
✅ Clean up after testing (free resources for teammates)
✅ Schedule testing around team's busy times
```

---

## Quick Reference Commands

### GitHub PR Commands

```bash
# Create test environment
/preview

# Destroy test environment (manual cleanup)
/destroy

# Re-deploy environment (force update)
/update

# Check environment status (if implemented)
/status
```

### SSH Access (Advanced)

```bash
# Connect to server
ssh forge@your-server-ip

# Navigate to test environment
cd /home/pr123user/pr-123.staging.kitthub.com

# View logs
tail -f storage/logs/laravel.log

# Run artisan commands
php artisan cache:clear
php artisan queue:restart
php artisan migrate:status

# Check queue workers
php artisan horizon:status

# Test database connection
mysql -u pr_123_user -p pr_123_customer_db
```

### Forge CLI (Advanced)

```bash
# List sites
forge sites

# Get site details
forge site pr-123.staging.kitthub.com

# View deployment log
forge deployment-log pr-123.staging.kitthub.com

# Trigger deployment
forge deploy pr-123.staging.kitthub.com

# Delete site
forge delete-site pr-123.staging.kitthub.com
```

### Testing URLs

```bash
# Staging pattern
https://pr-{PR_NUMBER}.staging.kitthub.com

# Examples
https://pr-123.staging.kitthub.com
https://pr-456.staging.kitthub.com

# Horizon dashboard
https://pr-123.staging.kitthub.com/horizon

# Health check (if implemented)
https://pr-123.staging.kitthub.com/health
```

### Test Credentials

```bash
# Stripe test card (always succeeds)
Card: 4242 4242 4242 4242
Expiry: Any future date
CVC: Any 3 digits

# Stripe test card (always declined)
Card: 4000 0000 0000 0002
```

---

## Environment Lifecycle Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      PR Lifecycle                                │
└─────────────────────────────────────────────────────────────────┘

1. CREATE PR
   ├─ Open PR on GitHub
   └─ Comment: /preview
        ↓
2. ENVIRONMENT CREATES (5-10 min)
   ├─ Site created
   ├─ Database cloned
   ├─ SSL installed
   └─ Code deployed
        ↓
3. TESTING PHASE (hours to days)
   ├─ Developer tests
   ├─ Stakeholders review
   ├─ Push updates (auto-deploys)
   └─ Iterate on feedback
        ↓
4. APPROVAL
   ├─ All feedback addressed
   ├─ Stakeholder approval
   └─ Ready for production
        ↓
5. MERGE PR
   ├─ Merge to main branch
   └─ Environment auto-deletes
        ↓
6. CLEANUP COMPLETE
   └─ Resources freed for next PR
```

---

## Support and Help

### Getting Help

**1. Check Documentation**:
- This workflow guide (you're reading it!)
- [Architecture Design](/home/dev/project-analysis/emphermal-llaravel-app/docs/3-critical-reading/1-architecture-design.md)
- [Implementation Checklist](/home/dev/project-analysis/emphermal-llaravel-app/docs/4-implementation/1-implementation-checklist.md)

**2. Check Logs**:
- GitHub Actions logs (for creation/cleanup issues)
- Forge deployment logs (for deployment issues)
- Laravel logs (for application issues)

**3. Ask the Team**:
- Post in team Slack/Discord
- Tag DevOps or senior developer
- Include PR number and error message

### Common Questions

**Q: How long does environment creation take?**
A: 5-10 minutes typically. Up to 15 minutes if SSL is slow.

**Q: Can I have multiple environments at once?**
A: Yes! Create multiple PRs, comment `/preview` on each.

**Q: What if I need to test locally first?**
A: Test locally first, then create PR environment when ready for review.

**Q: Can stakeholders create environments?**
A: No, only developers with write access. Developers share URLs with stakeholders.

**Q: What happens to my data when environment is destroyed?**
A: All data is deleted. It's a test environment with copied data, not production.

**Q: Can I restore a deleted environment?**
A: No, but you can recreate it by commenting `/preview` again (fresh data).

---

## Success Metrics

Track these to measure system effectiveness:

**Developer Metrics**:
- ✅ Time from PR to merge (should decrease)
- ✅ Bugs found before production (should increase)
- ✅ Developer confidence in deployments (should increase)

**Stakeholder Metrics**:
- ✅ Feedback cycle time (should decrease)
- ✅ Stakeholder engagement in reviews (should increase)
- ✅ Feature approval clarity (should increase)

**System Metrics**:
- ✅ Environment creation success rate (target: >95%)
- ✅ Average creation time (target: <10 minutes)
- ✅ Auto-cleanup success rate (target: >99%)

---

## Next Steps

**For New Users**:
1. ✅ Read this guide completely
2. ✅ Try creating your first test environment
3. ✅ Follow the testing checklist
4. ✅ Share with your team

**For Administrators**:
1. ✅ Share this guide with all team members
2. ✅ Run through testing checklist regularly
3. ✅ Monitor system metrics
4. ✅ Update guide based on team feedback

---

**Questions or issues?** Post in team channel or contact DevOps team.

**System working great?** Share your success story with the team! 🎉
