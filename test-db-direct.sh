#!/bin/bash

# Test direct database connectivity through Tailscale
# This bypasses the forwarder proxy to test end-to-end Tailscale connectivity

# Function to test connection with timeout
test_connection() {
    local host=$1
    local port=$2
    local timeout_sec=5
    
    # Run nc in background
    nc -zv $host $port &
    local nc_pid=$!
    
    # Wait for timeout or completion
    local count=0
    while [ $count -lt $timeout_sec ]; do
        if ! kill -0 $nc_pid 2>/dev/null; then
            # Process finished
            wait $nc_pid
            return $?
        fi
        sleep 1
        count=$((count + 1))
    done
    
    # Timeout reached, kill the process
    kill $nc_pid 2>/dev/null
    wait $nc_pid 2>/dev/null
    return 124  # timeout exit code
}

echo "=== Testing Direct Database Connectivity via Tailscale ==="
echo ""

# Test targets from config
DB1="172.16.4.207"
DB2="172.16.20.88"
SSH="172.16.20.31"
FTP="172.16.4.126"

echo "1. Testing TCP connectivity to DB servers..."
echo ""

# Test DB1 (Primary failing server from logs)
echo "Testing $DB1:1433 (Primary DB from error logs)..."
test_connection $DB1 1433
if [ $? -eq 0 ]; then
    echo "✓ TCP connection successful to $DB1:1433"
else
    echo "✗ TCP connection failed to $DB1:1433"
fi
echo ""

# Test DB2 (Secondary DB from logs)
echo "Testing $DB2:1433 (Secondary DB)..."
test_connection $DB2 1433
if [ $? -eq 0 ]; then
    echo "✓ TCP connection successful to $DB2:1433"
else
    echo "✗ TCP connection failed to $DB2:1433"
fi
echo ""

# Test SSH
echo "Testing $SSH:22 (SSH server)..."
test_connection $SSH 22
if [ $? -eq 0 ]; then
    echo "✓ TCP connection successful to $SSH:22"
else
    echo "✗ TCP connection failed to $SSH:22"
fi
echo ""

# Test FTP
echo "Testing $FTP:21 (FTP server)..."
test_connection $FTP 21
if [ $? -eq 0 ]; then
    echo "✓ TCP connection successful to $FTP:21"
else
    echo "✗ TCP connection failed to $FTP:21"
fi
echo ""

echo "=== Tailscale Route Check ==="
echo ""
echo "Checking Tailscale status for subnet routes..."
tailscale status | grep -E "offers|relay"
echo ""

echo "=== Ready for SQL Authentication Test ==="
echo ""
echo "If TCP connectivity succeeded, you can test SQL authentication with:"
echo ""
echo "For SQL Server authentication test, you'll need sqlcmd or a Python script."
echo "Would you like to proceed with SQL authentication testing?"
