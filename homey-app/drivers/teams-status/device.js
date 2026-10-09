'use strict';

const Homey = require('homey');
const WebSocket = require('ws');

const CAPABILITY_MAP = {
  inCall: 'alarm_generic.in_call',
  micEnabled: 'alarm_generic.mic_enabled',
  cameraEnabled: 'alarm_generic.camera_enabled',
};

module.exports = class TeamsStatusDevice extends Homey.Device {
  async onInit() {
    this.log('Teams Status device initialized');
    this._ws = null;
    this._reconnectTimer = null;
    this._reconnectDelayMs = 1000;
    this._destroyed = false;
    this._connect();
  }

  async onSettings({ changedKeys }) {
    if (changedKeys.includes('bridgeHost')) {
      this._reconnectDelayMs = 1000;
      this._teardownSocket();
      this._connect();
    }
  }

  async onDeleted() {
    this._destroyed = true;
    this._teardownSocket();
    if (this._reconnectTimer) clearTimeout(this._reconnectTimer);
  }

  _wsUrl() {
    const host = (this.getSetting('bridgeHost') || 'localhost:8942').trim();
    return `ws://${host}/ws`;
  }

  _connect() {
    if (this._destroyed) return;
    const url = this._wsUrl();
    this.log(`Connecting to ${url}`);

    let ws;
    try {
      ws = new WebSocket(url);
    } catch (err) {
      this.error('Failed to open WebSocket:', err.message);
      this._scheduleReconnect();
      return;
    }
    this._ws = ws;

    ws.on('open', () => {
      this.log('Connected to teams-bridge daemon');
      this._reconnectDelayMs = 1000;
    });

    ws.on('message', (data) => {
      this._handleStatus(data);
    });

    ws.on('close', () => {
      this._ws = null;
      this._scheduleReconnect();
    });

    ws.on('error', (err) => {
      this.error('WebSocket error:', err.message);
      // 'close' fires after 'error', which schedules the reconnect.
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

  _teardownSocket() {
    if (this._ws) {
      this._ws.removeAllListeners();
      this._ws.terminate();
      this._ws = null;
    }
    if (this._reconnectTimer) {
      clearTimeout(this._reconnectTimer);
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
