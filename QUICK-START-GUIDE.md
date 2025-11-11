# ⚡ Quick Start Guide

## One-Command PR Testing (5 Minutes)

### Setup (One Time)
```bash
cd /home/dev/project-analysis/laravel-forge-pr-testing

# Token already saved in .forge-token ✅
# SSH keys already configured ✅
```

### Create PR Test Site
```bash
./create-pr-site.sh feature-branch-name
```

That's it! Wait 5 minutes.

### Cleanup When Done
```bash
./destroy-pr-site.sh
```

---

## What Gets Created

- ✅ Forge site: pr-{branch}.on-forge.com
- ✅ PHP 8.3, 2GB memory
- ✅ GitHub code cloned (your branch)
- ✅ 77,909 orders from production
- ✅ All dependencies installed
- ✅ Ready to test!

---

## Files to Know

- **create-pr-site.sh** - Creates PR site
- **destroy-pr-site.sh** - Deletes PR site
- **LESSONS-LEARNED.md** - Everything we discovered
- **START-NEXT-TIME.md** - Resume guide

---

## GitHub

https://github.com/coder-r/laravel-forge-pr-testing

**8 commits, 30+ files, complete automation!**
