#!/bin/bash

# GCP Nginx MIG Deployment - Deploy Initial VM with Cloud Config
# This script deploys a VM instance with nginx using cloud-config

set -e

# Source environment variables from setup.sh
source "$(dirname "$0")/setup.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Deploying Initial VM with Nginx ===${NC}"

# Check if cloud-config file exists
if [ ! -f "configs/nginx-cloud-config.yaml" ]; then
    echo -e "${RED}ERROR: Cloud-config file not found at configs/nginx-cloud-config.yaml${NC}"
    exit 1
fi

# Create firewall rule for HTTP traffic (if it doesn't exist)
echo -e "${GREEN}Creating firewall rule for HTTP traffic...${NC}"
if ! gcloud compute firewall-rules describe allow-http --quiet 2>/dev/null; then
    gcloud compute firewall-rules create allow-http \
        --description="Allow HTTP traffic on port 80" \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=tcp:80 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=http-server
    echo -e "${GREEN}Firewall rule 'allow-http' created${NC}"
else
    echo -e "${YELLOW}Firewall rule 'allow-http' already exists${NC}"
fi

# Deploy VM instance with cloud-config
echo -e "${GREEN}Deploying VM instance: $VM_NAME${NC}"
gcloud compute instances create $VM_NAME \
    --zone=$ZONE \
    --machine-type=$MACHINE_TYPE \
    --network-interface=network-tier=PREMIUM,subnet=default \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account=$(gcloud config get-value account) \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --tags=http-server \
    --create-disk=auto-delete=yes,boot=yes,device-name=$VM_NAME,image=projects/$IMAGE_PROJECT/global/images/family/$IMAGE_FAMILY,mode=rw,size=10,type=projects/$PROJECT_ID/zones/$ZONE/diskTypes/pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=environment=demo,application=nginx,deployment-type=mig-template \
    --reservation-affinity=any \
    --metadata-from-file=user-data=configs/nginx-cloud-config.yaml

echo -e "${GREEN}VM instance $VM_NAME created successfully!${NC}"

# Wait for the instance to be running
echo -e "${YELLOW}Waiting for instance to be in RUNNING state...${NC}"
while true; do
    STATUS=$(gcloud compute instances describe $VM_NAME --zone=$ZONE --format="value(status)")
    if [ "$STATUS" = "RUNNING" ]; then
        echo -e "${GREEN}Instance is running!${NC}"
        break
    fi
    echo "Current status: $STATUS. Waiting..."
    sleep 10
done

# Get external IP
EXTERNAL_IP=$(gcloud compute instances describe $VM_NAME --zone=$ZONE --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
echo -e "${GREEN}External IP: $EXTERNAL_IP${NC}"

# Wait for nginx to be ready
echo -e "${YELLOW}Waiting for nginx to be ready (this may take a few minutes)...${NC}"
RETRY_COUNT=0
MAX_RETRIES=30

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f -s http://$EXTERNAL_IP/health > /dev/null 2>&1; then
        echo -e "${GREEN}Nginx is responding to health checks!${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Attempt $RETRY_COUNT/$MAX_RETRIES: Nginx not ready yet, waiting 10 seconds..."
    sleep 10
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}WARNING: Nginx did not respond within expected time${NC}"
    echo "You can check the instance status manually:"
    echo "gcloud compute instances get-serial-port-output $VM_NAME --zone=$ZONE"
else
    echo -e "${GREEN}Deployment verification successful!${NC}"
    echo ""
    echo -e "${YELLOW}=== Deployment Summary ===${NC}"
    echo "VM Name: $VM_NAME"
    echo "Zone: $ZONE"
    echo "External IP: $EXTERNAL_IP"
    echo "Nginx URL: http://$EXTERNAL_IP"
    echo "Health Check: http://$EXTERNAL_IP/health"
    echo ""
    echo -e "${GREEN}Next step: Run ./scripts/create-image.sh to create a custom image${NC}"
fi
