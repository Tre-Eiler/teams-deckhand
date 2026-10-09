import { action, SingletonAction, WillAppearEvent, WillDisappearEvent } from "@elgato/streamdeck";

import { bridge } from "../bridge-client";

const REFRESH_INTERVAL_MS = 1000; // clock needs to tick even with no status change

@action({ UUID: "com.teams-bridge.streamdeck.neo-status" })
export class NeoStatus extends SingletonAction {
	private timer: ReturnType<typeof setInterval> | null = null;
	private unsubscribe: (() => void) | null = null;

	override onWillAppear(ev: WillAppearEvent): void {
		bridge.connect();
		if (!ev.action.isNeoInfobar()) return;

		void ev.action.setFeedbackLayout("layouts/neo-status.json");
		void this.refresh();

		if (!this.timer) {
			this.timer = setInterval(() => void this.refresh(), REFRESH_INTERVAL_MS);
		}
		if (!this.unsubscribe) {
			this.unsubscribe = bridge.onStatus(() => void this.refresh());
		}
	}

	override onWillDisappear(_ev: WillDisappearEvent): void {
		if ([...this.actions].length > 0) return; // other Neo panels still visible
		if (this.timer) {
			clearInterval(this.timer);
			this.timer = null;
		}
		if (this.unsubscribe) {
			this.unsubscribe();
			this.unsubscribe = null;
		}
	}

	private async refresh(): Promise<void> {
		const panel = await bridge.fetchNeoPanel();
		if (!panel) return;
		for (const a of this.actions) {
			if (a.isNeoInfobar()) {
				void a.setFeedback({ panel });
			}
		}
	}
}
