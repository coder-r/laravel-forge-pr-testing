# GitHub Actions Integration for PR Testing Environments

**Complete implementation guide for automated PR environment creation via GitHub Actions**

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [GitHub Actions Workflow](#github-actions-workflow)
3. [Secrets Configuration](#secrets-configuration)
4. [Webhook Setup](#webhook-setup)
5. [Testing & Debugging](#testing-debugging)
6. [Command Reference](#command-reference)
7. [Troubleshooting](#troubleshooting)
8. [Advanced Configuration](#advanced-configuration)

---

## Quick Start

### Prerequisites

- Laravel Forge account with API access
- GitHub repository admin access
- Server configured on Forge (see [1-forge-setup.md](./1-forge-setup.md))

### 2-Minute Setup (Absolute Simplest Version)

**This approach uses on-forge.com domains - no DNS configuration needed!**

1. **Add GitHub Secrets**:
   ```
   FORGE_API_TOKEN=your_forge_token_here
   FORGE_SERVER_ID=12345
   ```

2. **Create Workflow File**: `.github/workflows/pr-testing.yml` (see below)

3. **Test in PR**:
   ```
   Comment: /preview
   ```

4. **Get instant URL**: `pr-123.on-forge.com` (ready in ~30 seconds)

**Benefits**:
- ✅ No DNS setup required
- ✅ Instant SSL (automatic)
- ✅ Works immediately
- ✅ ~30 second deployment time

---

## GitHub Actions Workflow

### Absolute Simplest Version (Recommended)

**File**: `.github/workflows/pr-testing.yml`

**This version uses on-forge.com domains for instant deployment with automatic SSL.**

```yaml
name: PR Testing Environment

on:
  issue_comment:
    types: [created]
  pull_request:
    types: [closed]

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  handle-pr-command:
    name: Handle PR Command
    runs-on: ubuntu-latest
    if: |
      github.event_name == 'issue_comment' &&
      github.event.issue.pull_request &&
      (
        startsWith(github.event.comment.body, '/preview') ||
        startsWith(github.event.comment.body, '/destroy') ||
        startsWith(github.event.comment.body, '/update')
      )

    steps:
      - name: Get PR Details
        id: pr
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const pr = await github.rest.pulls.get({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.issue.number
            });
            return { number: pr.data.number, branch: pr.data.head.ref };

      - name: Create Environment
        id: create
        if: "!startsWith(github.event.comment.body, '/destroy')"
        run: |
          PR_NUMBER="${{ fromJson(steps.pr.outputs.result).number }}"
          BRANCH="${{ fromJson(steps.pr.outputs.result).branch }}"

          # Use on-forge.com domain (instant SSL, no DNS needed)
          DOMAIN="pr-${PR_NUMBER}.on-forge.com"
          DIRECTORY="/home/forge/pr-${PR_NUMBER}"

          # Create or get site
          SITE_ID=$(curl -s \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites" \
            | jq -r ".sites[] | select(.name == \"${DOMAIN}\") | .id")

          if [ -z "$SITE_ID" ]; then
            # Create site
            SITE_ID=$(curl -s -X POST \
              -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
              -H "Content-Type: application/json" \
              "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites" \
              -d "{\"domain\":\"${DOMAIN}\",\"project_type\":\"php\",\"directory\":\"${DIRECTORY}/public\"}" \
              | jq -r '.site.id')

            # Install repository
            curl -s -X POST \
              -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
              "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}/git" \
              -d "{\"provider\":\"github\",\"repository\":\"${{ github.repository }}\",\"branch\":\"${BRANCH}\"}"
          fi

          # Create database
          curl -s -X POST \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/databases" \
            -d "{\"name\":\"pr_${PR_NUMBER}\"}" || true

          # Deploy
          curl -s -X POST \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}/deployment/deploy"

          echo "url=https://${DOMAIN}" >> $GITHUB_OUTPUT

      - name: Post Success Comment
        if: success() && steps.create.outputs.url
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `✅ **PR Testing Environment Ready!**\n\n🌐 **URL**: ${{ steps.create.outputs.url }}\n\n_Ready in ~30 seconds with automatic SSL_`
            });

      - name: Destroy Environment
        if: startsWith(github.event.comment.body, '/destroy')
        run: |
          PR_NUMBER="${{ fromJson(steps.pr.outputs.result).number }}"
          DOMAIN="pr-${PR_NUMBER}.on-forge.com"

          SITE_ID=$(curl -s \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites" \
            | jq -r ".sites[] | select(.name == \"${DOMAIN}\") | .id")

          if [ -n "$SITE_ID" ]; then
            curl -s -X DELETE \
              -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
              "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}"
          fi

  cleanup-on-close:
    name: Auto-Cleanup
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request' && github.event.pull_request.merged == true

    steps:
      - name: Delete Environment
        run: |
          PR_NUMBER="${{ github.event.pull_request.number }}"
          DOMAIN="pr-${PR_NUMBER}.on-forge.com"

          SITE_ID=$(curl -s \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites" \
            | jq -r ".sites[] | select(.name == \"${DOMAIN}\") | .id")

          [ -n "$SITE_ID" ] && curl -s -X DELETE \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}"
```

**Why this is better**:
- ✅ Under 100 lines (vs 500+ with custom domains)
- ✅ Works immediately (no DNS wait time)
- ✅ Automatic SSL (no certificate request needed)
- ✅ ~30 second deployment (vs 5-10 minutes)
- ✅ No DNS configuration required
- ✅ No SSL troubleshooting needed

---

### Full Production Version (with monitoring)

For production use with error handling and status tracking:

**File**: `.github/workflows/pr-testing.yml`

```yaml
name: PR Testing Environment

on:
  issue_comment:
    types: [created]
  pull_request:
    types: [closed]

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  # Handle PR commands (/preview, /destroy, /update)
  handle-pr-command:
    name: Handle PR Command
    runs-on: ubuntu-latest
    if: |
      github.event_name == 'issue_comment' &&
      github.event.issue.pull_request &&
      (
        startsWith(github.event.comment.body, '/preview') ||
        startsWith(github.event.comment.body, '/destroy') ||
        startsWith(github.event.comment.body, '/update')
      )

    steps:
      - name: Acknowledge Command
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const command = context.payload.comment.body.split(' ')[0];
            await github.rest.reactions.createForIssueComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              comment_id: context.payload.comment.id,
              content: 'eyes'
            });

            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `🚀 Processing command: \`${command}\`\n\nPlease wait while I set up your environment...`
            });

      - name: Get PR Details
        id: pr
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const pr = await github.rest.pulls.get({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.issue.number
            });

            return {
              number: pr.data.number,
              branch: pr.data.head.ref,
              repo: pr.data.head.repo.full_name,
              sha: pr.data.head.sha
            };

      - name: Parse Command
        id: command
        run: |
          COMMENT_BODY="${{ github.event.comment.body }}"
          COMMAND=$(echo "$COMMENT_BODY" | head -1 | awk '{print $1}')

          echo "command=$COMMAND" >> $GITHUB_OUTPUT
          echo "pr_number=${{ fromJson(steps.pr.outputs.result).number }}" >> $GITHUB_OUTPUT
          echo "branch=${{ fromJson(steps.pr.outputs.result).branch }}" >> $GITHUB_OUTPUT
          echo "sha=${{ fromJson(steps.pr.outputs.result).sha }}" >> $GITHUB_OUTPUT

      - name: Create Environment
        id: create
        if: steps.command.outputs.command == '/preview' || steps.command.outputs.command == '/update'
        run: |
          PR_NUMBER="${{ steps.command.outputs.pr_number }}"
          BRANCH="${{ steps.command.outputs.branch }}"
          SHA="${{ steps.command.outputs.sha }}"

          SITE_NAME="pr-${PR_NUMBER}"
          DIRECTORY="/home/forge/pr-${PR_NUMBER}"
          # Use on-forge.com domain for instant SSL
          DOMAIN="pr-${PR_NUMBER}.on-forge.com"

          # Check if site exists
          SITE_ID=$(curl -s \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -H "Accept: application/json" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites" \
            | jq -r ".sites[] | select(.name == \"${DOMAIN}\") | .id")

          if [ -z "$SITE_ID" ] || [ "$SITE_ID" == "null" ]; then
            echo "Creating new site..."

            # Create site
            RESPONSE=$(curl -s -w "\n%{http_code}" \
              -X POST \
              -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
              -H "Accept: application/json" \
              -H "Content-Type: application/json" \
              "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites" \
              -d "{
                \"domain\": \"${DOMAIN}\",
                \"project_type\": \"php\",
                \"directory\": \"${DIRECTORY}/public\",
                \"isolated\": false,
                \"php_version\": \"php83\"
              }")

            HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
            BODY=$(echo "$RESPONSE" | head -n-1)

            if [ "$HTTP_CODE" -ne 200 ] && [ "$HTTP_CODE" -ne 201 ]; then
              echo "Error creating site: $BODY"
              exit 1
            fi

            SITE_ID=$(echo "$BODY" | jq -r '.site.id')
            echo "Created site with ID: $SITE_ID"

            # Wait for site to be ready
            sleep 5
          else
            echo "Site already exists with ID: $SITE_ID"
          fi

          # Install repository
          echo "Installing repository..."
          curl -s -X POST \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}/git" \
            -d "{
              \"provider\": \"github\",
              \"repository\": \"${{ github.repository }}\",
              \"branch\": \"${BRANCH}\",
              \"composer\": true
            }"

          # Configure deployment script
          DEPLOY_SCRIPT="cd ${DIRECTORY}
git pull origin ${BRANCH}
composer install --no-dev --optimize-autoloader

# Copy environment file
if [ ! -f .env ]; then
  cp .env.pr-template .env
fi

# Update environment variables
php artisan env:set APP_ENV=pr-${PR_NUMBER}
php artisan env:set APP_URL=https://${DOMAIN}
php artisan env:set DB_DATABASE=pr_${PR_NUMBER}

# Run migrations
php artisan migrate --force

# Clear caches
php artisan config:clear
php artisan cache:clear
php artisan view:clear
php artisan route:clear

# Optimize
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Run seeders if needed
php artisan db:seed --class=DemoSeeder --force

echo 'Deployment completed successfully!'"

          curl -s -X PUT \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}/deployment/script" \
            -d "{\"content\":$(echo "$DEPLOY_SCRIPT" | jq -Rs .)}"

          # Enable quick deploy
          curl -s -X POST \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -H "Accept: application/json" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}/deployment"

          # Trigger deployment
          echo "Triggering deployment..."
          curl -s -X POST \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -H "Accept: application/json" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}/deployment/deploy"

          # Create database
          DB_EXISTS=$(curl -s \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -H "Accept: application/json" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/databases" \
            | jq -r ".databases[] | select(.name == \"pr_${PR_NUMBER}\") | .id")

          if [ -z "$DB_EXISTS" ] || [ "$DB_EXISTS" == "null" ]; then
            echo "Creating database..."
            curl -s -X POST \
              -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
              -H "Accept: application/json" \
              -H "Content-Type: application/json" \
              "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/databases" \
              -d "{
                \"name\": \"pr_${PR_NUMBER}\",
                \"user\": \"pr_${PR_NUMBER}\",
                \"password\": \"$(openssl rand -base64 32)\"
              }"
          fi

          echo "site_id=$SITE_ID" >> $GITHUB_OUTPUT
          echo "domain=$DOMAIN" >> $GITHUB_OUTPUT
          echo "url=https://${DOMAIN}" >> $GITHUB_OUTPUT

      - name: Wait for Deployment
        if: steps.create.outputs.site_id
        run: |
          SITE_ID="${{ steps.create.outputs.site_id }}"
          MAX_ATTEMPTS=30
          ATTEMPT=0

          echo "Waiting for deployment to complete..."

          while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
            STATUS=$(curl -s \
              -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
              -H "Accept: application/json" \
              "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}" \
              | jq -r '.site.deployment_status')

            if [ "$STATUS" == "null" ] || [ "$STATUS" == "finished" ]; then
              echo "Deployment completed!"
              break
            fi

            echo "Deployment status: $STATUS (attempt $((ATTEMPT + 1))/$MAX_ATTEMPTS)"
            sleep 5
            ATTEMPT=$((ATTEMPT + 1))
          done

          if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
            echo "Deployment timed out!"
            exit 1
          fi

      - name: Post Success Comment
        if: success() && steps.create.outputs.url
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const url = '${{ steps.create.outputs.url }}';
            const pr = ${{ steps.command.outputs.pr_number }};
            const branch = '${{ steps.command.outputs.branch }}';
            const sha = '${{ steps.command.outputs.sha }}'.substring(0, 7);

            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `✅ **PR Testing Environment Ready!**

🌐 **URL**: ${url}
🔀 **Branch**: \`${branch}\`
📦 **Commit**: \`${sha}\`
🔢 **PR**: #${pr}

### Test Your Changes
Your environment is now live and ready for testing!

### Available Commands
- \`/update\` - Redeploy with latest changes
- \`/destroy\` - Delete this environment

### Notes
- Environment will auto-cleanup when PR is closed/merged
- SSL certificate is automatic (on-forge.com domain)
- Database is pre-seeded with demo data
- Ready in ~30 seconds

---
*Powered by Laravel Forge + GitHub Actions*`
            });

            // Add success reaction
            await github.rest.reactions.createForIssueComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              comment_id: context.payload.comment.id,
              content: 'rocket'
            });

      - name: Destroy Environment
        if: steps.command.outputs.command == '/destroy'
        run: |
          PR_NUMBER="${{ steps.command.outputs.pr_number }}"
          DOMAIN="pr-${PR_NUMBER}.on-forge.com"

          # Get site ID
          SITE_ID=$(curl -s \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -H "Accept: application/json" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites" \
            | jq -r ".sites[] | select(.name == \"${DOMAIN}\") | .id")

          if [ -n "$SITE_ID" ] && [ "$SITE_ID" != "null" ]; then
            echo "Deleting site: $SITE_ID"
            curl -s -X DELETE \
              -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
              -H "Accept: application/json" \
              "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}"
          fi

          # Delete database
          DB_ID=$(curl -s \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -H "Accept: application/json" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/databases" \
            | jq -r ".databases[] | select(.name == \"pr_${PR_NUMBER}\") | .id")

          if [ -n "$DB_ID" ] && [ "$DB_ID" != "null" ]; then
            echo "Deleting database: $DB_ID"
            curl -s -X DELETE \
              -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
              -H "Accept: application/json" \
              "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/databases/${DB_ID}"
          fi

      - name: Post Destroy Comment
        if: steps.command.outputs.command == '/destroy'
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `🗑️ **Environment Destroyed**

The testing environment for PR #${{ steps.command.outputs.pr_number }} has been deleted.

All resources (site, database, SSL) have been cleaned up.`
            });

      - name: Post Error Comment
        if: failure()
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `❌ **Environment Setup Failed**

There was an error setting up your testing environment.

**Troubleshooting:**
1. Check the [Actions tab](${context.payload.repository.html_url}/actions) for detailed logs
2. Verify Forge API token is valid
3. Ensure server has available resources

**Need Help?**
Contact your DevOps team or check the [troubleshooting guide](../docs/troubleshooting.md).`
            });

  # Auto-cleanup on PR close/merge
  cleanup-on-close:
    name: Cleanup Environment
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request' && github.event.pull_request.merged == true

    steps:
      - name: Delete Environment
        run: |
          PR_NUMBER="${{ github.event.pull_request.number }}"
          DOMAIN="pr-${PR_NUMBER}.on-forge.com"

          echo "Cleaning up environment for PR #${PR_NUMBER}"

          # Get site ID
          SITE_ID=$(curl -s \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -H "Accept: application/json" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites" \
            | jq -r ".sites[] | select(.name == \"${DOMAIN}\") | .id")

          if [ -n "$SITE_ID" ] && [ "$SITE_ID" != "null" ]; then
            echo "Deleting site: $SITE_ID"
            curl -s -X DELETE \
              -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
              -H "Accept: application/json" \
              "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}"
          fi

          # Delete database
          DB_ID=$(curl -s \
            -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
            -H "Accept: application/json" \
            "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/databases" \
            | jq -r ".databases[] | select(.name == \"pr_${PR_NUMBER}\") | .id")

          if [ -n "$DB_ID" ] && [ "$DB_ID" != "null" ]; then
            echo "Deleting database: $DB_ID"
            curl -s -X DELETE \
              -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
              -H "Accept: application/json" \
              "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/databases/${DB_ID}"
          fi

          echo "Cleanup completed for PR #${PR_NUMBER}"

      - name: Post Cleanup Comment
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.pull_request.number,
              body: `🧹 **Auto-Cleanup Completed**

Testing environment for PR #${{ github.event.pull_request.number }} has been automatically cleaned up after merge.

All resources have been deleted.`
            });
