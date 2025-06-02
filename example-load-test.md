# Make script executable
chmod +x load-test.sh

# Basic tests
./load-test.sh health                    # Check service health
./load-test.sh basic                     # Default: 60s, 50 connections
./load-test.sh basic 120s 100           # 2 minutes, 100 connections

# Rate-limited tests
./load-test.sh rate 60s 200             # 200 requests/second for 1 minute

# Stress testing (tests autoscaling)
./load-test.sh stress                   # Gradually increases load

# Sustained testing with monitoring
./load-test.sh sustained 300s 75       # 5 minutes with 75 connections

# Test specific endpoints
./load-test.sh endpoints 30s 25        # Test / and /health endpoints

# Run multiple test scenarios
./load-test.sh all                     # Runs basic test suite