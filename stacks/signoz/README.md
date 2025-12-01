# SigNoz Observability Stack

Full observability platform with **automatic field indexing** and **queryless UI**.

## What you get:
- ✅ **All JSON fields automatically indexed** - no config needed
- ✅ **Queryless UI** - point and click to explore logs
- ✅ **Logs, Traces, Metrics** - all in one place
- ✅ **Beautiful UI** - like Datadog but self-hosted

## Services
- **ClickHouse** - Fast columnar storage
- **Query Service** - SigNoz backend
- **Frontend** - SigNoz UI (port 3301)
- **OTel Collector** - Receives telemetry data
- **Alert Manager** - Alerting

## Ports
- **3301** - SigNoz UI
- **4317** - OTLP gRPC (send logs/traces/metrics here)
- **4318** - OTLP HTTP

## Running

```bash
docker compose -f stacks/signoz/docker-compose.yaml up -d
```

Then open **http://localhost:3301**

## Sending Logs

Your app should send logs via OTLP:
- gRPC: `localhost:4317`
- HTTP: `localhost:4318`

Or add this label to your Docker containers to have their logs scraped automatically:
```yaml
labels:
  service.name: your-service
```

## Log Format

Just log JSON - all fields will be automatically indexed:
```json
{
  "timestamp": "2024-01-01T00:00:00Z",
  "level": "info",
  "message": "User logged in",
  "userId": "12345",
  "traceId": "abc123",
  "anything": "you want"
}
```

Every field will be searchable and filterable in the UI!

