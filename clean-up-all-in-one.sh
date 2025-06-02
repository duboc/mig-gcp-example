#!/bin/bash

# Cleanup Script for Nginx GCP Deployment
# This script safely deletes all resources created by the nginx deployment script

set -e

# Configuration Variables (should match deployment script)
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
CUSTOM_IMAGE_NAME="nginx-custom-image"
IMAGE_FAMILY="nginx-family"

# Ops Agent Policy
POLICY_NAME="goog-ops-agent-v2-x86-template-1-4-0-$ZONE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local zone_or_region="$3"
    local additional_flags="$4"
    
    gcloud compute $resource_type describe "$resource_name" $zone_or_region $additional_flags --project=$PROJECT_ID &>/dev/null
}

# Function to delete resource with error handling
delete_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local zone_or_region="$3"
    local additional_flags="$4"
    
    if resource_exists "$resource_type" "$resource_name" "$zone_or_region" "$additional_flags"; then
        print_info "Deleting $resource_type: $resource_name"
        if gcloud compute $resource_type delete "$resource_name" $zone_or_region $additional_flags --project=$PROJECT_ID --quiet; then
            print_success "Deleted $resource_type: $resource_name"
        else
            print_error "Failed to delete $resource_type: $resource_name"
            return 1
        fi
    else
        print_warning "$resource_type '$resource_name' does not exist, skipping"
    fi
}

# Function to wait for operation to complete
wait_for_operation() {
    local operation_type="$1"
    local timeout=300  # 5 minutes timeout
    local elapsed=0
    
    print_info "Waiting for $operation_type to complete..."
    
    while [ $elapsed -lt $timeout ]; do
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    echo ""
    print_info "$operation_type wait completed"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    print_warning "This script will delete the following resources:"
    echo "  • Load Balancer (Forwarding Rule): $FORWARDING_RULE_NAME"
    echo "  • HTTP Target Proxy: $TARGET_PROXY_NAME"
    echo "  • URL Map: $URL_MAP_NAME"
    echo "  • Backend Service: $BACKEND_SERVICE_NAME"
    echo "  • Health Check: $HEALTH_CHECK_NAME"
    echo "  • Managed Instance Group: $MIG_NAME"
    echo "  • Instance Template: $TEMPLATE_NAME"
    echo "  • Custom Image: $CUSTOM_IMAGE_NAME"
    echo "  • Base Instance: $INSTANCE_NAME (if exists)"
    echo "  • Firewall Rules: allow-http, allow-health-check"
    echo "  • Ops Agent Policy: $POLICY_NAME"
    echo ""
    print_warning "Project: $PROJECT_ID"
    print_warning "Zone: $ZONE"
    echo ""
    
    if [ "$1" != "--force" ]; then
        read -p "Are you sure you want to delete all these resources? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Deletion cancelled by user"
            exit 0
        fi
    else
        print_warning "Force mode enabled, skipping confirmation"
    fi
}

# Function to list current resources
list_resources() {
    print_info "Checking current resources in project $PROJECT_ID..."
    echo ""
    
    # Check forwarding rules
    print_info "Forwarding Rules:"
    gcloud compute forwarding-rules list --project=$PROJECT_ID --filter="name:$FORWARDING_RULE_NAME" --format="table(name,region,target)" 2>/dev/null || echo "  None found"
    
    # Check MIG
    print_info "Managed Instance Groups:"
    gcloud compute instance-groups managed list --project=$PROJECT_ID --filter="name:$MIG_NAME" --format="table(name,zone,targetSize)" 2>/dev/null || echo "  None found"
    
    # Check instances
    print_info "Instances:"
    gcloud compute instances list --project=$PROJECT_ID --filter="name:($INSTANCE_NAME OR $MIG_NAME)" --format="table(name,zone,status)" 2>/dev/null || echo "  None found"
    
    # Check templates
    print_info "Instance Templates:"
    gcloud compute instance-templates list --project=$PROJECT_ID --filter="name:$TEMPLATE_NAME" --format="table(name,creationTimestamp)" 2>/dev/null || echo "  None found"
    
    # Check images
    print_info "Custom Images:"
    gcloud compute images list --project=$PROJECT_ID --filter="name:$CUSTOM_IMAGE_NAME" --format="table(name,family,status)" 2>/dev/null || echo "  None found"
    
    echo ""
}

# Function to delete load balancer components (in correct order)
delete_load_balancer() {
    print_info "=== Deleting Load Balancer Components ==="
    
    # 1. Delete forwarding rule (frontend)
    delete_resource "forwarding-rules" "$FORWARDING_RULE_NAME" "--global"
    
    # 2. Delete target proxy
    delete_resource "target-http-proxies" "$TARGET_PROXY_NAME" "--global"
    
    # 3. Delete URL map
    delete_resource "url-maps" "$URL_MAP_NAME" "--global"
    
    # 4. Delete backend service
    delete_resource "backend-services" "$BACKEND_SERVICE_NAME" "--global"
    
    # 5. Delete health check
    delete_resource "health-checks" "$HEALTH_CHECK_NAME" "--global"
    
    print_success "Load balancer components deletion completed"
}

