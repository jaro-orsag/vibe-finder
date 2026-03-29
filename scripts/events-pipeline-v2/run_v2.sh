#!/usr/bin/env bash
set -euo pipefail

RUN_ID_INPUT="${1:-}"
RUN_DATE="${2:-$(date +%Y-%m-%d)}"
NOW_TS="$(date +%Y-%m-%d_%H%M%S)"

if [[ -z "${RUN_ID_INPUT}" ]]; then
	RUN_ID="${NOW_TS}"
elif [[ "${RUN_ID_INPUT}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}.*$ ]]; then
	RUN_ID="${RUN_ID_INPUT}"
else
	RUN_ID="${RUN_ID_INPUT}_${NOW_TS}"
fi
EXTRA_ARGS="${*:3}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SOURCE_CATALOG="${REPO_ROOT}/data/sources/bratislava-event-sources.yaml"
OUTPUT_ROOT="${REPO_ROOT}/data/events-pipeline-v2"

cd "${REPO_ROOT}/apps/events-pipeline-v2"

if [[ -x "./gradlew" ]]; then
	./gradlew bootRun --args="--runId=${RUN_ID} --runDate=${RUN_DATE} --sourceCatalog=${SOURCE_CATALOG} --outputRoot=${OUTPUT_ROOT} ${EXTRA_ARGS}"
else
	gradle bootRun --args="--runId=${RUN_ID} --runDate=${RUN_DATE} --sourceCatalog=${SOURCE_CATALOG} --outputRoot=${OUTPUT_ROOT} ${EXTRA_ARGS}"
fi
