package com.vibefinder.eventspipelinev2.infrastructure;

import com.vibefinder.eventspipelinev2.application.PipelineConfig;
import com.vibefinder.eventspipelinev2.domain.EventRecord;
import com.vibefinder.eventspipelinev2.domain.FailureCategory;
import com.vibefinder.eventspipelinev2.domain.FailureRecord;
import com.vibefinder.eventspipelinev2.domain.SourceCrawlResult;
import java.io.IOException;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import org.springframework.stereotype.Component;
import org.yaml.snakeyaml.DumperOptions;
import org.yaml.snakeyaml.Yaml;

@Component
public class ReportWriter {

    public Path writeRunArtifacts(PipelineConfig config, List<SourceCrawlResult> results) throws IOException {
        Path runFolder = config.outputRoot().resolve(config.runId());
        Files.createDirectories(runFolder);

        Map<String, Object> runSummary = buildRunSummary(config, results);
        writeYaml(runFolder.resolve("run_summary.yaml"), runSummary);

        Map<String, Object> failureSummary = buildFailureSummary(results);
        writeYaml(runFolder.resolve("failure_summary.yaml"), failureSummary);

        Files.writeString(runFolder.resolve("run_summary.md"), buildRunMarkdown(config, results), StandardCharsets.UTF_8);

        Path sourcesFolder = runFolder.resolve("sources");
        Files.createDirectories(sourcesFolder);

        for (SourceCrawlResult result : results) {
            Path sourceFolder = sourcesFolder.resolve(result.source().id());
            Files.createDirectories(sourceFolder);
            writeYaml(sourceFolder.resolve("source_report.yaml"), sourceReport(config, result));
            writeYaml(sourceFolder.resolve("events.yaml"), sourceEvents(config, result));
            Files.write(sourceFolder.resolve("crawl.log"), result.crawlLog(), StandardCharsets.UTF_8);
            Files.writeString(sourceFolder.resolve("source_report.md"), buildSourceMarkdown(config, result), StandardCharsets.UTF_8);
        }

        return runFolder;
    }

