import { action } from "@elgato/streamdeck";

import { bridge, BridgeStatus } from "../bridge-client";
import { BridgeToggleAction } from "../toggle-action-base";

@action({ UUID: "com.teams-bridge.streamdeck.automute" })
export class AutoMuteToggle extends BridgeToggleAction {
	protected isOn(status: BridgeStatus): boolean {
		return status.autoMuteEnabled;
	}

	protected toggle(): Promise<BridgeStatus | null> {
		return bridge.toggleAutoMute();
	}
}
