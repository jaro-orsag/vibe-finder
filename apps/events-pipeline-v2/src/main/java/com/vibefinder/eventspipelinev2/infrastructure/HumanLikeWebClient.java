package com.vibefinder.eventspipelinev2.infrastructure;

import com.vibefinder.eventspipelinev2.application.PipelineConfig;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

@Component
public class HumanLikeWebClient {

    private static final Logger log = LoggerFactory.getLogger(HumanLikeWebClient.class);

    private static final List<String> USER_AGENTS = List.of(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0"
    );

    private final HttpClient httpClient;

    public HumanLikeWebClient() {
        this.httpClient = HttpClient.newBuilder()
            .followRedirects(HttpClient.Redirect.NORMAL)
            .connectTimeout(Duration.ofSeconds(15))
            .build();
    }

    public FetchResponse get(String url, PipelineConfig config) throws IOException, InterruptedException {
        long delay = ThreadLocalRandom.current().nextLong(config.minDelayMs(), config.maxDelayMs() + 1);
        Thread.sleep(delay);

        String userAgent = USER_AGENTS.get(ThreadLocalRandom.current().nextInt(USER_AGENTS.size()));
        HttpRequest request = HttpRequest.newBuilder(URI.create(url))
            .timeout(config.requestTimeout())
            .header("User-Agent", userAgent)
            .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            .header("Accept-Language", "en-US,en;q=0.8,sk;q=0.6")
            .GET()
            .build();

        log.debug("GET {} ua='{}' delayMs={}", url, userAgent, delay);
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
        return new FetchResponse(response.statusCode(), response.body(), response.uri().toString(), delay);
    }

    public record FetchResponse(int statusCode, String body, String finalUrl, long delayMs) {
    }
}
