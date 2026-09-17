#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

version="${LEARNIT_ORT_VERSION:-1.23.1}"
source_dir="${LEARNIT_ORT_SOURCE:-${repo_root}/build/phase1/upstream/onnxruntime}"
build_root="${LEARNIT_ORT_BUILD_ROOT:-${repo_root}/build/phase1/onnxruntime-build}"
package_root="${LEARNIT_ORT_PACKAGE_ROOT:-${repo_root}/build/phase1/onnxruntime-android}"
operator_config="${LEARNIT_ORT_OPERATOR_CONFIG:-${repo_root}/native/onnxruntime/supertonic_required_operators.config}"
python_bin="${LEARNIT_PYTHON:-python3}"
python_path="${LEARNIT_ORT_PYTHONPATH:-${repo_root}/build/phase1/python-packages}"
sdk_path="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/home/dev/android-sdk}}"
ndk_path="${LEARNIT_ANDROID_NDK:-${sdk_path}/ndk/28.2.13676358}"
android_api="${LEARNIT_ANDROID_API:-24}"
jobs="${LEARNIT_ORT_JOBS:-4}"
abi_csv="${LEARNIT_ANDROID_ABIS:-arm64-v8a x86_64}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "falta el comando requerido: $1"
}

require_command git
require_command cmake
require_command sha256sum
"$python_bin" --version >/dev/null 2>&1 ||
  die "no se encontró Python en LEARNIT_PYTHON: ${python_bin}"

[[ "$version" == "1.23.1" ]] ||
  die "v0.6.0 solo admite ONNX Runtime fijado a la versión 1.23.1"

expected_source_commit="d9b2048791efb5804fe3d53a04b4971256addebf"
if [[ ! -d "${source_dir}/.git" ]]; then
  mkdir -p "$(dirname -- "${source_dir}")"
  git clone --branch "v${version}" --depth 1 --recurse-submodules \
    https://github.com/microsoft/onnxruntime.git "${source_dir}"
fi

source_commit="$(git -C "${source_dir}" rev-parse HEAD)"
[[ "$source_commit" == "$expected_source_commit" ]] ||
  die "el checkout de ONNX Runtime no coincide con v${version}: ${source_commit}"
source_tag="$(git -C "${source_dir}" describe --tags --exact-match "$source_commit" 2>/dev/null || true)"
[[ "$source_tag" == "v${version}" ]] ||
  die "el checkout de ONNX Runtime no tiene el tag v${version}"
[[ -f "${source_dir}/cmake/external/onnxruntime_external_deps.cmake" ]] ||
  die "faltan submódulos de ONNX Runtime; ejecuta git submodule update en el checkout"

[[ -f "$operator_config" ]] ||
  die "no existe la configuración reducida: ${operator_config}"
[[ -d "${sdk_path}/platforms" ]] ||
  die "no se encontró el Android SDK en ${sdk_path}"
[[ -x "${ndk_path}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]] ||
  die "no existe el toolchain LLVM del NDK: ${ndk_path}"

PYTHONPATH="$python_path" "$python_bin" - <<'PY' >/dev/null
import flatbuffers
import onnx
PY
operator_hash="$(sha256sum "$operator_config" | awk '{print $1}')"

abi_csv="${abi_csv//,/ }"
read -r -a abi_list <<< "$abi_csv"
(("${#abi_list[@]}" > 0)) || die "LEARNIT_ANDROID_ABIS no puede estar vacío"
for abi in "${abi_list[@]}"; do
  case "$abi" in
    arm64-v8a|x86_64) ;;
    *) die "ABI no soportado por v0.6.0: ${abi}" ;;
  esac
done

package_dir="${package_root}/${version}"
mkdir -p "$package_dir"

