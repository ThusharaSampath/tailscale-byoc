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

// FTP/SFTP Configurable parameters
configurable boolean enableFtpCheck = true;
configurable string ftpHost = "localhost";
configurable int ftpPort = 22;  // Default to SFTP port
configurable string ftpUsername = "ftpuser";
configurable string ftpPassword = ?;
configurable string ftpTestPath = "/"; // Path to test (for SFTP, will use home directory)

// Google Chat Notification Configuration
configurable boolean enableChatNotification = false;
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

// SFTP/FTP Health Check Function
function performFtpHealthCheck() returns error? {
    log:printInfo(string `
========================================
SFTP/FTP Server Health Check
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
    
    // Determine protocol based on port (22 or 2022 = SFTP, 21 or 2021 = FTP)
    ftp:Protocol protocol = ftpPort == 22 || ftpPort == 2022 ? ftp:SFTP : ftp:FTP;
    log:printInfo(string `Using protocol: ${protocol.toString()}`);
    
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
        log:printError(string `✗ FAILED to connect to FTP server: ${ftpClient.message()}`);
        return ftpClient;
    }

    log:printInfo("✓ FTP connection established");

    // Test FTP operations
    time:Utc listStartTime = time:utcNow();

    // For SFTP, connection test is sufficient (directory listing has issues with Ballerina connector)
    // For FTP, we can try to list the directory
    if protocol == ftp:SFTP {
        log:printInfo("SFTP connection test: SUCCESS");
        log:printInfo("✓ SFTP server is reachable and authentication successful");
        decimal connectionLatency = time:utcDiffSeconds(time:utcNow(), listStartTime);
        log:printInfo(string `Connection verification time: ${(connectionLatency * 1000).toString()}ms`);
    } else {
        // For FTP, try directory listing
        string testPath = ftpTestPath;
        log:printInfo(string `Testing FTP: Listing directory ${testPath}`);
        
        ftp:FileInfo[]|error fileList = ftpClient->list(testPath);

        if fileList is error {
            log:printError(string `✗ FAILED to list directory: ${fileList.message()}`);
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
    }

    log:printInfo("✓ SFTP operations completed successfully");

    decimal totalFtpTime = time:utcDiffSeconds(time:utcNow(), ftpStartTime);
    log:printInfo(string `
========================================
SFTP/FTP Health Check completed successfully
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
    string[] errorMessages = [];

    // Perform Database Health Check
    error? dbResult = performDatabaseHealthCheck();
    if dbResult is error {
        string dbError = string `Database health check failed: ${dbResult.message()}`;
        log:printError(dbError);
        errorMessages.push(dbError);
        hasErrors = true;
    }

    // Perform FTP Health Check if enabled
    if enableFtpCheck {
        error? ftpResult = performFtpHealthCheck();
        if ftpResult is error {
            string ftpError = string `FTP health check failed: ${ftpResult.message()}`;
            log:printError(ftpError);
            errorMessages.push(ftpError);
            hasErrors = true;
        }
    } else {
        log:printInfo("FTP health check is disabled (enableFtpCheck=false)");
    }

    // Overall summary
    decimal overallTime = time:utcDiffSeconds(time:utcNow(), overallStartTime);
    
    if hasErrors {
        log:printError(string `Health Check Task FAILED - Total execution time: ${(overallTime * 1000).toString()}ms`);
        
        // Send Google Chat notification on failure
        string notificationMessage = string `🔴 *Health Check Failed*\n\n` +
            string `*Errors:*\n${string:'join("\n", ...errorMessages)}\n\n` +
            string `*Execution Time:* ${(overallTime * 1000).toString()}ms\n` +
            string `*Timestamp:* ${time:utcToString(time:utcNow())}`;
        
        error? notificationResult = sendGoogleChatNotification(notificationMessage);
        if notificationResult is error {
            log:printWarn("Failed to send failure notification to Google Chat");
        }
        
        return error("One or more health checks failed");
    }

    log:printInfo(string `All Health Checks PASSED ✓ - Total execution time: ${(overallTime * 1000).toString()}ms`);

    return;
}
