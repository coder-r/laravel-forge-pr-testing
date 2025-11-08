# Laravel PR Testing Environment - Developer Guide

## 📋 How to Use This Documentation

This documentation will guide you through setting up an automated PR testing environment system for your Laravel applications using Laravel Forge.

### Step 1: Quick Overview (15 minutes)
**Start here →** [1-QUICK-START.md](./1-QUICK-START.md)

Get the executive summary: what you're building, why, costs, and timeline.

### Step 2: Background Reading (1-2 hours)
**Understand the context →** [2-background-reading/](./2-background-reading/)

- [1-requirements-analysis.md](./2-background-reading/1-requirements-analysis.md) - Detailed requirements and user needs
- [2-forge-capabilities.md](./2-background-reading/2-forge-capabilities.md) - Laravel Forge features and API capabilities
- [3-infrastructure-overview.md](./2-background-reading/3-infrastructure-overview.md) - Current infrastructure and projects

### Step 3: Critical Reading (2-3 hours)
⚠️ **READ BEFORE CODING!** → [3-critical-reading/](./3-critical-reading/)

- [1-architecture-design.md](./3-critical-reading/1-architecture-design.md) - Complete system architecture
- [2-security-considerations.md](./3-critical-reading/2-security-considerations.md) - Security, database, and access controls
- [3-database-strategy.md](./3-critical-reading/3-database-strategy.md) - Database replication and snapshot strategy
- [4-forge-vps-modernization.md](./3-critical-reading/4-forge-vps-modernization.md) - **NEW!** Laravel VPS features (10x faster setup!)
- [5-on-forge-domains-quick-start.md](./3-critical-reading/5-on-forge-domains-quick-start.md) - **START HERE!** No DNS setup required! (1 day to working system)
- [6-cost-optimized-setup.md](./3-critical-reading/6-cost-optimized-setup.md) - **BUDGET-FRIENDLY!** Complete setup for $6/month
- [7-realistic-test-data-strategy.md](./3-critical-reading/7-realistic-test-data-strategy.md) - **WEEKEND PEAK DATA!** Test with real Saturday 6pm data
- [8-testing-with-live-peak-data.md](./3-critical-reading/8-testing-with-live-peak-data.md) - **DRIVER SCREEN TESTING!** See screens as they were at peak

### Step 4: Implementation (2-5 days)
**Follow these steps →** [4-implementation/](./4-implementation/)

- [1-forge-setup-checklist.md](./4-implementation/1-forge-setup-checklist.md) - Forge server and initial setup
- [2-github-integration.md](./4-implementation/2-github-integration.md) - GitHub Actions and webhook setup
- [3-automation-scripts.md](./4-implementation/3-automation-scripts.md) - Scripts for site creation and cleanup
- [4-deployment-workflow.md](./4-implementation/4-deployment-workflow.md) - End-to-end deployment process

### Step 5: Reference Materials (as needed)
**Lookup information →** [5-reference/](./5-reference/)

- [1-forge-api-reference.md](./5-reference/1-forge-api-reference.md) - Quick Forge API reference
- [2-troubleshooting.md](./5-reference/2-troubleshooting.md) - Common issues and solutions
- [3-cost-breakdown.md](./5-reference/3-cost-breakdown.md) - Detailed cost analysis

## 📁 Folder Structure

```
emphermal-llaravel-app/
├── README.md                           ← Project overview
├── CLAUDE.md                          ← Configuration (existing)
└── docs/
    ├── 0-README-START-HERE.md         ← This file
    ├── 1-QUICK-START.md               ← 15-min summary
    ├── 2-background-reading/          ← Context & analysis
    │   ├── 1-requirements-analysis.md
    │   ├── 2-forge-capabilities.md
    │   └── 3-infrastructure-overview.md
    ├── 3-critical-reading/            ← Must-read architecture
    │   ├── 1-architecture-design.md
    │   ├── 2-security-considerations.md
    │   └── 3-database-strategy.md
    ├── 4-implementation/              ← Step-by-step guides
    │   ├── 1-forge-setup-checklist.md
    │   ├── 2-github-integration.md
    │   ├── 3-automation-scripts.md
    │   └── 4-deployment-workflow.md
    └── 5-reference/                   ← Lookup materials
        ├── 1-forge-api-reference.md
        ├── 2-troubleshooting.md
        └── 3-cost-breakdown.md
```

## 🔴 CRITICAL FOCUS AREAS

Before implementing, make sure you understand:

1. **Database Strategy** ([3-critical-reading/3-database-strategy.md](./3-critical-reading/3-database-strategy.md))
   - How weekend evening snapshots provide realistic data
   - Database replication process
   - Privacy and data handling

2. **Architecture Design** ([3-critical-reading/1-architecture-design.md](./3-critical-reading/1-architecture-design.md))
   - Wildcard subdomain setup (*.staging.kitthub.com)
   - Site isolation for security
   - GitHub webhook trigger flow

3. **Security** ([3-critical-reading/2-security-considerations.md](./3-critical-reading/2-security-considerations.md))
   - API token management
   - Environment variable handling
   - Access controls for test environments

## ✅ Pre-Implementation Checklist

Before starting implementation, ensure you have:

- [ ] Read and understood the Quick Start guide
- [ ] Reviewed all critical reading documents
- [ ] Access to Laravel Forge account with API token
- [ ] Admin access to both GitHub repositories
- [ ] DNS management access for *.staging.kitthub.com wildcard
- [ ] Understanding of peak hours (weekend evenings) for DB snapshots
- [ ] Forge server with sufficient resources (or budget to create one)

## 🎯 Success Criteria

You'll know the system is working when:

1. ✅ Developer comments `/preview` on a PR
2. ✅ GitHub Action triggers and creates Forge site
3. ✅ Site appears at `pr-123.staging.kitthub.com` within 5-10 minutes
4. ✅ Database is populated with weekend snapshot data
5. ✅ Queue workers (Horizon) are running
6. ✅ Stakeholders can access and test the feature
7. ✅ Site auto-deletes when PR is merged/closed

## 🚀 Getting Started Now

**Your next step:** Open [1-QUICK-START.md](./1-QUICK-START.md) and spend 15 minutes understanding the big picture.

## 💡 Quick Tips

- **Don't skip Section 3** (Critical Reading) - it contains architecture decisions that affect everything else
- **Database snapshots** are taken from weekend evenings - this is when you get the most realistic test data
- **Both projects** (keatchen-customer-app and devpel-epos) use the same infrastructure pattern
- **Timeline is aggressive** (1-2 weeks) but achievable with proper planning
- **Testing is manual initially** - automated testing can be added later

## 📞 Questions?

Refer to [5-reference/2-troubleshooting.md](./5-reference/2-troubleshooting.md) for common issues, or check the Forge documentation at https://forge.laravel.com/docs
