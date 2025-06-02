#!/bin/bash

# Load Testing Script for Nginx Deployment using Bombardier
# This script performs various load testing scenarios against your GCP nginx deployment

set -e

# Configuration Variables
PROJECT_ID="conventodapenha"
FORWARDING_RULE_NAME="nginx-forwarding-rule"
MIG_NAME="nginx-mig"
ZONE="us-central1-c"
BACKEND_SERVICE_NAME="nginx-backend-service"

# Test Configuration
DEFAULT_DURATION="60s"
DEFAULT_CONNECTIONS="50"
DEFAULT_RATE="100"
BOMBARDIER_TIMEOUT="30s"

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

# Function to check if bombardier is installed
check_bombardier() {
    if ! command -v bombardier &> /dev/null; then
        print_error "Bombardier is not installed!"
        echo ""
        echo "To install bombardier:"
        echo "  # On macOS:"
        echo "  brew install bombardier"
        echo ""
        echo "  # On Linux (from releases):"
        echo "  wget https://github.com/codesenberg/bombardier/releases/latest/download/bombardier-linux-amd64"
        echo "  chmod +x bombardier-linux-amd64"
        echo "  sudo mv bombardier-linux-amd64 /usr/local/bin/bombardier"
        echo ""
        echo "  # Using Go:"
        echo "  go install github.com/codesenberg/bombardier@latest"
        exit 1
    fi
    print_success "Bombardier is installed: $(bombardier --version)"
}

# Function to get load balancer IP
get_lb_ip() {
    print_info "Getting load balancer IP..."
    LB_IP=$(gcloud compute forwarding-rules describe $FORWARDING_RULE_NAME \
        --global \
        --project=$PROJECT_ID \
        --format="value(IPAddress)" 2>/dev/null)
    
    if [ -z "$LB_IP" ]; then
        print_error "Could not retrieve load balancer IP"
        exit 1
    fi
    
    print_success "Load Balancer IP: $LB_IP"
    echo "http://$LB_IP"
}

# Function to check if the service is responding
check_service_health() {
    print_info "Checking service health..."
    
    if curl -s --max-time 10 "http://$LB_IP" > /dev/null; then
        print_success "Service is responding"
    else
        print_error "Service is not responding. Please check your deployment."
        exit 1
    fi
    
    # Check health endpoint
    if curl -s --max-time 10 "http://$LB_IP/health" > /dev/null; then
        print_success "Health endpoint is responding"
    else
        print_warning "Health endpoint is not responding"
    fi
}

# Function to get current MIG status
get_mig_status() {
    print_info "Current MIG status:"
    gcloud compute instance-groups managed describe $MIG_NAME \
        --zone=$ZONE \
        --project=$PROJECT_ID \
        --format="table(
            name,
            targetSize,
            currentActions.creating,
            currentActions.deleting,
            currentActions.running
        )" 2>/dev/null || print_warning "Could not get MIG status"
}

# Function to get backend service health
get_backend_health() {
    print_info "Backend service health:"
    gcloud compute backend-services get-health $BACKEND_SERVICE_NAME \
        --global \
        --project=$PROJECT_ID \
        --format="table(
            status.instance.basename(),
            status.healthState,
            status.ipAddress
        )" 2>/dev/null || print_warning "Could not get backend health"
}

# Function to run a basic load test
run_basic_test() {
    local duration=${1:-$DEFAULT_DURATION}
    local connections=${2:-$DEFAULT_CONNECTIONS}
    
    print_info "Running basic load test..."
    print_info "Duration: $duration, Connections: $connections"
    
    bombardier \
        --connections=$connections \
        --duration=$duration \
        --timeout=$BOMBARDIER_TIMEOUT \
        --print=intro,progress,result \
        "http://$LB_IP"
}

# Function to run a rate-limited test
run_rate_test() {
    local duration=${1:-$DEFAULT_DURATION}
    local rate=${2:-$DEFAULT_RATE}
    
    print_info "Running rate-limited load test..."
    print_info "Duration: $duration, Rate: $rate req/s"
    
    bombardier \
        --rate=$rate \
        --duration=$duration \
        --timeout=$BOMBARDIER_TIMEOUT \
        --print=intro,progress,result \
        "http://$LB_IP"
}

