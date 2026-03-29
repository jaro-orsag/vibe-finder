package com.vibefinder.eventspipelinev2.domain;

import java.time.Instant;

public record FailureRecord(
    String sourceId,
    FailureCategory category,
    String url,
    String message,
    Instant timestamp
) {
}
