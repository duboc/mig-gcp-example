# GCP Nginx Managed Instance Group Deployment Example

This repository provides a complete example of deploying nginx on Google Cloud Platform using:
- **Cloud Config** for automated nginx installation and configuration
- **Custom Image** creation for consistent deployments
- **Managed Instance Groups (MIG)** for auto-scaling and high availability
- **HTTP Load Balancer** for traffic distribution
- **Health Checks** for monitoring instance health

All deployments are done using the `gcloud` CLI with fully automated bash scripts.

## 🏗️ Architecture Overview

```
Internet → Load Balancer → Backend Service → MIG → nginx Instances
                    ↓
               Health Checks
```

**Components:**
- **Load Balancer**: HTTP(S) Load Balancer with external IP
- **Backend Service**: Routes traffic to healthy instances
- **Health Check**: Monitors `/health` endpoint on port 80
- **MIG**: Auto-scales between 2-5 instances based on CPU utilization (60%)
- **Instance Template**: Based on custom nginx image
- **Custom Image**: Ubuntu 20.04 + nginx + custom configuration
- **Cloud Config**: Automated nginx installation and setup

## 📋 Prerequisites

1. **GCP Project**: Active GCP project with billing enabled
2. **gcloud CLI**: Installed and configured
   ```bash
   # Install gcloud CLI (if not already installed)
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Authenticate
   gcloud auth login
   gcloud auth application-default login
   ```
3. **Required APIs**: Will be enabled automatically by the setup script
4. **Permissions**: Compute Engine Admin or Editor role

## 🚀 Quick Start

### Option 1: All-in-One Deployment (Recommended for Quick Testing)
```bash
git clone <repository-url>
cd mig-gcp-example

# Update PROJECT_ID in all-in-one.sh, then run:
./all-in-one.sh
```

### Option 2: Step-by-Step Deployment (Recommended for Learning)
```bash
git clone <repository-url>
cd mig-gcp-example

# Export your GCP project ID
export PROJECT_ID=your-project-id-here

# Setup environment and enable APIs
./scripts/setup.sh

# Deploy initial VM with nginx
./scripts/deploy-initial-vm.sh

# Create custom image from VM
./scripts/create-image.sh

# Deploy managed instance group
./scripts/deploy-mig.sh

# Setup load balancer
./scripts/setup-lb.sh
```

### 3. Test Your Deployment
After deployment, you'll receive a load balancer IP. Test with:
```bash
# Basic connectivity test
curl http://LOAD_BALANCER_IP

# Health check test
curl http://LOAD_BALANCER_IP/health

# Load testing (install apache2-utils first)
ab -n 1000 -c 10 http://LOAD_BALANCER_IP/
```

## 📁 Project Structure

```
mig-gcp-example/
├── scripts/                    # Step-by-step deployment scripts
│   ├── setup.sh              # Environment setup and API enablement
│   ├── deploy-initial-vm.sh   # Deploy VM with cloud-config
│   ├── create-image.sh        # Create custom image from VM
│   ├── deploy-mig.sh          # Deploy managed instance group
│   ├── setup-lb.sh           # Setup HTTP load balancer
│   └── cleanup.sh            # Clean up all resources
├── configs/
│   └── nginx-cloud-config.yaml # Cloud-init configuration
├── all-in-one.sh             # Complete deployment in single script
├── clean-up-all-in-one.sh    # Enhanced cleanup with verification
├── load-test.sh              # Load testing script using bombardier
├── example-load-test.md      # Load testing usage examples
└── README.md                 # This file
```

## 📜 Detailed Script Descriptions

### Core Deployment Scripts (Step-by-Step)

#### `setup.sh`
- Sets environment variables for consistent naming
- Enables required GCP APIs
- Configures gcloud defaults
- **Prerequisites**: `PROJECT_ID` environment variable

#### `deploy-initial-vm.sh`
- Creates HTTP firewall rule
- Deploys VM instance with cloud-config
- Waits for nginx to be ready
- Verifies deployment with health checks
- **Output**: Running VM with nginx

#### `create-image.sh`
- Stops the VM instance
- Creates custom image from VM disk
- Optionally deletes original VM
- **Output**: Custom image ready for instance template

