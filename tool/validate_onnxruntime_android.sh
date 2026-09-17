#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

version="${LEARNIT_ORT_VERSION:-1.23.1}"
package_dir="${1:-${LEARNIT_ORT_PACKAGE_ROOT:-${repo_root}/build/phase1/onnxruntime-android}/${version}}"
operator_config="${LEARNIT_ORT_OPERATOR_CONFIG:-${repo_root}/native/onnxruntime/supertonic_required_operators.config}"
python_bin="${LEARNIT_PYTHON:-python3}"
android_api="${LEARNIT_ANDROID_API:-24}"
abi_csv="${LEARNIT_ANDROID_ABIS:-arm64-v8a x86_64}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v readelf >/dev/null 2>&1 || die "falta el comando requerido: readelf"
command -v sha256sum >/dev/null 2>&1 || die "falta el comando requerido: sha256sum"
"$python_bin" --version >/dev/null 2>&1 ||
  die "no se encontró Python en LEARNIT_PYTHON: ${python_bin}"
[[ -f "${package_dir}/manifest.json" ]] ||
  die "no existe el manifiesto del paquete: ${package_dir}/manifest.json"
[[ -f "$operator_config" ]] ||
  die "no existe la configuración reducida: ${operator_config}"

operator_hash="$(sha256sum "$operator_config" | awk '{print $1}')"
abi_csv="${abi_csv//,/ }"
read -r -a abi_list <<< "$abi_csv"
(("${#abi_list[@]}" > 0)) || die "LEARNIT_ANDROID_ABIS no puede estar vacío"

"$python_bin" - "${package_dir}/manifest.json" "$version" "$android_api" \
  "$operator_hash" "${abi_list[@]}" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
expected_version = sys.argv[2]
expected_api = int(sys.argv[3])
expected_operator_hash = sys.argv[4]
expected_abis = sys.argv[5:]

checks = {
    "runtime": "onnxruntime",
    "version": expected_version,
    "android_api": expected_api,
    "abis": expected_abis,
    "android_stl": "c++_shared",
    "build_shared_lib": True,
    "client_package_build": True,
    "reduced_ops": True,
    "operator_config_sha256": expected_operator_hash,
}
for key, expected in checks.items():
    if manifest.get(key) != expected:
        raise SystemExit(
            f"manifest.json: {key}={manifest.get(key)!r}, "
            f"se esperaba {expected!r}"
        )
if not manifest.get("source_commit"):
    raise SystemExit("manifest.json: falta source_commit")
PY

for abi in "${abi_list[@]}"; do
  case "$abi" in
    arm64-v8a) expected_machine='AArch64' ;;
    x86_64) expected_machine='X86-64' ;;
    *) die "ABI no soportado por v0.6.0: ${abi}" ;;
  esac

  abi_dir="${package_dir}/${abi}"
  library="${abi_dir}/lib/libonnxruntime.so"
  [[ -f "${abi_dir}/version.txt" && "$(<"${abi_dir}/version.txt")" == "$version" ]] ||
    die "${abi}: version.txt no coincide con ${version}"
  [[ -f "${abi_dir}/abi.txt" && "$(<"${abi_dir}/abi.txt")" == "$abi" ]] ||
    die "${abi}: abi.txt no coincide con ${abi}"
  [[ -f "${abi_dir}/android_api.txt" && "$(<"${abi_dir}/android_api.txt")" == "$android_api" ]] ||
    die "${abi}: android_api.txt no coincide con ${android_api}"
  [[ -f "${abi_dir}/operator_config_sha256.txt" &&
     "$(<"${abi_dir}/operator_config_sha256.txt")" == "$operator_hash" ]] ||
    die "${abi}: hash de operadores no coincide"
  [[ -f "$library" ]] || die "${abi}: falta ${library}"
  [[ -f "${abi_dir}/sha256sums.txt" ]] || die "${abi}: falta sha256sums.txt"
  (
    cd "$abi_dir"
    sha256sum -c sha256sums.txt >/dev/null
  ) || die "${abi}: falló la verificación SHA-256 del paquete"

  elf_header="$(readelf -h "$library")"
  grep -Eq "Class:[[:space:]]+ELF64" <<< "$elf_header" ||
    die "${abi}: la biblioteca no es ELF64"
  grep -Eq "Machine:.*${expected_machine}" <<< "$elf_header" ||
    die "${abi}: máquina ELF inesperada"
  dynamic_section="$(readelf -d "$library")"
  grep -q 'SONAME.*libonnxruntime\.so' <<< "$dynamic_section" ||
    die "${abi}: falta SONAME libonnxruntime.so"
  grep -q 'NEEDED.*libc++_shared\.so' <<< "$dynamic_section" ||
    die "${abi}: la biblioteca no usa libc++_shared.so"
  grep -q 'NEEDED.*liblog\.so' <<< "$dynamic_section" ||
    die "${abi}: falta la dependencia Android liblog.so"
  readelf -Ws "$library" | grep -q 'OrtGetApiBase' ||
    die "${abi}: falta el símbolo público OrtGetApiBase"
  header_count="$(find "${abi_dir}/include" -maxdepth 1 -type f -name '*.h' | wc -l)"
  ((header_count >= 9)) || die "${abi}: faltan headers públicos (${header_count})"

  printf 'OK: ONNX Runtime %s / %s (%s)\n' "$version" "$abi" "$library"
done
