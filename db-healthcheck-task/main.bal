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

public function main() returns error? {
    log:printInfo(string `
========================================
Database Health Check Task
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
Task completed successfully
Total execution time: ${(totalTime * 1000).toString()}ms
========================================
`);

    return;
}
