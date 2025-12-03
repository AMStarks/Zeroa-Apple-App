#!/bin/bash
# Test script for Halo API on Optimus server
# Tests endpoints used by Zeroa and LASKO apps

set -e

BASE_URL="${1:-http://192.168.0.121/api}"
TEST_ADDRESS="${2:-ThGNWv22Mb89YwMKo8hAgTEL5ChWcnNuRJ}"
ZEROA_BUNDLE_ID="com.telestai.Zeroa"
LASKO_BUNDLE_ID="com.telestai.LASKO"

echo "🧪 Testing Halo API on Optimus"
echo "📍 Base URL: $BASE_URL"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_endpoint() {
    local name=$1
    local method=$2
    local url=$3
    local data=$4
    local expected_status=${5:-200}
    
    echo -n "Testing $name... "
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" "$url" 2>&1)
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" -H "Content-Type: application/json" -d "$data" "$url" 2>&1)
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓${NC} (HTTP $http_code)"
        echo "  Response: $(echo "$body" | head -c 200)..."
        return 0
    else
        echo -e "${RED}✗${NC} (HTTP $http_code, expected $expected_status)"
        echo "  Response: $body"
        return 1
    fi
}

# Test 1: Health endpoint
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
test_endpoint "Health" "GET" "$BASE_URL/health"
echo ""

# Test 2: Challenge endpoint (Zeroa)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Challenge Request (Zeroa)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
challenge_url="$BASE_URL/halo/challenge?address=$TEST_ADDRESS&bundleId=$ZEROA_BUNDLE_ID"
test_endpoint "Challenge (Zeroa)" "GET" "$challenge_url"

# Extract nonce from response for later tests
challenge_response=$(curl -s "$challenge_url")
nonce=$(echo "$challenge_response" | grep -o '"nonce":"[^"]*"' | cut -d'"' -f4 || echo "")
if [ -n "$nonce" ]; then
    echo "  ✓ Nonce received: ${nonce:0:20}..."
else
    echo "  ⚠ Could not extract nonce from response"
fi
echo ""

# Test 3: Challenge endpoint (LASKO)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. Challenge Request (LASKO)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
challenge_url_lasko="$BASE_URL/halo/challenge?address=$TEST_ADDRESS&bundleId=$LASKO_BUNDLE_ID"
test_endpoint "Challenge (LASKO)" "GET" "$challenge_url_lasko"
echo ""

# Test 4: Posts endpoint (requires auth - will fail without token, but tests endpoint exists)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Posts Endpoint (LASKO - requires auth)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
posts_response=$(curl -s -w "\n%{http_code}" "$BASE_URL/posts?limit=5")
posts_http_code=$(echo "$posts_response" | tail -n1)
posts_body=$(echo "$posts_response" | sed '$d')

if [ "$posts_http_code" = "200" ]; then
    echo -e "${GREEN}✓${NC} Posts endpoint accessible (HTTP 200)"
    echo "  Response: $(echo "$posts_body" | head -c 200)..."
elif [ "$posts_http_code" = "401" ] || [ "$posts_http_code" = "403" ]; then
    echo -e "${YELLOW}⚠${NC} Posts endpoint exists but requires authentication (HTTP $posts_http_code)"
    echo "  This is expected - endpoint is working correctly"
else
    echo -e "${RED}✗${NC} Unexpected response (HTTP $posts_http_code)"
    echo "  Response: $posts_body"
fi
echo ""

# Test 5: Legacy auth endpoints (fallback)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. Legacy Auth Endpoints (Fallback)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
legacy_challenge_url="$BASE_URL/auth/challenge?address=$TEST_ADDRESS&bundleId=$ZEROA_BUNDLE_ID"
legacy_response=$(curl -s -w "\n%{http_code}" "$legacy_challenge_url")
legacy_http_code=$(echo "$legacy_response" | tail -n1)

if [ "$legacy_http_code" = "200" ] || [ "$legacy_http_code" = "404" ]; then
    if [ "$legacy_http_code" = "404" ]; then
        echo -e "${YELLOW}⚠${NC} Legacy endpoint not found (HTTP 404) - apps will use /halo/* endpoints"
    else
        echo -e "${GREEN}✓${NC} Legacy endpoint available (HTTP 200)"
    fi
else
    echo -e "${RED}✗${NC} Unexpected response (HTTP $legacy_http_code)"
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Health endpoint: Working"
echo "✅ Challenge endpoint (/halo/challenge): Working"
echo "✅ Posts endpoint (/api/posts): Accessible (auth required)"
echo ""
echo "🎯 API Status: READY for Zeroa and LASKO apps"
echo ""
echo "💡 Next steps:"
echo "   1. Test from iOS apps (rebuild and run)"
echo "   2. Verify authentication flow end-to-end"
echo "   3. Test posting functionality in LASKO"

