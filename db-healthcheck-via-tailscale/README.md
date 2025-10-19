# Database Health Check via Tailscale

A Ballerina application to test database connectivity through Tailscale proxy in Choreo.

## Features

- ✅ **Connection pooling** - Configurable pool size (default: 10)
- ✅ **Random query intervals** - Simulates real application behavior
- ✅ **HTTP health check endpoint** - Monitor via `/health` and `/stats`
- ✅ **Comprehensive statistics** - Success rate, latency (avg, P50, P95, P99), QPS
- ✅ **Configurable** - All parameters configurable via Config.toml

## Configuration

Edit `Config.toml` to configure:

```toml
host = "localhost"              # Tailscale proxy host
port = 8082                     # Tailscale proxy port
username = "sa"                 # Database username
password = "YourPasswordHere"   # Database password (REQUIRED)
database = "master"             # Database name
poolSize = 10                   # Connection pool size
minIntervalSeconds = 1.0        # Min interval between queries
maxIntervalSeconds = 5.0        # Max interval between queries
testDurationMinutes = 10        # Test duration
```

## Local Testing

```bash
# Build
bal build

# Run with Config.toml
bal run

# Or run with command-line config
bal run -- \
  -Chost=172.19.239.28 \
  -Cport=8082 \
  -Cusername=sa \
  -Cpassword=YourPassword \
  -Cdatabase=master \
  -CpoolSize=20 \
  -CminIntervalSeconds=0.5 \
  -CmaxIntervalSeconds=3.0 \
  -CtestDurationMinutes=15
```

## Deploy to Choreo

### Step 1: Configure Environment Variables

In Choreo component settings, add:

- `HOST` - Tailscale proxy service name (e.g., `tailscale-proxy-service.default.svc.cluster.local`)
- `PORT` - Tailscale proxy port (e.g., `8082`)
- `USERNAME` - Database username
- `PASSWORD` - Database password (use Choreo secrets)
- `DATABASE` - Database name
- `POOL_SIZE` - Connection pool size (optional, default: 10)
- `MIN_INTERVAL_SECONDS` - Min interval (optional, default: 1.0)
- `MAX_INTERVAL_SECONDS` - Max interval (optional, default: 5.0)
- `TEST_DURATION_MINUTES` - Test duration (optional, default: 10)

### Step 2: Map Ballerina Configurables

Create ConfigMap or use Choreo's config:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-healthcheck-config
data:
  Config.toml: |
    host = "${HOST}"
    port = ${PORT}
    username = "${USERNAME}"
    password = "${PASSWORD}"
    database = "${DATABASE}"
    poolSize = ${POOL_SIZE}
    minIntervalSeconds = ${MIN_INTERVAL_SECONDS}
    maxIntervalSeconds = ${MAX_INTERVAL_SECONDS}
    testDurationMinutes = ${TEST_DURATION_MINUTES}
```

### Step 3: Deploy

Push to GitHub and deploy via Choreo.

## HTTP Endpoints

### Health Check
```bash
curl http://localhost:9090/health
```

Returns:
- `200 OK` - Database is reachable
- `500 Internal Server Error` - Database is down

### Statistics
```bash
curl http://localhost:9090/stats
```

Returns JSON:
```json
{
  "totalQueries": 120,
  "successfulQueries": 120,
  "failedQueries": 0,
  "successRate": 100.0,
  "elapsedSeconds": 300.5,
  "errorCount": 0
}
```

## Example Output

```
========================================
Database Health Check via Tailscale
========================================
Host:               172.19.239.28
Port:               8082
Database:           master
Username:           sa
Pool Size:          10
Query Interval:     1.0s - 5.0s
Test Duration:      10 minutes
========================================

✓ Connection pool initialized
✓ Health check HTTP service started on port 9090
Starting test workload...

[Query 1] ✓ SUCCESS - 54.3ms
[Query 2] ✓ SUCCESS - 52.1ms
[Query 3] ✓ SUCCESS - 55.7ms
...

--- Statistics (5m 0s elapsed) ---
Total Queries:    150
Successful:       150
Failed:           0
Success Rate:     100.0%
-------------------------------------------------

========================================
=== FINAL RESULTS ===
========================================
Total duration:     10m 0s

Total Queries:      300
  Successful:       300
  Failed:           0
  Success Rate:     100.0%
  Queries/second:   0.5

Query Latency:
  Average:          54.2ms
  P50 (median):     53.8ms
  P95:              68.5ms
  P99:              82.3ms
========================================
```

## Troubleshooting

### Connection Failures

If you see connection failures:

1. **Check Tailscale proxy is running**
   ```bash
   kubectl get pods | grep tailscale-proxy
   ```

2. **Verify proxy service**
   ```bash
   kubectl get svc tailscale-proxy-service
   ```

3. **Test connectivity from pod**
   ```bash
   kubectl exec -it <health-check-pod> -- nc -zv <proxy-service> <port>
   ```

4. **Check logs**
   ```bash
   kubectl logs <health-check-pod>
   ```

### High Latency

If latency is high (>100ms):

- Check DERP relay usage in Tailscale logs
- Verify direct connection is established (not DERP-only)
- Check network between Choreo and customer's Tailscale node

### Pool Exhaustion

If you see "connection pool exhausted":

- Increase `poolSize` in Config.toml
- Decrease query rate (increase intervals)
- Check database max connections limit
