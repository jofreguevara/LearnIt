#!/usr/bin/env bash
set -euo pipefail

manifest_path="${1:-docs/phase1-artifacts.v0.3.json}"
include_comparison=false
if [[ "${2:-}" == "--all" ]]; then
  include_comparison=true
fi

project_root="$(git rev-parse --show-toplevel)"
manifest_file="$project_root/$manifest_path"

if [[ ! -f "$manifest_file" ]]; then
  echo "No existe el manifiesto: $manifest_path" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Se necesita jq para validar el manifiesto." >&2
  exit 1
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "Se necesita sha256sum para validar los artefactos." >&2
  exit 1
fi

if [[ "$include_comparison" == true ]]; then
  selection='true'
else
  selection='.status == "pinned" or .status == "pinned-bundle"'
fi

missing=0
mismatched=0
checked=0
while IFS=$'\t' read -r artifact_id local_path expected_size expected_sha; do
  checked=$((checked + 1))
  artifact_file="$project_root/$local_path"
  if [[ ! -f "$artifact_file" ]]; then
    echo "PENDIENTE $artifact_id: falta $local_path"
    missing=$((missing + 1))
    continue
  fi

  actual_size="$(wc -c < "$artifact_file")"
  actual_sha="$(sha256sum "$artifact_file" | cut -d' ' -f1)"
  if [[ "$actual_size" != "$expected_size" || "${actual_sha,,}" != "${expected_sha,,}" ]]; then
    echo "ERROR $artifact_id: tamaño/hash no coinciden"
    echo "  esperado: $expected_size bytes $expected_sha"
    echo "  actual:   $actual_size bytes $actual_sha"
    mismatched=$((mismatched + 1))
    continue
  fi
  echo "OK $artifact_id"
done < <(
  jq -r ".artifacts[] | select($selection) | [.id, .local_path, (.size_bytes | tostring), .sha256] | @tsv" \
    "$manifest_file"
)

echo "Comprobados: $checked; pendientes: $missing; incorrectos: $mismatched"
if [[ "$mismatched" -gt 0 ]]; then
  exit 1
fi
if [[ "$missing" -gt 0 ]]; then
  exit 2
fi
