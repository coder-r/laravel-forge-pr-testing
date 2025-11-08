# PR Testing Workflow - Quick Start (30 minutes)

## Step 1: Get Forge Credentials (5 min)

### Generate API Token
1. Visit: https://forge.laravel.com/user/profile#/api
2. Click **"Create API Token"**
3. Name: `GitHub PR Testing`
4. Copy token (save for next step)

### Get Server ID
1. Visit: https://forge.laravel.com/servers
2. Click your server
3. URL: `https://forge.laravel.com/servers/{SERVER_ID}/...`
4. Copy the SERVER_ID number

## Step 2: Add GitHub Secrets (5 min)

1. Go to repository **Settings** → **Secrets and Variables** → **Actions**
2. Click **"New repository secret"**

**Secret 1:**
- Name: `FORGE_API_TOKEN`
- Value: (paste your token from Step 1)

**Secret 2:**
- Name: `FORGE_SERVER_ID`
- Value: (paste your server ID from Step 1)

## Step 3: Test the Workflow (10 min)

1. Create a test PR (or open existing one)
2. Comment on PR: `/preview`
3. Go to **Actions** tab to watch workflow
4. Wait 5-10 minutes
5. You'll get PR comment with test URL: `https://pr-123.on-forge.com`

## Step 4: Verify It Works (5 min)

1. Click test URL from PR comment
2. Should see Laravel app loading
3. Check Forge dashboard → see new site in list
4. Test is complete!

## Step 5: Try Other Commands (5 min)

### Test `/update` command
```
1. Make code change
2. Push to PR branch
3. Comment /update
4. Wait 2-3 minutes
```

### Test `/destroy` command
```
1. Comment /destroy
2. Wait <1 minute
3. Site deleted from Forge
```

### Test auto-cleanup
```
1. Close the PR (merge or reject)
2. Site auto-deletes in ~2 minutes
3. No manual action needed
```

---

## Available Commands

| Command | What It Does | Duration |
|---------|------------|----------|
| `/preview` | Create test environment | 5-10 min |
| `/update` | Redeploy code | 2-3 min |
| `/destroy` | Delete environment | <1 min |
| (auto) | Cleanup on PR close | automatic |

---

## What Gets Created

Each test environment includes:
- ✅ Site at `pr-{NUMBER}.on-forge.com`
- ✅ Code from your PR branch
- ✅ Database snapshot (production-like data)
- ✅ Queue workers (for background jobs)
- ✅ Automatic SSL (HTTPS)
- ✅ Unique test URL in PR comment

---

## Troubleshooting

**"Permission denied"**
→ You don't have push access. Ask repo admin to add you.

**"Failed to create site"**
→ Check secrets are correct in Settings → Secrets.

**"Site not found"**
→ Run `/preview` first to create environment.

**"HTTPS not working"**
→ Wait 5-10 minutes for Let's Encrypt certificate.

**"Code not deployed"**
→ Check PR branch name exists in GitHub.

More help: See `.github/workflows/WORKFLOW_REFERENCE.md`

---

## Next: Share with Team

1. Send team the **Setup Checklist**: `docs/4-implementation/6-workflow-setup-checklist.md`
2. They add their own secrets
3. Everyone can use `/preview` command
4. Done!

---

## You're All Set!

The workflow is ready to use. Just:

1. ✅ Added GitHub secrets
2. ✅ Tested `/preview` command
3. ✅ Got working test URL

**Now you can:**
- Create test environments on-demand
- Share URLs with stakeholders
- Test features before merging
- Everything auto-cleans up

Enjoy! 🚀

---

**Questions?** See documentation:
- Setup: `docs/4-implementation/6-workflow-setup-checklist.md`
- Complete: `docs/4-implementation/5-pr-testing-workflow-guide.md`
- Reference: `.github/workflows/WORKFLOW_REFERENCE.md`
