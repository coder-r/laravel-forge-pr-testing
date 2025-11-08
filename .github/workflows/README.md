# GitHub Actions Workflows

Production-ready GitHub Actions workflows for the Laravel PR Testing Environment.

## Workflows

### pr-testing.yml

**Automated PR testing environments using Laravel Forge**

Creates isolated test environments on-demand for pull requests with:

- ✅ Automatic site creation via Forge API
- ✅ Database snapshot cloning
- ✅ Code deployment from PR branch
- ✅ Queue worker setup
- ✅ Automatic SSL certificates
- ✅ Manual and automatic cleanup

**Triggers**:
- `/preview` command on PR → Create environment
- `/update` command on PR → Redeploy code
- `/destroy` command on PR → Delete environment
- PR close event → Auto-cleanup environment

**Usage**:

```
Comment on PR: /preview
```

Test URL posted in comment within 5-10 minutes.

## Configuration

### Secrets Required

Add to: Settings → Secrets and Variables → Actions

| Secret | Description | How to Get |
|--------|-------------|-----------|
| `FORGE_API_TOKEN` | Laravel Forge API token | https://forge.laravel.com/user/profile#/api |
| `FORGE_SERVER_ID` | Forge server ID | https://forge.laravel.com/servers → Click server |

### Environment Variables

Edit in workflow file:

```yaml
env:
  FORGE_API_BASE_URL: https://forge.laravel.com/api/v1
  DEPLOYMENT_TIMEOUT: 600  # Increase if database clone is slow
  LOG_RETENTION: 30  # GitHub Actions log retention
```

## Documentation

**Quick Start** (30 min setup):
→ See: `docs/4-implementation/6-workflow-setup-checklist.md`

**Complete Guide** (understanding & advanced):
→ See: `docs/4-implementation/5-pr-testing-workflow-guide.md`

**Technical Reference** (API details & troubleshooting):
→ See: `WORKFLOW_REFERENCE.md` (this directory)

## Available Commands

### /preview

Create new test environment for PR

```
Comment: /preview
```

**What happens**:
1. Creates isolated site on Forge
2. Deploys your PR branch code
3. Clones database snapshot
4. Configures environment variables
5. Sets up queue workers
6. Enables SSL
7. Posts test URL in comment

**Duration**: 5-10 minutes

**Example URL**: `https://pr-123.on-forge.com`

### /update

Redeploy code to existing environment

```
Comment: /update
```

**What happens**:
1. Finds your test site
2. Pulls latest code from PR branch
3. Runs deployment script
4. Site available in ~2-3 minutes

**When to use**: After pushing new commits to PR

### /destroy

Delete test environment

```
Comment: /destroy
```

**What happens**:
1. Finds your test site
2. Deletes site and all data
3. Posts confirmation

**When to use**: Manual cleanup (or let auto-cleanup do it)

### Auto-Cleanup

Runs automatically when PR is closed (merged or rejected)

**What happens**:
1. Detects PR close event
2. Finds test environment
3. Deletes site
4. Posts cleanup confirmation

**No action needed** - happens automatically

## Permissions

Only users with **push access** to repository can trigger commands.

To grant access:
1. Settings → Collaborators
2. Add user with "Write" or "Admin" role

## Security

- Minimal workflow permissions (read contents, write PRs)
- Tokens stored securely in GitHub Secrets
- Each environment isolated (separate Linux user, database, cache)
- No hardcoded secrets in workflow
- Auto-cleanup prevents resource leaks

## Troubleshooting

### Common Issues

**"Permission denied"**
→ User doesn't have push access. Add as collaborator in Settings.

**"Site not found"**
→ Run `/preview` first to create environment.

**"Failed to create site"**
→ Check API token in GitHub Secrets. Regenerate if expired.

**"Timeout waiting for installation"**
→ Increase `DEPLOYMENT_TIMEOUT` in workflow. Check server resources.

**"HTTPS not working"**
→ Wait 10 minutes for Let's Encrypt. Refresh page.

### Get Help

1. **Quick fixes**: See "Common Issues" above
2. **More details**: See `WORKFLOW_REFERENCE.md` (Troubleshooting section)
3. **Complete guide**: See `docs/4-implementation/5-pr-testing-workflow-guide.md`

## Performance

| Task | Duration | Notes |
|------|----------|-------|
| Create environment | 5-10 min | Database clone is main bottleneck |
| Redeploy code | 2-3 min | Faster than create |
| Delete environment | <1 min | Instant |
| Auto-cleanup on close | ~2 min | Automatic, no action needed |

## API Rate Limits

Forge API limit: 60 requests/minute

Typical workflow usage:
- Create: ~15 requests (5-10 min)
- Update: ~5 requests (2-3 min)
- Destroy: ~3 requests (<1 min)

**Total daily**: ~50 requests (well under limit)

## Cost

Uses existing Forge server infrastructure.

Per environment cost: **Free** (uses shared resources)

Monthly overhead: ~$0 (within existing $20/month server)

## Next Steps

1. **Add secrets** (5 min)
   - See: `docs/4-implementation/6-workflow-setup-checklist.md`

2. **Test workflow** (10 min)
   - Comment `/preview` on test PR
   - Get test URL

3. **Share with team** (5 min)
   - Post link to guide in Slack/Teams

4. **Start testing** (ongoing)
   - Use `/preview` for new features
   - Share URLs with stakeholders

## Files

```
.github/
├── workflows/
│   ├── pr-testing.yml                 ← Main workflow file
│   ├── README.md                      ← This file
│   └── WORKFLOW_REFERENCE.md          ← Technical reference
│
docs/4-implementation/
├── 5-pr-testing-workflow-guide.md     ← Complete guide
└── 6-workflow-setup-checklist.md      ← Quick setup (30 min)
```

## Support

**Documentation**: https://forge.laravel.com/docs

**API Reference**: https://forge.laravel.com/api-documentation

**GitHub Actions**: https://docs.github.com/en/actions

---

**Version**: 1.0.0  
**Status**: Production Ready  
**Last Updated**: January 2025