#### `deploy-mig.sh`
- Creates instance template using custom image
- Deploys managed instance group
- Configures auto-scaling (2-5 instances, 60% CPU target)
- Sets named ports for load balancer integration
- **Output**: MIG with auto-scaling enabled

#### `setup-lb.sh`
- Creates HTTP health check
- Creates backend service
- Adds MIG as backend
- Creates URL map and HTTP proxy
- Creates forwarding rule with external IP
- Tests load balancer connectivity
- **Output**: Fully functional HTTP load balancer

#### `cleanup.sh`
- Safely removes all created resources
- Provides verification of cleanup
- Interactive prompts for confirmation
- **Result**: Clean project state

### All-in-One Scripts

#### `all-in-one.sh`
- **Complete deployment in a single script**
- Hardcoded project variables (edit PROJECT_ID before use)
- Creates cloud-config file automatically
- Deploys entire infrastructure from scratch to load balancer
- Includes Ops Agent policy setup
- Automatically cleans up intermediate resources
- **Prerequisites**: Update PROJECT_ID and network variables in script
- **Output**: Fully functional nginx deployment with load balancer

#### `clean-up-all-in-one.sh`
- **Enhanced cleanup with comprehensive verification**
- Colored output and progress tracking
- Resource existence verification before deletion
- Proper deletion order to avoid dependency conflicts
- Post-cleanup verification
- Interactive and force modes
- List mode to view resources without deletion
- **Usage**: `./clean-up-all-in-one.sh [--force|--list]`

### Load Testing Scripts

#### `load-test.sh`
- **Comprehensive load testing using Bombardier**
- Multiple test scenarios: basic, rate-limited, stress, sustained
- Real-time MIG monitoring during tests
- Health checks and service validation
- Endpoint-specific testing (main page and /health)
- **Prerequisites**: bombardier installed, update PROJECT_ID in script
- **Usage**: `./load-test.sh [health|basic|rate|stress|endpoints|sustained|all]`

## ⚙️ Configuration Details

### Auto-scaling Configuration
- **Minimum instances**: 2 (high availability)
- **Maximum instances**: 5 (cost control)
- **Target CPU utilization**: 60%
- **Cool-down period**: 60 seconds

### Health Check Configuration
- **Protocol**: HTTP
- **Port**: 80
- **Path**: `/health`
- **Check interval**: 10 seconds
- **Timeout**: 5 seconds
- **Healthy threshold**: 2 consecutive successes
- **Unhealthy threshold**: 3 consecutive failures

### Instance Configuration
- **Machine type**: e2-micro (cost-effective)
- **Operating system**: Ubuntu 20.04 LTS
- **Disk**: 10GB balanced persistent disk
- **Network**: Premium tier
- **Security**: Shielded VM enabled

## 🎛️ Environment Variables

The following variables are set in `setup.sh`:

| Variable | Default Value | Description |
|----------|---------------|-------------|
| `PROJECT_ID` | *user-defined* | Your GCP project ID |
| `REGION` | `us-central1` | GCP region |
| `ZONE` | `us-central1-a` | GCP zone |
| `MACHINE_TYPE` | `e2-micro` | Instance machine type |
| `IMAGE_FAMILY` | `ubuntu-2004-lts` | Base OS image family |

## 🌐 Cloud Config Features

The `nginx-cloud-config.yaml` includes:

- **Automated package installation**: nginx, curl
- **Custom HTML page**: Shows instance metadata and styling
- **Health check endpoint**: `/health` returns "healthy"
- **Security configuration**: UFW firewall, server tokens disabled
- **Logging**: Deployment completion logging
- **Custom nginx configuration**: Optimized for load balancing

## ☁️ Understanding Cloud-Config

### What is Cloud-Config?

