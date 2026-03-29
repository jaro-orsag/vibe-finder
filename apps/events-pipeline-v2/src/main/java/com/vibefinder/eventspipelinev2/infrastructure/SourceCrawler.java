package com.vibefinder.eventspipelinev2.infrastructure;

import com.vibefinder.eventspipelinev2.application.PipelineConfig;
import com.vibefinder.eventspipelinev2.domain.EventRecord;
import com.vibefinder.eventspipelinev2.domain.FailureCategory;
import com.vibefinder.eventspipelinev2.domain.FailureRecord;
import com.vibefinder.eventspipelinev2.domain.SourceCrawlResult;
import com.vibefinder.eventspipelinev2.domain.SourceDescriptor;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpTimeoutException;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

@Component
public class SourceCrawler {

    private static final Logger log = LoggerFactory.getLogger(SourceCrawler.class);

    private final HumanLikeWebClient webClient;
    private final EventExtractor eventExtractor;

    public SourceCrawler(HumanLikeWebClient webClient, EventExtractor eventExtractor) {
        this.webClient = webClient;
        this.eventExtractor = eventExtractor;
    }

    public SourceCrawlResult crawlSource(SourceDescriptor source, PipelineConfig config) {
        long started = System.currentTimeMillis();
        List<FailureRecord> failures = new ArrayList<>();
        List<String> crawlLog = new ArrayList<>();

        Map<String, EventRecord> eventsBySignature = new LinkedHashMap<>();
        Set<String> visited = new LinkedHashSet<>();
        ArrayDeque<PageRef> queue = new ArrayDeque<>();

        for (String startUrl : source.eventListingUrls()) {
            queue.add(new PageRef(normalizeUrl(startUrl), 0));
        }

        while (!queue.isEmpty() && visited.size() < config.maxPagesPerSource()) {
            PageRef ref = queue.poll();
            if (ref == null || ref.url().isBlank()) {
                continue;
            }
            if (!visited.add(ref.url())) {
                continue;
            }
            if (ref.depth() > config.maxDepth()) {
                continue;
            }

            try {
                HumanLikeWebClient.FetchResponse response = webClient.get(ref.url(), config);
                crawlLog.add("GET " + ref.url() + " -> status=" + response.statusCode() + " delayMs=" + response.delayMs());
                if (response.statusCode() >= 400) {
                    FailureCategory category = response.statusCode() == 403 ? FailureCategory.ACCESS_DENIED : FailureCategory.FETCH_ERROR;
                    failures.add(new FailureRecord(source.id(), category, ref.url(), "HTTP " + response.statusCode(), Instant.now()));
                    continue;
                }

                Document document = Jsoup.parse(response.body(), response.finalUrl());
                List<EventRecord> foundOnPage = eventExtractor.extractFromPage(document, response.finalUrl(), source);
                mergeEvents(eventsBySignature, foundOnPage);

                if (ref.depth() < config.maxDepth()) {
                    List<String> links = extractSameHostLinks(document, source.homepageUrl());
                    for (String link : links) {
                        if (!visited.contains(link)) {
                            queue.add(new PageRef(link, ref.depth() + 1));
                        }
                    }
                }

                log.info("Source={} visitedPages={} queue={} uniqueEvents={}", source.id(), visited.size(), queue.size(), eventsBySignature.size());
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                failures.add(new FailureRecord(source.id(), FailureCategory.TIMEOUT, ref.url(), ex.getMessage(), Instant.now()));
            } catch (IllegalArgumentException ex) {
                failures.add(new FailureRecord(source.id(), FailureCategory.INVALID_SOURCE, ref.url(), detailedMessage(ex), Instant.now()));
            } catch (HttpTimeoutException ex) {
                failures.add(new FailureRecord(source.id(), FailureCategory.TIMEOUT, ref.url(), detailedMessage(ex), Instant.now()));
            } catch (IOException ex) {
                failures.add(new FailureRecord(source.id(), FailureCategory.FETCH_ERROR, ref.url(), detailedMessage(ex), Instant.now()));
            } catch (Exception ex) {
                failures.add(new FailureRecord(source.id(), classifyUnexpected(ex), ref.url(), detailedMessage(ex), Instant.now()));
            }
        }

        long durationMs = System.currentTimeMillis() - started;
        return new SourceCrawlResult(
            source,
            new ArrayList<>(eventsBySignature.values()),
            failures,
            crawlLog,
            visited.size(),
            durationMs
        );
    }

    private void mergeEvents(Map<String, EventRecord> eventsBySignature, List<EventRecord> foundOnPage) {
        for (EventRecord event : foundOnPage) {
            String signature = event.dedupSignature();
            EventRecord existing = eventsBySignature.get(signature);
            if (existing == null) {
                eventsBySignature.put(signature, event);
                continue;
            }
            Set<String> mergedUrls = new LinkedHashSet<>(existing.sourceUrls());
            mergedUrls.addAll(event.sourceUrls());
            eventsBySignature.put(signature, existing.mergeSources(mergedUrls));
        }
    }

    private List<String> extractSameHostLinks(Document document, String homepageUrl) {
        String homeHost = hostOf(homepageUrl);
        Map<String, String> unique = new HashMap<>();
        for (Element anchor : document.select("a[href]")) {
            String abs = normalizeUrl(anchor.attr("abs:href"));
            if (abs.isBlank()) {
                continue;
            }
            if (!Objects.equals(homeHost, hostOf(abs))) {
                continue;
            }
            unique.put(abs, abs);
        }
        return unique.values().stream().toList();
    }

    private String hostOf(String url) {
        try {
            return URI.create(url).getHost();
        } catch (Exception ex) {
            return null;
        }
    }

    private String normalizeUrl(String url) {
        if (url == null) {
            return "";
        }
        String cleaned = url.trim();
        if (cleaned.endsWith("/")) {
            cleaned = cleaned.substring(0, cleaned.length() - 1);
        }
        return cleaned;
    }

    private FailureCategory classifyUnexpected(Exception ex) {
        if (ex instanceof org.jsoup.UnsupportedMimeTypeException || ex instanceof org.jsoup.UncheckedIOException) {
            return FailureCategory.PARSE_ERROR;
        }
        return FailureCategory.UNKNOWN;
    }

    private String detailedMessage(Exception ex) {
        String message = ex.getMessage();
        if (message == null || message.isBlank()) {
            message = "no message";
        }
        return ex.getClass().getSimpleName() + ": " + message;
    }

    private record PageRef(String url, int depth) {
    }
}
