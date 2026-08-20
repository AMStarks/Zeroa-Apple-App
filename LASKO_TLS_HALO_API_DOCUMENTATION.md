# LASKO, TLS, and Halo Indexer API Documentation

## Table of Contents
1. [System Overview](#system-overview)
2. [Authentication & Security](#authentication--security)
3. [Halo Indexer API](#halo-indexer-api)
4. [TLS Blockchain API](#tls-blockchain-api)
5. [LASKO Client API](#lasko-client-api)
6. [Zeroa Integration API](#zeroa-integration-api)
7. [App Groups Communication](#app-groups-communication)
8. [Data Models](#data-models)
9. [Error Handling](#error-handling)
10. [Development & Testing](#development--testing)

---

## System Overview

### Architecture Layers
- **L1**: Telestai blockchain (daemon + RPC proxy)
- **L1.5**: Halo bridge (Indexer + API + Storage + Metrics)
- **L2**: LASKO UI + Zeroa iOS wallet

### Components
- **Halo Indexer**: Node.js/Express server (port 3001)
- **Storage**: Postgres (5432), Cassandra (9042), Redis (6380)
- **Observability**: Prometheus (9090), Grafana (3002)
- **API Gateway**: nginx 80/443 with HTTPS routing
- **iOS Apps**: LASKO (social media) + Zeroa (wallet)

---

## Authentication & Security

### JWT Token Flow
1. **Challenge Request**: Client requests nonce from Halo
2. **Signature**: Client signs canonical message with TLS private key
3. **Verification**: Halo verifies signature and issues JWT token
4. **API Access**: Client uses JWT for authenticated requests

### Canonical Message Format
```
LASKO|<nonce>|<ttlSeconds>|<bundleId>
```

### Security Headers
```http
Authorization: Bearer <JWT_TOKEN>
X-TLS-Address: <user_tls_address>
X-Bundle-Id: <app_bundle_id>
Content-Type: application/json
Accept: application/json
```

---

## Halo Indexer API

### Base URL
```
Production: https://halo.telestai.io/api
Development: http://localhost:3001/api
```

### 1. Health Check
**Endpoint**: `GET /api/health`
**Description**: Server health status
**Authentication**: None

**Response**:
```json
{
  "ok": true
}
```

### 2. Authentication Endpoints

#### 2.1 Challenge Request
**Endpoint**: `GET /api/halo/challenge`
**Description**: Request authentication challenge
**Authentication**: None

**Query Parameters**:
- `address` (string, required): TLS address
- `bundleId` (string, required): App bundle identifier

**Response**:
```json
{
  "nonce": "uuid-string",
  "ttlSeconds": 120
}
```

#### 2.2 Signature Verification
**Endpoint**: `POST /api/halo/verify`
**Description**: Verify signature and issue JWT token
**Authentication**: None

**Request Body**:
```json
{
  "address": "tls_address",
  "bundleId": "com.telestai.LASKO",
  "nonce": "challenge_nonce",
  "signature": "base64_signature",
  "pubkeyCompressedHex": "compressed_public_key"
}
```

**Response**:
```json
{
  "success": true,
  "token": "jwt_token",
  "exp": 1234567890,
  "expiresIn": 3600
}
```

#### 2.3 Alternative Auth Endpoints (Legacy)
**Endpoint**: `GET /api/auth/challenge`
**Endpoint**: `POST /api/auth/verify`
**Description**: Legacy authentication endpoints (fallback)

### 3. Posts API

#### 3.1 Fetch Posts
**Endpoint**: `GET /api/posts`
**Description**: Retrieve posts with pagination
**Authentication**: Required (JWT)

**Query Parameters**:
- `limit` (integer, optional): Number of posts (default: 50, max: 100)
- `page` (integer, optional): Page number (default: 0)

**Response**:
```json
{
  "success": true,
  "data": [
    {
      "id": "LAS#0000000000000000000000000000001",
      "sequentialCode": "LAS#0000000000000000000000000000001",
      "content": "Post content",
      "userAddress": "tls_address",
      "author": "tls_address",
      "address": "tls_address",
      "createdAt": "2024-01-01T00:00:00.000Z",
      "timestamp": 1704067200000,
      "timestampMs": 1704067200000,
      "likes": 0,
      "likesCount": 0,
      "replies": 0,
      "repliesCount": 0,
      "userRank": "Bronze",
      "postType": "free",
      "signature": "base64_signature",
      "pubkey": "compressed_public_key"
    }
  ],
  "pagination": {
    "page": 0,
    "limit": 50,
    "hasMore": true
  }
}
```

#### 3.2 Create Post
**Endpoint**: `POST /api/posts`
**Description**: Create new post or comment
**Authentication**: Required (JWT)

**Request Headers**:
```http
Authorization: Bearer <JWT_TOKEN>
X-TLS-Address: <tls_address>
X-Bundle-Id: <bundle_id>
Content-Type: application/json
```

**Request Body**:
```json
{
  "content": "Post content (max 1000 chars)",
  "userAddress": "tls_address",
  "signature": "base64_signature",
  "pubkey": "compressed_public_key",
  "timestamp": 1704067200000,
  "postType": "free",
  "parentSequentialCode": "optional_parent_id_for_comments"
}
```

**Response**:
```json
{
  "success": true,
  "data": {
    "id": "LAS#0000000000000000000000000000001",
    "sequentialCode": "LAS#0000000000000000000000000000001",
    "content": "Post content",
    "userAddress": "tls_address",
    "createdAt": "2024-01-01T00:00:00.000Z",
    "timestamp": 1704067200000,
    "likesCount": 0,
    "repliesCount": 0,
    "postType": "free"
  },
  "sequentialCode": "LAS#0000000000000000000000000000001"
}
```

#### 3.3 Get Single Post
**Endpoint**: `GET /api/posts/:id`
**Description**: Retrieve specific post by ID
**Authentication**: Required (JWT)

**Response**: Same as post object in fetch posts

#### 3.4 Get Post Replies
**Endpoint**: `GET /api/posts/:id/replies`
**Description**: Retrieve replies/comments for a post
**Authentication**: Required (JWT)

**Alternative Endpoints**:
- `GET /api/posts/:id/comments`
- `GET /api/comments?parentSequentialCode=:id`

**Response**:
```json
{
  "success": true,
  "data": [
    {
      "id": "LAS#0000000000000000000000000000002",
      "content": "Reply content",
      "userAddress": "tls_address",
      "parentSequentialCode": "parent_post_id",
      "createdAt": "2024-01-01T00:00:00.000Z",
      "timestamp": 1704067200000,
      "likesCount": 0,
      "repliesCount": 0
    }
  ]
}
```

### 4. Moderation API

#### 4.1 Get Moderation Charter
**Endpoint**: `GET /api/moderation/charter`
**Description**: Retrieve current moderation rules
**Authentication**: None

**Response**:
```json
{
  "success": true,
  "data": {
    "version": "2025-08-Preview-1",
    "categories": [
      {
        "key": "illegal",
        "title": "Illegal Content",
        "severity": "hard"
      },
      {
        "key": "sexual",
        "title": "Sexual Content",
        "severity": "soft"
      }
    ],
    "uiHints": {
      "suggestEdits": true,
      "highlightSpans": true
    }
  }
}
```

#### 4.2 Content Moderation Check
**Endpoint**: `POST /api/moderation/check`
**Description**: Check content against moderation rules
**Authentication**: None

**Request Body**:
```json
{
  "content": "Content to moderate",
  "postType": "free"
}
```

**Response**:
```json
{
  "success": true,
  "data": {
    "action": "allow",
    "violations": [],
    "categories": [],
    "reason": null,
    "charterVersion": "2025-08-Preview-1"
  }
}
```

#### 4.3 Media Moderation Check
**Endpoint**: `POST /api/moderation/media-check`
**Description**: Check media URLs against moderation rules
**Authentication**: None

**Request Body**:
```json
{
  "url": "https://example.com/image.jpg",
  "type": "image"
}
```

**Response**:
```json
{
  "success": true,
  "data": {
    "action": "allow",
    "violations": [],
    "mediaType": "image"
  }
}
```

---

## TLS Blockchain API

### Base URL
```
https://telestai.cryptoscope.io/api
```

### 1. Network Statistics
**Endpoint**: `GET /api/stats/`
**Description**: Get network statistics
**Authentication**: None

**Response**: Network statistics object

### 2. Address Information
**Endpoint**: `GET /api/getaddress/?address={address}`
**Description**: Get address balance and transaction history
**Authentication**: None

**Response**:
```json
{
  "timestamp": 1704067200000,
  "address": "tls_address",
  "balance": "100.5",
  "received": "150.0",
  "sent": "49.5",
  "groupid": null,
  "last_txs": [
    {
      "tx_time": 1704067200,
      "block_ix": 12345,
      "txid": "transaction_hash",
      "amount": "10.0",
      "is_reward": false
    }
  ]
}
```

### 3. Transaction Information
**Endpoint**: `GET /api/gettransaction/?txid={txid}`
**Description**: Get transaction details
**Authentication**: None

**Response**: Transaction details object

### 4. Block Information
**Endpoint**: `GET /api/getblock/?height={height}`
**Description**: Get block information
**Authentication**: None

**Response**: Block details object

---

## LASKO Client API

### Internal Service Methods

#### 1. Authentication Management
```swift
// Request Zeroa authentication
func requestZeroaAuthentication()

// Check authentication status
func checkZeroaAuthentication()

// Check for auth response
func checkForAuthResponse()

// Get display name for address
func getDisplayName(for address: String) -> String
```

#### 2. Post Management
```swift
// Fetch posts
func fetchPosts() async

// Create post
func createPost(content: String) async -> Bool

// Create comment
func createComment(content: String, parentSequentialCode: String) async -> Bool

// Fetch comments
func fetchComments(forSequentialCode: String) async

// Like post
func likePost(_ post: Post) async
```

#### 3. Token Management
```swift
// Ensure valid token for address
func ensureTokenForAddress(_ tlsAddress: String, timeoutSeconds: Double) async -> String?

// Ensure valid Halo token
func ensureValidHaloToken(timeoutSeconds: Double) async -> String?

// Read Halo token
func readHaloToken() -> String?

// Check token freshness
func tokenIsFresh(_ token: String, leewaySeconds: TimeInterval) -> Bool
```

#### 4. Signature Management
```swift
// SHA256 hash
func sha256Hex(of data: Data) -> String

// Verify signature via backend
func backendVerifySignature(address: String, message: String, signature: String) async -> Bool

// Verify signature
func verifySignature(address: String, message: String, signature: String) async -> Bool
```

---

## Zeroa Integration API

### Halo Service Methods
```swift
// Ensure valid token
func ensureToken(bundleId: String) async

// Check authentication status
var isAuthenticated: Bool
var tokenExp: Int64
```

### Halo API Service Methods
```swift
// Request challenge
func requestChallenge(address: String, bundleId: String) async throws -> Challenge

// Verify signature
func verify(address: String, bundleId: String, nonce: String, signature: String, pubkeyCompressedHex: String) async throws -> VerifyResponse

// Store token
func storeToken(_ token: String, exp: Int64)

// Get stored token
func storedToken() -> (token: String, exp: Int64)?
```

### LASKO Auth Service Methods
```swift
// Create auth session
func createLASKOAuthSession(permissions: [String]) async throws -> LASKOAuthSession

// Send auth response to LASKO
func sendAuthResponseToLASKO(_ session: LASKOAuthSession)

// Check for pending auth request
func checkForPendingAuthRequest() -> LASKOAuthRequest?

// Clear auth request
func clearAuthRequest()
```

---

## App Groups Communication

### Shared Container
```
Identifier: group.com.telestai.zeroa-lasko
```

### Key-Value Storage

#### Authentication Keys
```swift
// LASKO Auth Request
"lasko_auth_request": [String: Any]
"lasko_auth_request_nonce": String
"lasko_auth_request_timestamp": Double

// LASKO Auth Response
"lasko_auth_response": [String: Any]

// Halo Token
"halo_access_token": String
"haloAccessToken": String (backward compatibility)
"halo_token_expires_at": Int64
"halo_token_refresh_request": Bool
"halo_token_refreshed_at": Int
"halo_token_for_address": String

// Post Signing
"lasko_post_sign_request": [String: Any]
"lasko_post_sign_response": [String: Any]

// TLS Address
"tls_wallet_address": String

// Public Key
"zeroa_pubkey_compressed_hex": String

// Base URL Override
"halo_indexer_base_url": String
```

#### Data Structures

**LASKO Auth Request**:
```json
{
  "appName": "LASKO",
  "appId": "com.telestai.LASKO",
  "permissions": ["post", "read"],
  "callbackURL": "lasko://auth/callback",
  "timestamp": 1704067200.0,
  "nonce": "uuid-string",
  "expiresAt": 1704067500.0,
  "username": "optional_username"
}
```

**LASKO Auth Response**:
```json
{
  "tlsAddress": "tls_address",
  "sessionToken": "session_uuid",
  "signature": "base64_signature",
  "timestamp": 1704067200,
  "expiresAt": 1704070800,
  "permissions": ["post", "read"],
  "responseTimestamp": 1704067200.0
}
```

**Post Sign Request**:
```json
{
  "contentHashHex": "sha256_hash",
  "timestamp": 1704067200000
}
```

**Post Sign Response**:
```json
{
  "signatureBase64": "base64_signature",
  "pubkeyCompressedHex": "compressed_public_key",
  "timestampMs": 1704067200000
}
```

---

## Data Models

### Post Model
```swift
struct Post: Identifiable, Codable {
    let id: String
    let content: String
    let author: String
    let timestamp: Date
    let likes: Int
    let replies: Int
    var isLiked: Bool
    let userRank: String
}
```

### TLS Address Model
```swift
struct TLSAddress: Codable {
    let address: String
    let balance: Double
    let transactions: [TLSTransaction]
}
```

### TLS Transaction Model
```swift
struct TLSTransaction: Codable {
    let txid: String
    let amount: Double
    let fee: Double
    let confirmations: Int
    let timestamp: Int
    let type: String
    let from: String?
    let to: String?
    let message: String?
    let messageType: String?
}
```

### LASKO Auth Request Model
```swift
struct LASKOAuthRequest: Codable {
    let appName: String
    let appId: String
    let permissions: [String]
    let callbackURL: String
    let username: String?
    let nonce: String?
}
```

### LASKO Auth Session Model
```swift
struct LASKOAuthSession: Codable {
    let tlsAddress: String
    let sessionToken: String
    let signature: String
    let timestamp: Int64
    let expiresAt: Int64
    let permissions: [String]
}
```

### Challenge Model
```swift
struct Challenge: Decodable {
    let nonce: String
    let ttlSeconds: Int
}
```

### Verify Response Model
```swift
struct VerifyResponse: Decodable {
    let success: Bool?
    let token: String
    let exp: Int64?
    let expiresIn: Int?
}
```

---

## Error Handling

### HTTP Status Codes
- `200`: Success
- `201`: Created
- `400`: Bad Request
- `401`: Unauthorized
- `404`: Not Found
- `422`: Unprocessable Entity (Moderation blocked)
- `500`: Internal Server Error

### Error Response Format
```json
{
  "error": "Error message",
  "message": "Detailed error description",
  "code": "ERROR_CODE"
}
```

### Common Error Scenarios

#### Authentication Errors
```json
{
  "error": "Authentication failed",
  "message": "Invalid JWT token or signature"
}
```

#### Moderation Errors
```json
{
  "error": "Moderation blocked",
  "message": "Content violates moderation policy",
  "decision": {
    "action": "hard_block",
    "violations": [
      {
        "category": "illegal",
        "score": 1.0
      }
    ]
  }
}
```

#### Validation Errors
```json
{
  "error": "Invalid content",
  "message": "Content must not be empty and must be under 1000 characters"
}
```

---

## Development & Testing

### Environment Variables
```bash
# Halo Indexer
PORT=3001
CHARTER_VERSION=2025-08-Preview-1
GROK_API_KEY=optional_grok_api_key

# TLS Blockchain
TLS_API_BASE_URL=https://telestai.cryptoscope.io/api

# Development Overrides
HALO_INDEXER_BASE_URL=http://localhost:3001/api
```

### Testing Endpoints

#### Health Check
```bash
curl http://localhost:3001/api/health
```

#### Create Test Post
```bash
curl -X POST http://localhost:3001/api/posts \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "X-TLS-Address: YOUR_TLS_ADDRESS" \
  -d '{
    "content": "Test post content",
    "userAddress": "YOUR_TLS_ADDRESS",
    "signature": "test_signature",
    "timestamp": 1704067200000,
    "postType": "free"
  }'
```

#### Fetch Posts
```bash
curl http://localhost:3001/api/posts \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "X-TLS-Address: YOUR_TLS_ADDRESS"
```

### Mock Data
```swift
// LASKO Mock Posts
static let mockPosts = [
    Post(
        id: "LAS#0000000000000000000000000000001",
        content: "Welcome to LASKO!",
        author: "tls_address",
        timestamp: Date(),
        likes: 5,
        replies: 2,
        isLiked: false,
        userRank: "Gold"
    )
]
```

### Debug Logging
All services include comprehensive debug logging with emoji prefixes:
- 🔍: Information/checking
- ✅: Success
- ❌: Error
- ⚠️: Warning
- 🔐: Authentication
- 📤: Sending data
- 📥: Receiving data
- ⏱️: Timeout/timing
- 🧹: Cleanup

---

## Security Considerations

### Token Security
- JWT tokens have 60-second leeway for clock skew
- Tokens are bound to specific TLS addresses
- Automatic token refresh with timeout handling
- Tokens stored securely in App Groups

### Signature Security
- All posts require cryptographic signatures
- Signatures use SHA256 hash of content
- Public keys are compressed hex format
- Signatures are Base64 encoded

### Network Security
- All production endpoints use HTTPS
- CORS protection enabled
- Rate limiting via nginx
- Security headers (HSTS, X-Frame-Options, etc.)

### App Groups Security
- Shared container with restricted access
- TTL enforcement for auth requests/responses
- Callback URL validation
- Bundle ID verification

---

This documentation provides a comprehensive overview of all APIs, data structures, and integration points for the LASKO, TLS, and Halo Indexer systems. For implementation details, refer to the source code in the respective service files.
