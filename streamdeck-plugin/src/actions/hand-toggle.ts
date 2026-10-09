import { action } from "@elgato/streamdeck";

import { bridge, BridgeStatus } from "../bridge-client";
import { BridgeToggleAction } from "../toggle-action-base";

@action({ UUID: "com.teams-bridge.streamdeck.hand" })
export class HandToggle extends BridgeToggleAction {
	protected isOn(status: BridgeStatus): boolean {
		return status.handRaised;
	}

	protected toggle(): Promise<BridgeStatus | null> {
		return bridge.toggleHand();
	}
}