Cloud-config is a YAML-based configuration format used by [cloud-init](https://cloud-init.readthedocs.io/), a standard for cloud instance initialization. It allows you to automate the setup and configuration of VM instances during their first boot, making deployments consistent and repeatable.

### How It Works in This Example

When a GCP VM instance starts, cloud-init reads the `user-data` metadata (our cloud-config file) and executes the specified configuration:

1. **Package Management**: Updates packages and installs required software
2. **File Creation**: Creates configuration files and web content
3. **Service Configuration**: Starts and enables services
4. **Security Setup**: Configures firewall and security settings

### Key Sections Breakdown

#### 1. Package Management
```yaml
package_update: true  # Updates package lists
packages:            # Installs specified packages
  - nginx
  - curl
```

#### 2. File Creation
```yaml
write_files:
  - path: /var/www/html/index.html
    content: |
      # Your HTML content here
    permissions: '0644'
    owner: www-data:www-data
```

**Key parameters:**
- `path`: Absolute file path
- `content`: File contents (supports multi-line with `|`)
- `permissions`: Unix file permissions (octal format)
- `owner`: File ownership (user:group)

#### 3. Command Execution
```yaml
runcmd:
  - systemctl enable nginx
  - systemctl start nginx
  - ufw allow 'Nginx Full'
```

**Important**: Commands run as root and execute in order.

### Customization Examples

#### Add Custom Packages
```yaml
packages:
  - nginx
  - curl
  - htop
  - git
  - python3-pip
```

#### Create Multiple Configuration Files
```yaml
write_files:
  - path: /etc/nginx/sites-available/api
    content: |
      server {
        listen 8080;
        location /api {
          proxy_pass http://localhost:3000;
        }
      }
    permissions: '0644'
  
  - path: /opt/app/config.json
    content: |
      {
        "database_url": "postgres://localhost:5432/myapp",
        "redis_url": "redis://localhost:6379"
      }
    permissions: '0600'
    owner: app:app
```

#### Set Environment Variables
```yaml
write_files:
  - path: /etc/environment
    content: |
      ENVIRONMENT=production
      LOG_LEVEL=info
      API_KEY=your-api-key
    append: true
```

### Best Practices

#### 1. Idempotency
Make commands idempotent (safe to run multiple times):
```yaml
runcmd:
  - [ sh, -c, "nginx -t && systemctl reload nginx || systemctl start nginx" ]
  - [ sh, -c, "ufw status | grep -q 'Status: active' || ufw --force enable" ]
```

#### 2. Error Handling
Use conditional execution:
```yaml
runcmd:
  - command -v docker >/dev/null 2>&1 || curl -fsSL https://get.docker.com | sh
  - [ sh, -c, "if ! id appuser >/dev/null 2>&1; then useradd -m appuser; fi" ]
```

#### 3. Security Considerations
```yaml
write_files:
  - path: /etc/ssl/private/app.key
    content: |
      -----BEGIN PRIVATE KEY-----
      # Your private key here
      -----END PRIVATE KEY-----
    permissions: '0600'  # Restrict access
    owner: root:root
```

### Troubleshooting Cloud-Config

#### Check Status and Logs
```bash
# Check cloud-init status
sudo cloud-init status
sudo cloud-init status --long

# View logs
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log
```

#### Validate Configuration
```bash
# Test YAML syntax
python3 -c "import yaml; yaml.safe_load(open('configs/nginx-cloud-config.yaml'))"

# Validate cloud-config schema
sudo cloud-init schema --config-file configs/nginx-cloud-config.yaml
```

This comprehensive cloud-config foundation enables you to build automated, consistent, and maintainable infrastructure deployments across your GCP environment.

## 📊 Monitoring and Management

### Monitor Instance Status
```bash
# List MIG instances
gcloud compute instance-groups managed list-instances nginx-mig --zone=us-central1-a

# Check backend health
gcloud compute backend-services get-health nginx-backend-service --global

# Monitor auto-scaling
watch -n 5 'gcloud compute instance-groups managed describe nginx-mig --zone=us-central1-a --format="value(targetSize)"'
```

### Load Testing

#### Option 1: Using Bombardier (Recommended)
```bash
# Install bombardier
brew install bombardier              # macOS
# OR download from: https://github.com/codesenberg/bombardier/releases

# Update PROJECT_ID in load-test.sh, then run tests:
./load-test.sh health               # Check service health
./load-test.sh basic                # Basic load test (60s, 50 connections)
./load-test.sh basic 120s 100       # Custom duration and connections
./load-test.sh rate 60s 200         # Rate-limited test (200 req/s)
./load-test.sh stress               # Stress test with increasing load
./load-test.sh sustained 300s 75    # 5-minute sustained test with monitoring
./load-test.sh endpoints            # Test specific endpoints
./load-test.sh all                  # Run complete test suite
```

#### Option 2: Using Apache Bench
```bash
# Install Apache Bench
sudo apt-get install apache2-utils  # Ubuntu/Debian
brew install apache2-utils          # macOS

# Run load test
ab -n 1000 -c 10 http://LOAD_BALANCER_IP/
```

### Scaling Commands
```bash
# Manual scaling
gcloud compute instance-groups managed resize nginx-mig --size=3 --zone=us-central1-a

# Update auto-scaling parameters
gcloud compute instance-groups managed set-autoscaling nginx-mig \
    --zone=us-central1-a \
    --max-num-replicas=10 \
    --min-num-replicas=3 \
    --target-cpu-utilization=70
```

## 🧹 Cleanup

### Option 1: Enhanced Cleanup (Recommended)
```bash
# Update PROJECT_ID and other variables in clean-up-all-in-one.sh, then run:
./clean-up-all-in-one.sh               # Interactive cleanup with verification
./clean-up-all-in-one.sh --force       # Skip confirmation prompts
./clean-up-all-in-one.sh --list        # List resources without deleting
```

### Option 2: Basic Cleanup
```bash
./scripts/cleanup.sh
```

The enhanced cleanup script provides:
- ✅ Resource verification before deletion
- ✅ Colored output and progress tracking
- ✅ Proper deletion order to avoid dependency issues
- ✅ Post-cleanup verification
- ✅ Better error handling and reporting

Both scripts will safely delete:
- Load balancer components
- Managed instance group and instances
- Instance template
- Custom image
- Original VM (if exists)
- Firewall rules (optional)
- Ops Agent policies

## 💰 Cost Considerations

**Estimated monthly costs** (us-central1, as of 2025):
- **2x e2-micro instances**: ~$12/month
- **Load balancer**: ~$22/month
- **Network egress**: Variable based on traffic
- **Persistent disks**: ~$4/month

**Cost optimization tips**:
- Use preemptible instances for dev/test
- Adjust auto-scaling parameters
- Use regional persistent disks
- Monitor and optimize traffic patterns

## 🔧 Troubleshooting

### Common Issues

1. **"Permission denied" errors**
   ```bash
   # Ensure proper authentication
   gcloud auth login
   gcloud auth application-default login
   ```

2. **"API not enabled" errors**
   ```bash
   # Re-run setup script
   ./scripts/setup.sh
   ```

3. **Load balancer not responding**
   - Wait 5-10 minutes for full propagation
   - Check backend health status
   - Verify firewall rules

4. **Instances not starting**
   ```bash
   # Check cloud-init logs
   gcloud compute instances get-serial-port-output INSTANCE_NAME --zone=us-central1-a
   ```

### Useful Debug Commands

```bash
# Check cloud-init status
gcloud compute ssh INSTANCE_NAME --zone=us-central1-a --command="sudo cloud-init status"

# View nginx logs
gcloud compute ssh INSTANCE_NAME --zone=us-central1-a --command="sudo journalctl -u nginx"

# Test internal connectivity
gcloud compute ssh INSTANCE_NAME --zone=us-central1-a --command="curl localhost/health"
```

## 🔐 Security Best Practices

This example includes several security features:
- **Firewall rules**: Only allow necessary traffic
- **Shielded VMs**: Protection against rootkits and bootkits
- **Service accounts**: Minimal required permissions
- **Health checks**: Ensure only healthy instances serve traffic
- **Server tokens disabled**: Reduce information disclosure

For production use, consider:
- **HTTPS/SSL termination**
- **Cloud Armor** for DDoS protection
- **VPC firewall rules** for internal traffic
- **IAM roles** with principle of least privilege
- **Cloud KMS** for secret management

## 📚 Additional Resources

- [GCP Compute Engine Documentation](https://cloud.google.com/compute/docs)
- [Load Balancer Documentation](https://cloud.google.com/load-balancing/docs)
- [Cloud-init Documentation](https://cloud-init.readthedocs.io/)
- [Instance Groups Documentation](https://cloud.google.com/compute/docs/instance-groups)

## 🤝 Contributing

Feel free to submit issues and enhancement requests. This example is designed to be educational and can be extended for production use cases.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