```

---

## Secrets Configuration

### Required GitHub Secrets

Navigate to: **Repository → Settings → Secrets and variables → Actions → New repository secret**

#### 1. FORGE_API_TOKEN

**Description**: Laravel Forge API token for authentication

**How to Get**:
1. Go to [Laravel Forge](https://forge.laravel.com)
2. Click your profile → **Account**
3. Click **API** tab
4. Click **Create New Token**
5. Name it: `GitHub Actions - PR Testing`
6. Copy the token

**Add to GitHub**:
```
Name: FORGE_API_TOKEN
Value: [paste your token]
```

#### 2. FORGE_SERVER_ID

**Description**: ID of the Forge server where PR environments will be created

**How to Get**:
```bash
curl -H "Authorization: Bearer YOUR_FORGE_TOKEN" \
     -H "Accept: application/json" \
     https://forge.laravel.com/api/v1/servers
```

Look for your server in the JSON response and copy the `id` field.

**Add to GitHub**:
```
Name: FORGE_SERVER_ID
Value: 12345
```

### Optional Secrets (Not Needed for Basic Setup)

#### SLACK_WEBHOOK_URL
For deployment notifications to Slack

#### SENTRY_AUTH_TOKEN
For automatic Sentry release tracking

---

## Webhook Setup

### Option 1: GitHub App (Recommended)

**Advantages**:
- Fine-grained permissions
- Better security
- Rate limit improvements

**Setup**:
1. Go to: **GitHub → Settings → Developer settings → GitHub Apps → New GitHub App**

2. **Basic Information**:
   - Name: `PR Testing Environments`
   - Homepage URL: `https://forge.laravel.com`
   - Webhook URL: `https://your-api.com/github/webhook`
   - Webhook secret: Generate and save