    private Map<String, Object> buildRunSummary(PipelineConfig config, List<SourceCrawlResult> results) {
        Map<String, Object> root = new LinkedHashMap<>();
        root.put("contract", "bratislava_events_v2_run_summary");
        root.put("schema_version", "1.0.0");
        root.put("run_id", config.runId());
        root.put("run_date", config.runDate());
        root.put("generated_at", Instant.now().toString());

        List<Map<String, Object>> sourceMetrics = new ArrayList<>();
        for (SourceCrawlResult result : results) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("source_id", result.source().id());
            row.put("source_name", result.source().name());
            row.put("unique_events", result.events().size());
            row.put("visited_pages", result.visitedPages());
            row.put("failures", result.failures().size());
            row.put("duration_ms", result.durationMillis());
            sourceMetrics.add(row);
        }
        root.put("source_metrics", sourceMetrics);
        return root;
    }

    private Map<String, Object> buildFailureSummary(List<SourceCrawlResult> results) {
        Map<String, Integer> byCategory = new TreeMap<>();
        Map<String, Map<String, Integer>> bySourceThenCategory = new TreeMap<>();

        for (SourceCrawlResult result : results) {
            for (FailureRecord failure : result.failures()) {
                String category = failure.category().name();
                byCategory.put(category, byCategory.getOrDefault(category, 0) + 1);
                bySourceThenCategory.putIfAbsent(failure.sourceId(), new TreeMap<>());
                Map<String, Integer> sourceCounts = bySourceThenCategory.get(failure.sourceId());
                sourceCounts.put(category, sourceCounts.getOrDefault(category, 0) + 1);
            }
        }

        Map<String, Object> root = new LinkedHashMap<>();
        root.put("contract", "bratislava_events_v2_failure_summary");
        root.put("schema_version", "1.0.0");
        root.put("failures_by_category", byCategory);
        root.put("failures_by_category_by_source", bySourceThenCategory);
        return root;
    }

    private Map<String, Object> sourceReport(PipelineConfig config, SourceCrawlResult result) {
        Map<String, Object> root = new LinkedHashMap<>();
        root.put("contract", "bratislava_events_v2_source_report");
        root.put("schema_version", "1.0.0");
        root.put("run_id", config.runId());
        root.put("run_date", config.runDate());
        root.put("source_id", result.source().id());
        root.put("source_name", result.source().name());
        root.put("source_type", result.source().sourceType());
        root.put("visited_pages", result.visitedPages());
        root.put("unique_events", result.events().size());
        root.put("duration_ms", result.durationMillis());

        Map<String, Integer> failureCounts = new TreeMap<>();
        for (FailureCategory category : FailureCategory.values()) {
            int count = 0;
            for (FailureRecord failure : result.failures()) {
                if (failure.category() == category) {
                    count++;
                }
            }
            if (count > 0) {
                failureCounts.put(category.name(), count);
            }
        }
        root.put("failure_counts", failureCounts);
        root.put("failures", failureRows(result.failures()));
        return root;
    }

    private List<Map<String, Object>> failureRows(List<FailureRecord> failures) {
        List<Map<String, Object>> rows = new ArrayList<>();
        for (FailureRecord failure : failures) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("source_id", failure.sourceId());
            row.put("category", failure.category().name());
            row.put("url", failure.url());
            row.put("message", failure.message());
            row.put("timestamp", failure.timestamp().toString());
            rows.add(row);
        }
        return rows;
    }

    private Map<String, Object> sourceEvents(PipelineConfig config, SourceCrawlResult result) {
        Map<String, Object> root = new LinkedHashMap<>();
        root.put("contract", "bratislava_events");
        root.put("schema_version", "1.0.0");
        root.put("pipeline_stage", "v2_source");
        root.put("run_date", config.runDate());

        List<Map<String, Object>> events = new ArrayList<>();
        for (EventRecord event : result.events()) {
            Map<String, Object> node = new LinkedHashMap<>();
            node.put("id", event.id());
            node.put("title", event.title());
            node.put("date", event.date());
            node.put("venue_name", event.venueName());
            node.put("venue_city", event.venueCity());
            node.put("categories", event.categories());
            node.put("source_urls", event.sourceUrls().stream().toList());
            node.put("status", event.status());
            node.put("confidence", event.confidence());
            node.put("description", event.description());
            events.add(node);
        }
        root.put("events", events);
        return root;
    }

    private String buildRunMarkdown(PipelineConfig config, List<SourceCrawlResult> results) {
        StringBuilder sb = new StringBuilder();
        sb.append("# Run Summary: ").append(config.runId()).append("\n\n");
        sb.append("**Run date:** ").append(config.runDate()).append("  \n");
        sb.append("**Generated at:** ").append(Instant.now()).append("\n\n");

        sb.append("## Source Metrics\n\n");
        sb.append("| Source | Events | Pages visited | Failures | Duration (ms) |\n");
        sb.append("|--------|-------:|-------------:|---------:|--------------:|\n");
        long totalEvents = 0, totalFailures = 0;
        for (SourceCrawlResult r : results) {
            sb.append("| ").append(r.source().name())
                .append(" | ").append(r.events().size())
                .append(" | ").append(r.visitedPages())
                .append(" | ").append(r.failures().size())
                .append(" | ").append(r.durationMillis())
                .append(" |\n");
            totalEvents += r.events().size();
            totalFailures += r.failures().size();
        }
        sb.append("| **TOTAL** | **").append(totalEvents).append("** | | **").append(totalFailures).append("** | |\n\n");

        // Failure breakdown
        Map<String, Integer> byCategory = new TreeMap<>();
        Map<String, Map<String, Integer>> bySource = new TreeMap<>();
        List<FailureRecord> allFailures = new ArrayList<>();
        for (SourceCrawlResult r : results) {
            for (FailureRecord f : r.failures()) {
                byCategory.merge(f.category().name(), 1, Integer::sum);
                bySource.computeIfAbsent(f.sourceId(), k -> new TreeMap<>()).merge(f.category().name(), 1, Integer::sum);
                allFailures.add(f);
            }
        }

        if (byCategory.isEmpty()) {
            sb.append("## Failures\n\nNo failures recorded.\n");
        } else {
            sb.append("## Failures\n\n");
            sb.append("### By Category\n\n");
            sb.append("| Category | Count | Description |\n");
            sb.append("|----------|------:|-------------|\n");
            for (Map.Entry<String, Integer> e : byCategory.entrySet()) {
                sb.append("| ").append(e.getKey())
                    .append(" | ").append(e.getValue())
                    .append(" | ").append(categoryDescription(e.getKey()))
                    .append(" |\n");
            }
            sb.append("\n");

            sb.append("### By Source\n\n");
            sb.append("| Source | Category | Count |\n");
            sb.append("|--------|----------|------:|\n");
            for (Map.Entry<String, Map<String, Integer>> se : bySource.entrySet()) {
                for (Map.Entry<String, Integer> ce : se.getValue().entrySet()) {
                    sb.append("| ").append(se.getKey())
                        .append(" | ").append(ce.getKey())
                        .append(" | ").append(ce.getValue())
                        .append(" |\n");
                }
            }
            sb.append("\n");

            sb.append("### Failure Details\n\n");
            sb.append("| Source | Category | URL | Message |\n");
            sb.append("|--------|----------|-----|---------|\n");
            for (FailureRecord f : allFailures) {
                sb.append("| ").append(f.sourceId())
                    .append(" | ").append(f.category().name())
                    .append(" | ").append(f.url())
                    .append(" | ").append(f.message().replace("|", "\\|"))
                    .append(" |\n");
            }
            sb.append("\n");
        }
        return sb.toString();
    }

    private String buildSourceMarkdown(PipelineConfig config, SourceCrawlResult result) {
        StringBuilder sb = new StringBuilder();
        sb.append("# Source Report: ").append(result.source().name()).append("\n\n");
        sb.append("**Source ID:** ").append(result.source().id()).append("  \n");
        sb.append("**Source type:** ").append(result.source().sourceType()).append("  \n");
        sb.append("**Run ID:** ").append(config.runId()).append("  \n");
        sb.append("**Run date:** ").append(config.runDate()).append("\n\n");

        sb.append("## Stats\n\n");
        sb.append("- **Unique events found:** ").append(result.events().size()).append("\n");
        sb.append("- **Pages visited:** ").append(result.visitedPages()).append("\n");
        sb.append("- **Duration:** ").append(result.durationMillis()).append(" ms\n\n");

        if (result.failures().isEmpty()) {
            sb.append("## Failures\n\nNo failures.\n");
        } else {
            Map<String, Integer> byCat = new TreeMap<>();
            for (FailureRecord f : result.failures()) {
                byCat.merge(f.category().name(), 1, Integer::sum);
            }

            sb.append("## Failures\n\n");
            sb.append("| Category | Count | Description |\n");
            sb.append("|----------|------:|-------------|\n");
            for (Map.Entry<String, Integer> e : byCat.entrySet()) {
                sb.append("| ").append(e.getKey())
                    .append(" | ").append(e.getValue())
                    .append(" | ").append(categoryDescription(e.getKey()))
                    .append(" |\n");
            }
            sb.append("\n");

            sb.append("### Failure Details\n\n");
            sb.append("| Category | URL | Message |\n");
            sb.append("|----------|-----|---------|\n");
            for (FailureRecord f : result.failures()) {
                sb.append("| ").append(f.category().name())
                    .append(" | ").append(f.url())
                    .append(" | ").append(f.message().replace("|", "\\|"))
                    .append(" |\n");
            }
            sb.append("\n");
        }
        return sb.toString();
    }

    private String categoryDescription(String category) {
        return switch (category) {
            case "FETCH_ERROR" -> "HTTP error or network-level failure when fetching a URL (e.g. connection refused, 4xx/5xx response)";
            case "ACCESS_DENIED" -> "Server returned 401/403 or presented a CAPTCHA/login wall";
            case "PARSE_ERROR" -> "HTML could not be parsed or had an unexpected MIME type (e.g. PDF, binary response)";
            case "INVALID_SOURCE" -> "The source URL or configuration is malformed and cannot be processed (e.g. bad URI)";
            case "TIMEOUT" -> "Request exceeded the configured timeout before a response was received";
            case "UNKNOWN" -> "Unexpected exception not matched by any known category — check the message for details";
            default -> "";
        };
    }

    private void writeYaml(Path target, Map<String, Object> content) throws IOException {
        DumperOptions options = new DumperOptions();
        options.setDefaultFlowStyle(DumperOptions.FlowStyle.BLOCK);
        options.setPrettyFlow(true);
        options.setIndent(2);

        Yaml yaml = new Yaml(options);
        try (Writer writer = Files.newBufferedWriter(target, StandardCharsets.UTF_8)) {
            writer.write("---\n");
            yaml.dump(content, writer);
        }
    }
}
