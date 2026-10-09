'use strict';

const Homey = require('homey');

module.exports = class DeckhandApp extends Homey.App {
  async onInit() {
    this.log('Deckhand app initialized');
  }
};
