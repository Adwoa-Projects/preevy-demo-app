# Preevy Demo App Documentation

## Overview

This **Preevy Demo App** demonstrates how to integrate [Preevy](https://preevy.dev) with a containerized application to create automated preview environments for pull requests. While the application itself is a simple React/Vite boilerplate, the focus is on showcasing Preevy's capabilities for:

- **Automated PR Preview Environments**: Spin up isolated environments for each pull request
- **Google Cloud Integration**: Deploy containers to GCP using Preevy
- **GitHub Actions Automation**: Seamless CI/CD pipeline for preview deployments
- **Docker Containerization**: Production-ready container setup optimized for Preevy

## Preevy Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitHub PR     │───▶│ GitHub Actions  │───▶│ Preevy Engine   │
│   (Trigger)     │    │   (Workflow)    │    │  (Orchestrator) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                                              ┌─────────────────┐
                                              │ Google Cloud    │
                                              │  (Infrastructure)│
                                              └─────────────────┘
                                                       │
                                              ┌─────────────────┐
                                              │ Docker Container│
                                              │  (Application)  │
                                              └─────────────────┘
```

## Key Preevy Components

### 1. Docker Configuration
The application is containerized for consistent deployment across environments.

### 2. GitHub Actions Workflows
- **preevy-up.yml**: Deploys preview environments on PR events
- **preevy-down.yml**: Cleans up environments when PRs are closed

### 3. Google Cloud Platform Integration
- Service account authentication for cloud resource management
- Dynamic provisioning of compute resources per preview environment

### 4. Docker Compose Service Definition
- Defines the application stack for Preevy to deploy

## Docker Configuration Deep Dive

### Dockerfile Analysis

The `Dockerfile` implements a **multi-stage build** optimized for Preevy deployments:

```dockerfile
# ---- Build stage ----
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# ---- Runtime stage ----
FROM node:22-alpine
WORKDIR /app
RUN npm i -g serve
COPY --from=build /app/dist ./dist

# Run as non-root user
RUN chown -R node:node /app
USER node

EXPOSE 3000
CMD ["serve", "-s", "dist", "-l", "3000"]
```

#### Key Design Decisions for Preevy:

1. **Multi-stage Build**: Reduces final image size by excluding build dependencies
2. **Alpine Linux**: Minimal base image for faster deployments
3. **Non-root User**: Security best practice for cloud deployments
4. **Static File Serving**: Uses `serve` package for production-ready static hosting
5. **Port 3000**: Standardized port that Preevy can reliably expose

#### Docker Compose Configuration

```yaml
services:
  frontend:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - '3000:3000'
    restart: always
    networks: [appnet]

networks:
  appnet: {}
```

- **Restart Policy**: Ensures service availability in cloud environments
- **Network Isolation**: Creates dedicated network for the service
- **Port Mapping**: Exposes application on port 3000 for Preevy URL generation

## Google Cloud Platform Setup for Preevy

### Prerequisites
To run this Preevy demo, you need:

1. **Google Cloud Project** with billing enabled
2. **Service Account** with appropriate permissions
3. **Preevy Profile** configured for GCP

### Required GCP Permissions

The service account used by Preevy needs these IAM roles:
- `Compute Engine Admin` - For creating/managing VM instances
- `Compute Network Admin` - For VPC and firewall management
- `Cloud Build Editor` - For container image building (if needed)
- `Storage Admin` - For storing Preevy state and logs

### Service Account Setup

#### Using Google Cloud Console (Recommended)

1. **Navigate to IAM & Admin > Service Accounts** in the Google Cloud Console
2. **Click "Create Service Account"**
3. **Enter Service Account Details**:
   - Name: `preevy-sa` (or your preferred name)
   - Description: "Service account for Preevy deployments"
   - Click "Create and Continue"

4. **Assign Required Roles**:
   - Add `Compute Engine Admin` role
   - Add `Compute Network Admin` role
   - Add `Storage Admin` role (for Preevy state storage)
   - Click "Continue"

5. **Create and Download Key**:
   - Click "Create Key"
   - Select "JSON" format
   - Download the key file (save as `preevy-sa-key.json`)
   - Store securely and add to GitHub secrets

#### Alternative: CLI Setup
You can also create the service account using the `gcloud` CLI if you prefer command-line tools.

### Preevy Profile Configuration

This demo uses a Preevy profile stored in Google Cloud Storage, created and managed through the Preevy CLI.

#### Creating the Profile

1. **Install Preevy CLI**:
   ```bash
   npm install -g preevy
   ```

2. **Initialize Profile**:
   ```bash
   preevy profile create gce my-profile --project-id YOUR_PROJECT_ID
   ```

3. **Configure Profile Settings**:
   The CLI will prompt you to configure:
   - **Machine Type**: e2-micro (for demo) or larger for production workloads
   - **Zone**: us-central1-a (or your preferred zone)
   - **Network**: default VPC or custom network
   - **Storage Options**: Profile stored in GCS bucket

4. **Upload Profile to Cloud Storage**:
   The profile is automatically stored in a GCS bucket and a URL is generated for access.

#### Profile Storage in GCS

- Preevy creates a dedicated GCS bucket for profile storage
- The profile URL format: `gs://preevy-profiles-[hash]/[profile-name].json`
- This URL is used in the `PREEVY_PROFILE_URL` GitHub variable
- Benefits:
  - **Centralized**: Accessible from any CI/CD environment
  - **Secure**: Uses GCP IAM for access control
  - **Versioned**: Profile changes are tracked
  - **Shared**: Multiple team members can use the same profile

#### Key Profile Settings for This Demo

The profile typically includes:
- **Driver**: `gce` (Google Compute Engine)
- **Machine Type**: `e2-micro` (cost-effective for demos)
- **Boot Disk**: 20GB persistent disk
- **Network**: Default VPC with automatic firewall rules
- **Labels**: Environment tags for resource management

### GitHub Secrets Configuration

Add these secrets to your GitHub repository:

| Secret Name | Description | Value |
|-------------|-------------|-------|
| `PREEVY_SA_KEY` | GCP service account key | Contents of `preevy-sa-key.json` |

### GitHub Variables Configuration

Add these variables to your GitHub repository:

| Variable Name | Description | Value |
|---------------|-------------|-------|
| `PREEVY_PROFILE_URL` | Preevy profile configuration | URL to your profile config |

## GitHub Actions Workflows

### Preevy Up Workflow (`preevy-up.yml`)

This workflow creates preview environments when PRs are opened, reopened, or updated:

```yaml
name: Deploy Preevy environment
on:
  pull_request:
    types:
      - opened
      - reopened
      - synchronize
permissions:
  id-token: write
  contents: read
  pull-requests: write
concurrency: preevy-${{ github.event.number }}
```

#### Key Components:

1. **Trigger Events**:
   - `opened`: New PR created
   - `reopened`: Closed PR reopened
   - `synchronize`: New commits pushed to PR

2. **Permissions**:
   - `id-token: write`: For OIDC authentication with GCP
   - `pull-requests: write`: To post preview URLs as comments

3. **Concurrency Control**:
   - Ensures only one deployment per PR runs at a time
   - Cancels previous runs if new commits are pushed

4. **Environment Configuration**:
   ```yaml
   environment:
     name: pr-${{ github.event.number }}
     url: ${{ fromJson(steps.preevy_up.outputs.urls-map).frontend[3000] }}
   ```
   - Creates GitHub environment named after PR number
   - Dynamically sets environment URL from Preevy output

5. **GCP Authentication**:
   ```yaml
   - name: 'Authenticate to Google Cloud'
     uses: 'google-github-actions/auth@v1'
     with:
       credentials_json: '${{ secrets.PREEVY_SA_KEY }}'
   ```

6. **Preevy Deployment**:
   ```yaml
   - uses: livecycle/preevy-up-action@v2.4.0
     id: preevy_up
     with:
       install: gh-release
       profile-url: ${{ vars.PREEVY_PROFILE_URL }}
   ```

### Preevy Down Workflow (`preevy-down.yml`)

This workflow cleans up preview environments when PRs are closed:

```yaml
name: Teardown Preevy environment
on:
  pull_request:
    types:
      - closed
permissions:
  id-token: write
  contents: read
concurrency: preevy-${{ github.event.number }}
```

#### Key Components:

1. **Cleanup Process**:
   ```yaml
   - uses: livecycle/preevy-down-action@v1.4.0
     with:
       profile-url: ${{ vars.PREEVY_PROFILE_URL }}
       install: gh-release
       args: '--force'
   ```
   - `--force`: Ensures environment is torn down even if errors occur
   - Removes GCP resources (VMs, networks, storage)
   - Cleans up Preevy state

### Workflow Benefits

1. **Cost Optimization**: Automatic cleanup prevents resource waste
2. **Isolation**: Each PR gets its own environment
3. **Fast Feedback**: Developers see changes in live environment
4. **Security**: Proper authentication and permission scoping

## Preevy Deployment Flow

### Step-by-Step Process

1. **PR Creation/Update**
   - Developer creates PR or pushes new commits
   - GitHub webhook triggers `preevy-up.yml` workflow

2. **Environment Preparation**
   - GitHub Actions authenticates with GCP using service account
   - Preevy reads profile configuration
   - Determines resource requirements

3. **Infrastructure Provisioning**
   - Preevy creates GCP VM instance
   - Sets up networking and firewall rules
   - Configures Docker environment on VM

4. **Application Deployment**
   - Docker image is built from repository
   - Container is deployed to provisioned VM
   - Service is exposed via generated URL

5. **Notification**
   - Preview URL is posted to PR as comment
   - GitHub environment is updated with URL
   - Deployment status is reported

6. **Cleanup (PR Closure)**
   - `preevy-down.yml` workflow triggered
   - All GCP resources are destroyed
   - Costs stop accumulating immediately

### Preview Environment Features

- **Unique URLs**: Each PR gets a distinct subdomain
- **Automatic SSL**: HTTPS certificates automatically provisioned
- **Isolated Resources**: No shared state between environments
- **Real-time Updates**: New commits trigger redeployments

## Getting Started with This Demo

### Prerequisites
- GitHub repository with admin access
- Google Cloud Platform account with billing enabled
- Basic understanding of Docker and GitHub Actions

### Setup Steps

1. **Fork this repository**
2. **Set up GCP service account** (see GCP Setup section)
3. **Configure Preevy profile** for your GCP project
4. **Add GitHub secrets and variables**
5. **Create a test pull request** to trigger deployment

### Testing the Demo

1. **Create a Feature Branch**:
   ```bash
   git checkout -b test-preevy-demo
   ```

2. **Make a Simple Change**:
   - Edit `src/App.jsx` to change the title
   - Commit and push changes

3. **Create Pull Request**:
   - Open PR from your branch to main
   - Watch GitHub Actions logs for deployment progress

4. **Access Preview Environment**:
   - Check PR comments for preview URL
   - Visit the URL to see your changes live

5. **Test Updates**:
   - Make additional commits to the PR
   - Observe automatic redeployments

6. **Cleanup**:
   - Close or merge the PR
   - Verify environment is torn down

## Troubleshooting Preevy Issues

### Common Problems

1. **Authentication Failures**
   ```
   Error: Unable to authenticate with Google Cloud
   ```
   - Verify `PREEVY_SA_KEY` secret is correctly formatted JSON
   - Check service account has required permissions
   - Ensure GCP project billing is enabled

2. **Profile Configuration Issues**
   ```
   Error: Failed to load Preevy profile
   ```
   - Verify `PREEVY_PROFILE_URL` points to accessible configuration
   - Check profile YAML syntax
   - Ensure GCP quotas are sufficient

3. **Deployment Timeouts**
   ```
   Error: Deployment timed out
   ```
   - Check GCP VM instance creation in console
   - Verify Docker image builds successfully locally
   - Review firewall and networking configuration

4. **Resource Cleanup Issues**
   ```
   Warning: Some resources may not have been cleaned up
   ```
   - Manually check GCP console for orphaned resources
   - Use `--force` flag in preevy-down action
   - Verify service account delete permissions

### Debug Commands

When troubleshooting locally:

```bash
# Test Docker build
docker build -t preevy-demo-app .

# Test container locally
docker run -p 3000:3000 preevy-demo-app

# Validate Preevy profile
preevy profile validate

# Check Preevy logs
preevy logs --environment pr-123
```

## Best Practices for Preevy

### Resource Management
- Set appropriate machine types for your workload
- Use preemptible instances for cost savings
- Configure auto-scaling policies if needed
- Monitor costs and set billing alerts

### Security
- Use least-privilege service account permissions
- Regularly rotate service account keys
- Enable audit logging for compliance
- Use private networks when possible

### Performance
- Optimize Docker images for faster deployments
- Use multi-stage builds to reduce image size
- Cache dependencies appropriately
- Consider using regional persistent disks

### Monitoring
- Set up alerts for failed deployments
- Monitor resource utilization
- Track deployment times and success rates
- Use structured logging for better debugging

## Cost Considerations

### Typical Costs for This Demo
- **e2-micro VM**: ~$0.006/hour
- **Network egress**: Minimal for demo traffic
- **Storage**: ~$0.04/month for 20GB disk

### Cost Optimization Tips
- Use smallest sufficient machine type
- Enable automatic cleanup (already configured)
- Set GCP billing alerts
- Use preemptible instances for non-critical testing
- Monitor and cleanup orphaned resources

## Extending This Demo

### Adding Services
To demonstrate multi-service applications:
```yaml
# compose.yml
services:
  frontend:
    # ... existing config
  backend:
    build: ./backend
    ports:
      - "8080:8080"
  database:
    image: postgres:15
    environment:
      POSTGRES_DB: demo
```

### Custom Domains
Configure custom domain routing in Preevy profile:
```yaml
# preevy-profile.yml
tunnel:
  domain: preview.yourdomain.com
  ssl: true
```

### Environment Variables
Add environment-specific configuration:
```yaml
# compose.yml
services:
  frontend:
    environment:
      - REACT_APP_API_URL=${API_URL:-http://localhost:8080}
      - REACT_APP_ENV=preview
```

This demo provides a solid foundation for understanding Preevy's capabilities and can be extended to demonstrate more complex deployment scenarios.