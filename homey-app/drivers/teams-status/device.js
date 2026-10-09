'use strict';

const Homey = require('homey');
const WebSocket = require('ws');
const { DEFAULT_PORT } = require('../../lib/bridge');

const CAPABILITY_MAP = {
  inCall: 'alarm_generic.in_call',
  micEnabled: 'alarm_generic.mic_enabled',
  cameraEnabled: 'alarm_generic.camera_enabled',
  handRaised: 'alarm_generic.hand_raised',
  autoMuteEnabled: 'alarm_generic.automute_enabled',
};

// A sleeping Mac or a dropped Wi-Fi link can leave a TCP connection looking
// open forever. Ping regularly and give up on one that stops answering.
const PING_INTERVAL_MS = 20_000;

module.exports = class TeamsStatusDevice extends Homey.Device {
  async onInit() {
    this._ws = null;
    this._reconnectTimer = null;
    this._pingTimer = null;
    this._reconnectDelayMs = 1000;
    this._destroyed = false;

    // Devices paired with an older version lack capabilities added since.
    for (const capability of Object.values(CAPABILITY_MAP)) {
      if (!this.hasCapability(capability)) await this.addCapability(capability);
    }

    await this.setUnavailable(this.homey.__('device.connecting')).catch(this.error);
    this._connect();
  }

  async onSettings({ newSettings, changedKeys }) {
    if (changedKeys.includes('bridgeHost')) {
      if (!String(newSettings.bridgeHost || '').trim()) throw new Error(this.homey.__('device.address_required'));
      this._reconnectDelayMs = 1000;
      this._teardownSocket();
      this._connect();
    }
  }

  async onDeleted() {
    this._destroyed = true;
    this._teardownSocket();
  }

  _wsUrl() {
    let host = (this.getSetting('bridgeHost') || '').trim().replace(/^[a-z]+:\/\//i, '').replace(/\/.*$/, '');
    if (host && !/:\d+$/.test(host)) host += `:${DEFAULT_PORT}`;
    return `ws://${host || `localhost:${DEFAULT_PORT}`}/ws`;
  }

  _connect() {
    if (this._destroyed) return;
    const url = this._wsUrl();
    this.log(`Connecting to ${url}`);

    let ws;
    try {
      ws = new WebSocket(url, { handshakeTimeout: 10_000 });
    } catch (err) {
      this.error('Failed to open WebSocket:', err.message);
      this._scheduleReconnect();
      return;
    }
    this._ws = ws;

    ws.on('open', () => {
      this.log('Connected');
      this._reconnectDelayMs = 1000;
      ws.isAlive = true;
      this._pingTimer = this.homey.setInterval(() => {
        if (ws.isAlive === false) {
          this.log('No answer to ping; reconnecting');
          ws.terminate();
          return;
        }
        ws.isAlive = false;
        try { ws.ping(); } catch (err) { ws.terminate(); }
      }, PING_INTERVAL_MS);
    });

    ws.on('pong', () => { ws.isAlive = true; });

    ws.on('message', (data) => {
      ws.isAlive = true;
      this._handleStatus(data);
    });

    ws.on('close', () => {
      if (this._ws !== ws) return; // an old socket we already replaced
      this._ws = null;
      this._clearPing();
      this.setUnavailable(this.homey.__('device.unreachable')).catch(this.error);
      this._scheduleReconnect();
    });

    ws.on('error', (err) => {
      this.error('WebSocket error:', err.message);
      // 'close' follows 'error' and schedules the reconnect.
    });
  }

  _scheduleReconnect() {
    if (this._destroyed || this._reconnectTimer) return;
    this._reconnectTimer = this.homey.setTimeout(() => {
      this._reconnectTimer = null;
      this._connect();
    }, this._reconnectDelayMs);
    this._reconnectDelayMs = Math.min(this._reconnectDelayMs * 2, 30_000);
  }

  _clearPing() {
    if (this._pingTimer) {
      this.homey.clearInterval(this._pingTimer);
      this._pingTimer = null;
    }
  }

  _teardownSocket() {
    this._clearPing();
    if (this._ws) {
      const ws = this._ws;
      this._ws = null;
      ws.removeAllListeners();
      ws.on('error', () => {});
      ws.terminate();
    }
    if (this._reconnectTimer) {
      this.homey.clearTimeout(this._reconnectTimer);
      this._reconnectTimer = null;
    }
  }

  async _handleStatus(raw) {
    let status;
    try {
      status = JSON.parse(raw.toString());
    } catch (err) {
      this.error('Received malformed status frame:', err.message);
      return;
    }
    if (!status || typeof status !== 'object') return;

    if (!this.getAvailable()) await this.setAvailable().catch(this.error);

    for (const [field, capability] of Object.entries(CAPABILITY_MAP)) {
      if (typeof status[field] !== 'boolean') continue;
      if (this.getCapabilityValue(capability) === status[field]) continue;
      try {
        await this.setCapabilityValue(capability, status[field]);
      } catch (err) {
        this.error(`Failed to set ${capability}:`, err.message);
      }
    }
  }
};
