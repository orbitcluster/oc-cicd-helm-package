#!/bin/bash
set -e

# Default values
CHART_PATH=""
GH_TOKEN=""
VERSION_OVERRIDE=""

# Argument Parsing
while getopts "p:t:v:" opt; do
  case ${opt} in
    p) CHART_PATH="$OPTARG" ;;
    t) GH_TOKEN="$OPTARG" ;;
    v) VERSION_OVERRIDE="$OPTARG" ;;
    \?) echo "Invalid option -$OPTARG" >&2; exit 1 ;;
  esac
done

# 1. Validation: Chart.yaml existence
if [ ! -f "${CHART_PATH}/Chart.yaml" ] || [ ! -r "${CHART_PATH}/Chart.yaml" ]; then
    echo "Error: Chart.yaml not found or not readable at ${CHART_PATH}"
    exit 1
fi

cd "${CHART_PATH}"

# 2. Extract Info
# Using yq to extract name (assuming yq is available on runner, typical for GH Actions)
# Fallback to grep if needed, but requirements said "Use yq"
CHART_NAME=$(yq eval '.name' Chart.yaml)
BASE_VERSION_RAW=$(yq eval '.version' Chart.yaml)

# Strip pre-release suffixes (e.g., 1.0.0-rc1 -> 1.0.0)
# Extract only the x.y.z part
BASE_VERSION=$(echo "$BASE_VERSION_RAW" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

echo "Chart Name: ${CHART_NAME}"
echo "Base Version: ${BASE_VERSION}"

# 3. OCI Repo Path
# ghcr.io/{github_repository}/helm -> lowercase
LOWER_REPO=$(echo "${GITHUB_REPOSITORY}" | tr '[:upper:]' '[:lower:]')
OCI_REPO="oci://ghcr.io/${LOWER_REPO}/helm"
echo "OCI Registry: ${OCI_REPO}"

# 4. Versioning Logic
FINAL_VERSION=""

if [ -n "$VERSION_OVERRIDE" ]; then
    echo "Using version override: ${VERSION_OVERRIDE}"
    FINAL_VERSION="${VERSION_OVERRIDE}"
else
    # Check Environment Variables for Branch Info
    # For PRs, GITHUB_HEAD_REF is set. For pushes, GITHUB_REF_NAME is set.
    # Note: Action runner context might need passing. We assume env vars are available.

    BRANCH_NAME=""
    if [ -n "$GITHUB_HEAD_REF" ]; then
        BRANCH_NAME="${GITHUB_HEAD_REF}"
        echo "Detected PR Branch: ${BRANCH_NAME}"
    elif [ -n "$GITHUB_REF_NAME" ]; then
        BRANCH_NAME="${GITHUB_REF_NAME}"
        echo "Detected Branch: ${BRANCH_NAME}"
    else
        echo "Error: Could not determine branch name."
        exit 1
    fi

    if [ "$BRANCH_NAME" == "main" ]; then
        echo "Branch is main. Using base version."
        FINAL_VERSION="${BASE_VERSION}"
    else
        echo "Branch is ${BRANCH_NAME}. Generating pre-release version."
        # Short Commit SHA
        SHORT_SHA=$(echo "${GITHUB_SHA}" | cut -c1-7)

        # Sanitize Branch Name (replace _ and / with -)
        SAFE_BRANCH=$(echo "${BRANCH_NAME}" | tr '_/' '--')

        # Format: {version}-{branch-name}-{short-commit}
        FINAL_VERSION="${BASE_VERSION}-${SAFE_BRANCH}-${SHORT_SHA}"
    fi
fi

# Sanitize Final Version just in case (Helm requires semantic versioning, alphanumeric + hyphens)
# We already sanitized parts, but let's ensure it's clean if needed.
echo "Target Version: ${FINAL_VERSION}"

# 5. Helm Operations

# Registry Login
echo "Logging into GHCR..."
echo "${GH_TOKEN}" | helm registry login ghcr.io --username "${GITHUB_ACTOR}" --password-stdin

# Dependency Build
echo "Building dependencies..."
helm dependency build

# Package
echo "Packaging chart..."
helm package . --version "${FINAL_VERSION}" --app-version "${FINAL_VERSION}"

PACKAGE_FILE="${CHART_NAME}-${FINAL_VERSION}.tgz"

if [ ! -f "$PACKAGE_FILE" ]; then
    echo "Error: Packaging failed. File ${PACKAGE_FILE} not found."
    exit 1
fi

# Push
echo "Pushing chart to ${OCI_REPO}..."
PUSH_OUTPUT=$(helm push "${PACKAGE_FILE}" "${OCI_REPO}")
echo "${PUSH_OUTPUT}"

# Registry Logout
helm registry logout ghcr.io

# 6. Parse Outputs for Action
# extract Digest: and Pushed: values from output
# Output format example:
# Pushed: ghcr.io/org/repo/helm/mychart:0.0.1
# Digest: sha256:7f...

# Use awk to reliably get the last word which is the value
PUSHED_REF=$(echo "${PUSH_OUTPUT}" | grep "Pushed:" | awk '{print $NF}')
DIGEST=$(echo "${PUSH_OUTPUT}" | grep "Digest:" | awk '{print $NF}')

# Construct full image reference
# PUSHED_REF already contains Ref:Tag
FULL_IMAGE="${PUSHED_REF}@${DIGEST}"

# Set GitHub Outputs
echo "chart-archive=${PACKAGE_FILE}" >> $GITHUB_OUTPUT
echo "image=${FULL_IMAGE}" >> $GITHUB_OUTPUT
echo "package=${LOWER_REPO}/helm/${CHART_NAME}" >> $GITHUB_OUTPUT
echo "version=${FINAL_VERSION}" >> $GITHUB_OUTPUT

echo "::notice::Successfully pushed ${FULL_IMAGE}"