# Function to run a stress test (gradually increasing load)
run_stress_test() {
    print_info "Running stress test with gradually increasing load..."
    
    local rates=(10 25 50 100 200 500)
    local duration="30s"
    
    for rate in "${rates[@]}"; do
        print_info "Testing at $rate req/s for $duration"
        bombardier \
            --rate=$rate \
            --duration=$duration \
            --timeout=$BOMBARDIER_TIMEOUT \
            --print=result \
            "http://$LB_IP"
        
        print_info "Waiting 10 seconds before next test..."
        sleep 10
        
        # Check MIG status between tests
        get_mig_status
        echo ""
    done
}

# Function to test specific endpoints
run_endpoint_tests() {
    local duration=${1:-"30s"}
    local connections=${2:-25}
    
    print_info "Testing specific endpoints..."
    
    # Test main page
    print_info "Testing main page (/) for $duration"
    bombardier \
        --connections=$connections \
        --duration=$duration \
        --timeout=$BOMBARDIER_TIMEOUT \
        --print=result \
        "http://$LB_IP/"
    
    echo ""
    
    # Test health endpoint
    print_info "Testing health endpoint (/health) for $duration"
    bombardier \
        --connections=$connections \
        --duration=$duration \
        --timeout=$BOMBARDIER_TIMEOUT \
        --print=result \
        "http://$LB_IP/health"
}

# Function to run sustained load test
run_sustained_test() {
    local duration=${1:-"300s"}  # 5 minutes default
    local connections=${2:-$DEFAULT_CONNECTIONS}
    
    print_info "Running sustained load test..."
    print_info "Duration: $duration, Connections: $connections"
    print_warning "This test will run for an extended period. Monitor your GCP console for autoscaling."
    
    bombardier \
        --connections=$connections \
        --duration=$duration \
        --timeout=$BOMBARDIER_TIMEOUT \
        --print=intro,progress,result \
        "http://$LB_IP" &
    
    BOMBARDIER_PID=$!
    
    # Monitor MIG status during the test
    local counter=0
    while kill -0 $BOMBARDIER_PID 2>/dev/null; do
        sleep 30
        counter=$((counter + 1))
        print_info "Status check #$counter (every 30s):"
        get_mig_status
        echo ""
    done
    
    wait $BOMBARDIER_PID
}

# Function to display usage
usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  health              Check service health and status"
    echo "  basic [duration] [connections]   Run basic load test (default: 60s, 50 connections)"
    echo "  rate [duration] [rate]           Run rate-limited test (default: 60s, 100 req/s)"
    echo "  stress              Run stress test with increasing load"
    echo "  endpoints [duration] [connections] Test specific endpoints (default: 30s, 25 connections)"
    echo "  sustained [duration] [connections] Run sustained test with monitoring (default: 300s, 50 connections)"
    echo "  all                 Run all test scenarios"
    echo ""
    echo "Examples:"
    echo "  $0 basic 120s 100              # 2-minute test with 100 connections"
    echo "  $0 rate 60s 200                # 1-minute test at 200 req/s"
    echo "  $0 sustained 600s 75           # 10-minute sustained test with 75 connections"
    echo ""
    echo "Note: Make sure your nginx deployment is running before starting tests."
}

# Main script logic
main() {
    echo "=========================================="
    echo "Nginx Load Testing Script"
    echo "=========================================="
    
    # Check prerequisites
    check_bombardier
    
    # Get load balancer IP
    get_lb_ip
    
    case "${1:-basic}" in
        "health")
            check_service_health
            get_mig_status
            get_backend_health
            ;;
        "basic")
            check_service_health
            run_basic_test "$2" "$3"
            ;;
        "rate")
            check_service_health
            run_rate_test "$2" "$3"
            ;;
        "stress")
            check_service_health
            run_stress_test
            ;;
        "endpoints")
            check_service_health
            run_endpoint_tests "$2" "$3"
            ;;
        "sustained")
            check_service_health
            print_info "Starting sustained load test. Press Ctrl+C to stop early."
            run_sustained_test "$2" "$3"
            ;;
        "all")
            check_service_health
            print_info "Running complete test suite..."
            
            run_basic_test "30s" "25"
            sleep 15
            
            run_rate_test "30s" "50"
            sleep 15
            
            run_endpoint_tests "30s" "25"
            sleep 15
            
            print_info "Skipping stress and sustained tests in 'all' mode. Run them individually if needed."
            ;;
        "help"|"-h"|"--help")
            usage
            ;;
        *)
            print_error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
    
    print_success "Load testing completed!"
    print_info "Check your GCP Console for autoscaling activity and metrics."
}

# Run main function with all arguments
main "$@"