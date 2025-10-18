#!/bin/sh

# Simple DERP Performance Test
# Run from Choreo container

HOST="0.0.0.0"
PORT="8080"
DURATION=600  # 10 minutes
INTERVAL=1    # seconds between requests

echo "=== DERP Performance Test ==="
echo "Target: $HOST:$PORT"
echo "Duration: $DURATION seconds"
echo "Start: $(date)"
echo ""

success=0
failed=0
total=0
total_latency=0

start_time=$(date +%s)
end_time=$((start_time + DURATION))

while [ $(date +%s) -lt $end_time ]; do
    total=$((total + 1))
    payload="packet-$total-$(date +%s)"

    # Measure latency
    start=$(date +%s%N 2>/dev/null || date +%s)
    response=$(echo "$payload" | nc -w 2 $HOST $PORT 2>&1)
    rc=$?
    end=$(date +%s%N 2>/dev/null || date +%s)

    # Calculate latency in ms
    if [ -n "$start" ] && [ -n "$end" ]; then
        latency=$(( (end - start) / 1000000 ))
    else
        latency=0
    fi

    if [ $rc -eq 0 ] && [ "$response" = "$payload" ]; then
        success=$((success + 1))
        total_latency=$((total_latency + latency))
        echo "[$total] OK - ${latency}ms"
    else
        failed=$((failed + 1))
        echo "[$total] FAIL - rc=$rc response='$response'"
    fi

    # Stats every 60 requests
    if [ $((total % 60)) -eq 0 ]; then
        rate=$((success * 100 / total))
        avg_latency=$((total_latency / success))
        echo ""
        echo "--- $total requests | Success: $success | Failed: $failed | Rate: ${rate}% | Avg: ${avg_latency}ms ---"
        echo ""
    fi

    sleep $INTERVAL
done

# Final stats
elapsed=$(($(date +%s) - start_time))
rate=$((success * 100 / total))
if [ $success -gt 0 ]; then
    avg_latency=$((total_latency / success))
else
    avg_latency=0
fi

echo ""
echo "=== COMPLETE ==="
echo "Duration: ${elapsed}s"
echo "Total: $total | Success: $success | Failed: $failed"
echo "Success rate: ${rate}%"
echo "Avg latency: ${avg_latency}ms"