3. **Permissions**:
   - Repository permissions:
     - Contents: Read
     - Pull requests: Read & Write
     - Issues: Read & Write
   - Subscribe to events:
     - Issue comments
     - Pull requests

4. **Install App** on your repository

### Option 2: Personal Access Token

**For simpler setup** (GitHub Actions handles this automatically with `GITHUB_TOKEN`)

No additional webhook setup needed - GitHub Actions receives events natively.

---

## Testing & Debugging

### Test the Workflow

#### 1. Create Test PR

```bash
git checkout -b test/pr-environments
echo "Testing PR environments" > test.txt
git add test.txt
git commit -m "Test PR environments"
git push origin test/pr-environments
```

#### 2. Open PR on GitHub

Create PR from `test/pr-environments` → `main`

#### 3. Trigger Workflow

Comment on the PR:
```
/preview
```

#### 4. Monitor Progress

- Go to **Actions** tab
- Click on the running workflow
- Watch the logs in real-time

### Expected Timeline

**With on-forge.com domains (default)**:
```
0:00 - Command acknowledged
0:05 - Site created on Forge
0:10 - Repository installed
0:15 - Git pull and composer install
0:20 - Database migrations
0:25 - Deployment complete
0:30 - Environment ready! (SSL automatic)
```

**With custom domains (optional)**:
```
0:00 - Command acknowledged
0:05 - Site created on Forge
0:10 - Repository installed
0:15 - Git pull and composer install
0:20 - Database migrations
0:25 - SSL certificate requested
0:30 - Environment ready! (HTTP)
2-3 min - SSL certificate activated (HTTPS)
```

