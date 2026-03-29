package com.vibefinder.eventspipelinev2.domain;

public enum FailureCategory {
    FETCH_ERROR,
    ACCESS_DENIED,
    PARSE_ERROR,
    INVALID_SOURCE,
    TIMEOUT,
    UNKNOWN
}
