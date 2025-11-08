# Laravel Forge PR Testing System

🚀 **Complete API-driven PR testing automation for Laravel apps**

**Repository**: https://github.com/coder-r/laravel-forge-pr-testing

## Quick Start

```bash
# 1. Get Forge API token
export FORGE_API_TOKEN="your-token"

# 2. Create test environment (via API!)
./scripts/orchestrate-pr-system.sh \
  --pr-number 123 \
  --project-name keatchen-customer-app \
  --github-branch feature/new-feature

# 3. Access at:
https://pr-123-keatchen.on-forge.com

# Done in 5 minutes via Forge API!
```

## What This Does

**100% API-Driven** Laravel PR testing environments:

✅ Create VPS via Forge API (POST /api/v1/servers)
✅ Deploy Laravel sites via API (POST /api/v1/servers/{id}/sites)  
✅ Clone databases via API + SSH
✅ Monitor in real-time via API (GET /api/v1/servers/{id})
✅ Auto-cleanup via API (DELETE /api/v1/servers/{id})

**No manual Forge dashboard usage required!**

## Features

- **Laravel VPS**: <10 second provisioning via API
- **On-Forge.com Domains**: Instant DNS + SSL (no configuration)
- **Database Snapshots**: Weekend peak data for realistic testing
- **Driver Screen Testing**: See Saturday 6pm rush with timestamp shifting
- **Complete Automation**: GitHub Actions + Forge API
- **Cost**: $21/month ($15 Forge + $6 VPS usage)

## Documentation

📂 **[START HERE](./docs/0-README-START-HERE.md)** - Navigation guide

📖 **Key Docs**:
- [IMPLEMENTATION-PLAN.md](./IMPLEMENTATION-PLAN.md) - Complete phased approach
- [EXECUTE-NOW.md](./EXECUTE-NOW.md) - API implementation guide  
- [docs/1-QUICK-START.md](./docs/1-QUICK-START.md) - 15-minute overview

## API Scripts

All operations via Forge API v1:

- `scripts/lib/forge-api.sh` - Complete API client (24 functions)
- `scripts/orchestrate-pr-system.sh` - Create PR environment
- `scripts/implement-complete-system.sh` - Deploy entire system
- `scripts/monitor-via-api.sh` - Real-time monitoring
- `scripts/cleanup-environment.sh` - Destroy environments

## GitHub Actions

`.github/workflows/pr-testing.yml` - Complete automation:

```bash
# Comment on PR:
/preview

# GitHub Action runs:
# - Creates VPS via Forge API
# - Deploys code
# - Clones database
# - Posts URL: https://pr-123.on-forge.com

# Auto-cleanup on PR close
```

## Cost

**$21/month** for complete system:
- Forge account: $15/month
- VPS usage: ~$6/month (300 hours)
- Perfect for 1-3 developers, 1-3 concurrent PRs

## Timeline

**1 day to working system**:
- Read docs: 2 hours
- Configure API: 30 minutes
- Test via API: 30 minutes
- Deploy automation: 1 hour

## Support

- **Documentation**: [docs/](./docs/)
- **API Reference**: [docs/5-reference/1-forge-api-reference.md](./docs/5-reference/1-forge-api-reference.md)
- **Troubleshooting**: [docs/5-reference/2-troubleshooting.md](./docs/5-reference/2-troubleshooting.md)
- **Issues**: https://github.com/coder-r/laravel-forge-pr-testing/issues

---

**Built for**: keatchen-customer-app + devpel-epos
**Automated via**: Laravel Forge API v1
**Ready to**: Deploy today!
