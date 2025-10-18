#!/bin/bash

# Test for intermittent connection failures through Tailscale
# This will help identify if failures are timing-related or random

TARGET_HOST="172.16.4.207"
TARGET_PORT="1433"
ITERATIONS=100
DELAY=10  # seconds between tests

success=0
failed=0
total=0

echo "=== Testing Intermittent Connection Issues ==="
echo "Target: $TARGET_HOST:$TARGET_PORT"
echo "Iterations: $ITERATIONS"
echo "Delay: ${DELAY}s"
echo ""
echo "Starting test at $(date)"
echo ""

for i in $(seq 1 $ITERATIONS); do
    total=$i

    # Use nc with 2 second timeout
    result=$(nc -zv -G 2 $TARGET_HOST $TARGET_PORT 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        success=$((success + 1))
        echo "[$i/$ITERATIONS] ✓ Success"
    else
        failed=$((failed + 1))
        echo "[$i/$ITERATIONS] ✗ FAILED - $result"

        # On failure, check Tailscale connectivity
        echo "    Checking Tailscale ping..."
        tailscale_ping=$(tailscale ping --c 1 --timeout 2s 100.97.54.81 2>&1 | head -1)
        echo "    $tailscale_ping"
    fi

    # Progress summary every 10 iterations
    if [ $((i % 10)) -eq 0 ]; then
        success_rate=$(awk "BEGIN {printf \"%.1f\", ($success/$total)*100}")
        echo "    --- Progress: $success/$total successful ($success_rate%) ---"
        echo ""
    fi

    sleep $DELAY
done

echo ""
echo "=== Test Complete at $(date) ==="
echo ""
echo "Results:"
echo "  Total attempts: $total"
echo "  Successful: $success"
echo "  Failed: $failed"
success_rate=$(awk "BEGIN {printf \"%.2f\", ($success/$total)*100}")
echo "  Success rate: $success_rate%"
echo ""

if [ $failed -gt 0 ]; then
    failure_rate=$(awk "BEGIN {printf \"%.2f\", ($failed/$total)*100}")
    echo "⚠️  Detected $failed failures ($failure_rate% failure rate)"
    echo "This suggests intermittent connectivity issues."
else
    echo "✓ All connections successful - no intermittent issues detected"
fi
