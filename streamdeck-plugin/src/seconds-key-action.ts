import {
	DidReceiveSettingsEvent,
	KeyAction,
	KeyDownEvent,
	SingletonAction,
	WillAppearEvent,
	WillDisappearEvent,
} from "@elgato/streamdeck";

import { bridge, BridgeStatus } from "./bridge-client";

/** Per-key setting edited in the Property Inspector (stored as text there). */
export type SecondsSettings = {
	seconds?: number | string;
};

const DEFAULT_SECONDS = 30;
const MAX_SECONDS = 3600;

export function parseSeconds(raw: unknown): number {
	const n = typeof raw === "number" ? Math.trunc(raw) : Number.parseInt(String(raw ?? ""), 10);
	return Number.isFinite(n) && n > 0 ? Math.min(n, MAX_SECONDS) : DEFAULT_SECONDS;
}

/**
 * A key configured with a number of seconds whose face is drawn live by the
 * daemon (a countdown ring, a "+30"). Each placed key can have its own
 * seconds value, so everything is tracked per action instance.
 */
export abstract class SecondsKeyAction extends SingletonAction<SecondsSettings> {
	/** Which daemon renderer draws this key: /key/<kind>.png */
	protected abstract readonly imageKind: "timeout" | "addtime";

	protected abstract press(seconds: number, action: KeyAction<SecondsSettings>): Promise<void>;

	private secondsById = new Map<string, number>();
	private drawnUrlById = new Map<string, string>();
	private unsubscribe: (() => void) | null = null;

	override onWillAppear(ev: WillAppearEvent<SecondsSettings>): void {
		this.secondsById.set(ev.action.id, parseSeconds(ev.payload.settings.seconds));
		bridge.connect();
		if (!this.unsubscribe) {
			this.unsubscribe = bridge.onStatus((status) => void this.render(status));
		}
		const status = bridge.getLastStatus();
		if (status) void this.render(status);
	}

	override onWillDisappear(ev: WillDisappearEvent<SecondsSettings>): void {
		this.secondsById.delete(ev.action.id);
		this.drawnUrlById.delete(ev.action.id);
		if (this.secondsById.size === 0 && this.unsubscribe) {
			this.unsubscribe();
			this.unsubscribe = null;
		}
	}

	override onDidReceiveSettings(ev: DidReceiveSettingsEvent<SecondsSettings>): void {
		this.secondsById.set(ev.action.id, parseSeconds(ev.payload.settings.seconds));
		this.drawnUrlById.delete(ev.action.id);
		const status = bridge.getLastStatus();
		if (status) void this.render(status);
	}

	override async onKeyDown(ev: KeyDownEvent<SecondsSettings>): Promise<void> {
		await this.press(parseSeconds(ev.payload.settings.seconds), ev.action);
	}

	private imageUrl(seconds: number, status: BridgeStatus): string {
		const params = new URLSearchParams({
			seconds: String(seconds),
			timeout: String(status.autoMuteTimeoutSeconds),
			enabled: status.autoMuteEnabled ? "1" : "0",
		});
		if (status.autoMuteRemainingSeconds !== undefined) {
			params.set("remaining", String(status.autoMuteRemainingSeconds));
		}
		if (status.autoMuteHolding) params.set("holding", "1");
		return `/key/${this.imageKind}.png?${params}`;
	}

	private async render(status: BridgeStatus): Promise<void> {
		for (const action of this.actions) {
			if (!action.isKey()) continue;
			const seconds = this.secondsById.get(action.id) ?? DEFAULT_SECONDS;
			const url = this.imageUrl(seconds, status);
			// The image is a pure function of its URL, so an unchanged URL
			// needs no fetch and no redraw.
			if (this.drawnUrlById.get(action.id) === url) continue;
			this.drawnUrlById.set(action.id, url);

			const image = await bridge.fetchKeyImage(url);
			if (image) {
				await action.setImage(image);
			} else {
				this.drawnUrlById.delete(action.id); // daemon unreachable: retry on the next status
			}
		}
	}
}
