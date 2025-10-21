import ballerina/ftp;
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

// FTP Configurable parameters
configurable boolean enableFtpCheck = true;
configurable string ftpHost = "localhost";
configurable int ftpPort = 21;
configurable string ftpUsername = "ftpuser";
configurable string ftpPassword = ?;
configurable string ftpTestPath = "/"; // Path to test (list or check)

// FTP Health Check Function
function performFtpHealthCheck() returns error? {
    log:printInfo(string `
========================================
FTP Server Health Check
========================================
Host:               ${ftpHost}
Port:               ${ftpPort}
Username:           ${ftpUsername}
Test Path:          ${ftpTestPath}
========================================
`);

    time:Utc ftpStartTime = time:utcNow();

    // Create FTP client configuration
    log:printInfo("Attempting to connect to FTP server...");
    
    ftp:ClientConfiguration ftpConfig = {
        protocol: ftp:FTP,
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
        log:printError(string `✗ FAILED to connect to FTP server: ${ftpClient.message()}`);
        return ftpClient;
    }

    log:printInfo("✓ FTP connection established");

    // Test FTP operations - list directory
    log:printInfo(string `Listing directory: ${ftpTestPath}`);
    time:Utc listStartTime = time:utcNow();

    ftp:FileInfo[]|error fileList = ftpClient->list(ftpTestPath);

    if fileList is error {
        log:printError(string `✗ FAILED to list FTP directory: ${fileList.message()}`);
        return fileList;
    }

    decimal listLatency = time:utcDiffSeconds(time:utcNow(), listStartTime);
    log:printInfo(string `✓ SUCCESS: Directory listed in ${(listLatency * 1000).toString()}ms`);
    log:printInfo(string `Found ${fileList.length()} items in directory`);

    // Log some file details
    if fileList.length() > 0 {
        log:printInfo("Sample files/directories:");
        int maxDisplay = fileList.length() < 5 ? fileList.length() : 5;
        foreach int i in 0 ..< maxDisplay {
            ftp:FileInfo fileInfo = fileList[i];
            log:printInfo(string `  ${fileInfo.name} (${fileInfo.size} bytes)`);
        }
        if fileList.length() > 5 {
            log:printInfo(string `  ... and ${fileList.length() - 5} more items`);
        }
    }

    log:printInfo("✓ FTP operations completed successfully");

    decimal totalFtpTime = time:utcDiffSeconds(time:utcNow(), ftpStartTime);
    log:printInfo(string `
========================================
FTP Health Check completed successfully
Total execution time: ${(totalFtpTime * 1000).toString()}ms
========================================
`);

    return;
}

// Database Health Check Function
function performDatabaseHealthCheck() returns error? {
    log:printInfo(string `
========================================
Database Health Check
========================================
Host:               ${host}
Port:               ${port}
Database:           ${database}
Username:           ${username}
========================================
`);

    // Record start time
    time:Utc startTime = time:utcNow();

    // Create database connection
    log:printInfo("Attempting to connect to database...");
    mssql:Client|error dbClient = new (
        host = host,
        port = port,
        user = username,
        password = password,
        database = database
    );

    if dbClient is error {
        log:printError(string `✗ FAILED to connect to database: ${dbClient.message()}`);
        return dbClient;
    }

    log:printInfo("✓ Database connection established");

    // Execute health check query
    log:printInfo("Executing health check query...");
    time:Utc queryStartTime = time:utcNow();
    
    stream<record {}, sql:Error?>|sql:Error resultStream = dbClient->query(`
        SELECT 
            GETDATE() as QueryTime,
            @@VERSION as SQLVersion,
            @@SERVERNAME as ServerName,
            DB_NAME() as DatabaseName,
            SUSER_NAME() as LoginName,
            @@SPID as SessionID
    `);

    if resultStream is sql:Error {
        log:printError(string `✗ FAILED to execute query: ${resultStream.message()}`);
        check dbClient.close();
        return resultStream;
    }

    // Fetch the result
    record {|record {} value;|}|sql:Error? result = resultStream.next();
    check resultStream.close();

    if result is sql:Error {
        log:printError(string `✗ FAILED to fetch query results: ${result.message()}`);
        check dbClient.close();
        return result;
    }

    if result is () {
        log:printError("✗ FAILED: No results returned from query");
        check dbClient.close();
        return error("No results returned from query");
    }

    // Calculate query execution time
    decimal queryLatency = time:utcDiffSeconds(time:utcNow(), queryStartTime);
    
    // Log success with query details
    log:printInfo(string `✓ SUCCESS: Query executed in ${(queryLatency * 1000).toString()}ms`);
    log:printInfo(string `Query Results: ${result.value.toString()}`);

    // Close database connection
    error? closeResult = dbClient.close();
    if closeResult is error {
        log:printWarn(string `Warning: Failed to close database connection: ${closeResult.message()}`);
    } else {
        log:printInfo("✓ Database connection closed");
    }

    // Calculate total execution time
    decimal totalTime = time:utcDiffSeconds(time:utcNow(), startTime);
    log:printInfo(string `
========================================
Database Health Check completed successfully
Total execution time: ${(totalTime * 1000).toString()}ms
========================================
`);

    return;
}

public function main() returns error? {
    log:printInfo("=== Health Check Task Started ===");

    time:Utc overallStartTime = time:utcNow();
    boolean hasErrors = false;

    // Perform Database Health Check
    error? dbResult = performDatabaseHealthCheck();
    if dbResult is error {
        log:printError(string `Database health check failed: ${dbResult.message()}`);
        hasErrors = true;
    }

    // Perform FTP Health Check if enabled
    if enableFtpCheck {
        error? ftpResult = performFtpHealthCheck();
        if ftpResult is error {
            log:printError(string `FTP health check failed: ${ftpResult.message()}`);
            hasErrors = true;
        }
    } else {
        log:printInfo("FTP health check is disabled (enableFtpCheck=false)");
    }

    // Overall summary
    decimal overallTime = time:utcDiffSeconds(time:utcNow(), overallStartTime);
    
    if hasErrors {
        log:printError(string `Health Check Task FAILED - Total execution time: ${(overallTime * 1000).toString()}ms`);
        return error("One or more health checks failed");
    }

    log:printInfo(string `All Health Checks PASSED ✓ - Total execution time: ${(overallTime * 1000).toString()}ms`);

    return;
}
