import ballerina/ftp;
import ballerina/http;
import ballerina/log;
import ballerina/sql;
import ballerina/time;
import ballerinax/mssql;

// Database Configurable parameters
configurable string host = "localhost";
configurable int port = 1433;
configurable string username = "sa";
configurable string password = ?;
configurable string database = "master";
configurable int poolSize = 10;
configurable decimal minIntervalSeconds = 1.0;
configurable decimal maxIntervalSeconds = 5.0;

// SFTP Configurable parameters
configurable boolean enableFtpCheck = ?;
configurable string ftpHost = "localhost";
configurable int ftpPort = 22;
configurable string ftpUsername = "ftpuser";
configurable string ftpPassword = ?;
configurable string ftpTestPath = "/";

// Google Chat Notification Configuration
configurable boolean enableChatNotification = ?;
configurable string googleChatWebhookUrl = "";

// Function to send Google Chat notification
function sendGoogleChatNotification(string message) returns error? {
    if !enableChatNotification || googleChatWebhookUrl == "" {
        return;
    }

    log:printInfo("Sending notification to Google Chat...");

    http:Client chatClient = check new (googleChatWebhookUrl);

    json payload = {
        "text": message
    };

    http:Response|error response = chatClient->post("", payload);

    if response is error {
        log:printError(string `Failed to send Google Chat notification: ${response.message()}`);
        return response;
    }

    if response.statusCode == 200 {
        log:printInfo("✓ Notification sent to Google Chat successfully");
    } else {
        log:printWarn(string `Google Chat notification returned status: ${response.statusCode}`);
    }

    return;
}

// Database Health Check Function
function performDatabaseHealthCheck(mssql:Client dbClient) returns error? {
    stream<record {}, sql:Error?> resultStream = dbClient->query(`SELECT 1 as result`);
    error? closeResult = resultStream.close();
    if closeResult is error {
        return closeResult;
    }
    return;
}

// SFTP Health Check Function
function performSftpHealthCheck() returns error? {
    if !enableFtpCheck {
        return; // Skip if disabled
    }

    // Determine protocol based on port
    ftp:Protocol protocol = ftpPort == 22 ? ftp:SFTP : ftp:FTP;

    ftp:ClientConfiguration ftpConfig = {
        protocol: protocol,
        host: ftpHost,
        port: ftpPort,
        auth: {
            credentials: {
                username: ftpUsername,
                password: ftpPassword
            }
        }
    };

    ftp:Client|error ftpClient = new (ftpConfig);

    if ftpClient is error {
        return ftpClient;
    }

    return;
}

// Statistics tracking
type Statistics record {|
    int totalQueries = 0;
    int successfulQueries = 0;
    int failedQueries = 0;
    decimal[] queryLatencies = [];
    string[] errors = [];
    time:Utc startTime;
|};

Statistics stats = {
    startTime: time:utcNow()
};

public function main() returns error? {
    log:printInfo(string `
========================================
Database Health Check via Tailscale
========================================
Host:               ${host}
Port:               ${port}
Database:           ${database}
Username:           ${username}
Pool Size:          ${poolSize}
Query Interval:     ${minIntervalSeconds}s - ${maxIntervalSeconds}s
Mode:               Continuous (long-running server)
========================================
`);

    // Create connection pool
    mssql:Client dbClient = check new (
        host = host,
        port = port,
        user = username,
        password = password,
        database = database,
        connectionPool = {
            maxOpenConnections: poolSize,
            maxConnectionLifeTime: 1800,
            minIdleConnections: poolSize / 2
        }
    );

    log:printInfo("✓ Connection pool initialized");

    // Start HTTP service for health check endpoint
    _ = check startHealthCheckService(dbClient);

    // Run continuous workload (never stops)
    check runTestWorkload(dbClient);

    return;
}

// Start HTTP service for health check endpoint
function startHealthCheckService(mssql:Client dbClient) returns error? {
    _ = start httpService(dbClient);
    log:printInfo("✓ Health check HTTP service started on port 9090");
    return;
}

