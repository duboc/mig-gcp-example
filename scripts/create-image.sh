#!/bin/bash

# GCP Nginx MIG Deployment - Create Custom Image from VM
# This script stops the VM and creates a custom image for the instance template

set -e

# Source environment variables from setup.sh
source "$(dirname "$0")/setup.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Creating Custom Image from VM ===${NC}"

# Check if VM exists
if ! gcloud compute instances describe $VM_NAME --zone=$ZONE --quiet 2>/dev/null; then
    echo -e "${RED}ERROR: VM instance $VM_NAME not found in zone $ZONE${NC}"
    echo "Please run ./scripts/deploy-initial-vm.sh first"
    exit 1
fi

# Get VM status
VM_STATUS=$(gcloud compute instances describe $VM_NAME --zone=$ZONE --format="value(status)")
echo -e "${YELLOW}Current VM status: $VM_STATUS${NC}"

# Stop the VM if it's running
if [ "$VM_STATUS" = "RUNNING" ]; then
    echo -e "${GREEN}Stopping VM instance $VM_NAME...${NC}"
    gcloud compute instances stop $VM_NAME --zone=$ZONE
    
    # Wait for the instance to be stopped
    echo -e "${YELLOW}Waiting for instance to stop...${NC}"
    while true; do
        STATUS=$(gcloud compute instances describe $VM_NAME --zone=$ZONE --format="value(status)")
        if [ "$STATUS" = "TERMINATED" ]; then
            echo -e "${GREEN}Instance stopped successfully!${NC}"
            break
        fi
        echo "Current status: $STATUS. Waiting..."
        sleep 5
    done
fi

# Create custom image from the VM disk
echo -e "${GREEN}Creating custom image: $CUSTOM_IMAGE_NAME${NC}"
gcloud compute images create $CUSTOM_IMAGE_NAME \
    --source-disk=$VM_NAME \
    --source-disk-zone=$ZONE \
    --description="Custom nginx image created from $VM_NAME with cloud-config setup" \
    --labels=environment=demo,application=nginx,deployment-type=mig-template \
    --family=nginx-custom

echo -e "${GREEN}Custom image created successfully!${NC}"

# Optional: Delete the original VM since we now have the image
echo -e "${YELLOW}Do you want to delete the original VM instance? (y/N)${NC}"
read -r RESPONSE
if [[ "$RESPONSE" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${GREEN}Deleting original VM instance $VM_NAME...${NC}"
    gcloud compute instances delete $VM_NAME --zone=$ZONE --quiet
    echo -e "${GREEN}VM instance deleted${NC}"
else
    echo -e "${YELLOW}Keeping original VM instance${NC}"
fi

# Verify image was created
echo -e "${GREEN}Verifying image creation...${NC}"
gcloud compute images describe $CUSTOM_IMAGE_NAME --format="table(name,family,status,diskSizeGb,creationTimestamp)"

echo ""
echo -e "${GREEN}=== Image Creation Summary ===${NC}"
echo "Custom Image: $CUSTOM_IMAGE_NAME"
echo "Image Family: nginx-custom"
echo "Source VM: $VM_NAME"
echo ""
echo -e "${GREEN}Next step: Run ./scripts/deploy-mig.sh to create managed instance group${NC}"
