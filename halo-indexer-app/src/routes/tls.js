const express = require('express');
const router = express.Router();
const http = require('http');

// Ensure dotenv is loaded (in case routes are loaded before index.js loads it)
// Load from the app root directory (parent of src/)
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

// TLS RPC daemon endpoint (localhost only)
const TLS_RPC_URL = process.env.TLS_RPC_URL || 'http://127.0.0.1:8766';
const TLS_RPC_USER = process.env.TLS_RPC_USER || '';
const TLS_RPC_PASS = process.env.TLS_RPC_PASS || '';

// Debug: Log RPC config (without password)
console.log('TLS RPC Config:', {
  url: TLS_RPC_URL,
  user: TLS_RPC_USER || '(not set)',
  passSet: !!TLS_RPC_PASS
});

// RPC Proxy endpoint - forwards RPC calls to telestaid
router.post('/rpc', async (req, res) => {
  try {
    const { method, params, id } = req.body;
    
    if (!method) {
      return res.status(400).json({ error: { code: -1, message: 'Method required' } });
    }
    
    // Build RPC request
    const rpcRequest = {
      method,
      params: params || [],
      id: id || Math.floor(Math.random() * 1000000)
    };
    
    // Create HTTP request to telestaid
    const url = new URL(TLS_RPC_URL);
    const headers = {
      'Content-Type': 'application/json'
    };
    
    // Only add Authorization header if credentials are provided
    if (TLS_RPC_USER && TLS_RPC_PASS) {
      headers['Authorization'] = 'Basic ' + Buffer.from(`${TLS_RPC_USER}:${TLS_RPC_PASS}`).toString('base64');
    }
    
    const options = {
      hostname: url.hostname,
      port: url.port || 8766,
      path: '/',
      method: 'POST',
      headers: headers
    };
    
    const rpcResponse = await new Promise((resolve, reject) => {
      const httpReq = http.request(options, (httpRes) => {
        let data = '';
        
        httpRes.on('data', (chunk) => { data += chunk; });
        httpRes.on('end', () => {
          if (!data || data.trim().length === 0) {
            console.error('Empty response from RPC daemon. Status:', httpRes.statusCode, 'Headers:', JSON.stringify(httpRes.headers));
            return reject(new Error(`Empty response from RPC daemon (status ${httpRes.statusCode})`));
          }
          try {
            const parsed = JSON.parse(data);
            
            // Telestaid returns HTTP 500 for RPC errors, but the actual error is in the JSON body
            // Always return the parsed JSON response, even if HTTP status is 500
            // The client will handle RPC errors from the error field in the JSON
            if (parsed.error) {
              console.warn(`RPC error (HTTP ${httpRes.statusCode}):`, parsed.error);
            }
            
            // Return the parsed response regardless of HTTP status code
            // This allows RPC errors to be properly propagated to the client
            resolve(parsed);
          } catch (e) {
            console.error('JSON parse error. Status:', httpRes.statusCode, 'Response data (first 200 chars):', data.substring(0, 200));
            reject(new Error(`Invalid JSON response (status ${httpRes.statusCode}): ${e.message}`));
          }
        });
      });
      
      httpReq.on('error', (e) => {
        console.error('HTTP request error:', e.message);
        reject(new Error(`RPC request failed: ${e.message}`));
      });
      
      // Set timeout
      httpReq.setTimeout(10000, () => {
        httpReq.destroy();
        reject(new Error('RPC request timeout'));
      });
      
      const requestBody = JSON.stringify(rpcRequest);
      console.log('Sending RPC request:', method, 'to', TLS_RPC_URL);
      httpReq.write(requestBody);
      httpReq.end();
    });
    
    res.json(rpcResponse);
    
  } catch (error) {
    console.error('TLS RPC proxy error:', error);
    res.status(500).json({
      error: {
        code: -1,
        message: error.message || 'RPC proxy error'
      },
      id: req.body?.id || null
    });
  }
});

// Transaction signing endpoint
// NOTE: This is a temporary solution. Ideally, signing should happen client-side.
// This endpoint accepts the private key, which is not ideal for security.
// Route is mounted at /api/tls, so /sign becomes /api/tls/sign
router.post('/sign', async (req, res) => {
  try {
    const { rawHex, privateKeyHex } = req.body;
    
    if (!rawHex || !privateKeyHex) {
      return res.status(400).json({ error: 'rawHex and privateKeyHex required' });
    }
    
    // Use RPC signrawtransaction with private key
    const rpcRequest = {
      method: 'signrawtransaction',
      params: [rawHex, [], [privateKeyHex]],
      id: Math.floor(Math.random() * 1000000)
    };
    
    const url = new URL(TLS_RPC_URL);
    const headers = {
      'Content-Type': 'application/json'
    };
    
    // Only add Authorization header if credentials are provided
    if (TLS_RPC_USER && TLS_RPC_PASS) {
      headers['Authorization'] = 'Basic ' + Buffer.from(`${TLS_RPC_USER}:${TLS_RPC_PASS}`).toString('base64');
    }
    
    const options = {
      hostname: url.hostname,
      port: url.port || 8766,
      path: '/',
      method: 'POST',
      headers: headers
    };
    
    const rpcResponse = await new Promise((resolve, reject) => {
      const httpReq = http.request(options, (httpRes) => {
        let data = '';
        httpRes.on('data', (chunk) => { data += chunk; });
        httpRes.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            resolve(parsed);
          } catch (e) {
            reject(new Error(`Invalid JSON response: ${e.message}`));
          }
        });
      });
      
      httpReq.on('error', (e) => {
        reject(new Error(`RPC request failed: ${e.message}`));
      });
      
      httpReq.write(JSON.stringify(rpcRequest));
      httpReq.end();
    });
    
    if (rpcResponse.error) {
      return res.status(400).json({ error: rpcResponse.error.message });
    }
    
    if (!rpcResponse.result || !rpcResponse.result.hex) {
      return res.status(500).json({ error: 'Invalid signing response' });
    }
    
    res.json({ signedHex: rpcResponse.result.hex });
    
  } catch (error) {
    console.error('TLS signing error:', error);
    res.status(500).json({ error: error.message || 'Signing failed' });
  }
});

module.exports = router;