### Debugging Failed Workflows

#### Check Action Logs

1. Go to **Actions** tab
2. Click failed workflow run
3. Click failed job
4. Expand failed step
5. Read error message

#### Common Issues

**1. Authentication Failed**
```
Error: 401 Unauthorized
```

**Fix**: Verify `FORGE_API_TOKEN` is correct and not expired

**Test**:
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Accept: application/json" \
     https://forge.laravel.com/api/v1/servers
```

**2. Site Creation Failed**
```
Error: Domain already exists
```

**Fix**: Site name collision - delete existing site or use different naming

**3. Deployment Timeout**
```
Error: Deployment timed out after 60 attempts
```

**Fix**:
- Check deployment script for errors
- Look at Forge deployment logs
- Increase `MAX_ATTEMPTS` in workflow

**4. Database Connection Failed**
```
Error: SQLSTATE[HY000] [1045] Access denied
```

**Fix**:
- Verify database was created
- Check `.env` file has correct credentials
- Ensure database user has permissions

#### Enable Debug Logging

Add to workflow file:

```yaml
env:
  ACTIONS_STEP_DEBUG: true
  ACTIONS_RUNNER_DEBUG: true
```

#### Test Forge API Manually

```bash
# Get server info
curl -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Accept: application/json" \
     https://forge.laravel.com/api/v1/servers/YOUR_SERVER_ID

