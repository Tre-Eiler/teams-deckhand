'use strict';

const Homey = require('homey');
const { normalizeAddress, fetchStatus } = require('../../lib/bridge');

module.exports = class TeamsStatusDriver extends Homey.Driver {
  async onInit() {
    this.log('Teams Status driver initialized');
  }

  async onPair(session) {
    let address = null;

    // The address screen asks for the Mac's host or IP, and only moves on once
    // that address really answers as Deckhand.
    session.setHandler('validate', async ({ host }) => {
      const normalized = normalizeAddress(host);
      await fetchStatus(normalized);
      address = normalized;
      return normalized;
    });

    session.setHandler('list_devices', async () => {
      if (!address) throw new Error('Enter the Mac\'s address first.');
      return [
        {
          name: `Deckhand (${address.replace(/:\d+$/, '')})`,
          data: { id: address },
          settings: { bridgeHost: address },
        },
      ];
    });
  }
};
