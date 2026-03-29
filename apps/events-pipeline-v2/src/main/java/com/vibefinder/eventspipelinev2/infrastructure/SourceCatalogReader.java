package com.vibefinder.eventspipelinev2.infrastructure;

import com.vibefinder.eventspipelinev2.domain.SourceDescriptor;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.yaml.snakeyaml.Yaml;

@Component
public class SourceCatalogReader {

    private static final Logger log = LoggerFactory.getLogger(SourceCatalogReader.class);

    public List<SourceDescriptor> readActiveNonSocialSources(Path sourceCatalogPath) throws IOException {
        if (!Files.exists(sourceCatalogPath)) {
            throw new IllegalArgumentException("Source catalog not found: " + sourceCatalogPath);
        }

        Yaml yaml = new Yaml();
        try (InputStream in = Files.newInputStream(sourceCatalogPath)) {
            Map<String, Object> root = yaml.load(in);
            Object sourcesNode = root.get("sources");
            if (!(sourcesNode instanceof List<?> rawSources)) {
                return List.of();
            }

            List<SourceDescriptor> sources = new ArrayList<>();
            for (Object entry : rawSources) {
                if (!(entry instanceof Map<?, ?> sourceMapRaw)) {
                    continue;
                }
                Map<String, Object> sourceMap = (Map<String, Object>) sourceMapRaw;
                boolean active = boolValue(sourceMap.get("active"));
                String sourceType = stringValue(sourceMap.get("source_type"));
                if (!active || sourceType.toLowerCase(Locale.ROOT).contains("social")) {
                    continue;
                }

                String id = stringValue(sourceMap.get("id"));
                String name = stringValue(sourceMap.get("name"));
                String homepage = stringValue(sourceMap.get("homepage_url"));
                List<String> listingUrls = listOfStrings(sourceMap.get("event_listing_urls"));
                if (listingUrls.isEmpty() && !homepage.isBlank()) {
                    listingUrls = List.of(homepage);
                }

                if (id.isBlank() || name.isBlank() || listingUrls.isEmpty()) {
                    log.warn("Skipping malformed source id={} name={}", id, name);
                    continue;
                }

                sources.add(new SourceDescriptor(id, name, homepage, listingUrls, sourceType, true));
            }
            return sources;
        }
    }

    private boolean boolValue(Object value) {
        if (value instanceof Boolean b) {
            return b;
        }
        return "true".equalsIgnoreCase(String.valueOf(value));
    }

    private String stringValue(Object value) {
        return value == null ? "" : String.valueOf(value).trim();
    }

    private List<String> listOfStrings(Object value) {
        if (value instanceof List<?> list) {
            List<String> values = new ArrayList<>();
            for (Object item : list) {
                String text = stringValue(item);
                if (!text.isBlank()) {
                    values.add(text);
                }
            }
            return values;
        }
        String one = stringValue(value);
        if (one.isBlank()) {
            return Collections.emptyList();
        }
        return List.of(one);
    }
}
