#!/bin/bash

# GCP Nginx MIG Deployment - Cleanup Resources
# This script removes all resources created during the deployment

set -e

# Source environment variables from setup.sh
source "$(dirname "$0")/setup.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Cleaning up GCP Resources ===${NC}"
echo -e "${RED}WARNING: This will delete all resources created by this deployment!${NC}"
echo -e "${YELLOW}Resources to be deleted:${NC}"
echo "- Load balancer components (forwarding rule, proxy, URL map, backend service, health check)"
echo "- Managed instance group and all instances"
echo "- Instance template"
echo "- Custom image"
echo "- Firewall rule (optional)"
echo "- Original VM (if still exists)"
echo ""

read -p "Are you sure you want to proceed? (y/N): " -r CONFIRM
if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo -e "${GREEN}Starting cleanup...${NC}"

# Function to safely delete resource
delete_resource() {
    local resource_type=$1
    local resource_name=$2
    local additional_flags=$3
    
    if gcloud compute $resource_type describe $resource_name $additional_flags --quiet 2>/dev/null; then
        echo -e "${YELLOW}Deleting $resource_type: $resource_name${NC}"
        gcloud compute $resource_type delete $resource_name $additional_flags --quiet
        echo -e "${GREEN}✓ $resource_name deleted${NC}"
    else
        echo -e "${YELLOW}$resource_type $resource_name not found, skipping${NC}"
    fi
}

# 1. Delete forwarding rule
delete_resource "forwarding-rules" "$FORWARDING_RULE_NAME" "--global"

# 2. Delete HTTP proxy
delete_resource "target-http-proxies" "$HTTP_PROXY_NAME"

# 3. Delete URL map
delete_resource "url-maps" "$URL_MAP_NAME"

# 4. Delete backend service
delete_resource "backend-services" "$BACKEND_SERVICE_NAME" "--global"

# 5. Delete health check
delete_resource "health-checks" "$HEALTH_CHECK_NAME"

# 6. Delete managed instance group (this will delete all instances)
if gcloud compute instance-groups managed describe $MIG_NAME --zone=$ZONE --quiet 2>/dev/null; then
    echo -e "${YELLOW}Deleting managed instance group: $MIG_NAME${NC}"
    gcloud compute instance-groups managed delete $MIG_NAME --zone=$ZONE --quiet
    echo -e "${GREEN}✓ MIG and all instances deleted${NC}"
else
    echo -e "${YELLOW}MIG $MIG_NAME not found, skipping${NC}"
fi

# 7. Delete instance template
delete_resource "instance-templates" "$INSTANCE_TEMPLATE_NAME"

# 8. Delete custom image
delete_resource "images" "$CUSTOM_IMAGE_NAME"

# 9. Delete original VM if it still exists
delete_resource "instances" "$VM_NAME" "--zone=$ZONE"

# 10. Optionally delete firewall rule
echo ""
read -p "Delete firewall rule 'allow-http'? This might affect other resources. (y/N): " -r DELETE_FIREWALL
if [[ "$DELETE_FIREWALL" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    delete_resource "firewall-rules" "allow-http"
fi

echo ""
echo -e "${GREEN}=== Cleanup Summary ===${NC}"
echo -e "${GREEN}✓ All deployment resources have been cleaned up${NC}"
echo ""
echo -e "${YELLOW}Remaining resources that were NOT deleted:${NC}"
echo "- Project and billing settings"
echo "- Default VPC network"
echo "- Service accounts"
echo "- API enablements"
if [[ ! "$DELETE_FIREWALL" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "- Firewall rule 'allow-http' (kept by choice)"
fi
echo ""
echo -e "${GREEN}Cleanup completed successfully! 🧹${NC}"

# Verify cleanup
echo ""
echo -e "${YELLOW}Verification - Checking for remaining resources:${NC}"

echo -n "Forwarding rules: "
REMAINING_FRS=$(gcloud compute forwarding-rules list --filter="name:$FORWARDING_RULE_NAME" --format="value(name)" | wc -l)
if [ "$REMAINING_FRS" -eq 0 ]; then
    echo -e "${GREEN}✓ None found${NC}"
else
    echo -e "${RED}⚠ $REMAINING_FRS still exist${NC}"
fi

echo -n "MIGs: "
REMAINING_MIGS=$(gcloud compute instance-groups managed list --filter="name:$MIG_NAME" --format="value(name)" | wc -l)
if [ "$REMAINING_MIGS" -eq 0 ]; then
    echo -e "${GREEN}✓ None found${NC}"
else
    echo -e "${RED}⚠ $REMAINING_MIGS still exist${NC}"
fi

echo -n "Custom images: "
REMAINING_IMAGES=$(gcloud compute images list --filter="name:$CUSTOM_IMAGE_NAME" --format="value(name)" | wc -l)
if [ "$REMAINING_IMAGES" -eq 0 ]; then
    echo -e "${GREEN}✓ None found${NC}"
else
    echo -e "${RED}⚠ $REMAINING_IMAGES still exist${NC}"
fi

echo ""
echo -e "${GREEN}You can now safely run the deployment again if needed.${NC}"
