import ballerina/http;

// REST API service
service /api on new http:Listener(8080) {
    
    // Resource to execute validation query
    resource function get validate() returns ApiResponse|http:InternalServerError {
        do {
            // Execute validation query
            ValidationResult result = check dbClient->queryRow(`select 1 as result`);
            
            return {
                success: true,
                message: "Database validation successful",
                data: result
            };
        } on fail error e {
            return <http:InternalServerError>{
                body: {
                    success: false,
                    message: string `Database validation failed: ${e.message()}`,
                    data: ()
                }
            };
        }
    }
    
    // Health check resource
    resource function get health() returns ApiResponse {
        return {
            success: true,
            message: "API is running",
            data: ()
        };
    }
    
//test function 
    resource function get firstName(string memberId) returns string|http:InternalServerError{
    do{
        NameResult result =check dbClient->queryRow(`SELECT FirstName FROM mockmembers where MemberID=${memberId}`);
        return result.FirstName ;
    }
    on fail error e{
    return <http:InternalServerError>{
                body: {
                    success: false,
                    message: string `Database query failed: ${e.message()}`,
                    data: ()
                }
            };
    }
 
}

}