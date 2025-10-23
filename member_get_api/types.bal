// Database validation result record
public type ValidationResult record {|
    int result;
|};

// API response record
public type ApiResponse record {|
    boolean success;
    string message;
    ValidationResult? data;
|};

public type NameResult record {|
    string FirstName;
|};