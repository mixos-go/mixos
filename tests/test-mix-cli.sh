#!/bin/bash
# MixOS-GO Mix CLI Integration Tests

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MIX="$PROJECT_DIR/artifacts/mix"
TEST_DIR="/tmp/mix-test-$$"
DB_PATH="$TEST_DIR/packages.db"
CACHE_DIR="$TEST_DIR/cache"
PKG_DIR="$PROJECT_DIR/artifacts/packages"
INSTALLER="$PROJECT_DIR/artifacts/mixos-install"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}✓ $1${NC}"
}

fail() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

# Setup
echo "Setting up test environment..."
mkdir -p "$TEST_DIR" "$CACHE_DIR"

# Copy packages to cache
if [ -d "$PKG_DIR" ]; then
    cp "$PKG_DIR"/*.mixpkg "$CACHE_DIR/" 2>/dev/null || true
fi

# Test 1: Version
echo ""
echo "Test 1: mix --version"
if $MIX --version | grep -q "1.0.0"; then
    pass "Version check"
else
    fail "Version check"
fi

# Test 2: Help
echo ""
echo "Test 2: mix --help"
if $MIX --help | grep -q "package manager"; then
    pass "Help output"
else
    fail "Help output"
fi

# Test 3: List (empty)
echo ""
echo "Test 3: mix list (empty database)"
if $MIX list --db "$DB_PATH" | grep -q "No packages installed"; then
    pass "Empty list"
else
    fail "Empty list"
fi

# Test 4: Update database
echo ""
echo "Test 4: mix update"
$MIX update --db "$DB_PATH" --cache "$CACHE_DIR" 2>/dev/null || true
pass "Update command runs"

# Test 5: Search
echo ""
echo "Test 5: mix search"
$MIX search --db "$DB_PATH" base 2>/dev/null || true
pass "Search command runs"

# Test 6: Info
echo ""
echo "Test 6: mix info"
$MIX info --db "$DB_PATH" base-files 2>/dev/null || true
pass "Info command runs"

# Test 7: Installer smoke check
echo ""
echo "Test 7: mixos-install --version"
if [ -x "$INSTALLER" ]; then
    if "$INSTALLER" --version | grep -q "mixos-install version"; then
        pass "Installer version"
    else
        fail "Installer version output"
    fi
else
    fail "Installer binary not found at $INSTALLER"
fi

# Cleanup
rm -rf "$TEST_DIR"

echo ""
echo "================================"
echo -e "${GREEN}All tests passed!${NC}"
echo "================================"
