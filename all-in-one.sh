#!/bin/bash

# Set variables
PROJECT_ID="conventodapenha"
REGION="us-central1"
ZONE="us-central1-c"
NETWORK="defaultzona"
SUBNET="defaultzona"
INSTANCE_NAME="nginx-base-instance"
TEMPLATE_NAME="nginx-template"
MIG_NAME="nginx-mig"
HEALTH_CHECK_NAME="nginx-health-check"
BACKEND_SERVICE_NAME="nginx-backend-service"
URL_MAP_NAME="nginx-url-map"
TARGET_PROXY_NAME="nginx-target-proxy"
FORWARDING_RULE_NAME="nginx-forwarding-rule"

# Set the project
gcloud config set project $PROJECT_ID

# Step 1: Create cloud-config file for nginx
cat > cloud-config.yaml << 'EOF'
#cloud-config
package_update: true
packages:
  - nginx

write_files:
  - path: /var/www/html/index.html
    content: |
      <!DOCTYPE html>
      <html>
      <head>
          <title>Welcome to Nginx on GCP</title>
      </head>
      <body>
          <h1>Hello from Nginx!</h1>
          <p>Instance: $(hostname)</p>
          <p>This server is running on Google Cloud Platform</p>
      </body>
      </html>
    permissions: '0644'

  - path: /etc/nginx/sites-available/default
    content: |
      server {
          listen 80 default_server;
          listen [::]:80 default_server;
          
          root /var/www/html;
          index index.html index.htm index.nginx-debian.html;
          
          server_name _;
          
          location / {
              try_files $uri $uri/ =404;
          }
          
          location /health {
              access_log off;
              return 200 "healthy\n";
              add_header Content-Type text/plain;
          }
      }
    permissions: '0644'

runcmd:
  - systemctl enable nginx
  - systemctl start nginx
  - ufw allow 'Nginx Full'
EOF

# Step 2: Create the base instance with cloud-config
echo "Creating base instance with nginx..."
gcloud compute instances create $INSTANCE_NAME \
    --project=$PROJECT_ID \
    --zone=$ZONE \
    --machine-type=e2-medium \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=$SUBNET \
    --metadata=enable-osconfig=TRUE \
    --metadata-from-file user-data=cloud-config.yaml \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account=713488125678-compute@developer.gserviceaccount.com \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
    --create-disk=auto-delete=yes,boot=yes,device-name=$INSTANCE_NAME,image=projects/debian-cloud/global/images/debian-12-bookworm-v20250513,mode=rw,size=10,type=pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ops-agent-policy=v2-x86-template-1-4-0,goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any \
    --tags=http-server,https-server

# Wait for the instance to be ready
echo "Waiting for instance to be ready..."
sleep 60

# Check if Ops Agent policy exists and create if needed
POLICY_NAME="goog-ops-agent-v2-x86-template-1-4-0-$ZONE"
echo "Checking if Ops Agent policy exists..."

if gcloud compute instances ops-agents policies describe $POLICY_NAME --project=$PROJECT_ID --zone=$ZONE &>/dev/null; then
    echo "Ops Agent policy '$POLICY_NAME' already exists, skipping creation."
else
    echo "Creating Ops Agent policy..."
    printf 'agentsRule:\n  packageState: installed\n  version: latest\ninstanceFilter:\n  inclusionLabels:\n  - labels:\n      goog-ops-agent-policy: v2-x86-template-1-4-0\n' > ops-agent-config.yaml
    
    gcloud compute instances ops-agents policies create $POLICY_NAME \
        --project=$PROJECT_ID \
        --zone=$ZONE \
        --file=ops-agent-config.yaml
    
    if [ $? -eq 0 ]; then
        echo "Ops Agent policy created successfully."
    else
        echo "Failed to create Ops Agent policy, but continuing with deployment."
    fi
fi

# Step 3: Stop the instance to create image
echo "Stopping instance to create image..."
gcloud compute instances stop $INSTANCE_NAME --zone=$ZONE

# Step 4: Create custom image from the instance
echo "Creating custom image..."
gcloud compute images create nginx-custom-image \
    --source-disk=$INSTANCE_NAME \
    --source-disk-zone=$ZONE \
    --family=nginx-family

