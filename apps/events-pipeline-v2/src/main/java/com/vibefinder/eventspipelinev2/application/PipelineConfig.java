package com.vibefinder.eventspipelinev2.application;

import java.nio.file.Path;
import java.time.Duration;

public record PipelineConfig(
    String runId,
    String runDate,
    Path sourceCatalogPath,
    Path outputRoot,
    int maxDepth,
    int maxPagesPerSource,
    Duration requestTimeout,
    long minDelayMs,
    long maxDelayMs
) {
}
