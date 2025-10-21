# Health Check Task

A Ballerina task that performs database and FTP server health checks and exits.

## Overview

This task can:
1. Connect to a Microsoft SQL Server database and execute a health check query
2. Connect to an FTP server and test connectivity by listing a directory
3. Log detailed results (success or failure) for each check
4. Exit with appropriate status code

## Configuration

Edit `Config.toml` to configure the health checks:

### Database Configuration
```toml
host = "your-database-host"
port = 1433
username = "your-username"
password = "your-password"
database = "your-database"
```

### FTP Configuration
```toml
enableFtpCheck = true  # Set to true to enable FTP health checks
ftpHost = "ftp.example.com"
ftpPort = 21
ftpUsername = "ftpuser"
ftpPassword = "ftppassword"
ftpTestPath = "/"  # Path to test (e.g., "/" or "/uploads")
```

## Running the Task

```bash
# Build the project
bal build

# Run the task (database check only)
bal run

# Run with FTP check enabled
bal run -- --enableFtpCheck=true --ftpHost=ftp.example.com --ftpUsername=user --ftpPassword=pass

# Run with all custom config
bal run -- --host=localhost --port=1433 --username=sa --password=yourpass --database=master --enableFtpCheck=true --ftpHost=ftp.example.com --ftpPort=21 --ftpUsername=ftpuser --ftpPassword=ftppass --ftpTestPath=/
```

## Output

The task will log:
- Connection status
- Query execution status
- Query execution time
- Query results (database version, server name, etc.)
- Total execution time

### Success Example (Database + FTP):
```
╔════════════════════════════════════════╗
║   Health Check Task Started            ║
╚════════════════════════════════════════╝

========================================
Database Health Check
========================================
Host:               172.16.20.88
Port:               1433
Database:           Devant
Username:           Devantdev
========================================
time=... level=INFO message="Attempting to connect to database..."
time=... level=INFO message="✓ Database connection established"
time=... level=INFO message="Executing health check query..."
time=... level=INFO message="✓ SUCCESS: Query executed in 45.23ms"
time=... level=INFO message="Query Results: {...}"
time=... level=INFO message="✓ Database connection closed"
========================================
Database Health Check completed successfully
Total execution time: 150.45ms
========================================

========================================
FTP Server Health Check
========================================
Host:               ftp.example.com
Port:               21
Username:           ftpuser
Test Path:          /
========================================
time=... level=INFO message="Attempting to connect to FTP server..."
time=... level=INFO message="✓ FTP connection established"
time=... level=INFO message="Listing directory: /"
time=... level=INFO message="✓ SUCCESS: Directory listed in 23.45ms"
time=... level=INFO message="Found 5 items in directory"
time=... level=INFO message="Sample files/directories:"
time=... level=INFO message="  file1.txt (1024 bytes)"
time=... level=INFO message="  file2.pdf (2048 bytes)"
time=... level=INFO message="✓ FTP operations completed successfully"
========================================
FTP Health Check completed successfully
Total execution time: 89.67ms
========================================

╔════════════════════════════════════════╗
║   All Health Checks PASSED ✓           ║
║   Total execution time: 240.12ms
╚════════════════════════════════════════╝
```

### Failure Example:
```
time=... level=ERROR message="✗ FAILED to connect to database: Connection refused"
time=... level=ERROR message="Database health check failed: Connection refused"
╔════════════════════════════════════════╗
║   Health Check Task FAILED             ║
║   Total execution time: 50.23ms
╚════════════════════════════════════════╝
```

## Use Cases

This task is suitable for:
- Kubernetes CronJobs for periodic database and FTP health checks
- CI/CD pipeline health verification
- Scheduled connectivity monitoring for databases and file servers
- Quick connection testing for databases and FTP servers
- Container readiness/liveness probes
- Monitoring VPN/Tailscale connectivity to internal resources

## Deployment

### As a Kubernetes CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-healthcheck
spec:
  schedule: "*/5 * * * *"  # Every 5 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: db-healthcheck
            image: your-registry/db-healthcheck-task:latest
            env:
            - name: HOST
              value: "database-host"
            - name: PORT
              value: "1433"
            - name: USERNAME
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: username
            - name: PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
            - name: DATABASE
              value: "your-database"
          restartPolicy: OnFailure
```

## Exit Codes

- `0`: Success - Database is healthy
- Non-zero: Failure - Database connection or query failed
