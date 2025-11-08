# PR Testing Workflow Setup Checklist

**Quick reference for getting the workflow live (30 minutes)**

---

## Pre-Setup Requirements

- [ ] Forge account with server already running
- [ ] GitHub repository admin access
- [ ] Able to access Forge dashboard
- [ ] Team member names for access grants

---

## Step 1: Get Forge Credentials (5 minutes)

### 1.1 Generate Forge API Token

1. Navigate to: https://forge.laravel.com/user/profile#/api
2. Look for "API Tokens" section
3. Click **"Create API Token"**
4. Set name: `GitHub PR Testing`
5. Click **"Create"**
6. **Copy token immediately** (you won't see it again!)
7. Save it temporarily (we'll add to GitHub next)

**Credentials Checklist:**
- [ ] API Token copied
- [ ] Token works (test with curl if confident)

### 1.2 Get Your Server ID

1. Navigate to: https://forge.laravel.com/servers
2. Find your server in the list
3. Click server name
4. URL becomes: `https://forge.laravel.com/servers/{SERVER_ID}/...`
5. Copy that `{SERVER_ID}` number

**Example**: If URL is `https://forge.laravel.com/servers/12345/sites`, your ID is `12345`

**Credentials Checklist:**
- [ ] Server ID identified
- [ ] Server ID saved

---

## Step 2: Add GitHub Secrets (5 minutes)

### 2.1 Navigate to Secrets

1. Go to your GitHub repository
2. Click **Settings** (top right)
3. In left sidebar, click **Secrets and variables**
4. Click **Actions**

### 2.2 Create FORGE_API_TOKEN Secret

1. Click **New repository secret**
2. **Name**: `FORGE_API_TOKEN`
3. **Value**: Paste your token from Step 1.1
4. Click **Add secret**

### 2.3 Create FORGE_SERVER_ID Secret

1. Click **New repository secret**
2. **Name**: `FORGE_SERVER_ID`
3. **Value**: Paste your server ID from Step 1.2
4. Click **Add secret**

**Secrets Checklist:**
- [ ] FORGE_API_TOKEN added
- [ ] FORGE_SERVER_ID added
- [ ] Both visible in Settings → Secrets
- [ ] ✅ No tokens in repository or chat

---

## Step 3: Verify Workflow File (5 minutes)

### 3.1 Check File Location

The workflow file should be at:
```
.github/workflows/pr-testing.yml
```

### 3.2 Verify File Content

File should contain these jobs:
- [ ] `route-command` - Parse PR comments
- [ ] `create-environment` - Create site
- [ ] `update-environment` - Redeploy code
- [ ] `destroy-environment` - Delete site
- [ ] `auto-cleanup-on-pr-close` - Auto cleanup

### 3.3 Check Permissions

Workflow should have minimal permissions:
```yaml
permissions:
  contents: read
  pull-requests: write
```

**Workflow Checklist:**
- [ ] File at `.github/workflows/pr-testing.yml`
- [ ] All 5 jobs present
- [ ] Permissions correct
- [ ] No hardcoded secrets in file

---

## Step 4: Test with a PR (10 minutes)

### 4.1 Create Test PR

1. Create a feature branch:
   ```bash
   git checkout -b test/pr-workflow
   echo "# Test PR" >> README.md
   git add .
   git commit -m "Test PR workflow"
   git push origin test/pr-workflow
   ```

2. Open PR on GitHub
3. Wait for checks to run
4. See PR comment box at bottom

### 4.2 Trigger Preview Command

1. In PR comment box, type: `/preview`
2. Click **Comment**
3. Go to **Checks** tab to watch workflow
4. Wait 5-10 minutes

**What to expect:**
- ✅ "eyes" reaction added to your comment
- ✅ Workflow runs in Actions tab
- ✅ After ~5 minutes: PR comment with test URL
- ✅ Test URL format: `https://pr-123.on-forge.com`

### 4.3 Verify Test Environment

1. Click test URL from PR comment
2. Should see Laravel app loading
3. Check Forge dashboard → see new site in list
4. Verify site name: `pr-{PR_NUMBER}.on-forge.com`

**Test Checklist:**
- [ ] `/preview` command triggered successfully
- [ ] Workflow completed without errors
- [ ] Test URL posted in PR comment
- [ ] Site accessible in browser
- [ ] Site visible in Forge dashboard

### 4.4 Test Update Command

1. Make small change to code
2. Commit and push to PR branch
3. Comment `/update` on PR
4. Wait 2-3 minutes
5. Verify site shows new code

**Update Checklist:**
- [ ] `/update` command works
- [ ] Code redeployed in 2-3 minutes
- [ ] No database reset

### 4.5 Test Cleanup Command

1. Comment `/destroy` on PR
2. Wait 1 minute
3. Verify site no longer appears in Forge
4. See cleanup confirmation in PR comment

**Cleanup Checklist:**
- [ ] `/destroy` command works
- [ ] Site deleted from Forge
- [ ] Cleanup comment posted
- [ ] Preview label removed

### 4.6 Test Auto-Cleanup

1. Create another test PR (or reopen the first)
2. Run `/preview` again
3. Once environment created, **close the PR**
4. Check that site auto-deletes within 2 minutes
5. Verify cleanup comment posted

**Auto-Cleanup Checklist:**
- [ ] Environment created successfully
- [ ] PR closure triggers auto-cleanup job
- [ ] Site auto-deleted from Forge
- [ ] Cleanup comment posted

---

## Step 5: Configure Team Access (5 minutes)

### 5.1 Who Can Use Workflow?

Only users with **push access** to repository can trigger commands.

### 5.2 Grant Access if Needed

1. Go to repository **Settings**
2. Click **Collaborators**
3. Add team members who need access
4. Set role to **Write** or higher

**Access Checklist:**
- [ ] All developers added as collaborators
- [ ] Permissions set to "Write" or higher
- [ ] Developers notified of new feature

---

## Step 6: Create Setup Documentation (Optional, 5 minutes)

### 6.1 Create Team Guide

Create `WORKFLOW_USAGE.md` in repository:

```markdown
# PR Testing Workflow Usage

## Quick Start

1. Open PR
2. Comment `/preview`
3. Get test URL in comment
4. Test feature
5. Comment `/destroy` when done (or let auto-cleanup do it)

## Commands

- `/preview` - Create test environment
- `/update` - Redeploy latest code
- `/destroy` - Delete environment

## Questions?

See: [docs/4-implementation/5-pr-testing-workflow-guide.md](./docs/4-implementation/5-pr-testing-workflow-guide.md)
```

### 6.2 Share with Team

1. Post link to new guide in Slack/Teams
2. Share PR testing workflow link
3. Give team time to read (5 min)
4. Do one demo together

**Documentation Checklist:**
- [ ] Created team-friendly guide
- [ ] Shared with team
- [ ] Team read documentation

---

## Troubleshooting Quick Reference

### Problem: Permission denied error

**Solution**:
1. Check user is collaborator: Settings → Collaborators
2. Add if missing
3. Try command again

### Problem: Forge API token invalid

**Solution**:
1. Go to https://forge.laravel.com/user/profile#/api
2. Generate new token
3. Update GitHub secret
4. Try command again

### Problem: Site creation timeout

**Solution**:
1. Check Forge server has space (20GB free)
2. Check Forge server not under high load
3. Try again (may be temporary API delay)

### Problem: HTTPS not working

**Solution**:
1. Wait 10 minutes (Let's Encrypt can be slow)
2. Refresh page
3. Check Forge dashboard for certificate errors

### Problem: Code not deployed

**Solution**:
1. Check branch name is correct (case-sensitive)
2. Make sure branch exists on GitHub
3. Try `/update` command
4. SSH to site and check git status

### Problem: Database not cloned

**Solution**:
1. Check master snapshot exists in Forge server
2. Check database user permissions
3. Check server has disk space
4. Check database size (>5GB needs time)

---

## Success Criteria

You'll know workflow is working when:

- [ ] ✅ `/preview` creates site in <10 minutes
- [ ] ✅ Test URL posted automatically in PR
- [ ] ✅ Site accessible with HTTPS
- [ ] ✅ Code from PR branch deployed
- [ ] ✅ Database snapshot included
- [ ] ✅ `/update` redeploys code in 2-3 min
- [ ] ✅ `/destroy` deletes site in <1 min
- [ ] ✅ Auto-cleanup works on PR close
- [ ] ✅ Team can use without errors

---

## Post-Setup Tasks

### Weekly Maintenance

- [ ] **Sunday evening**: Refresh master database snapshot
  - Take sanitized backup from production
  - Replace master snapshot on Forge server
  - Verify next test uses latest data

### Monthly Review

- [ ] Check workflow logs for errors
- [ ] Review Forge activity log
- [ ] Verify no orphaned test sites
- [ ] Check API rate limiting usage
- [ ] Review team feedback

### Security Review

- [ ] [ ] Rotate Forge API token quarterly
- [ ] [ ] Verify only needed users have access
- [ ] [ ] Check no secrets leaked in logs
- [ ] [ ] Review database snapshot contains no sensitive data

---

## Quick Reference Card

### Commands (Copy/Paste)

```
/preview    - Create test environment
/update     - Redeploy code to existing environment
/destroy    - Delete test environment
```

### URLs

- **Workflow file**: `.github/workflows/pr-testing.yml`
- **Guide**: `docs/4-implementation/5-pr-testing-workflow-guide.md`
- **Forge dashboard**: https://forge.laravel.com/servers
- **GitHub secrets**: Settings → Secrets and Variables → Actions

### Credentials Needed

| Item | Where | Created By |
|------|-------|-----------|
| `FORGE_API_TOKEN` | GitHub Secrets | Forge dashboard |
| `FORGE_SERVER_ID` | GitHub Secrets | From Forge URL |

### Time Estimates

| Task | Duration |
|------|----------|
| Create test environment | 5-10 minutes |
| Redeploy code | 2-3 minutes |
| Delete environment | <1 minute |
| Auto-cleanup | ~2 minutes |

---

## Getting Help

**Workflow not working?**

1. Check GitHub Actions tab → latest run → see error
2. Common issues:
   - Wrong secrets → Check Settings → Secrets
   - Permission denied → Check user is collaborator
   - API timeout → Wait 5 minutes, try again
   - Site creation fails → Check Forge server status

**Need more details?**

See: `docs/4-implementation/5-pr-testing-workflow-guide.md` → Troubleshooting section

---

**Status**: ✅ Complete and Production Ready

**Last Updated**: January 2025

**Next Steps**: Run your first `/preview` command!
