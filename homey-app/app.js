'use strict';

const Homey = require('homey');

module.exports = class TeamsBridgeApp extends Homey.App {
  async onInit() {
    this.log('Teams Bridge app initialized');
  }
};
