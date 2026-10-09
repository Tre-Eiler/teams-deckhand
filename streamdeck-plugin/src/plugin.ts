import streamDeck from "@elgato/streamdeck";

import { AutoMuteAddTime } from "./actions/automute-add";
import { AutoMuteTimeout } from "./actions/automute-timeout";
import { AutoMuteToggle } from "./actions/automute-toggle";
import { CameraToggle } from "./actions/camera-toggle";
import { HandToggle } from "./actions/hand-toggle";
import { HangUp } from "./actions/hangup";
import { MicToggle } from "./actions/mic-toggle";
import { NeoStatus } from "./actions/neo-status";

streamDeck.logger.setLevel("info");

streamDeck.actions.registerAction(new MicToggle());
streamDeck.actions.registerAction(new CameraToggle());
streamDeck.actions.registerAction(new HandToggle());
streamDeck.actions.registerAction(new NeoStatus());
streamDeck.actions.registerAction(new HangUp());
streamDeck.actions.registerAction(new AutoMuteToggle());
streamDeck.actions.registerAction(new AutoMuteTimeout());
streamDeck.actions.registerAction(new AutoMuteAddTime());

streamDeck.connect();
