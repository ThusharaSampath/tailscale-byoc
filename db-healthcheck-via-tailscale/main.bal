import ballerina/http;
import ballerina/log;
import ballerina/sql;
import ballerina/time;
import ballerinax/mssql;

// Configurable parameters
configurable string host = "localhost";
configurable int port = 1433;
configurable string username = "sa";
configurable string password = ?;
configurable string database = "master";
configurable int poolSize = 10;
configurable decimal minIntervalSeconds = 1.0;
configurable decimal maxIntervalSeconds = 5.0;
configurable int testDurationMinutes = 10;

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
Test Duration:      ${testDurationMinutes} minutes
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

    // Run test workload
    check runTestWorkload(dbClient, testDurationMinutes);

    // Print final statistics
    printFinalStatistics();

    // Close connection pool
    check dbClient.close();
    log:printInfo("✓ Connection pool closed");

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
            log:printInfo("Received health check request");
            stream<record {}, sql:Error?> resultStream = dbClient->query(`SELECT 1 as result`);
            error? closeResult = resultStream.close();
            if closeResult is error {
                log:printError(string `Health check failed: ${closeResult.message()}`);
                return http:INTERNAL_SERVER_ERROR;
            }
            log:printInfo("Health check succeeded");
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

// Run test workload with random intervals
function runTestWorkload(mssql:Client dbClient, int durationMinutes) returns error? {
    time:Utc endTime = time:utcAddSeconds(time:utcNow(), durationMinutes * 60);
    int queryCount = 0;

    log:printInfo("Starting test workload...");

    while <decimal>time:utcDiffSeconds(endTime, time:utcNow()) > 0d {
        queryCount += 1;

        // Execute health check query
        time:Utc queryStart = time:utcNow();
        error? queryResult = executeHealthQuery(dbClient, queryCount);
        decimal latency = time:utcDiffSeconds(time:utcNow(), queryStart);

        // Update statistics
        stats.totalQueries += 1;
        if queryResult is error {
            stats.failedQueries += 1;
            string errorMsg = queryResult.message();
            if !stats.errors.some(e => e == errorMsg) {
                stats.errors.push(errorMsg);
            }
            log:printError(string `[Query ${queryCount}] ✗ FAILED - ${errorMsg}`);
        } else {
            stats.successfulQueries += 1;
            stats.queryLatencies.push(latency);
            log:printInfo(string `[Query ${queryCount}] ✓ SUCCESS - ${(latency * 1000).toString()}ms`);
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

    log:printInfo("Test workload completed");
    return;
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