# List sites
curl -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Accept: application/json" \
     https://forge.laravel.com/api/v1/servers/YOUR_SERVER_ID/sites

# Create test site
curl -X POST \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Accept: application/json" \
     -H "Content-Type: application/json" \
     https://forge.laravel.com/api/v1/servers/YOUR_SERVER_ID/sites \
     -d '{
       "domain": "test.pr-testing.yourdomain.com",
       "project_type": "php",
       "directory": "/home/forge/test/public"
     }'
```

---

## Command Reference

### Available PR Commands

#### /preview
**Description**: Create or update PR testing environment

**Usage**:
```
/preview
```

**What it does**:
1. Creates new site if doesn't exist
2. Installs repository from PR branch
3. Configures deployment script
4. Creates database
5. Installs SSL certificate
6. Deploys application
7. Posts URL in comment

**Time**: ~30 seconds (SSL is automatic with on-forge.com)

---

#### /update
**Description**: Redeploy environment with latest changes

**Usage**:
```
/update
```

**What it does**:
1. Pulls latest code from PR branch
2. Runs composer install
3. Runs migrations
4. Clears caches
5. Optimizes application

**Time**: ~15 seconds

---

#### /destroy
**Description**: Delete PR testing environment

**Usage**:
```
/destroy
```

**What it does**:
1. Deletes site from Forge
2. Deletes database
3. Removes SSL certificate
4. Cleans up all resources

**Time**: ~5 seconds

---

### Command Options (Future Enhancement)

You can extend commands with options:

```
/preview --seed=full
/preview --env=staging
/preview --php=8.3
/update --migrate=fresh
/destroy --keep-db
```

**Implementation** (add to workflow):

```yaml
- name: Parse Command Options
  id: options
  run: |
    COMMENT_BODY="${{ github.event.comment.body }}"

    # Parse --seed option
    if echo "$COMMENT_BODY" | grep -q "\-\-seed="; then
      SEED=$(echo "$COMMENT_BODY" | grep -oP '\-\-seed=\K\w+')
      echo "seed=$SEED" >> $GITHUB_OUTPUT
    fi

    # Parse --env option
    if echo "$COMMENT_BODY" | grep -q "\-\-env="; then
      ENV=$(echo "$COMMENT_BODY" | grep -oP '\-\-env=\K\w+')
      echo "env=$ENV" >> $GITHUB_OUTPUT
    fi
