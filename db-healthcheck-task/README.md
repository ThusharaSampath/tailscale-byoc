# Database Health Check Task

A simple Ballerina task that performs a one-time database health check and exits.

## Overview

This task:
1. Connects to a Microsoft SQL Server database
2. Executes a health check query
3. Logs the results (success or failure)
4. Closes the connection and exits

## Configuration

Edit `Config.toml` to configure the database connection:

```toml
host = "your-database-host"
port = 1433
username = "your-username"
password = "your-password"
database = "your-database"
```

## Running the Task

```bash
# Build the project
bal build

# Run the task
bal run

# Or run with custom config
bal run -- --host=localhost --port=1433 --username=sa --password=yourpass --database=master
```

## Output

The task will log:
- Connection status
- Query execution status
- Query execution time
- Query results (database version, server name, etc.)
- Total execution time

### Success Example:
```
========================================
Database Health Check Task
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
time=... level=INFO message="
========================================
Task completed successfully
Total execution time: 150.45ms
========================================
"
```

### Failure Example:
```
time=... level=ERROR message="✗ FAILED to connect to database: Connection refused"
```

## Use Cases

This task is suitable for:
- Kubernetes CronJobs for periodic database health checks
- CI/CD pipeline health verification
- Scheduled database connectivity monitoring
- Quick database connection testing
- Container readiness/liveness probes

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
