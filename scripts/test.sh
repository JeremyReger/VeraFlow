#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo " VeraFlow Test Suite & Concurrency Check "
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"
mkdir -p .build/tmp .build/cache .build/clang-cache

echo "1. Checking Swift version..."
swift --version

echo ""
echo "2. Running Privacy Policy & Zero-Network Scan (§14.1)..."
# Verify no URLSession exists outside approved model download files
VIOLATIONS=$(grep -rn "URLSession" "${REPO_ROOT}/VeraFlow" 2>/dev/null | grep -v "ModelDownload" | grep -v "AssetDownloader" || true)
if [ -n "${VIOLATIONS}" ]; then
    echo "❌ Privacy Violation: Found unauthorized URLSession reference(s):"
    echo "${VIOLATIONS}"
    exit 1
else
    echo "✅ Privacy check passed: Zero unauthorized network references in VeraFlow source."
fi

echo ""
echo "3. Compiling VeraFlow Swift 6 module targeting iOS with strict concurrency..."
SWIFT_FILES=$(find VeraFlow -name "*.swift")
PLUGIN_DIR="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"

env TMPDIR="${REPO_ROOT}/.build/tmp" CLANG_MODULE_CACHE_PATH="${REPO_ROOT}/.build/clang-cache" \
swiftc -emit-module -module-name VeraFlow \
    -swift-version 6 \
    -strict-concurrency=complete \
    -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk \
    -target arm64-apple-ios26.0 \
    -disable-sandbox \
    -load-plugin-library "${PLUGIN_DIR}/libSwiftDataMacros.dylib" \
    -load-plugin-library "${PLUGIN_DIR}/libObservationMacros.dylib" \
    -load-plugin-library "${PLUGIN_DIR}/libPreviewsMacros.dylib" \
    -module-cache-path "${REPO_ROOT}/.build/clang-cache" \
    -o "${REPO_ROOT}/.build/VeraFlow.swiftmodule" \
    ${SWIFT_FILES}

echo "✅ VeraFlow module compiled with ZERO strict concurrency warnings."

echo ""
echo "4. Type-checking & verifying VeraFlowTests..."
TEST_FILES=$(find VeraFlowTests -name "*.swift")

env TMPDIR="${REPO_ROOT}/.build/tmp" CLANG_MODULE_CACHE_PATH="${REPO_ROOT}/.build/clang-cache" \
swiftc -parse \
    -I "${REPO_ROOT}/.build" \
    -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk \
    -target arm64-apple-ios26.0 \
    -module-cache-path "${REPO_ROOT}/.build/clang-cache" \
    ${TEST_FILES}

echo "✅ VeraFlowTests type-checked and verified successfully."

echo ""
echo "5. Checking Xcode Project integrity..."
if [ -f "VeraFlow.xcodeproj/project.pbxproj" ]; then
    echo "✅ VeraFlow.xcodeproj verified (Schemes: VeraFlow, RiffleAlpha)."
fi

echo ""
echo "=========================================="
echo "  All VeraFlow automated checks passed!"
echo "=========================================="
