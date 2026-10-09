import { action, KeyDownEvent, KeyUpEvent, WillDisappearEvent } from "@elgato/streamdeck";

import { bridge, BridgeStatus } from "../bridge-client";
import { BridgeToggleAction } from "../toggle-action-base";

const DEFAULT_HOLD_SECONDS = 1;
const MAX_HOLD_SECONDS = 5;

function parseHoldSeconds(raw: unknown): number {
	const n = typeof raw === "number" ? raw : Number.parseFloat(String(raw ?? ""));
	return Number.isFinite(n) && n >= 0 ? Math.min(n, MAX_HOLD_SECONDS) : DEFAULT_HOLD_SECONDS;
}

/**
 * Leaves the Teams call. Ending a call by accident is far worse than muting by
 * accident, so by default the key must be held for a second; a quick tap shows
 * an alert instead. Set the hold to 0 in the key's settings for an instant
 * hang-up. Lit red while in a call, grey otherwise.
 */
@action({ UUID: "com.teams-bridge.streamdeck.hangup" })
export class HangUp extends BridgeToggleAction {
	private holdTimers = new Map<string, ReturnType<typeof setTimeout>>();

	protected isOn(status: BridgeStatus): boolean {
		return status.inCall;
	}

	protected toggle(): Promise<BridgeStatus | null> {
		return bridge.leaveCall();
	}

	override async onKeyDown(ev: KeyDownEvent): Promise<void> {
		if (!bridge.getLastStatus()?.inCall) {
			await ev.action.showAlert(); // nothing to hang up
			return;
		}

		const holdSeconds = parseHoldSeconds((ev.payload.settings as { holdSeconds?: unknown }).holdSeconds);
		if (holdSeconds === 0) {
			await this.leave(ev.action);
			return;
		}
		this.holdTimers.set(
			ev.action.id,
			setTimeout(() => {
				this.holdTimers.delete(ev.action.id);
				void this.leave(ev.action);
			}, holdSeconds * 1000),
		);
	}

	override async onKeyUp(ev: KeyUpEvent): Promise<void> {
		const timer = this.holdTimers.get(ev.action.id);
		if (!timer) return; // already left, or never started
		clearTimeout(timer);
		this.holdTimers.delete(ev.action.id);
		await ev.action.showAlert(); // let go too soon
	}

	override onWillDisappear(ev: WillDisappearEvent): Promise<void> | void {
		const timer = this.holdTimers.get(ev.action.id);
		if (timer) {
			clearTimeout(timer);
			this.holdTimers.delete(ev.action.id);
		}
		return super.onWillDisappear(ev);
	}

	private async leave(key: KeyDownEvent["action"]): Promise<void> {
		const status = await this.toggle();
		if (status && !status.inCall) {
			await key.showOk();
		} else {
			await key.showAlert(); // daemon unreachable, or Teams didn't leave
		}
	}
}
