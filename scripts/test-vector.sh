#!/usr/bin/env bash
# ==============================================================================
# Vector VRL Unit Testing & Regression Runner
# ==============================================================================
# Runs native Vector configuration unit tests (vector test) against the VRL
# transforms in vector/ across all storage profiles (base, hdd, ssd).
#
# Usage:
#   bash scripts/test-vector.sh             # Tests all production profiles
#   bash scripts/test-vector.sh --all       # Explicitly tests all profiles
#   bash scripts/test-vector.sh --profile hdd # Tests specific profile (base|hdd|ssd)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TEST_DIR="${ROOT_DIR}/tests/vector"
VECTOR_IMAGE="timberio/vector:0.45.0-alpine"

show_help() {
  echo "Usage: $(basename "$0") [OPTIONS]"
  echo ""
  echo "Runs native Vector unit tests ('vector test') against project configurations."
  echo ""
  echo "Options:"
  echo "  --all                 Test all production profiles (vector.yaml, vector.hdd.yaml, vector.ssd.yaml) [default]"
  echo "  --profile <name>      Test specific profile: base, hdd, ssd"
  echo "  -h, --help            Show this help message and exit"
  echo ""
}

PROFILE_MODE="all"
SPECIFIC_PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      PROFILE_MODE="all"
      shift
      ;;
    --profile)
      if [[ -z "${2:-}" ]]; then
        echo "❌ Error: --profile requires an argument (base, hdd, ssd)"
        exit 1
      fi
      PROFILE_MODE="single"
      SPECIFIC_PROFILE="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "❌ Unknown argument: $1"
      show_help
      exit 1
      ;;
  esac
done

# Collect test files
TEST_FILES=()
for test_file in "${TEST_DIR}"/test_*.yaml; do
  if [[ -f "${test_file}" ]]; then
    TEST_FILES+=("${test_file}")
  fi
done

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "❌ No test files found in ${TEST_DIR}!"
  exit 1
fi

# Detect whether vector is installed locally, else use Docker
RUN_CMD=()
if command -v vector >/dev/null 2>&1; then
  echo "ℹ️  Using local Vector binary: $(vector --version | head -n1)"
  RUN_CMD=("vector" "test")
else
  echo "ℹ️  Using Docker image: ${VECTOR_IMAGE}"
  RUN_CMD=("docker" "run" "--rm" "-v" "${ROOT_DIR}:/workspace" "${VECTOR_IMAGE}" "test")
fi

run_profile_test() {
  local profile_name="$1"
  local config_file="$2"

  echo "--------------------------------------------------------------------------------"
  echo "🧪 Testing Vector profile: [${profile_name}] -> ${config_file}"
  echo "--------------------------------------------------------------------------------"

  if [[ ! -f "${ROOT_DIR}/${config_file}" ]]; then
    echo "❌ Configuration file ${ROOT_DIR}/${config_file} not found!"
    return 1
  fi

  local exec_args=()
  if command -v vector >/dev/null 2>&1; then
    exec_args=("${ROOT_DIR}/${config_file}")
    for tf in "${TEST_FILES[@]}"; do
      exec_args+=("${tf}")
    done
  else
    exec_args=("/workspace/${config_file}")
    for tf in "${TEST_FILES[@]}"; do
      rel_path="${tf#"${ROOT_DIR}/"}"
      exec_args+=("/workspace/${rel_path}")
    done
  fi

  "${RUN_CMD[@]}" "${exec_args[@]}"
  echo "   ✅ Profile [${profile_name}] passed all unit tests!"
  echo ""
}

echo "================================================================================"
echo "🚀 [Vector Unit Tests] Starting VRL Regression Test Suite..."
echo "================================================================================"
echo "Found ${#TEST_FILES[@]} test suite files in tests/vector/:"
for tf in "${TEST_FILES[@]}"; do
  echo "  - $(basename "${tf}")"
done
echo ""

TOTAL_FAILURES=0

if [[ "${PROFILE_MODE}" == "single" ]]; then
  case "${SPECIFIC_PROFILE}" in
    base)
      run_profile_test "Base (vector.yaml)" "vector/vector.yaml" || TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
      ;;
    hdd)
      run_profile_test "HDD (vector.hdd.yaml)" "vector/vector.hdd.yaml" || TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
      ;;
    ssd)
      run_profile_test "SSD (vector.ssd.yaml)" "vector/vector.ssd.yaml" || TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
      ;;
    *)
      echo "❌ Invalid profile name: ${SPECIFIC_PROFILE}. Expected: base, hdd, ssd"
      exit 1
      ;;
  esac
else
  run_profile_test "Base (vector.yaml)" "vector/vector.yaml" || TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
  run_profile_test "HDD (vector.hdd.yaml)" "vector/vector.hdd.yaml" || TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
  run_profile_test "SSD (vector.ssd.yaml)" "vector/vector.ssd.yaml" || TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
fi

echo "================================================================================"
if [[ ${TOTAL_FAILURES} -eq 0 ]]; then
  echo "🎉 [SUCCESS] All Vector profiles passed 100% of VRL unit test assertions!"
  echo "================================================================================"
  exit 0
else
  echo "❌ [FAILURE] ${TOTAL_FAILURES} profile(s) failed Vector unit test assertions!"
  echo "================================================================================"
  exit 1
fi