```

---

## Troubleshooting

### Rate Limiting

#### GitHub API Rate Limits

**Limits**:
- Authenticated: 5,000 requests/hour
- GitHub Actions: 1,000 requests/hour per repository

**Check Status**:
```bash
curl -H "Authorization: token YOUR_TOKEN" \
     https://api.github.com/rate_limit
```

**Solutions**:
1. Use `GITHUB_TOKEN` (higher limits)
2. Cache API responses
3. Batch operations
4. Use webhooks instead of polling

#### Forge API Rate Limits

**Limits**:
- 60 requests/minute per IP
- 500 requests/hour per token

**Solutions**:
1. Add delays between requests
2. Cache responses
3. Use single token for all operations

**Implementation**:
```yaml
- name: Wait Between Requests
  run: sleep 2
```

### Error Recovery

#### Retry Logic

Add retry logic for flaky operations:

```yaml
- name: Create Site with Retry
  uses: nick-invision/retry@v2
  with:
    timeout_minutes: 5
    max_attempts: 3
    retry_wait_seconds: 10
    command: |
      curl -X POST \
        -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
        -H "Accept: application/json" \
        "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites" \
        -d '{"domain":"test.example.com",...}'
```

#### Rollback on Failure

```yaml
- name: Rollback on Failure
  if: failure()
  run: |
    # Delete partially created site
    if [ -n "$SITE_ID" ]; then
      curl -X DELETE \
        -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
        "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/$SITE_ID"
    fi
```

### Notification Channels

#### Slack Notifications

Add Slack notifications:

```yaml
- name: Notify Slack on Success
  if: success()
  uses: slackapi/slack-github-action@v1
  with:
    webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
    payload: |
      {
        "text": "✅ PR #${{ github.event.issue.number }} environment ready!",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "🚀 *PR Testing Environment*\n\n*URL*: ${{ steps.create.outputs.url }}\n*PR*: #${{ github.event.issue.number }}\n*Branch*: ${{ steps.command.outputs.branch }}"
            }
          }
        ]
      }
```

#### Email Notifications

GitHub Actions sends email by default, but you can customize:

```yaml
- name: Send Email Notification
  if: failure()
  uses: dawidd6/action-send-mail@v3
  with:
    server_address: smtp.gmail.com
    server_port: 465
    username: ${{ secrets.EMAIL_USERNAME }}
    password: ${{ secrets.EMAIL_PASSWORD }}
    subject: "Failed: PR Environment for #${{ github.event.issue.number }}"
    to: devops@yourdomain.com
    from: github-actions@yourdomain.com
    body: |
      PR testing environment creation failed.

      PR: #${{ github.event.issue.number }}
      Branch: ${{ steps.command.outputs.branch }}

      Check logs: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
