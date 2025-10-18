#!/bin/sh

# DERP Connection Performance Test
# Run this from Choreo container to test connection to local echo server

HOST="0.0.0.0"
PORT="8080"
DURATION=600  # 10 minutes in seconds
INTERVAL=1    # Send every 1 second

echo "=== DERP Performance Test ==="
echo "Target: $HOST:$PORT"
echo "Duration: $DURATION seconds (10 minutes)"
echo "Interval: $INTERVAL second(s)"
echo "Start time: $(date)"
echo ""

# Create named pipes for persistent connection
input_pipe="/tmp/derp_input_$$"
output_pipe="/tmp/derp_output_$$"
mkfifo "$input_pipe" "$output_pipe"

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    kill $nc_pid 2>/dev/null
    rm -f "$input_pipe" "$output_pipe"
    exit 0
}

# Set up signal handlers
trap cleanup INT TERM EXIT

# Start persistent netcat connection
nc $HOST $PORT < "$input_pipe" > "$output_pipe" &
nc_pid=$!

# Give netcat time to establish connection
sleep 1

success=0
failed=0
total=0
start_time=$(date +%s)
end_time=$((start_time + DURATION))

while [ $(date +%s) -lt $end_time ]; do
    total=$((total + 1))
    timestamp=$(date +%s)
    payload="test-packet-$total-timestamp-$timestamp"

    # Send data and measure time
    start=$(date +%s%3N)  # milliseconds
    
    # Send payload through the persistent connection
    echo "$payload" > "$input_pipe" &
    
    # Read response with timeout
    response=$(timeout 2 head -n 1 "$output_pipe" 2>/dev/null)
    exit_code=$?
    end=$(date +%s%3N)

    latency=$((end - start))

    if [ $exit_code -eq 0 ] && [ "$response" = "$payload" ]; then
        success=$((success + 1))
        echo "[$total] SUCCESS - ${latency}ms - $response"
    else
        failed=$((failed + 1))
        echo "[$total] FAILED - exit_code=$exit_code"
        
        # Check if connection is still alive
        if ! kill -0 $nc_pid 2>/dev/null; then
            echo "Connection lost, attempting to reconnect..."
            nc $HOST $PORT < "$input_pipe" > "$output_pipe" &
            nc_pid=$!
            sleep 1
        fi
    fi

    # Show stats every 60 requests
    if [ $((total % 60)) -eq 0 ]; then
        success_rate=$((success * 100 / total))
        echo ""
        echo "--- Stats after $total requests ---"
        echo "Success: $success | Failed: $failed | Rate: ${success_rate}%"
        echo ""
    fi

    sleep $INTERVAL
done

# Final statistics
elapsed=$(($(date +%s) - start_time))
success_rate=$((success * 100 / total))

echo ""
echo "=== Test Complete ==="
echo "End time: $(date)"
echo "Duration: $elapsed seconds"
echo "Total requests: $total"
echo "Successful: $success"
echo "Failed: $failed"
echo "Success rate: ${success_rate}%"
