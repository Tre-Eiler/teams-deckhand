'use strict';

const Homey = require('homey');

module.exports = class TeamsStatusDriver extends Homey.Driver {
  async onInit() {
    this.log('Teams Status driver initialized');
  }

  // There's only ever one teams-bridge daemon to talk to, so pairing just
  // offers a single fixed device rather than discovering anything.
  async onPairListDevices() {
    return [
      {
        name: 'Teams Status',
        data: { id: 'teams-bridge-daemon' },
      },
    ];
  }
};
