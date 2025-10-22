# Database & SFTP Health Check via Tailscale

A Ballerina application to continuously test database and SFTP connectivity through Tailscale proxy in Choreo.

## Features

- ✅ **Database Connection pooling** - Configurable pool size (default: 10)
- ✅ **SFTP Health Check** - Test SFTP server connectivity
- ✅ **Random query intervals** - Simulates real application behavior
- ✅ **HTTP health check endpoints** - Monitor via `/health` and `/stats`
- ✅ **Google Chat Notifications** - Get alerted on failures
- ✅ **Comprehensive statistics** - Success rate, latency (avg, P50, P95, P99), QPS
- ✅ **Continuous operation** - Runs as a long-running server
- ✅ **Configurable** - All parameters configurable via Config.toml

## Configuration

Edit `Config.toml` to configure:

### Database Configuration
```toml
host = "localhost"              # Tailscale proxy host
port = 8082                     # Tailscale proxy port
username = "sa"                 # Database username
password = "YourPasswordHere"   # Database password (REQUIRED)
database = "master"             # Database name
poolSize = 10                   # Connection pool size
minIntervalSeconds = 1.0        # Min interval between queries
maxIntervalSeconds = 5.0        # Max interval between queries
```

### SFTP Configuration
```toml
enableFtpCheck = true           # Enable/disable SFTP health check (REQUIRED)
ftpHost = "172.16.20.31"        # SFTP server host
ftpPort = 22                    # SFTP server port (22 for SFTP, 21 for FTP)
ftpUsername = "WSO2"            # SFTP username
ftpPassword = "YourPassword"    # SFTP password
ftpTestPath = ""                # Test path (leave empty for connection test only)
```

### Google Chat Notification Configuration
```toml
enableChatNotification = true   # Enable/disable Google Chat notifications (REQUIRED)
googleChatWebhookUrl = "https://chat.googleapis.com/v1/spaces/YOUR_SPACE/messages?key=YOUR_KEY"
```

> **Note**: `enableFtpCheck` and `enableChatNotification` are required parameters. Set them to `false` if you don't want to use these features.

## Local Testing

```bash
# Build
bal build

# Run with Config.toml (runs continuously)
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
  -CenableFtpCheck=true \
  -CenableChatNotification=true

# Stop with Ctrl+C
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
- `ENABLE_FTP_CHECK` - Enable SFTP health checks (true/false)
- `ENABLE_CHAT_NOTIFICATION` - Enable Google Chat notifications (true/false)
- `GOOGLE_CHAT_WEBHOOK_URL` - Google Chat webhook URL (if notifications enabled)

### Step 2: Deploy

Push to GitHub and deploy via Choreo. The application will run continuously as a long-running service.

## HTTP Endpoints

### Health Check (Database + SFTP)
```bash
curl http://localhost:9090/health
```

This endpoint performs:
- ✅ **Database health check** - Verifies database connectivity
- ✅ **SFTP health check** - Verifies SFTP server connectivity (if enabled)

Returns:
- `200 OK` - All health checks passed
- `500 Internal Server Error` - One or more health checks failed (sends Google Chat notification if enabled)

**Response on Success:**
```json
{
  "status": "All health checks succeeded"
}
```

**Response on Failure:**
```json
{
  "status": "Health check failed"
}
```

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
Mode:               Continuous (long-running server)
SFTP Enabled:       true
SFTP Host:          172.16.20.31:22
Notifications:      enabled
========================================

✓ Connection pool initialized
✓ Health check HTTP service started on port 9090
Starting continuous workload...

[Query 1] ✓ DB SUCCESS - 54.3ms
[Query 2] ✓ DB SUCCESS - 52.1ms
[Query 3] ✓ DB SUCCESS - 55.7ms
...
[Query 10] ✓ DB SUCCESS - 53.2ms
[Query 10] ✓ SFTP SUCCESS - 145.8ms
...

--- Statistics (5m 0s elapsed) ---
Total Queries:    150
Successful:       150
Failed:           0
Success Rate:     100.0%
-------------------------------------------------

(Application continues running indefinitely...)
```

> **Note**: 
> - The application runs continuously until stopped (Ctrl+C or container termination)
> - SFTP health check is performed every 10 database queries to avoid excessive connection overhead
> - Statistics are printed every 50 queries

## Google Chat Notifications

When `enableChatNotification=true`, the application sends notifications to Google Chat webhook on failures:

**Database Health Check Failure (from /health endpoint):**
```
� Database Health Check Failed
Error: Connection timeout
Timestamp: 2025-01-10T10:30:45Z
```

**Database Health Check Failure (from workload):**
```
🔴 Database Health Check Failed (Workload)
Error: Connection timeout
Query: 145
Timestamp: 2025-01-10T10:30:45Z
```

**SFTP Health Check Failure:**
```
� SFTP Health Check Failed (Workload)
Error: Authentication failed
Host: 172.16.20.31:22
Timestamp: 2025-01-10T10:30:45Z
```

### Setting up Google Chat Webhook

1. Go to Google Chat space settings
2. Configure Webhooks
3. Create a new webhook
4. Copy the webhook URL to `Config.toml`

## How It Works

### Health Check Workflow

1. **HTTP `/health` Endpoint**:
   - Checks database connectivity
   - Checks SFTP connectivity (if enabled)
   - Returns 200 OK if both pass, 500 if either fails
   - Sends Google Chat notification on any failure

2. **Background Workload**:
   - Continuously executes database queries at random intervals
   - Performs SFTP health check every 10 database queries
   - Sends Google Chat notification on any failure
   - Tracks statistics (success rate, latency, QPS)

## Troubleshooting

### Database Connection Failures

If you see database connection failures:

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

### SFTP Connection Failures

If SFTP health check fails:

1. **Verify SFTP credentials**
   ```bash
   sftp -P 22 WSO2@172.16.20.31
   ```

2. **Check port configuration**
   - Port 22 for SFTP (SSH File Transfer Protocol)
   - Port 21 for FTP (File Transfer Protocol)

3. **Test from local environment**
   ```bash
   curl http://localhost:9090/sftp
   ```

4. **Verify Tailscale connectivity to SFTP server**
   ```bash
   ping 172.16.20.31
   ```

### Google Chat Notifications Not Received

If notifications are not received:

1. **Verify webhook URL is correct**
   - Check `googleChatWebhookUrl` in Config.toml
   - Test webhook manually:
     ```bash
     curl -X POST "YOUR_WEBHOOK_URL" \
       -H "Content-Type: application/json" \
       -d '{"text":"Test message"}'
     ```

2. **Check enableChatNotification is true**
   ```toml
   enableChatNotification = true
   ```

3. **Review application logs** for HTTP errors when posting to webhook
- Decrease query rate (increase intervals)
- Check database max connections limit
