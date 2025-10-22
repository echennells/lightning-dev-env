#!/bin/bash

# Build Docker images from source for bleeding-edge testing
# This script clones repos and builds images from latest commits

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

VERSION_SET="$1"
BUILD_DIR="./builds"

if [ -z "$VERSION_SET" ]; then
  echo -e "${RED}Error: Version set name required${NC}"
  echo "Usage: $0 <version-set-name>"
  exit 1
fi

if [ ! -f "version-matrix.json" ]; then
  echo -e "${RED}Error: version-matrix.json not found${NC}"
  exit 1
fi

# Get build configuration for this version set
BUILD_CONFIG=$(jq -r ".version_sets[] | select(.name == \"$VERSION_SET\") | .build_from_source" version-matrix.json)

if [ "$BUILD_CONFIG" = "null" ] || [ -z "$BUILD_CONFIG" ]; then
  echo -e "${CYAN}No source builds required for version set: $VERSION_SET${NC}"
  exit 0
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Building components from source for: ${YELLOW}$VERSION_SET${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

mkdir -p "$BUILD_DIR"

# Parse build configurations
COMPONENTS=$(echo "$BUILD_CONFIG" | jq -r 'keys[]' 2>/dev/null || echo "")

if [ -z "$COMPONENTS" ]; then
  echo -e "${CYAN}No components to build${NC}"
  exit 0
fi

# Build each component
while IFS= read -r component; do
  echo -e "${BLUE}Building component: ${YELLOW}$component${NC}"

  REPO=$(echo "$BUILD_CONFIG" | jq -r ".$component.repo")
  BRANCH=$(echo "$BUILD_CONFIG" | jq -r ".$component.branch")
  DOCKERFILE=$(echo "$BUILD_CONFIG" | jq -r ".$component.dockerfile")

  COMPONENT_DIR="$BUILD_DIR/$component"

  echo "  Repository: $REPO"
  echo "  Branch: $BRANCH"
  echo ""

  # Clone or update repository
  if [ -d "$COMPONENT_DIR" ]; then
    echo -e "${YELLOW}  Updating existing clone...${NC}"
    cd "$COMPONENT_DIR"
    git fetch origin "$BRANCH:$BRANCH" 2>/dev/null || git fetch origin "$BRANCH"
    git checkout "$BRANCH"
    git pull origin "$BRANCH" 2>/dev/null || true
    COMMIT=$(git rev-parse --short HEAD)
  else
    echo -e "${YELLOW}  Cloning repository...${NC}"
    git clone --depth 1 --branch "$BRANCH" "$REPO" "$COMPONENT_DIR"
    cd "$COMPONENT_DIR"
    COMMIT=$(git rev-parse --short HEAD)
  fi

  echo -e "${GREEN}  ✓ Latest commit: $COMMIT${NC}"

  # Build Docker image
  echo -e "${YELLOW}  Building Docker image...${NC}"

  # Determine image name and tag
  # Use "local-" prefix so Docker Compose won't try to pull from Docker Hub
  case "$component" in
    lnbits)
      IMAGE_NAME="local-lnbits"
      TAG="dev-$COMMIT"
      ;;
    *)
      IMAGE_NAME="local-$component"
      TAG="dev-$COMMIT"
      ;;
  esac

  if docker build --platform linux/amd64 -t "$IMAGE_NAME:$TAG" -f "$DOCKERFILE" . 2>&1 | tee "$SCRIPT_DIR/$BUILD_DIR/build-$component.log"; then
    # Also tag as "dev" for version variable
    docker tag "$IMAGE_NAME:$TAG" "$IMAGE_NAME:dev"
    echo -e "${GREEN}  ✓ Built successfully: $IMAGE_NAME:$TAG${NC}"
    echo -e "${GREEN}  ✓ Tagged as: $IMAGE_NAME:dev${NC}"

    # Save commit info
    echo "$COMMIT" > "$SCRIPT_DIR/$BUILD_DIR/$component-commit.txt"
    git log -1 --format="%H%n%an%n%ae%n%ai%n%s" > "$SCRIPT_DIR/$BUILD_DIR/$component-commit-info.txt"

    echo ""
    echo -e "${CYAN}  Commit details:${NC}"
    echo "    Hash: $COMMIT"
    echo "    Author: $(git log -1 --format='%an <%ae>')"
    echo "    Date: $(git log -1 --format='%ai')"
    echo "    Message: $(git log -1 --format='%s')"
  else
    echo -e "${RED}  ✗ Build failed${NC}"
    cd "$SCRIPT_DIR"
    exit 1
  fi

  cd "$SCRIPT_DIR"
  echo ""

done <<< "$COMPONENTS"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ All source builds completed successfully${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}Build artifacts:${NC}"
ls -lh "$BUILD_DIR"/*.txt 2>/dev/null || echo "  (none)"
