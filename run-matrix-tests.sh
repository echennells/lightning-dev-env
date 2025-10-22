#!/bin/bash

# Version Matrix Test Runner
# Runs tests across different version combinations defined in version-matrix.json

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Results directory
RESULTS_DIR="./test-results"
mkdir -p "$RESULTS_DIR"

# Parse command line arguments
RUN_SPECIFIC_SET=""
SKIP_DEPLOY=false
LIST_SETS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --set)
      RUN_SPECIFIC_SET="$2"
      shift 2
      ;;
    --skip-deploy)
      SKIP_DEPLOY=true
      shift
      ;;
    --list)
      LIST_SETS=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --set NAME          Run tests only for specific version set"
      echo "  --skip-deploy       Skip destroy/deploy, just run tests on current deployment"
      echo "  --list              List available version sets and exit"
      echo "  --help              Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo -e "${RED}Error: jq is required but not installed${NC}"
  exit 1
fi

# Read version sets from version-matrix.json
if [ ! -f "version-matrix.json" ]; then
  echo -e "${RED}Error: version-matrix.json not found${NC}"
  exit 1
fi

VERSION_SETS=$(jq -r '.version_sets[] | @json' version-matrix.json)

# List version sets if requested
if [ "$LIST_SETS" = true ]; then
  echo -e "${CYAN}Available version sets:${NC}"
  echo ""
  jq -r '.version_sets[] | "  \(.name): \(.description)"' version-matrix.json
  exit 0
fi

# Test tracking
TOTAL_SETS=0
PASSED_SETS=0
FAILED_SETS=0
RESULTS_SUMMARY=""

echo -e "${CYAN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${CYAN}┃  VERSION MATRIX TEST RUNNER                     ┃${NC}"
echo -e "${CYAN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo ""