function httpService(mssql:Client dbClient) returns error? {
    http:Service healthService = service object {
        resource function get health() returns http:Ok|http:InternalServerError {
            log:printInfo("Received health check request (database + SFTP)");
            
            // Check both database and SFTP health before responding
            error? dbResult = performDatabaseHealthCheck(dbClient);
            error? sftpResult = enableFtpCheck ? performSftpHealthCheck() : ();
            
            // Build combined error message if any check failed
            string[] failures = [];
            
            if dbResult is error {
                log:printError(string `Database health check failed: ${dbResult.message()}`);
                failures.push(string `*Database:* ${dbResult.message()}`);
            } else {
                log:printInfo("✓ Database health check succeeded");
            }
            
            if sftpResult is error {
                log:printError(string `SFTP health check failed: ${sftpResult.message()}`);
                failures.push(string `*SFTP (${ftpHost}:${ftpPort}):* ${sftpResult.message()}`);
            } else if enableFtpCheck {
                log:printInfo("✓ SFTP health check succeeded");
            }
            
            // If any check failed, send notification and return error
            if failures.length() > 0 {
                string failuresText = "";
                foreach string failure in failures {
                    failuresText += failure + "\n";
                }
                
                string notificationMessage = string `🔴 *Health Check Failed*\n\n${failuresText}\n*Timestamp:* ${time:utcToString(time:utcNow())}`;
                error? notificationResult = sendGoogleChatNotification(notificationMessage);
                if notificationResult is error {
                    log:printWarn("Failed to send failure notification to Google Chat");
                }
                
                return http:INTERNAL_SERVER_ERROR;
            }
            
            log:printInfo("✓ All health checks succeeded");
            return http:OK;
        }

        resource function get stats() returns json {
            return getStatisticsJson();
        }
    };

    http:Listener httpListener = check new (9090);
    check httpListener.attach(healthService, "/");
    check httpListener.'start();
    return;
}

// Run continuous workload (infinite loop)
function runTestWorkload(mssql:Client dbClient) returns error? {
    int queryCount = 0;

    log:printInfo("Starting continuous workload...");

    while true {
        queryCount += 1;

        // Execute database health check query
        time:Utc queryStart = time:utcNow();
        error? dbResult = executeHealthQuery(dbClient, queryCount);
        decimal dbLatency = time:utcDiffSeconds(time:utcNow(), queryStart);

        // Perform SFTP health check if enabled (every 10 queries)
        error? sftpResult = ();
        decimal sftpLatency = 0.0;
        
        if enableFtpCheck {
            time:Utc sftpStart = time:utcNow();
            sftpResult = performSftpHealthCheck();
            sftpLatency = time:utcDiffSeconds(time:utcNow(), sftpStart);
        }

        // Build combined error message if any check failed
        string[] failures = [];
        
        if dbResult is error {
            failures.push(string `*Database:* ${dbResult.message()}`);
            log:printError(string `[Query ${queryCount}] ✗ DB FAILED - ${dbResult.message()}`);
            
            stats.failedQueries += 1;
            string errorMsg = dbResult.message();
            if !stats.errors.some(e => e == errorMsg) {
                stats.errors.push(errorMsg);
            }
        } else {
            stats.successfulQueries += 1;
            stats.queryLatencies.push(dbLatency);
            log:printInfo(string `[Query ${queryCount}] ✓ DB SUCCESS - ${(dbLatency * 1000).toString()}ms`);
        }
        
        if enableFtpCheck {
            if sftpResult is error {
                failures.push(string `*SFTP (${ftpHost}:${ftpPort}):* ${sftpResult.message()}`);
                log:printError(string `[Query ${queryCount}] ✗ SFTP FAILED - ${sftpResult.message()}`);
            } else {
                log:printInfo(string `[Query ${queryCount}] ✓ SFTP SUCCESS - ${(sftpLatency * 1000).toString()}ms`);
            }
        }

        // Update statistics
        stats.totalQueries += 1;

        // Send combined notification if any check failed
        if failures.length() > 0 {
            string failuresText = "";
            foreach string failure in failures {
                failuresText += failure + "\n";
            }
            
            string notificationMessage = string `🔴 *Health Check Failed (Workload)*\n\n${failuresText}\n*Query:* ${queryCount}\n*Timestamp:* ${time:utcToString(time:utcNow())}`;
            error? notificationResult = sendGoogleChatNotification(notificationMessage);
            if notificationResult is error {
                log:printWarn("Failed to send failure notification to Google Chat");
            }
        }

        // Print periodic statistics
        if queryCount % 50 == 0 {
            printPeriodicStatistics();
        }

        // Random interval between queries
        decimal interval = getRandomInterval(minIntervalSeconds, maxIntervalSeconds);
        // Using a simple busy wait instead of runtime:sleep
        time:Utc waitStart = time:utcNow();
        while <decimal>time:utcDiffSeconds(time:utcNow(), waitStart) < interval {
            // Busy wait
        }
    }
}

