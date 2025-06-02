#!/bin/bash

# GCP Nginx MIG Deployment - Setup Load Balancer
# This script creates a complete HTTP load balancer with health checks

set -e

# Source environment variables from setup.sh
source "$(dirname "$0")/setup.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Setting up HTTP Load Balancer ===${NC}"

# Check if MIG exists
if ! gcloud compute instance-groups managed describe $MIG_NAME --zone=$ZONE --quiet 2>/dev/null; then
    echo -e "${RED}ERROR: Managed instance group $MIG_NAME not found${NC}"
    echo "Please run ./scripts/deploy-mig.sh first"
    exit 1
fi

# Step 1: Create health check
echo -e "${GREEN}Creating health check: $HEALTH_CHECK_NAME${NC}"
gcloud compute health-checks create http $HEALTH_CHECK_NAME \
    --description="Health check for nginx instances" \
    --port=80 \
    --request-path="/health" \
    --check-interval=10s \
    --timeout=5s \
    --healthy-threshold=2 \
    --unhealthy-threshold=3

echo -e "${GREEN}Health check created!${NC}"

# Step 2: Create backend service
echo -e "${GREEN}Creating backend service: $BACKEND_SERVICE_NAME${NC}"
gcloud compute backend-services create $BACKEND_SERVICE_NAME \
    --description="Backend service for nginx MIG" \
    --health-checks=$HEALTH_CHECK_NAME \
    --port-name=http \
    --protocol=HTTP \
    --timeout=30s \
    --enable-logging \
    --global

echo -e "${GREEN}Backend service created!${NC}"

# Step 3: Add MIG as backend to the backend service
echo -e "${GREEN}Adding MIG as backend to the service...${NC}"
gcloud compute backend-services add-backend $BACKEND_SERVICE_NAME \
    --instance-group=$MIG_NAME \
    --instance-group-zone=$ZONE \
    --balancing-mode=UTILIZATION \
    --max-utilization=0.8 \
    --capacity-scaler=1.0 \
    --global

echo -e "${GREEN}Backend added to service!${NC}"

# Step 4: Create URL map
echo -e "${GREEN}Creating URL map: $URL_MAP_NAME${NC}"
gcloud compute url-maps create $URL_MAP_NAME \
    --description="URL map for nginx load balancer" \
    --default-service=$BACKEND_SERVICE_NAME

echo -e "${GREEN}URL map created!${NC}"

# Step 5: Create HTTP proxy
echo -e "${GREEN}Creating HTTP proxy: $HTTP_PROXY_NAME${NC}"
gcloud compute target-http-proxies create $HTTP_PROXY_NAME \
    --description="HTTP proxy for nginx load balancer" \
    --url-map=$URL_MAP_NAME

echo -e "${GREEN}HTTP proxy created!${NC}"

# Step 6: Create forwarding rule (this creates the external IP)
echo -e "${GREEN}Creating forwarding rule: $FORWARDING_RULE_NAME${NC}"
gcloud compute forwarding-rules create $FORWARDING_RULE_NAME \
    --description="Forwarding rule for nginx load balancer" \
    --global \
    --target-http-proxy=$HTTP_PROXY_NAME \
    --ports=80

echo -e "${GREEN}Forwarding rule created!${NC}"

# Wait for load balancer to be ready
echo -e "${YELLOW}Waiting for load balancer to be ready (this may take a few minutes)...${NC}"
sleep 30

# Get the external IP
LOAD_BALANCER_IP=$(gcloud compute forwarding-rules describe $FORWARDING_RULE_NAME --global --format="value(IPAddress)")
echo -e "${GREEN}Load Balancer External IP: $LOAD_BALANCER_IP${NC}"

# Wait for load balancer to start serving traffic
echo -e "${YELLOW}Testing load balancer connectivity...${NC}"
RETRY_COUNT=0
MAX_RETRIES=20

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f -s --connect-timeout 5 http://$LOAD_BALANCER_IP/ > /dev/null 2>&1; then
        echo -e "${GREEN}Load balancer is responding!${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Attempt $RETRY_COUNT/$MAX_RETRIES: Load balancer not ready yet, waiting 15 seconds..."
    sleep 15
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}WARNING: Load balancer did not respond within expected time${NC}"
    echo "This is normal for new load balancers. It may take up to 5-10 minutes to be fully operational."
fi

# Display backend health status
echo ""
echo -e "${GREEN}Checking backend health status...${NC}"
gcloud compute backend-services get-health $BACKEND_SERVICE_NAME --global

# Display complete load balancer information
echo ""
echo -e "${GREEN}=== Load Balancer Setup Complete ===${NC}"
echo ""
echo -e "${YELLOW}Load Balancer Details:${NC}"
echo "External IP: $LOAD_BALANCER_IP"
echo "URL: http://$LOAD_BALANCER_IP"
echo "Health Check: $HEALTH_CHECK_NAME"
echo "Backend Service: $BACKEND_SERVICE_NAME"
echo "URL Map: $URL_MAP_NAME"
echo "HTTP Proxy: $HTTP_PROXY_NAME"
echo "Forwarding Rule: $FORWARDING_RULE_NAME"
echo ""
echo -e "${YELLOW}MIG Details:${NC}"
echo "Instance Group: $MIG_NAME"
echo "Zone: $ZONE"
echo "Min Instances: 2"
echo "Max Instances: 5"
echo "Target CPU: 60%"
echo ""
echo -e "${GREEN}=== Testing Commands ===${NC}"
echo "Test the load balancer:"
echo "curl http://$LOAD_BALANCER_IP"
echo ""
echo "Test health check:"
echo "curl http://$LOAD_BALANCER_IP/health"
echo ""
echo "Load test (install apache2-utils first):"
echo "ab -n 1000 -c 10 http://$LOAD_BALANCER_IP/"
echo ""
echo -e "${GREEN}=== Monitoring Commands ===${NC}"
echo "Monitor instances:"
echo "gcloud compute instance-groups managed list-instances $MIG_NAME --zone=$ZONE"
echo ""
echo "Check backend health:"
echo "gcloud compute backend-services get-health $BACKEND_SERVICE_NAME --global"
echo ""
echo "Monitor auto-scaling:"
echo "watch -n 5 'gcloud compute instance-groups managed describe $MIG_NAME --zone=$ZONE --format=\"value(currentActions.recreating,targetSize,status.autoscaler.lastScaleUpTime)\"'"
echo ""
echo -e "${GREEN}Deployment completed successfully! 🎉${NC}"