# Iterate through version sets
while IFS= read -r version_set; do
  SET_NAME=$(echo "$version_set" | jq -r '.name')
  SET_DESC=$(echo "$version_set" | jq -r '.description')

  # Skip if specific set requested and this isn't it
  if [ -n "$RUN_SPECIFIC_SET" ] && [ "$SET_NAME" != "$RUN_SPECIFIC_SET" ]; then
    continue
  fi

  TOTAL_SETS=$((TOTAL_SETS + 1))

  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}Testing Version Set: ${YELLOW}$SET_NAME${NC}"
  echo -e "${BLUE}Description: ${NC}$SET_DESC"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  # Extract versions
  BITCOIN_VERSION=$(echo "$version_set" | jq -r '.versions.bitcoin_core')
  LITD_VERSION=$(echo "$version_set" | jq -r '.versions.litd')
  LND_VERSION=$(echo "$version_set" | jq -r '.versions.lnd')
  LNBITS_VERSION=$(echo "$version_set" | jq -r '.versions.lnbits')
  TAPROOT_ASSETS_VERSION=$(echo "$version_set" | jq -r '.versions.taproot_assets_ext')
  BITCOINSWITCH_VERSION=$(echo "$version_set" | jq -r '.versions.bitcoinswitch_ext')

  # Display version configuration
  echo -e "${CYAN}Version Configuration:${NC}"
  echo "  Bitcoin Core:      $BITCOIN_VERSION"
  echo "  LiT:               $LITD_VERSION"
  echo "  LND:               $LND_VERSION"
  echo "  LNbits:            $LNBITS_VERSION"
  echo "  Taproot Assets:    $TAPROOT_ASSETS_VERSION"
  echo "  Bitcoin Switch:    $BITCOINSWITCH_VERSION"
  echo ""

  # Export versions as environment variables
  export BITCOIN_CORE_VERSION="$BITCOIN_VERSION"
  export LITD_VERSION="$LITD_VERSION"
  export LND_VERSION="$LND_VERSION"
  export LNBITS_VERSION="$LNBITS_VERSION"
  export TAPROOT_ASSETS_VERSION="$TAPROOT_ASSETS_VERSION"
  export BITCOINSWITCH_VERSION="$BITCOINSWITCH_VERSION"

  # Set LNBITS_IMAGE for dev builds (local images)
  if [ "$LNBITS_VERSION" = "dev" ]; then
    export LNBITS_IMAGE="local-lnbits:dev"
  else
    # Unset LNBITS_IMAGE for official versions (let docker-compose use default)
    unset LNBITS_IMAGE
  fi

  # Create timestamped result file
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  RESULT_FILE="$RESULTS_DIR/test-${SET_NAME}-${TIMESTAMP}.log"
  RESULT_JSON="$RESULTS_DIR/test-${SET_NAME}-${TIMESTAMP}.json"

  # Build components from source if needed
  if [ -f "./build-from-source.sh" ]; then
    if ! ./build-from-source.sh "$SET_NAME" > "$RESULTS_DIR/build-${SET_NAME}-${TIMESTAMP}.log" 2>&1; then
      echo -e "${RED}✗ Source build failed${NC}"
      FAILED_SETS=$((FAILED_SETS + 1))
      RESULTS_SUMMARY+="\n${RED}✗${NC} $SET_NAME - Source build failed"
      continue
    fi
  fi

  # Deploy environment if not skipped
  if [ "$SKIP_DEPLOY" = false ]; then
    echo -e "${YELLOW}Deploying environment...${NC}"
    if ./destroy.sh </dev/null > /dev/null 2>&1; then
      echo -e "${GREEN}✓ Environment destroyed${NC}"
    else
      echo -e "${YELLOW}⚠ Destroy may have had warnings (continuing)${NC}"
    fi

    if ./bootstrap-with-taproot-assets.sh </dev/null > "$RESULTS_DIR/bootstrap-${SET_NAME}-${TIMESTAMP}.log" 2>&1; then
      echo -e "${GREEN}✓ Environment deployed${NC}"
    else
      echo -e "${RED}✗ Deployment failed${NC}"
      FAILED_SETS=$((FAILED_SETS + 1))
      RESULTS_SUMMARY+="\n${RED}✗${NC} $SET_NAME - Deployment failed"
      continue
    fi
  else
    echo -e "${YELLOW}Skipping deployment (using existing environment)${NC}"
  fi

  # Run test suite
  echo ""
  echo -e "${YELLOW}Running test suite...${NC}"

  if ./test-suite.sh </dev/null 2>&1 | tee "$RESULT_FILE"; then
    TEST_EXIT_CODE=0
  else
    TEST_EXIT_CODE=$?
  fi

  # Extract test results
  TESTS_PASSED=$(grep "^Passed:" "$RESULT_FILE" | awk '{print $2}' | sed 's/\x1b\[[0-9;]*m//g' || echo "0")
  TESTS_FAILED=$(grep "^Failed:" "$RESULT_FILE" | awk '{print $2}' | sed 's/\x1b\[[0-9;]*m//g' || echo "0")
  TESTS_TOTAL=$(grep "^Total Tests:" "$RESULT_FILE" | awk '{print $3}' | sed 's/\x1b\[[0-9;]*m//g' || echo "0")

  # Create JSON result
  cat > "$RESULT_JSON" <<EOF
{
  "version_set": "$SET_NAME",
  "description": "$SET_DESC",
  "timestamp": "$TIMESTAMP",
  "versions": {
    "bitcoin_core": "$BITCOIN_VERSION",
    "litd": "$LITD_VERSION",
    "lnd": "$LND_VERSION",
    "lnbits": "$LNBITS_VERSION",
    "taproot_assets_ext": "$TAPROOT_ASSETS_VERSION",
    "bitcoinswitch_ext": "$BITCOINSWITCH_VERSION"
  },
  "results": {
    "total": $TESTS_TOTAL,
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "exit_code": $TEST_EXIT_CODE
  },
  "log_file": "$RESULT_FILE"
}
EOF

  # Update tracking
  if [ "$TEST_EXIT_CODE" -eq 0 ]; then
    PASSED_SETS=$((PASSED_SETS + 1))
    echo ""
    echo -e "${GREEN}✅ ALL TESTS PASSED for $SET_NAME${NC}"
    RESULTS_SUMMARY+="\n${GREEN}✓${NC} $SET_NAME - $TESTS_PASSED/$TESTS_TOTAL tests passed"
  else
    FAILED_SETS=$((FAILED_SETS + 1))
    echo ""
    echo -e "${RED}❌ SOME TESTS FAILED for $SET_NAME${NC}"
    RESULTS_SUMMARY+="\n${RED}✗${NC} $SET_NAME - $TESTS_FAILED/$TESTS_TOTAL tests failed"
  fi

  echo -e "${CYAN}Results saved to:${NC}"
  echo "  Log:  $RESULT_FILE"
  echo "  JSON: $RESULT_JSON"

done <<< "$VERSION_SETS"

# Print summary
echo ""
echo -e "${CYAN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${CYAN}┃  MATRIX TEST SUMMARY                            ┃${NC}"
echo -e "${CYAN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo ""
echo -e "Total Version Sets Tested: ${BLUE}$TOTAL_SETS${NC}"
echo -e "Passed: ${GREEN}$PASSED_SETS${NC}"
echo -e "Failed: ${RED}$FAILED_SETS${NC}"
echo ""
echo -e "${CYAN}Results by Version Set:${NC}"
echo -e "$RESULTS_SUMMARY"
echo ""

if [ $FAILED_SETS -eq 0 ]; then
  echo -e "${GREEN}🎉 ALL VERSION SETS PASSED!${NC}"
  exit 0
else
  echo -e "${RED}❌ SOME VERSION SETS FAILED${NC}"
  exit 1
fi
