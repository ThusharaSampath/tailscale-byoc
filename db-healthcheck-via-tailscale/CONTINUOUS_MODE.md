# Continuous Mode Update Summary

## Changes Made

### 1. Removed Time-Limited Execution
**Before:**
- Application ran for a fixed duration (`testDurationMinutes`)
- Stopped after the duration elapsed
- Printed final statistics and closed connections

**After:**
- Application runs continuously (infinite loop)
- Never stops unless manually terminated (Ctrl+C or container killed)
- Perfect for long-running server deployments in Choreo/Kubernetes

### 2. Code Changes

#### Removed Configuration:
```ballerina
// REMOVED
configurable int testDurationMinutes = 10;
```

#### Updated main() function:
```ballerina
// Before:
check runTestWorkload(dbClient, testDurationMinutes);
printFinalStatistics();
check dbClient.close();

// After:
check runTestWorkload(dbClient);
// Never reaches here - runs forever
```

#### Updated runTestWorkload() function:
```ballerina
// Before:
function runTestWorkload(mssql:Client dbClient, int durationMinutes) returns error? {
    time:Utc endTime = time:utcAddSeconds(time:utcNow(), durationMinutes * 60);
    while <decimal>time:utcDiffSeconds(endTime, time:utcNow()) > 0d {
        // ... execute queries
    }
    log:printInfo("Test workload completed");
}

// After:
function runTestWorkload(mssql:Client dbClient) returns error? {
    while true {  // Infinite loop
        // ... execute queries
    }
    // Never reaches here
}
```

### 3. Updated Files

#### main.bal
- Removed `testDurationMinutes` configurable
- Updated startup banner: "Mode: Continuous (long-running server)"
- Changed `while` condition from time-based to `while true`
- Removed final statistics printing
- Removed connection pool closing

#### Config.toml
- Removed `testDurationMinutes = 1` parameter

#### README.md
- Updated feature list to mention "Continuous operation"
- Removed `testDurationMinutes` from configuration examples
- Updated deployment instructions
- Updated example output to show continuous operation
- Added note about stopping with Ctrl+C

### 4. Behavior

**Continuous Operation:**
```
Application starts
    ↓
Initialize database connection pool
    ↓
Start HTTP service on port 9090
    ↓
Start infinite workload loop:
    ├─ Execute DB query every 1-5 seconds
    ├─ Execute SFTP check every 10 queries
    ├─ Send notifications on failures
    ├─ Print statistics every 50 queries
    └─ Repeat forever...
```

**How to Stop:**
- **Local Development**: Press `Ctrl+C`
- **Docker/Kubernetes**: Send SIGTERM signal (container stop)
- **Choreo**: Stop the component

### 5. Statistics

**Periodic Statistics (every 50 queries):**
- Still printed to logs
- Shows cumulative stats since startup
- Useful for monitoring long-running health

**Final Statistics:**
- No longer printed (app never stops)
- Use `/stats` HTTP endpoint to get current statistics
- Statistics accumulate indefinitely

### 6. Use Cases

**Perfect for:**
✅ Long-running health check services in Kubernetes/Choreo
✅ Continuous database connectivity monitoring
✅ Production environments requiring 24/7 monitoring
✅ Sidecar containers for health checking

**Not suitable for:**
❌ One-time health checks (use db-healthcheck-task instead)
❌ Time-limited performance tests
❌ Batch job scenarios

### 7. Deployment Considerations

**Resource Management:**
- Connection pool size: Adjust based on load
- Memory: Statistics arrays grow indefinitely (consider periodic reset)
- CPU: Minimal usage during sleep intervals

**Monitoring:**
- Use `/health` endpoint for liveness probe
- Use `/stats` endpoint for metrics collection
- Monitor logs for periodic statistics

**Graceful Shutdown:**
- Application responds to SIGTERM
- Ballerina runtime handles cleanup
- Connection pool automatically closed on shutdown

## Testing

### Local Test:
```bash
cd /Users/wso2/Desktop/WSO2/RnD/tailscale-byoc/db-healthcheck-via-tailscale

# Run continuously (stop with Ctrl+C)
bal run

# In another terminal:
curl http://localhost:9090/health
curl http://localhost:9090/stats
```

### Expected Output:
```
Starting continuous workload...
[Query 1] ✓ DB SUCCESS - 54.3ms
[Query 2] ✓ DB SUCCESS - 52.1ms
...
(continues forever until stopped)
```

### Kubernetes Deployment:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db-healthcheck
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: healthcheck
        image: your-image:latest
        ports:
        - containerPort: 9090
        livenessProbe:
          httpGet:
            path: /health
            port: 9090
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 9090
          initialDelaySeconds: 10
          periodSeconds: 5
```

## Migration Notes

If you were using the time-limited version and need to migrate:

1. **Remove from Config.toml:**
   ```toml
   # DELETE THIS LINE:
   testDurationMinutes = 10
   ```

2. **Remove from command-line args:**
   ```bash
   # DON'T USE:
   bal run -- -CtestDurationMinutes=15
   
   # INSTEAD USE:
   bal run  # Runs forever
   ```

3. **Update monitoring:**
   - Don't wait for final statistics (they won't appear)
   - Use `/stats` endpoint instead
   - Monitor periodic statistics in logs

## Benefits

✅ **Simpler**: No need to configure duration
✅ **Production-ready**: Designed for long-running services
✅ **Kubernetes-native**: Works perfectly with container orchestration
✅ **Always-on monitoring**: Continuous health checking
✅ **Real-world usage**: Matches actual production scenarios
