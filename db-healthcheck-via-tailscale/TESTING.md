# Testing Guide - Combined Health Check Notifications

## What Changed

### Before:
- Database check failed → immediate notification + return 500
- Then SFTP check runs → separate notification if it fails

### After:
- Database check runs (don't return yet)
- SFTP check runs (if enabled)
- Collect all errors
- Send ONE combined notification with all failures
- Then return 500 if any failed

## Testing Scenarios

### Scenario 1: Both Services Healthy
**Expected:**
```bash
curl http://localhost:9090/health
# Returns: 200 OK
# Logs: "✓ Database health check succeeded"
#       "✓ SFTP health check succeeded"
#       "✓ All health checks succeeded"
# Notification: None
```

### Scenario 2: Database Fails, SFTP OK
**Expected:**
```bash
curl http://localhost:9090/health
# Returns: 500 Internal Server Error
# Logs: "✗ Database health check failed"
#       "✓ SFTP health check succeeded"
# Notification: 
# 🔴 Health Check Failed
# *Database:* <error message>
# Timestamp: <timestamp>
```

### Scenario 3: Database OK, SFTP Fails
**Expected:**
```bash
curl http://localhost:9090/health
# Returns: 500 Internal Server Error
# Logs: "✓ Database health check succeeded"
#       "✗ SFTP health check failed"
# Notification:
# 🔴 Health Check Failed
# *SFTP (172.16.20.31:22):* <error message>
# Timestamp: <timestamp>
```

### Scenario 4: Both Services Fail
**Expected:**
```bash
curl http://localhost:9090/health
# Returns: 500 Internal Server Error
# Logs: "✗ Database health check failed"
#       "✗ SFTP health check failed"
# Notification:
# 🔴 Health Check Failed
# *Database:* <db error>
# *SFTP (172.16.20.31:22):* <sftp error>
# Timestamp: <timestamp>
```

### Scenario 5: Workload with Failures (Query 10)
**Expected in logs:**
```
[Query 10] ✓ DB SUCCESS - 54.3ms
[Query 10] ✗ SFTP FAILED - Authentication failed

# Notification sent:
# 🔴 Health Check Failed (Workload)
# *SFTP (172.16.20.31:22):* Authentication failed
# Query: 10
# Timestamp: <timestamp>
```

### Scenario 6: SFTP Disabled
**Expected:**
```bash
# Config.toml: enableFtpCheck = false
curl http://localhost:9090/health
# Returns: 200 OK (only checks database)
# Logs: "✓ Database health check succeeded"
#       "✓ All health checks succeeded"
# No SFTP check performed
```

## How to Test

### 1. Test with Both Services Up
```bash
cd /Users/wso2/Desktop/WSO2/RnD/tailscale-byoc/db-healthcheck-via-tailscale

# Make sure Config.toml has correct settings:
# enableFtpCheck = true
# enableChatNotification = true
# googleChatWebhookUrl = "https://..."

bal run

# In another terminal:
curl http://localhost:9090/health
```

### 2. Test with Database Down
```bash
# Stop database or change Config.toml to wrong host/port
# Then:
curl http://localhost:9090/health

# Check Google Chat for notification
```

### 3. Test with SFTP Down
```bash
# Change ftpHost or ftpPassword in Config.toml to wrong values
# Then:
curl http://localhost:9090/health

# Check Google Chat for notification
```

### 4. Test Workload
```bash
# Let the application run for a few minutes
# Monitor logs for:
# - DB checks every 1-5 seconds
# - SFTP checks every 10 queries (query 10, 20, 30...)
# - Combined notifications on failures
```

## Verification Checklist

- [ ] `/health` endpoint checks both DB and SFTP before responding
- [ ] Single notification sent with all failures combined
- [ ] No immediate return on first failure
- [ ] Workload checks SFTP every 10 queries
- [ ] Workload sends combined notification if any check fails
- [ ] SFTP check skipped when `enableFtpCheck = false`
- [ ] Notification includes all failed services
- [ ] Notification only sent when `enableChatNotification = true`

## Code Flow

```
/health endpoint called
    ↓
Check Database (don't return yet)
    ↓
Check SFTP (if enabled)
    ↓
Build failures array
    ↓
If failures.length() > 0:
    ↓
    Send combined notification
    ↓
    Return 500
Else:
    ↓
    Return 200
```

```
Workload running
    ↓
Execute DB query
    ↓
Check if query count % 10 == 0
    ↓
If yes: Execute SFTP check
    ↓
Build failures array
    ↓
If failures.length() > 0:
    ↓
    Send combined notification
    ↓
Update statistics
    ↓
Continue to next query
```
