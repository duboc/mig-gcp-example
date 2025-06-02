#!/bin/bash

# GCP Nginx MIG Deployment - Deploy Managed Instance Group
# This script creates an instance template and deploys a managed instance group

set -e

# Source environment variables from setup.sh
source "$(dirname "$0")/setup.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Deploying Managed Instance Group ===${NC}"

# Check if custom image exists
if ! gcloud compute images describe $CUSTOM_IMAGE_NAME --quiet 2>/dev/null; then
    echo -e "${RED}ERROR: Custom image $CUSTOM_IMAGE_NAME not found${NC}"
    echo "Please run ./scripts/create-image.sh first"
    exit 1
fi

# Auto-scaling configuration
MIN_INSTANCES=2
MAX_INSTANCES=5
TARGET_CPU_UTILIZATION=60

echo -e "${YELLOW}MIG Configuration:${NC}"
echo "Min instances: $MIN_INSTANCES"
echo "Max instances: $MAX_INSTANCES"
echo "Target CPU utilization: $TARGET_CPU_UTILIZATION%"
echo ""

# Create instance template
echo -e "${GREEN}Creating instance template: $INSTANCE_TEMPLATE_NAME${NC}"
gcloud compute instance-templates create $INSTANCE_TEMPLATE_NAME \
    --machine-type=$MACHINE_TYPE \
    --network-interface=network-tier=PREMIUM,subnet=default \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account=$(gcloud config get-value account) \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --tags=http-server,mig-instance \
    --create-disk=auto-delete=yes,boot=yes,device-name=instance-template,image=projects/$PROJECT_ID/global/images/$CUSTOM_IMAGE_NAME,mode=rw,size=10,type=pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=environment=demo,application=nginx,deployment-type=mig

echo -e "${GREEN}Instance template created successfully!${NC}"

# Create managed instance group
echo -e "${GREEN}Creating managed instance group: $MIG_NAME${NC}"
gcloud compute instance-groups managed create $MIG_NAME \
    --base-instance-name=nginx-mig \
    --size=$MIN_INSTANCES \
    --template=$INSTANCE_TEMPLATE_NAME \
    --zone=$ZONE \
    --description="Managed instance group for nginx load balancing demo"

echo -e "${GREEN}Managed instance group created!${NC}"

# Set auto-scaling policy
echo -e "${GREEN}Configuring auto-scaling...${NC}"
gcloud compute instance-groups managed set-autoscaling $MIG_NAME \
    --zone=$ZONE \
    --max-num-replicas=$MAX_INSTANCES \
    --min-num-replicas=$MIN_INSTANCES \
    --target-cpu-utilization=$TARGET_CPU_UTILIZATION \
    --cool-down-period=60

echo -e "${GREEN}Auto-scaling configured!${NC}"

# Set named ports for load balancer
echo -e "${GREEN}Setting named ports for load balancer integration...${NC}"
gcloud compute instance-groups managed set-named-ports $MIG_NAME \
    --zone=$ZONE \
    --named-ports=http:80

echo -e "${GREEN}Named ports configured!${NC}"

# Wait for instances to be created and running
echo -e "${YELLOW}Waiting for instances to be created and healthy...${NC}"
RETRY_COUNT=0
MAX_RETRIES=20

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RUNNING_INSTANCES=$(gcloud compute instance-groups managed list-instances $MIG_NAME --zone=$ZONE --filter="status=RUNNING" --format="value(name)" | wc -l)
    
    if [ "$RUNNING_INSTANCES" -ge "$MIN_INSTANCES" ]; then
        echo -e "${GREEN}All instances are running!${NC}"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Attempt $RETRY_COUNT/$MAX_RETRIES: $RUNNING_INSTANCES/$MIN_INSTANCES instances running, waiting..."
    sleep 15
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}WARNING: Not all instances are running within expected time${NC}"
    echo "You can check the status manually:"
    echo "gcloud compute instance-groups managed list-instances $MIG_NAME --zone=$ZONE"
fi

# List the instances
echo -e "${GREEN}Listing MIG instances:${NC}"
gcloud compute instance-groups managed list-instances $MIG_NAME --zone=$ZONE --format="table(name,status,instanceStatus,currentAction)"

# Get instance external IPs for verification
echo ""
echo -e "${GREEN}Instance External IPs:${NC}"
INSTANCE_NAMES=$(gcloud compute instance-groups managed list-instances $MIG_NAME --zone=$ZONE --format="value(name)")

for INSTANCE_NAME in $INSTANCE_NAMES; do
    EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "N/A")
    echo "$INSTANCE_NAME: $EXTERNAL_IP"
done

echo ""
echo -e "${GREEN}=== MIG Deployment Summary ===${NC}"
echo "Instance Template: $INSTANCE_TEMPLATE_NAME"
echo "Managed Instance Group: $MIG_NAME"
echo "Zone: $ZONE"
echo "Min Instances: $MIN_INSTANCES"
echo "Max Instances: $MAX_INSTANCES"
echo "Target CPU Utilization: $TARGET_CPU_UTILIZATION%"
echo ""
echo -e "${GREEN}Next step: Run ./scripts/setup-lb.sh to create load balancer${NC}"
