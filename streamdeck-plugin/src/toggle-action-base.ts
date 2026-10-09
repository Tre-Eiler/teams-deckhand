import { KeyDownEvent, SingletonAction, WillAppearEvent, WillDisappearEvent } from "@elgato/streamdeck";

import { bridge, BridgeStatus } from "./bridge-client";

/**
 * Shared behavior for a two-state Stream Deck key backed by the
 * teams-bridge-daemon: state 1 while the tracked thing is "on", state 0
 * otherwise. Subclasses just say which status field they track and what to
 * do on press.
 */
export abstract class BridgeToggleAction extends SingletonAction {
	private unsubscribe: (() => void) | null = null;

	protected abstract isOn(status: BridgeStatus): boolean;
	protected abstract toggle(): Promise<BridgeStatus | null>;

	override onWillAppear(_ev: WillAppearEvent): Promise<void> | void {
		bridge.connect();
		if (!this.unsubscribe) {
			this.unsubscribe = bridge.onStatus((status) => this.render(status));
		}
	}

	override onWillDisappear(_ev: WillDisappearEvent): Promise<void> | void {
		// Only tear down once nothing of this action type is visible anywhere.
		if (this.unsubscribe && [...this.actions].length <= 1) {
			this.unsubscribe();
			this.unsubscribe = null;
		}
	}

	override async onKeyDown(_ev: KeyDownEvent): Promise<void> {
		await this.toggle();
	}

	private render(status: BridgeStatus): void {
		const state = this.isOn(status) ? 1 : 0;
		for (const action of this.actions) {
			if (action.isKey()) {
				void action.setState(state);
			}
		}
	}
}
