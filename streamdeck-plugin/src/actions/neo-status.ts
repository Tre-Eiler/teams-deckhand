import {
	action,
	DidReceiveSettingsEvent,
	SingletonAction,
	WillAppearEvent,
	WillDisappearEvent,
} from "@elgato/streamdeck";

import { bridge } from "../bridge-client";

const REFRESH_INTERVAL_MS = 1000; // clock needs to tick even with no status change

/** What the Property Inspector stores. Anything never touched is undefined and means "the default". */
export type NeoSettings = {
	showMic?: boolean;
	showCamera?: boolean;
	use24Hour?: boolean;
	showCountdown?: boolean;
	/** Seconds before muting that the countdown takes over the panel (select values are strings). */
	countdownWindow?: number | string;
	countdownStyle?: "fill" | "tint";
};

const DEFAULT_WINDOW_SECONDS = 10;

/** The daemon draws the panel from these, so they are the whole request. */
export function panelQuery(settings: NeoSettings): string {
	const window = Number.parseInt(String(settings.countdownWindow ?? ""), 10);
	return new URLSearchParams({
		mic: settings.showMic === false ? "0" : "1",
		camera: settings.showCamera === false ? "0" : "1",
		h24: settings.use24Hour === true ? "1" : "0",
		countdown: settings.showCountdown === false ? "0" : "1",
		window: String(Number.isFinite(window) && window > 0 ? window : DEFAULT_WINDOW_SECONDS),
		style: settings.countdownStyle === "tint" ? "tint" : "fill",
	}).toString();
}

@action({ UUID: "com.teams-bridge.streamdeck.neo-status" })
export class NeoStatus extends SingletonAction<NeoSettings> {
	private timer: ReturnType<typeof setInterval> | null = null;
	private unsubscribe: (() => void) | null = null;
	private settingsById = new Map<string, NeoSettings>();

	override onWillAppear(ev: WillAppearEvent<NeoSettings>): void {
		bridge.connect();
		if (!ev.action.isNeoInfobar()) return;

		this.settingsById.set(ev.action.id, ev.payload.settings);
		void ev.action.setFeedbackLayout("layouts/neo-status.json");
		void this.refresh();

		if (!this.timer) {
			this.timer = setInterval(() => void this.refresh(), REFRESH_INTERVAL_MS);
		}
		if (!this.unsubscribe) {
			this.unsubscribe = bridge.onStatus(() => void this.refresh());
		}
	}

	override onDidReceiveSettings(ev: DidReceiveSettingsEvent<NeoSettings>): void {
		this.settingsById.set(ev.action.id, ev.payload.settings);
		void this.refresh();
	}

	override onWillDisappear(ev: WillDisappearEvent<NeoSettings>): void {
		this.settingsById.delete(ev.action.id);
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
		for (const a of this.actions) {
			if (!a.isNeoInfobar()) continue;
			const panel = await bridge.fetchNeoPanel(panelQuery(this.settingsById.get(a.id) ?? {}));
			if (panel) void a.setFeedback({ panel });
		}
	}
}
