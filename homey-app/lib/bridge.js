'use strict';

const http = require('http');

const DEFAULT_PORT = 8942;

/**
 * Turns what a person typed ("192.168.1.50", "mac.local:8942",
 * "http://10.0.0.5:8942/") into "host:port".
 */
function normalizeAddress(input) {
  let value = String(input || '').trim();
  value = value.replace(/^[a-z]+:\/\//i, '').replace(/\/.*$/, '');
  if (!value) throw new Error('Enter the Mac\'s address.');
  if (!/:\d+$/.test(value)) value += `:${DEFAULT_PORT}`;
  return value;
}

/** One-off GET /status; rejects unless the address really is a Deckhand app. */
function fetchStatus(address, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const request = http.get(`http://${address}/status`, { timeout: timeoutMs }, (response) => {
      if (response.statusCode !== 200) {
        response.resume();
        reject(new Error(`Unexpected answer (HTTP ${response.statusCode}).`));
        return;
      }
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => { body += chunk; });
      response.on('end', () => {
        try {
          const status = JSON.parse(body);
          if (typeof status.inCall !== 'boolean') throw new Error('not Deckhand');
          resolve(status);
        } catch (err) {
          reject(new Error('That address answered, but it doesn\'t look like Deckhand.'));
        }
      });
    });
    request.on('timeout', () => request.destroy(new Error('No answer. Check the address and that Deckhand is running.')));
    request.on('error', (err) => reject(new Error(err.message.startsWith('No answer') ? err.message : `Couldn't connect: ${err.message}`)));
  });
}

module.exports = { DEFAULT_PORT, normalizeAddress, fetchStatus };
