import { action } from "@elgato/streamdeck";

import { bridge } from "../bridge-client";
import { SecondsKeyAction } from "../seconds-key-action";

/** Pressing selects this key's seconds as the active auto-mute timeout. */
@action({ UUID: "com.teams-bridge.streamdeck.automute-timeout" })
export class AutoMuteTimeout extends SecondsKeyAction {
	protected readonly imageKind = "timeout";

	protected async press(seconds: number): Promise<void> {
		await bridge.setAutoMuteTimeout(seconds);
	}
}