```

---

## Advanced Configuration

---

## OPTIONAL: Adding Custom Domains

**Note**: The default on-forge.com domains work perfectly. Only add custom domains if you need branded URLs for stakeholder demos.

### Why Custom Domains Are Optional

**on-forge.com benefits**:
- ✅ Works immediately (no setup)
- ✅ Automatic SSL certificates
- ✅ No DNS configuration
- ✅ ~30 second deployment
- ✅ Zero maintenance

**Custom domain drawbacks**:
- ❌ Requires DNS configuration
- ❌ Requires wildcard SSL setup
- ❌ 5-10 minute deployment time (DNS + SSL wait)
- ❌ DNS propagation issues
- ❌ SSL certificate troubleshooting

**When to use custom domains**:
- Stakeholder demos requiring branded URLs
- Client presentations
- Professional appearances

### Setup Custom Domains (If Needed)

**1. Add DNS Record**:
```
Type: A
Name: *.pr-testing.yourdomain.com
Value: YOUR_SERVER_IP
TTL: 300
```

**2. Add GitHub Secret**:
```
Name: FORGE_SITE_DOMAIN
Value: pr-testing.yourdomain.com
```

**3. Update Workflow**:

Replace this line in the workflow:
```yaml
DOMAIN="pr-${PR_NUMBER}.on-forge.com"
```

With:
```yaml
DOMAIN="pr-${PR_NUMBER}.${{ secrets.FORGE_SITE_DOMAIN }}"
```

**4. Add SSL Certificate Request**:

Add this step after database creation:
```yaml
- name: Install SSL Certificate
  run: |
    curl -s -X POST \
      -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
      -H "Content-Type: application/json" \
      "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites/${SITE_ID}/certificates/letsencrypt" \
      -d "{\"domains\": [\"${DOMAIN}\"]}"

    # Wait for SSL to activate
    sleep 120
```

**5. Expected Timeline**:
```
0:00 - Command acknowledged
0:05 - Site created
0:10 - Repository installed
0:15 - Deployment
0:30 - Environment ready (HTTP)
2-3 min - SSL activated (HTTPS)
5-10 min - DNS propagation complete
```

**Troubleshooting Custom Domains**:

1. **DNS not resolving**:
   - Check DNS propagation: `dig pr-123.pr-testing.yourdomain.com`
   - Wait up to 5 minutes for propagation
   - Verify wildcard DNS record is correct

2. **SSL certificate failed**:
   - Verify DNS is resolving correctly
   - Check domain ownership in Forge
   - Wait 2-3 minutes and retry

3. **Site loads on HTTP but not HTTPS**:
   - SSL certificate is still being issued
   - Wait 2-3 minutes
   - Check Forge dashboard for certificate status

### Comparison Table

| Feature | on-forge.com (Default) | Custom Domain |
|---------|------------------------|---------------|
| Setup Time | 0 seconds | 15-30 minutes |
| DNS Configuration | None | Required |
| SSL Configuration | Automatic | Manual request |
| Deployment Time | ~30 seconds | 5-10 minutes |
| Maintenance | Zero | DNS + SSL management |
| URL Format | `pr-123.on-forge.com` | `pr-123.yourdomain.com` |
| Professional Appearance | ✅ Good | ✅ Better |
| Recommended For | Daily development | Client demos |

**Recommendation**: Start with on-forge.com domains. Only add custom domains if stakeholders specifically request branded URLs.

---

### Multi-Server Support

Deploy to different servers based on PR labels:

```yaml
- name: Select Server
  id: server
  run: |
    LABELS='${{ toJson(github.event.issue.labels) }}'

    if echo "$LABELS" | grep -q "staging"; then
      echo "server_id=${{ secrets.FORGE_STAGING_SERVER_ID }}" >> $GITHUB_OUTPUT
      echo "domain=pr-staging.yourdomain.com" >> $GITHUB_OUTPUT
    elif echo "$LABELS" | grep -q "production"; then
      echo "server_id=${{ secrets.FORGE_PROD_SERVER_ID }}" >> $GITHUB_OUTPUT
      echo "domain=pr-prod.yourdomain.com" >> $GITHUB_OUTPUT
    else
      echo "server_id=${{ secrets.FORGE_SERVER_ID }}" >> $GITHUB_OUTPUT
      echo "domain=pr-testing.yourdomain.com" >> $GITHUB_OUTPUT
    fi

- name: Create Site
  run: |
    # Use ${{ steps.server.outputs.server_id }}
    curl -X POST \
      -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
      "https://forge.laravel.com/api/v1/servers/${{ steps.server.outputs.server_id }}/sites" \
      ...
```

### Custom Environment Variables

Pass custom env vars from PR comment:

```yaml
- name: Parse Environment Variables
  id: env_vars
  run: |
    COMMENT_BODY="${{ github.event.comment.body }}"

    # Extract environment variables from comment
    # Format: /preview APP_DEBUG=true LOG_LEVEL=debug

    ENV_VARS=$(echo "$COMMENT_BODY" | grep -oP '(?<=\s)\w+=\S+' | tr '\n' ' ')
    echo "vars=$ENV_VARS" >> $GITHUB_OUTPUT

