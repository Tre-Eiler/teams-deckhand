import { action } from "@elgato/streamdeck";

import { bridge, BridgeStatus } from "../bridge-client";
import { BridgeToggleAction } from "../toggle-action-base";

@action({ UUID: "com.teams-bridge.streamdeck.mic" })
export class MicToggle extends BridgeToggleAction {
	protected isOn(status: BridgeStatus): boolean {
		return status.micEnabled;
	}

	protected toggle(): Promise<BridgeStatus | null> {
		return bridge.toggleMic();
	}
}
