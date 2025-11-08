# Claude Code Configuration - Laravel Forge PR Testing System

## Project Purpose
Automated PR testing environments for Laravel applications using Laravel Forge VPS with on-forge.com domains.

## Key Features
- Laravel VPS provisioning via Forge API
- On-forge.com domains (no DNS setup)
- Weekend peak database snapshots
- Cost-optimized: $21/month
- Complete automation via API

## Important Instructions
- Use Forge API for ALL operations (no manual Forge dashboard usage)
- All scripts use real API endpoints (https://forge.laravel.com/api/v1)
- API token stored in environment variables (never hardcoded)
- Follow documentation structure for all new docs

## Quick Commands
- `./scripts/implement-complete-system.sh` - Deploy entire system via API
- `./scripts/orchestrate-pr-system.sh` - Create single PR environment via API
- `./scripts/monitor-via-api.sh` - Real-time monitoring dashboard
