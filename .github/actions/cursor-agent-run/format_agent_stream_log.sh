#!/usr/bin/env bash
# Склеивает подряд идущие stream-json события:
# - thinking + subtype delta
# - assistant с content только из type=text (стрим токенов в отдельные строки JSON)
set -euo pipefail

buf_thinking=""
buf_assistant=""

flush_thinking() {
  if [[ -n "$buf_thinking" ]]; then
    echo "--- agent thinking ---"
    printf '%s' "$buf_thinking"
    echo
    buf_thinking=""
  fi
}

flush_assistant() {
  if [[ -n "$buf_assistant" ]]; then
    echo "--- agent assistant ---"
    printf '%s' "$buf_assistant"
    echo
    buf_assistant=""
  fi
}

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  if ! jq -e . >/dev/null 2>&1 <<<"$line"; then
    flush_thinking
    flush_assistant
    printf '%s\n' "$line"
    continue
  fi
  # Стрим ответа ассистента: много строк JSON с крошечными .text — склеиваем.
  if [[ "$(jq -r '
    if .type == "assistant" then
      (.message.content // []) as $c |
      if ($c | length) > 0 and all($c[]; .type == "text") then "y" else "n" end
    else "n" end
  ' <<<"$line")" == "y" ]]; then
    flush_thinking
    buf_assistant+=$(jq -r '[.message.content[]? | select(.type == "text") | .text // ""] | join("")' <<<"$line")
    continue
  fi
  if [[ "$(jq -r 'if (.type == "thinking" and .subtype == "delta") then "y" else "n" end' <<<"$line")" == "y" ]]; then
    flush_assistant
    buf_thinking+=$(jq -r '.text // ""' <<<"$line")
    continue
  fi
  flush_thinking
  flush_assistant
  printf '%s\n' "$line"
done
flush_thinking
flush_assistant
