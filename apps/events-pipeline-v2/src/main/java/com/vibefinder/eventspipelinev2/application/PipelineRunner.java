package com.vibefinder.eventspipelinev2.application;

import com.vibefinder.eventspipelinev2.domain.SourceCrawlResult;
import com.vibefinder.eventspipelinev2.domain.SourceDescriptor;
import com.vibefinder.eventspipelinev2.infrastructure.ReportWriter;
import com.vibefinder.eventspipelinev2.infrastructure.SourceCatalogReader;
import com.vibefinder.eventspipelinev2.infrastructure.SourceCrawler;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Component
public class PipelineRunner implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(PipelineRunner.class);

    private final SourceCatalogReader sourceCatalogReader;
    private final SourceCrawler sourceCrawler;
    private final ReportWriter reportWriter;

    public PipelineRunner(SourceCatalogReader sourceCatalogReader, SourceCrawler sourceCrawler, ReportWriter reportWriter) {
        this.sourceCatalogReader = sourceCatalogReader;
        this.sourceCrawler = sourceCrawler;
        this.reportWriter = reportWriter;
    }

    @Override
    public void run(ApplicationArguments args) throws Exception {
        PipelineConfig config = buildConfig(args);
        log.info("Starting Events Pipeline v2 runId={} date={}", config.runId(), config.runDate());
        log.info("Input catalog={} outputRoot={}", config.sourceCatalogPath(), config.outputRoot());

        List<SourceDescriptor> sources = sourceCatalogReader.readActiveNonSocialSources(config.sourceCatalogPath());
        sources = applySourceFilters(sources, args);
        log.info("Loaded {} active non-social sources", sources.size());

        List<SourceCrawlResult> results = new ArrayList<>();
        int total = sources.size();
        for (int i = 0; i < total; i++) {
            SourceDescriptor source = sources.get(i);
            log.info("Source {}/{} id={} name={}", i + 1, total, source.id(), source.name());
            SourceCrawlResult result = sourceCrawler.crawlSource(source, config);
            results.add(result);
            log.info("Completed source id={} uniqueEvents={} failures={} visitedPages={} durationMs={}",
                source.id(),
                result.events().size(),
                result.failures().size(),
                result.visitedPages(),
                result.durationMillis()
            );
        }

        Path runFolder = reportWriter.writeRunArtifacts(config, results);
        log.info("Finished run. Artifacts written to {}", runFolder);
    }

    private PipelineConfig buildConfig(ApplicationArguments args) {
        String runId = option(args, "runId").orElseGet(() -> LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd_HHmmss")));
        String runDate = option(args, "runDate").orElse(LocalDate.now().toString());
        Path sourceCatalogPath = Path.of(option(args, "sourceCatalog").orElse("data/sources/bratislava-event-sources.yaml"));
        Path outputRoot = Path.of(option(args, "outputRoot").orElse("data/events-pipeline-v2"));
        int maxDepth = Integer.parseInt(option(args, "maxDepth").orElse("2"));
        int maxPagesPerSource = Integer.parseInt(option(args, "maxPagesPerSource").orElse("80"));
        long minDelayMs = Long.parseLong(option(args, "minDelayMs").orElse("800"));
        long maxDelayMs = Long.parseLong(option(args, "maxDelayMs").orElse("2200"));
        Duration requestTimeout = Duration.ofSeconds(Long.parseLong(option(args, "requestTimeoutSeconds").orElse("20")));

        return new PipelineConfig(
            runId,
            runDate,
            sourceCatalogPath,
            outputRoot,
            maxDepth,
            maxPagesPerSource,
            requestTimeout,
            minDelayMs,
            maxDelayMs
        );
    }

    private java.util.Optional<String> option(ApplicationArguments args, String name) {
        if (!args.containsOption(name)) {
            return java.util.Optional.empty();
        }
        List<String> values = args.getOptionValues(name);
        if (values == null || values.isEmpty()) {
            return java.util.Optional.empty();
        }
        return java.util.Optional.ofNullable(values.get(0));
    }

    private List<SourceDescriptor> applySourceFilters(List<SourceDescriptor> sources, ApplicationArguments args) {
        List<SourceDescriptor> filtered = new ArrayList<>(sources);

        option(args, "sourceIds").ifPresent(value -> {
            Set<String> allowed = new HashSet<>();
            for (String id : value.split(",")) {
                String trimmed = id.trim();
                if (!trimmed.isBlank()) {
                    allowed.add(trimmed);
                }
            }
            filtered.removeIf(source -> !allowed.contains(source.id()));
        });

        int maxSources = Integer.parseInt(option(args, "maxSources").orElse("0"));
        if (maxSources > 0 && filtered.size() > maxSources) {
            return new ArrayList<>(filtered.subList(0, maxSources));
        }

        return filtered;
    }
}
