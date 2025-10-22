# Changes Summary - SFTP & Google Chat Integration

## Overview
Updated the database health check API to include SFTP health checks and Google Chat notifications, integrated into both the HTTP endpoint and background workload.

## ⚠️ IMPORTANT BEHAVIOR UPDATE (Latest)

**Combined Health Check Notifications:**
- The system now checks BOTH database and SFTP before sending any notification
- Only ONE combined notification is sent with all failures included
- No immediate return on first failure - both checks complete first

## Key Changes

### 1. New Health Check Functions

#### `performDatabaseHealthCheck(mssql:Client dbClient)`
- Extracted database health check logic into a reusable function
- Returns error if database connection fails
- Used by both HTTP endpoint and background workload

#### `performSftpHealthCheck()`
- Tests SFTP/FTP connectivity based on configured port
- Port 22 = SFTP, Port 21 = FTP
- Returns error if connection fails
- Skips check if `enableFtpCheck = false`

### 2. HTTP `/health` Endpoint Behavior

**OLD Behavior:**
- Only checked database connectivity

**NEW Behavior:**
- Checks database connectivity
- Checks SFTP connectivity (if enabled)
- Returns `200 OK` only if BOTH checks pass
- Returns `500 Internal Server Error` if ANY check fails
- Sends Google Chat notification on failures

### 3. Background Workload (`runTestWorkload`)

**Added:**
- SFTP health check every 10 database queries
- Google Chat notifications on database failures
- Google Chat notifications on SFTP failures
- Separate logging for DB vs SFTP checks

**Log Format:**
```
[Query 1] ✓ DB SUCCESS - 54.3ms
[Query 10] ✓ DB SUCCESS - 53.2ms
[Query 10] ✓ SFTP SUCCESS - 145.8ms
```

### 4. Google Chat Notifications

**UPDATED BEHAVIOR:** Combined notifications only, sent after checking all services.

Two types of notifications:

1. **Combined failure from /health endpoint:**
   ```
   🔴 Health Check Failed
   *Database:* Connection timeout
   *SFTP (172.16.20.31:22):* Authentication failed
   
   Timestamp: <timestamp>
   ```

2. **Combined failure from workload:**
   ```
   🔴 Health Check Failed (Workload)
   *Database:* Connection timeout
   *SFTP (172.16.20.31:22):* Authentication failed
   
   Query: <query number>
   Timestamp: <timestamp>
   ```

**Key Points:**
- ✅ Checks BOTH services before sending notification
- ✅ Single notification with all failures combined
- ✅ If only one service fails, only that service appears in the notification
- ❌ NO separate notifications for each failure
- ❌ NO immediate return on first failure

### 5. Configuration

Required parameters:
```toml
enableFtpCheck = true              # REQUIRED
enableChatNotification = true      # REQUIRED
```

Optional SFTP parameters (if enableFtpCheck=true):
```toml
ftpHost = "172.16.20.31"
ftpPort = 22
ftpUsername = "WSO2"
ftpPassword = "password"
ftpTestPath = ""
```

Optional notification parameter (if enableChatNotification=true):
```toml
googleChatWebhookUrl = "https://chat.googleapis.com/..."
```

## Testing

### Test Health Endpoint
```bash
# Should check both DB and SFTP
curl http://localhost:9090/health

# Returns 200 if both pass
# Returns 500 if either fails
```

### Test with Config
```bash
cd /Users/wso2/Desktop/WSO2/RnD/tailscale-byoc/db-healthcheck-via-tailscale
bal run
```

### Monitor Logs
Look for:
- `[Query X] ✓ DB SUCCESS`
- `[Query X] ✓ SFTP SUCCESS` (every 10 queries)
- Google Chat notification messages on failures

## Architecture

```
┌─────────────────────────────────────────────────┐
│           HTTP Service (Port 9090)              │
│                                                 │
│  GET /health                                    │
│    ├─ performDatabaseHealthCheck()              │
│    └─ performSftpHealthCheck() (if enabled)     │
│                                                 │
│  GET /stats                                     │
│    └─ Returns query statistics                  │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│         Background Workload (Async)             │
│                                                 │
│  Every 1-5 seconds:                             │
│    ├─ executeHealthQuery() (DB check)           │
│    └─ Send notification on failure              │
│                                                 │
│  Every 10 queries:                              │
│    ├─ performSftpHealthCheck()                  │
│    └─ Send notification on failure              │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│         Google Chat Notifications               │
│                                                 │
│  Triggered by:                                  │
│    ├─ /health endpoint failures                 │
│    ├─ Background DB query failures              │
│    └─ Background SFTP check failures            │
└─────────────────────────────────────────────────┘
```

## Differences from db-healthcheck-task

| Feature | db-healthcheck-task | db-healthcheck-via-tailscale |
|---------|---------------------|------------------------------|
| Execution Model | One-time batch job | Long-running service |
| HTTP Endpoints | None | /health, /stats |
| DB Health Check | One-time at start | Continuous (every 1-5s) |
| SFTP Health Check | One-time at start | Every 10 DB queries |
| Statistics | Printed at end | Available via /stats |
| Notifications | On task completion | On each failure |
