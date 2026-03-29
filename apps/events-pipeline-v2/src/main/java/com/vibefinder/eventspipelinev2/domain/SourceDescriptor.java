package com.vibefinder.eventspipelinev2.domain;

import java.util.List;

public record SourceDescriptor(
    String id,
    String name,
    String homepageUrl,
    List<String> eventListingUrls,
    String sourceType,
    boolean active
) {
}
