#!/bin/bash

# GCP Nginx MIG Deployment - Environment Setup
# This script sets up the environment variables and enables required APIs

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== GCP Environment Setup ===${NC}"

# Check if PROJECT_ID is set
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}ERROR: PROJECT_ID environment variable is not set${NC}"
    echo "Please export your GCP project ID:"
    echo "export PROJECT_ID=your-project-id"
    exit 1
fi

# Export environment variables
export REGION=us-central1
export ZONE=us-central1-a
export MACHINE_TYPE=e2-micro
export IMAGE_FAMILY=ubuntu-2004-lts
export IMAGE_PROJECT=ubuntu-os-cloud

# Resource names
export VM_NAME=nginx-template-vm
export CUSTOM_IMAGE_NAME=nginx-custom-image
export INSTANCE_TEMPLATE_NAME=nginx-instance-template
export MIG_NAME=nginx-mig
export HEALTH_CHECK_NAME=nginx-health-check
export BACKEND_SERVICE_NAME=nginx-backend-service
export URL_MAP_NAME=nginx-url-map
export HTTP_PROXY_NAME=nginx-http-proxy
export FORWARDING_RULE_NAME=nginx-forwarding-rule

echo -e "${YELLOW}Environment Variables:${NC}"
echo "PROJECT_ID: $PROJECT_ID"
echo "REGION: $REGION"
echo "ZONE: $ZONE"
echo "MACHINE_TYPE: $MACHINE_TYPE"
echo ""

# Set default project
echo -e "${GREEN}Setting default project and region...${NC}"
gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

# Enable required APIs
echo -e "${GREEN}Enabling required APIs...${NC}"
gcloud services enable compute.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com

echo -e "${GREEN}Environment setup complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Run ./scripts/deploy-initial-vm.sh to deploy the initial VM"
echo "2. Run ./scripts/create-image.sh to create custom image"
echo "3. Run ./scripts/deploy-mig.sh to deploy managed instance group"
echo "4. Run ./scripts/setup-lb.sh to setup load balancer"
