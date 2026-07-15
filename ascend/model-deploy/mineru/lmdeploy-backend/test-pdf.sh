#!/usr/bin/env bash
set -Eeuo pipefail

API_URL="${API_URL:-http://127.0.0.1:8000}"
PDF_FILE="${1:-/data/mineru/input/xxxxx.pdf}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/data/mineru/output/evaluation}"
START_PAGE="${START_PAGE:-0}"
END_PAGE="${END_PAGE:-99999}"
CONTAINER_NAME="${CONTAINER_NAME:-mineru-api}"

RUN_ID="$(date +'%Y%m%d-%H%M%S')"
OUTPUT_DIR="${OUTPUT_ROOT}/pages-${START_PAGE}-${END_PAGE}-${RUN_ID}"
ZIP_FILE="${OUTPUT_DIR}/result.zip"
EXTRACT_DIR="${OUTPUT_DIR}/extracted"
METRICS_FILE="${OUTPUT_DIR}/metrics.txt"
LOG_FILE="${OUTPUT_DIR}/mineru-request.log"
SUMMARY_FILE="${OUTPUT_DIR}/summary.txt"

if [[ ! -f "${PDF_FILE}" ]]; then
  echo "PDF不存在: ${PDF_FILE}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}" "${EXTRACT_DIR}"

curl -fsS "${API_URL}/health" > "${OUTPUT_DIR}/health.json"
START_TIME="$(date --iso-8601=seconds)"

set +e
CURL_METRICS="$(
  curl --silent --show-error --max-time 3600 \
    -X POST "${API_URL}/file_parse" \
    -F "files=@${PDF_FILE};type=application/pdf" \
    -F "lang_list=ch" \
    -F "backend=vlm-engine" \
    -F "start_page_id=${START_PAGE}" \
    -F "end_page_id=${END_PAGE}" \
    -F "return_md=true" \
    -F "return_middle_json=true" \
    -F "return_model_output=true" \
    -F "return_content_list=true" \
    -F "return_images=true" \
    -F "response_format_zip=true" \
    -o "${ZIP_FILE}" \
    -w $'http_code=%{http_code}\ntime_total=%{time_total}\nsize_upload=%{size_upload}\nsize_download=%{size_download}\n'
)"
CURL_EXIT=$?
set -e

printf '%s\n' "${CURL_METRICS}" | tee "${METRICS_FILE}"
docker logs --since "${START_TIME}" "${CONTAINER_NAME}" > "${LOG_FILE}" 2>&1 || true

HTTP_CODE="$(awk -F= '/^http_code=/{print $2}' "${METRICS_FILE}")"

if [[ ${CURL_EXIT} -ne 0 || "${HTTP_CODE}" != "200" ]]; then
  echo "请求失败: curl_exit=${CURL_EXIT}, HTTP=${HTTP_CODE}" >&2
  head -c 4096 "${ZIP_FILE}" 2>/dev/null || true
  exit 1
fi

unzip -tq "${ZIP_FILE}"
unzip -oq "${ZIP_FILE}" -d "${EXTRACT_DIR}"

MD_FILE="$(find "${EXTRACT_DIR}" -type f -name '*.md' -print -quit)"
IMAGE_COUNT="$(find "${EXTRACT_DIR}" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' \) | wc -l)"
JSON_COUNT="$(find "${EXTRACT_DIR}" -type f -name '*.json' | wc -l)"
INVALID_BBOX_COUNT="$(grep -c 'Invalid bbox' "${LOG_FILE}" || true)"
FORMAT_WARNING_COUNT="$(grep -c 'does not match expected format' "${LOG_FILE}" || true)"

{
  echo "PDF=${PDF_FILE}"
  echo "pages=${START_PAGE}-${END_PAGE}"
  echo "output=${OUTPUT_DIR}"
  echo "input_sha256=$(sha256sum "${PDF_FILE}" | awk '{print $1}')"
  cat "${METRICS_FILE}"
  echo "markdown=${MD_FILE}"
  echo "markdown_lines=$(wc -l < "${MD_FILE}")"
  echo "markdown_chars=$(wc -m < "${MD_FILE}")"
  echo "images=${IMAGE_COUNT}"
  echo "json_files=${JSON_COUNT}"
  echo "invalid_bbox_warnings=${INVALID_BBOX_COUNT}"
  echo "format_warnings=${FORMAT_WARNING_COUNT}"
} | tee "${SUMMARY_FILE}"

echo "测试完成: ${OUTPUT_DIR}"