for abi in "${abi_list[@]}"; do
  build_dir="${build_root}/android-${abi}"
  release_dir="${build_dir}/Release"
  output_library="${release_dir}/libonnxruntime.so"
  stamp_file="${release_dir}/.learnit-v06-onnxruntime-build"
  extra_build_args=()
  contrib_ops_mode="disabled"
  if [[ "$abi" == "arm64-v8a" ]]; then
    # ORT's ARM FP16 kernel references GetFusedActivationAttr from the
    # contrib sources even though the reduced Supertonic graph uses only
    # standard ai.onnx operators. Keep those sources available for linking;
    # operator reduction still controls the registered graph kernels.
    contrib_ops_mode="link_support"
  else
    extra_build_args+=(--disable_contrib_ops)
  fi
  stamp="$(printf '%s\n' \
    "version=${version}" \
    "source_commit=${source_commit}" \
    "abi=${abi}" \
    "android_api=${android_api}" \
    "operator_config_sha256=${operator_hash}" \
    "android_ndk=${ndk_path}" \
    "android_stl=c++_shared" \
    "build_shared_lib=true" \
    "client_package_build=true" \
    "reduced_ops=true" \
    "contrib_ops=${contrib_ops_mode}" \
    "unit_tests=false" \
    "benchmarks=false")"

  if [[ -f "$output_library" && -f "$stamp_file" ]] &&
     [[ "$(<"$stamp_file")" == "$stamp" ]]; then
    printf 'ONNX Runtime %s (%s): build existente, se reutiliza\n' "$version" "$abi"
  else
    printf 'ONNX Runtime %s (%s): compilando ABI móvil\n' "$version" "$abi"
    (
      cd "$source_dir"
      PYTHONPATH="$python_path" "$python_bin" tools/ci_build/build.py \
        --build_dir "$build_dir" \
        --config Release \
        --android \
        --android_abi "$abi" \
        --android_api "$android_api" \
        --android_sdk_path "$sdk_path" \
        --android_ndk_path "$ndk_path" \
        --android_cpp_shared \
        --build_shared_lib \
        --client_package_build \
        --include_ops_by_config "$operator_config" \
        "${extra_build_args[@]}" \
        --disable_ml_ops \
        --disable_rtti \
        --skip_tests \
        --skip_submodule_sync \
        --parallel "$jobs" \
        --cmake_extra_defines \
          onnxruntime_BUILD_UNIT_TESTS=OFF \
          onnxruntime_BUILD_BENCHMARKS=OFF
    )
    [[ -f "$output_library" ]] ||
      die "ONNX Runtime no produjo ${output_library}"
    printf '%s\n' "$stamp" > "$stamp_file"
  fi

  install_prefix="${build_dir}/install"
  cmake --install "$release_dir" --prefix "$install_prefix" >/dev/null
  installed_include="${install_prefix}/include/onnxruntime"
  installed_library="${install_prefix}/lib/libonnxruntime.so"
  [[ -d "$installed_include" && -f "$installed_library" ]] ||
    die "la instalación de ONNX Runtime quedó incompleta para ${abi}"

  stage_dir="${package_dir}/${abi}"
  mkdir -p "${stage_dir}/include" "${stage_dir}/lib"
  cp -f "${installed_include}"/*.h "${stage_dir}/include/"
  cp -f "$installed_library" "${stage_dir}/lib/libonnxruntime.so"
  printf '%s\n' "$version" > "${stage_dir}/version.txt"
  printf '%s\n' "$abi" > "${stage_dir}/abi.txt"
  printf '%s\n' "$android_api" > "${stage_dir}/android_api.txt"
  printf '%s\n' "$source_commit" > "${stage_dir}/source_commit.txt"
  printf '%s\n' "$operator_hash" > "${stage_dir}/operator_config_sha256.txt"
  printf '%s\n' \
    "runtime=onnxruntime" \
    "version=${version}" \
    "source_commit=${source_commit}" \
    "abi=${abi}" \
    "android_api=${android_api}" \
    "android_stl=c++_shared" \
    "build_shared_lib=true" \
    "client_package_build=true" \
    "reduced_ops=true" \
    "contrib_ops=${contrib_ops_mode}" \
    "operator_config_sha256=${operator_hash}" \
    > "${stage_dir}/build_options.txt"
  (
    cd "$stage_dir"
    sha256sum include/*.h lib/libonnxruntime.so
  ) > "${stage_dir}/sha256sums.txt"
done

"$python_bin" - "$package_dir" "$version" "$source_commit" "$android_api" \
  "$operator_hash" "${abi_list[@]}" <<'PY'
import json
import pathlib
import sys

package_dir = pathlib.Path(sys.argv[1])
version = sys.argv[2]
source_commit = sys.argv[3]
android_api = int(sys.argv[4])
operator_hash = sys.argv[5]
abis = sys.argv[6:]

manifest = {
    "runtime": "onnxruntime",
    "version": version,
    "source_commit": source_commit,
    "android_api": android_api,
    "abis": abis,
    "android_stl": "c++_shared",
    "build_shared_lib": True,
    "client_package_build": True,
    "reduced_ops": True,
    "operator_config_sha256": operator_hash,
}
(package_dir / "manifest.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

bash "${script_dir}/validate_onnxruntime_android.sh" "$package_dir"
printf 'Paquete móvil listo: %s\n' "$package_dir"
