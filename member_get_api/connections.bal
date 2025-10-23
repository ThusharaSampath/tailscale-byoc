import ballerinax/mssql;

// Initialize MSSQL client
final mssql:Client dbClient = check new (
    host = dbHost,
    user = dbUser,
    password = dbPassword,
    database = dbName,
    port = dbPort
);