import WebSocket from "ws";

export type BridgeStatus = {
	inCall: boolean;
	micEnabled: boolean;
	cameraEnabled: boolean;
	handRaised: boolean;
	autoMuteEnabled: boolean;
	/** The active auto-mute timeout, in seconds of silence. */
	autoMuteTimeoutSeconds: number;
	/** Seconds until auto-mute fires; absent when no countdown is running. */
	autoMuteRemainingSeconds?: number;
	/** True while the countdown is parked because the daemon can't hear the mic. */
	autoMuteHolding?: boolean;
};

// The daemon's loopback-only server (main port + 1). Controls and key images
// live only here; the network-facing port is a read-only status feed for
// Homey / Home Assistant. 127.0.0.1 rather than "localhost": the server is
// IPv4-only.
const BASE_URL = "http://127.0.0.1:8943";
const WS_URL = "ws://127.0.0.1:8943/ws";

type Listener = (status: BridgeStatus) => void;

/**
 * Shared connection to the teams-bridge-daemon (one WebSocket for the whole
 * plugin process, regardless of how many action instances are visible).
 * Reconnects with backoff if the daemon isn't running yet or restarts.
 */
class BridgeClient {
	private ws: WebSocket | null = null;
	private listeners = new Set<Listener>();
	private lastStatus: BridgeStatus | null = null;
	private reconnectDelayMs = 1000;
	private connecting = false;

	connect(): void {
		if (this.ws || this.connecting) return;
		this.connecting = true;

		const ws = new WebSocket(WS_URL);
		this.ws = ws;

		ws.on("open", () => {
			this.connecting = false;
			this.reconnectDelayMs = 1000;
		});
		ws.on("message", (data) => {
			try {
				const status = JSON.parse(data.toString()) as BridgeStatus;
				this.publish(status);
			} catch {
				// ignore malformed frames
			}
		});
		const scheduleReconnect = () => {
			const knownTimeout = this.lastStatus?.autoMuteTimeoutSeconds ?? 30;
			this.ws = null;
			this.connecting = false;
			this.lastStatus = null;
			this.publish({
				inCall: false,
				micEnabled: false,
				cameraEnabled: false,
				handRaised: false,
				autoMuteEnabled: false,
				autoMuteTimeoutSeconds: knownTimeout,
			});
			setTimeout(() => this.connect(), this.reconnectDelayMs);
			this.reconnectDelayMs = Math.min(this.reconnectDelayMs * 2, 30_000);
		};
		ws.on("close", scheduleReconnect);
		ws.on("error", scheduleReconnect);
	}

	/** Subscribes to status updates; immediately replays the last known status if any. */
	onStatus(listener: Listener): () => void {
		this.listeners.add(listener);
		if (this.lastStatus) listener(this.lastStatus);
		return () => {
			this.listeners.delete(listener);
		};
	}

	getLastStatus(): BridgeStatus | null {
		return this.lastStatus;
	}

	async toggleMic(): Promise<BridgeStatus | null> {
		return this.post("/mic/toggle");
	}

	async toggleCamera(): Promise<BridgeStatus | null> {
		return this.post("/camera/toggle");
	}

	/** Leaves the current Teams call (never ends it for everyone). */
	async leaveCall(): Promise<BridgeStatus | null> {
		return this.post("/call/leave");
	}

	async toggleHand(): Promise<BridgeStatus | null> {
		return this.post("/hand/toggle");
	}

	async toggleAutoMute(): Promise<BridgeStatus | null> {
		return this.post("/automute/toggle");
	}

	/** Selects the active auto-mute timeout (and restarts the countdown). */
	async setAutoMuteTimeout(seconds: number): Promise<BridgeStatus | null> {
		return this.post(`/automute/timeout?seconds=${seconds}`);
	}

	/** Adds time to the running countdown; the status comes back without a countdown if none was running. */
	async addAutoMuteTime(seconds: number): Promise<BridgeStatus | null> {
		return this.post(`/automute/add?seconds=${seconds}`);
	}

	/** Fetches the current rendered Neo panel image as a data: URI; `query` carries the panel's settings. */
	async fetchNeoPanel(query = ""): Promise<string | null> {
		return this.fetchImage(query ? `/neo-panel.png?${query}` : "/neo-panel.png");
	}

	/** Fetches a daemon-rendered key image (path includes any query string) as a data: URI. */
	async fetchKeyImage(path: string): Promise<string | null> {
		return this.fetchImage(path);
	}

	private async fetchImage(path: string): Promise<string | null> {
		try {
			const res = await fetch(`${BASE_URL}${path}`);
			if (!res.ok) return null;
			const buf = Buffer.from(await res.arrayBuffer());
			return `data:image/png;base64,${buf.toString("base64")}`;
		} catch {
			return null;
		}
	}

	private publish(status: BridgeStatus): void {
		this.lastStatus = status;
		for (const listener of this.listeners) listener(status);
	}

	private async post(path: string): Promise<BridgeStatus | null> {
		try {
			const res = await fetch(`${BASE_URL}${path}`, { method: "POST" });
			if (!res.ok) return null;
			const status = (await res.json()) as BridgeStatus;
			this.publish(status);
			return status;
		} catch {
			return null;
		}
	}
}

export const bridge = new BridgeClient();