# Step 5: Create instance template
echo "Creating instance template..."
gcloud compute instance-templates create $TEMPLATE_NAME \
    --project=$PROJECT_ID \
    --machine-type=e2-medium \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=$SUBNET \
    --metadata=enable-osconfig=TRUE \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account=713488125678-compute@developer.gserviceaccount.com \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
    --create-disk=auto-delete=yes,boot=yes,device-name=$TEMPLATE_NAME,image=nginx-custom-image,mode=rw,size=10,type=pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ops-agent-policy=v2-x86-template-1-4-0,goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any \
    --tags=http-server,https-server

# Step 6: Create firewall rules (if they don't exist)
echo "Creating firewall rules..."
gcloud compute firewall-rules create allow-http \
    --allow tcp:80 \
    --source-ranges 0.0.0.0/0 \
    --target-tags http-server \
    --network $NETWORK \
    --description "Allow HTTP traffic" || echo "HTTP rule already exists"

gcloud compute firewall-rules create allow-health-check \
    --allow tcp:80 \
    --source-ranges 130.211.0.0/22,35.191.0.0/16 \
    --target-tags http-server \
    --network $NETWORK \
    --description "Allow health check traffic" || echo "Health check rule already exists"

# Step 7: Create health check
echo "Creating health check..."
gcloud compute health-checks create http $HEALTH_CHECK_NAME \
    --port 80 \
    --request-path /health \
    --check-interval 10s \
    --timeout 5s \
    --healthy-threshold 2 \
    --unhealthy-threshold 3

# Step 8: Create managed instance group
echo "Creating managed instance group..."
gcloud compute instance-groups managed create $MIG_NAME \
    --template=$TEMPLATE_NAME \
    --size=2 \
    --zone=$ZONE

# Step 9: Set autoscaling for the MIG
echo "Setting up autoscaling..."
gcloud compute instance-groups managed set-autoscaling $MIG_NAME \
    --zone=$ZONE \
    --max-num-replicas=5 \
    --min-num-replicas=2 \
    --target-cpu-utilization=0.6 \
    --cool-down-period=90s

# Step 10: Set named ports for the MIG
echo "Setting named ports..."
gcloud compute instance-groups managed set-named-ports $MIG_NAME \
    --named-ports http:80 \
    --zone=$ZONE

# Step 11: Create backend service
echo "Creating backend service..."
gcloud compute backend-services create $BACKEND_SERVICE_NAME \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=$HEALTH_CHECK_NAME \
    --global

# Step 12: Add the MIG as backend to the backend service
echo "Adding MIG as backend..."
gcloud compute backend-services add-backend $BACKEND_SERVICE_NAME \
    --instance-group=$MIG_NAME \
    --instance-group-zone=$ZONE \
    --global

# Step 13: Create URL map
echo "Creating URL map..."
gcloud compute url-maps create $URL_MAP_NAME \
    --default-backend-service=$BACKEND_SERVICE_NAME

# Step 14: Create HTTP target proxy
echo "Creating target HTTP proxy..."
gcloud compute target-http-proxies create $TARGET_PROXY_NAME \
    --url-map=$URL_MAP_NAME

# Step 15: Create global forwarding rule (load balancer)
echo "Creating global forwarding rule..."
gcloud compute forwarding-rules create $FORWARDING_RULE_NAME \
    --global \
    --target-http-proxy=$TARGET_PROXY_NAME \
    --ports=80

# Step 16: Clean up the original instance
echo "Cleaning up original instance..."
gcloud compute instances delete $INSTANCE_NAME --zone=$ZONE --quiet

# Step 17: Get the load balancer IP
echo "Getting load balancer IP..."
LB_IP=$(gcloud compute forwarding-rules describe $FORWARDING_RULE_NAME --global --format="value(IPAddress)")

echo ""
echo "=================================="
echo "Deployment completed successfully!"
echo "=================================="
echo "Load Balancer IP: $LB_IP"
echo ""
echo "You can test your deployment with:"
echo "curl http://$LB_IP"
echo ""
echo "It may take a few minutes for the load balancer to become fully operational."
echo ""
echo "To check the status of your MIG:"
echo "gcloud compute instance-groups managed list-instances $MIG_NAME --zone=$ZONE"
echo ""
echo "To check backend service health:"
echo "gcloud compute backend-services get-health $BACKEND_SERVICE_NAME --global"

# Clean up config files
rm cloud-config.yaml
[ -f ops-agent-config.yaml ] && rm ops-agent-config.yaml