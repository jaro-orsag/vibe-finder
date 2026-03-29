package com.vibefinder.eventspipelinev2.domain;

import java.util.ArrayList;
import java.util.List;

public record SourceCrawlResult(
    SourceDescriptor source,
    List<EventRecord> events,
    List<FailureRecord> failures,
    List<String> crawlLog,
    int visitedPages,
    long durationMillis
) {
    public SourceCrawlResult {
        events = new ArrayList<>(events);
        failures = new ArrayList<>(failures);
        crawlLog = new ArrayList<>(crawlLog);
    }
}
