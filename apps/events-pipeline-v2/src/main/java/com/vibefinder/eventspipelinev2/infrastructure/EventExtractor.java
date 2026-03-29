package com.vibefinder.eventspipelinev2.infrastructure;

import com.vibefinder.eventspipelinev2.domain.EventRecord;
import com.vibefinder.eventspipelinev2.domain.SourceDescriptor;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.select.Elements;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

@Component
public class EventExtractor {

    private static final Logger log = LoggerFactory.getLogger(EventExtractor.class);

    private static final Pattern DATE_PATTERN = Pattern.compile("(\\d{4}-\\d{2}-\\d{2})|(\\d{1,2}\\.\\d{1,2}\\.\\d{4})");

    public List<EventRecord> extractFromPage(Document document, String pageUrl, SourceDescriptor source) {
        List<EventRecord> events = new ArrayList<>();

        // First pass: HTML elements commonly used for event cards.
        Elements likelyCards = document.select("article, .event, .events-item, [itemtype*=Event]");
        for (Element card : likelyCards) {
            EventRecord event = eventFromElement(card, pageUrl, source);
            if (event != null) {
                events.add(event);
            }
        }

        // Fallback pass: search text blocks with date-like patterns.
        if (events.isEmpty()) {
            for (Element block : document.select("h1, h2, h3, p, li")) {
                EventRecord event = eventFromText(block.text(), pageUrl, source);
                if (event != null) {
                    events.add(event);
                }
            }
        }

        if (!events.isEmpty()) {
            log.debug("Extracted {} candidates from {}", events.size(), pageUrl);
        }
        return events;
    }

    private EventRecord eventFromElement(Element element, String pageUrl, SourceDescriptor source) {
        String text = element.text();
        return eventFromText(text, pageUrl, source);
    }

    private EventRecord eventFromText(String text, String pageUrl, SourceDescriptor source) {
        if (text == null || text.isBlank()) {
            return null;
        }
        Matcher matcher = DATE_PATTERN.matcher(text);
        if (!matcher.find()) {
            return null;
        }

        String dateText = matcher.group();
        String normalizedDate = normalizeDate(dateText);
        if (normalizedDate == null) {
            return null;
        }

        String title = normalizeTitle(text.replace(dateText, "").trim());
        if (title.isBlank() || title.length() < 4) {
            return null;
        }

        String id = "evt_" + normalizedDate.replace("-", "") + "_" + slug(source.id()) + "_" + slug(title);
        Set<String> urls = new LinkedHashSet<>();
        urls.add(pageUrl);

        return new EventRecord(
            id,
            title,
            normalizedDate,
            source.name(),
            "Bratislava",
            List.of("mixed"),
            urls,
            "upcoming",
            "low",
            "Auto-extracted from page content without URL/path assumptions"
        );
    }

    private String normalizeDate(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            if (value.contains("-")) {
                return LocalDate.parse(value, DateTimeFormatter.ISO_LOCAL_DATE).toString();
            }
            DateTimeFormatter skFormat = DateTimeFormatter.ofPattern("d.M.yyyy", Locale.ROOT);
            return LocalDate.parse(value, skFormat).toString();
        } catch (DateTimeParseException ex) {
            return null;
        }
    }

    private String normalizeTitle(String value) {
        return value.replaceAll("\\s+", " ").trim();
    }

    private String slug(String text) {
        String normalized = text.toLowerCase(Locale.ROOT)
            .replaceAll("[^a-z0-9]+", "_")
            .replaceAll("_+", "_")
            .replaceAll("^_", "")
            .replaceAll("_$", "");
        if (normalized.isBlank()) {
            return "event";
        }
        return normalized.substring(0, Math.min(60, normalized.length()));
    }
}