// Execute a health check query
function executeHealthQuery(mssql:Client dbClient, int queryId) returns error? {
    stream<record {}, sql:Error?> resultStream = dbClient->query(`
        SELECT
            GETDATE() as QueryTime,
            @@SPID as SessionID,
            ${queryId} as QueryID
    `);

    record {|record {} value;|}? result = check resultStream.next();
    check resultStream.close();

    if result is () {
        return error("No result returned from query");
    }

    return;
}

// Get random interval between min and max
function getRandomInterval(decimal min, decimal max) returns decimal {
    // Simple random number generation (for demo purposes)
    // In production, use a proper random library
    decimal randomMs = <decimal>(time:utcNow()[1] % 1000000000);
    decimal range = max - min;
    decimal random = (randomMs % 1000d) / 1000d;
    return min + (random * range);
}

// Print periodic statistics
function printPeriodicStatistics() {
    decimal elapsedSeconds = time:utcDiffSeconds(time:utcNow(), stats.startTime);
    int elapsedMinutes = <int>(elapsedSeconds / 60);
    int elapsedSecs = <int>(elapsedSeconds % 60);

    decimal successRate = 0.0;
    if stats.totalQueries > 0 {
        successRate = (<decimal>stats.successfulQueries / <decimal>stats.totalQueries) * 100.0;
    }

    log:printInfo(string `
--- Statistics (${elapsedMinutes}m ${elapsedSecs}s elapsed) ---
Total Queries:    ${stats.totalQueries}
Successful:       ${stats.successfulQueries}
Failed:           ${stats.failedQueries}
Success Rate:     ${successRate.toString()}%
-------------------------------------------------
`);
}

// Print final statistics
function printFinalStatistics() {
    decimal elapsedSeconds = time:utcDiffSeconds(time:utcNow(), stats.startTime);
    int elapsedMinutes = <int>(elapsedSeconds / 60);
    int elapsedSecs = <int>(elapsedSeconds % 60);

    decimal successRate = 0.0;
    decimal qps = 0.0;
    decimal avgLatency = 0.0;
    decimal p50 = 0.0;
    decimal p95 = 0.0;
    decimal p99 = 0.0;

    if stats.totalQueries > 0 {
        successRate = (<decimal>stats.successfulQueries / <decimal>stats.totalQueries) * 100.0;
        qps = <decimal>stats.totalQueries / elapsedSeconds;
    }

    if stats.queryLatencies.length() > 0 {
        // Calculate average latency
        decimal sum = 0.0;
        foreach decimal latency in stats.queryLatencies {
            sum += latency;
        }
        avgLatency = sum / <decimal>stats.queryLatencies.length();

        // Calculate percentiles (simple sorting)
        decimal[] sorted = stats.queryLatencies.sort();
        int len = sorted.length();
        p50 = sorted[len / 2];
        p95 = sorted[<int>(<decimal>len * 0.95d)];
        p99 = sorted[<int>(<decimal>len * 0.99d)];
    }

    log:printInfo(string `
========================================
=== FINAL RESULTS ===
========================================
Total duration:     ${elapsedMinutes}m ${elapsedSecs}s

Total Queries:      ${stats.totalQueries}
  Successful:       ${stats.successfulQueries}
  Failed:           ${stats.failedQueries}
  Success Rate:     ${successRate.toString()}%
  Queries/second:   ${qps.toString()}

Query Latency (seconds):
  Average:          ${(avgLatency * 1000).toString()}ms
  P50 (median):     ${(p50 * 1000).toString()}ms
  P95:              ${(p95 * 1000).toString()}ms
  P99:              ${(p99 * 1000).toString()}ms
========================================
`);

    if stats.errors.length() > 0 {
        log:printInfo("Connection Errors:");
        foreach int i in 0 ..< (stats.errors.length() > 10 ? 10 : stats.errors.length()) {
            log:printError(string `  - ${stats.errors[i]}`);
        }
        if stats.errors.length() > 10 {
            log:printInfo(string `  ... and ${stats.errors.length() - 10} more error types`);
        }
    }
}

// Get statistics as JSON
function getStatisticsJson() returns json {
    decimal elapsedSeconds = time:utcDiffSeconds(time:utcNow(), stats.startTime);
    decimal successRate = 0.0;
    if stats.totalQueries > 0 {
        successRate = (<decimal>stats.successfulQueries / <decimal>stats.totalQueries) * 100.0;
    }

    return {
        "totalQueries": stats.totalQueries,
        "successfulQueries": stats.successfulQueries,
        "failedQueries": stats.failedQueries,
        "successRate": successRate,
        "elapsedSeconds": elapsedSeconds,
        "errorCount": stats.errors.length()
    };
}