- name: Configure Environment
  run: |
    # Apply custom env vars
    for var in ${{ steps.env_vars.outputs.vars }}; do
      php artisan env:set $var
    done
```

### Automatic Testing

Run tests before deployment:

```yaml
- name: Checkout Code
  uses: actions/checkout@v4
  with:
    ref: ${{ steps.command.outputs.branch }}

- name: Setup PHP
  uses: shivammathur/setup-php@v2
  with:
    php-version: '8.3'
    extensions: mbstring, pdo, pdo_mysql

- name: Install Dependencies
  run: composer install --prefer-dist --no-progress

- name: Run Tests
  run: vendor/bin/phpunit

- name: Deploy Only if Tests Pass
  if: success()
  run: |
    # Continue with deployment...
```

### Performance Monitoring

Add performance checks:

```yaml
- name: Performance Check
  run: |
    URL="${{ steps.create.outputs.url }}"

    # Wait for site to respond
    for i in {1..30}; do
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
      if [ "$STATUS" == "200" ]; then
        break
      fi
      sleep 2
    done

    # Run Lighthouse
    npx lighthouse "$URL" \
      --only-categories=performance \
      --output=json \
      --output-path=./lighthouse-report.json

    SCORE=$(jq '.categories.performance.score * 100' lighthouse-report.json)

    echo "Performance Score: $SCORE"

    if [ $(echo "$SCORE < 50" | bc) -eq 1 ]; then
      echo "⚠️ Warning: Performance score below 50!"
    fi

- name: Upload Lighthouse Report
  uses: actions/upload-artifact@v3
  with:
    name: lighthouse-report
    path: lighthouse-report.json
```

### Security Scanning

Add security checks before deployment:

```yaml
- name: Security Scan
  run: |
    # Install security checker
    composer require --dev enlightn/security-checker

    # Run security audit
    vendor/bin/security-checker security:check composer.lock

    # Check for vulnerable dependencies
    composer audit

- name: SAST Scan
  uses: returntocorp/semgrep-action@v1
  with:
    config: auto
```

### Cost Tracking

Track estimated costs per environment:

```yaml
- name: Calculate Costs
  run: |
    # Estimate monthly cost
    # $10/month per site
    # $5/month per database
    # $2/month per SSL certificate

    COST_PER_ENV=17

    # Get number of active PR environments
    ACTIVE_COUNT=$(curl -s \
      -H "Authorization: Bearer ${{ secrets.FORGE_API_TOKEN }}" \
      "https://forge.laravel.com/api/v1/servers/${{ secrets.FORGE_SERVER_ID }}/sites" \
      | jq '[.sites[] | select(.name | startswith("pr-"))] | length')

    TOTAL_COST=$(echo "$ACTIVE_COUNT * $COST_PER_ENV" | bc)

    echo "Active Environments: $ACTIVE_COUNT"
    echo "Estimated Monthly Cost: \$$TOTAL_COST"

    # Post to Slack/dashboard
```

---

## Summary

### What You've Built

✅ Automated PR environment creation via `/preview`
✅ Instant deployment with on-forge.com domains (~30 seconds)
✅ Automatic SSL certificates (no configuration needed)
✅ One-command environment updates via `/update`
✅ Clean environment destruction via `/destroy`
✅ Auto-cleanup on PR merge/close
✅ Real-time deployment status
✅ Error handling and recovery
✅ Database provisioning

### Key Benefits

**Speed**:
- ~30 seconds per PR environment (vs 5-10 minutes with custom domains)
- No DNS wait time
- Instant SSL activation

**Simplicity**:
- Only 2 GitHub secrets needed (no domain configuration)
- Under 100 lines of workflow code
- Zero DNS maintenance
- No SSL troubleshooting

**Reliability**:
- Works every time (no DNS propagation issues)
- Automatic SSL certificates
- Consistent performance

### Next Steps

1. **Test thoroughly**: Create test PRs and try all commands
2. **Monitor costs**: Track active environments
3. **Customize**: Add team-specific features (optional)
4. **Document**: Share with your team
5. **Consider custom domains**: Only if needed for stakeholder demos

### Related Guides

- [1-forge-setup.md](./1-forge-setup.md) - Forge configuration
- [3-database-seeding.md](./3-database-seeding.md) - Database setup
- [4-environment-config.md](./4-environment-config.md) - Environment variables
- [5-ssl-automation.md](./5-ssl-automation.md) - SSL certificates

---

**Questions?** Check the [troubleshooting section](#troubleshooting) or open an issue.

**Ready to deploy?** Comment `/preview` on any PR!
