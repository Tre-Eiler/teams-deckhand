import { action } from "@elgato/streamdeck";

import { bridge, BridgeStatus } from "../bridge-client";
import { BridgeToggleAction } from "../toggle-action-base";

@action({ UUID: "com.teams-bridge.streamdeck.camera" })
export class CameraToggle extends BridgeToggleAction {
	protected isOn(status: BridgeStatus): boolean {
		return status.cameraEnabled;
	}

	protected toggle(): Promise<BridgeStatus | null> {
		return bridge.toggleCamera();
	}
}