# Function to delete compute resources
delete_compute_resources() {
    print_info "=== Deleting Compute Resources ==="
    
    # 1. Delete managed instance group (this will delete all instances in the group)
    if resource_exists "instance-groups managed" "$MIG_NAME" "--zone=$ZONE"; then
        print_info "Deleting managed instance group and all its instances..."
        gcloud compute instance-groups managed delete "$MIG_NAME" \
            --zone=$ZONE \
            --project=$PROJECT_ID \
            --quiet
        print_success "Deleted managed instance group: $MIG_NAME"
        
        # Wait for instances to be fully deleted
        wait_for_operation "MIG deletion"
    else
        print_warning "Managed instance group '$MIG_NAME' does not exist, skipping"
    fi
    
    # 2. Delete base instance (if it still exists)
    delete_resource "instances" "$INSTANCE_NAME" "--zone=$ZONE"
    
    # 3. Delete instance template
    delete_resource "instance-templates" "$TEMPLATE_NAME" "--global"
    
    # 4. Delete custom image
    delete_resource "images" "$CUSTOM_IMAGE_NAME" "--global"
    
    print_success "Compute resources deletion completed"
}

# Function to delete firewall rules
delete_firewall_rules() {
    print_info "=== Deleting Firewall Rules ==="
    
    # Delete HTTP firewall rule
    if gcloud compute firewall-rules describe "allow-http" --project=$PROJECT_ID &>/dev/null; then
        # Check if it's for our network
        rule_network=$(gcloud compute firewall-rules describe "allow-http" --project=$PROJECT_ID --format="value(network)" 2>/dev/null)
        if [[ "$rule_network" == *"$NETWORK"* ]]; then
            delete_resource "firewall-rules" "allow-http" ""
        else
            print_warning "Firewall rule 'allow-http' exists but is for a different network, skipping"
        fi
    else
        print_warning "Firewall rule 'allow-http' does not exist, skipping"
    fi
    
    # Delete health check firewall rule
    if gcloud compute firewall-rules describe "allow-health-check" --project=$PROJECT_ID &>/dev/null; then
        # Check if it's for our network
        rule_network=$(gcloud compute firewall-rules describe "allow-health-check" --project=$PROJECT_ID --format="value(network)" 2>/dev/null)
        if [[ "$rule_network" == *"$NETWORK"* ]]; then
            delete_resource "firewall-rules" "allow-health-check" ""
        else
            print_warning "Firewall rule 'allow-health-check' exists but is for a different network, skipping"
        fi
    else
        print_warning "Firewall rule 'allow-health-check' does not exist, skipping"
    fi
    
    print_success "Firewall rules deletion completed"
}

# Function to delete ops agent policy
delete_ops_agent_policy() {
    print_info "=== Deleting Ops Agent Policy ==="
    
    if gcloud compute instances ops-agents policies describe "$POLICY_NAME" --project=$PROJECT_ID --zone=$ZONE &>/dev/null; then
        print_info "Deleting Ops Agent policy: $POLICY_NAME"
        if gcloud compute instances ops-agents policies delete "$POLICY_NAME" --project=$PROJECT_ID --zone=$ZONE --quiet; then
            print_success "Deleted Ops Agent policy: $POLICY_NAME"
        else
            print_error "Failed to delete Ops Agent policy: $POLICY_NAME"
        fi
    else
        print_warning "Ops Agent policy '$POLICY_NAME' does not exist, skipping"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    print_info "=== Verifying Cleanup ==="
    
    local cleanup_success=true
    
    # Check if any resources still exist
    if resource_exists "forwarding-rules" "$FORWARDING_RULE_NAME" "--global"; then
        print_error "Forwarding rule still exists: $FORWARDING_RULE_NAME"
        cleanup_success=false
    fi
    
    if resource_exists "instance-groups managed" "$MIG_NAME" "--zone=$ZONE"; then
        print_error "Managed instance group still exists: $MIG_NAME"
        cleanup_success=false
    fi
    
    if resource_exists "instance-templates" "$TEMPLATE_NAME" "--global"; then
        print_error "Instance template still exists: $TEMPLATE_NAME"
        cleanup_success=false
    fi
    
    if resource_exists "images" "$CUSTOM_IMAGE_NAME" "--global"; then
        print_error "Custom image still exists: $CUSTOM_IMAGE_NAME"
        cleanup_success=false
    fi
    
    if $cleanup_success; then
        print_success "All resources have been successfully deleted!"
    else
        print_error "Some resources still exist. Please check manually."
        return 1
    fi
}

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --list              List current resources without deleting"
    echo "  --force             Skip confirmation prompt"
    echo "  --help, -h          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                  # Interactive deletion with confirmation"
    echo "  $0 --force          # Delete without confirmation"
    echo "  $0 --list           # Just list current resources"
    echo ""
    echo "This script deletes all resources created by the nginx deployment script."
}

# Main function
main() {
    echo "=========================================="
    echo "Nginx Deployment Cleanup Script"
    echo "=========================================="
    
    # Set the project
    gcloud config set project $PROJECT_ID
    
    case "${1}" in
        "--list")
            list_resources
            exit 0
            ;;
        "--help"|"-h")
            usage
            exit 0
            ;;
        "--force")
            confirm_deletion "--force"
            ;;
        "")
            list_resources
            confirm_deletion
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    
    print_info "Starting cleanup process..."
    
    # Delete resources in correct order to avoid dependency issues
    delete_load_balancer
    echo ""
    
    delete_compute_resources
    echo ""
    
    delete_firewall_rules
    echo ""
    
    delete_ops_agent_policy
    echo ""
    
    # Verify cleanup
    verify_cleanup
    
    print_success "Cleanup completed successfully!"
    print_info "All nginx deployment resources have been removed from project: $PROJECT_ID"
}

# Run main function with all arguments
main "$@"