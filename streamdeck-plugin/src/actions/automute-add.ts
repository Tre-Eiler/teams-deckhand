import { action, KeyAction } from "@elgato/streamdeck";

import { bridge } from "../bridge-client";
import { SecondsKeyAction, SecondsSettings } from "../seconds-key-action";

/** Pressing adds this key's seconds to the running auto-mute countdown. */
@action({ UUID: "com.teams-bridge.streamdeck.automute-add" })
export class AutoMuteAddTime extends SecondsKeyAction {
	protected readonly imageKind = "addtime";

	protected async press(seconds: number, keyAction: KeyAction<SecondsSettings>): Promise<void> {
		const status = await bridge.addAutoMuteTime(seconds);
		// No countdown running (feature off, muted, or not in a call) means
		// there was nothing to extend — say so rather than silently doing nothing.
		if (status?.autoMuteRemainingSeconds === undefined) {
			await keyAction.showAlert();
		}
	}
}
