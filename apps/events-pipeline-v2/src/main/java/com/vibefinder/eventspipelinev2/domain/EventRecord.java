package com.vibefinder.eventspipelinev2.domain;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;

public final class EventRecord {

    private final String id;
    private final String title;
    private final String date;
    private final String venueName;
    private final String venueCity;
    private final List<String> categories;
    private final Set<String> sourceUrls;
    private final String status;
    private final String confidence;
    private final String description;

    public EventRecord(
        String id,
        String title,
        String date,
        String venueName,
        String venueCity,
        List<String> categories,
        Set<String> sourceUrls,
        String status,
        String confidence,
        String description
    ) {
        this.id = id;
        this.title = title;
        this.date = date;
        this.venueName = venueName;
        this.venueCity = venueCity;
        this.categories = new ArrayList<>(categories);
        this.sourceUrls = new LinkedHashSet<>(sourceUrls);
        this.status = status;
        this.confidence = confidence;
        this.description = description;
    }

    public String id() {
        return id;
    }

    public String title() {
        return title;
    }

    public String date() {
        return date;
    }

    public String venueName() {
        return venueName;
    }

    public String venueCity() {
        return venueCity;
    }

    public List<String> categories() {
        return new ArrayList<>(categories);
    }

    public Set<String> sourceUrls() {
        return new LinkedHashSet<>(sourceUrls);
    }

    public String status() {
        return status;
    }

    public String confidence() {
        return confidence;
    }

    public String description() {
        return description;
    }

    public String dedupSignature() {
        return normalize(title) + "|" + normalize(date) + "|" + normalize(venueName);
    }

    public EventRecord mergeSources(Set<String> mergedUrls) {
        return new EventRecord(id, title, date, venueName, venueCity, categories, mergedUrls, status, confidence, description);
    }

    private static String normalize(String value) {
        return Objects.toString(value, "")
            .trim()
            .toLowerCase(Locale.ROOT)
            .replaceAll("\\s+", " ");
    }
}
