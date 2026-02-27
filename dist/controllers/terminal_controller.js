import { Controller } from "@hotwired/stimulus";
import { init, Terminal, FitAddon } from "ghostty-web";
// @ts-ignore -- no type declarations for actioncable
import { createConsumer } from "@rails/actioncable";
import { DEFAULT_THEME, THEMES } from "../themes";
// Default ActionCable channel name. Apps can
// override via the data-terminal-channel-name-value
// attribute if they mount the channel under a
// different class name.
const DEFAULT_CHANNEL = "TerminalChannel";
class TerminalController extends Controller {
    constructor() {
        super(...arguments);
        this.channel = null;
        this.term = null;
        this.fitAddon = null;
        this.consumer = null;
        this.ghosttyReady = false;
    }
    async connect() {
        this.consumer = createConsumer();
        await init();
        this.ghosttyReady = true;
        if (this.autoConnectValue) {
            this.connectTerminal();
        }
    }
    disconnect() {
        this.teardownSession();
        this.consumer?.disconnect();
        this.consumer = null;
    }
    // -- Actions ------------------------------------
    // Called when the fullscreen controller toggles.
    // Refit the terminal after a brief delay so the
    // layout has settled into its new dimensions.
    refitTerminal() {
        setTimeout(() => {
            this.fitAddon?.fit();
        }, 50);
    }
    changeAuthMethod() {
        if (!this.hasPasswordGroupTarget)
            return;
        if (this.authMethodTarget.value === "password") {
            this.passwordGroupTarget
                .classList.remove("hidden");
        }
        else {
            this.passwordGroupTarget
                .classList.add("hidden");
            if (this.hasPasswordTarget) {
                this.passwordTarget.value = "";
            }
        }
    }
    submitOnEnter(event) {
        if (event.key === "Enter") {
            event.preventDefault();
            this.connectTerminal();
        }
    }
    async connectTerminal() {
        if (!this.ghosttyReady)
            return;
        const channelName = this.channelNameValue;
        let subscriptionParams;
        if (this.modeValue === "ssh") {
            const params = this.readSshParams();
            if (!params)
                return;
            subscriptionParams = {
                channel: channelName,
                mode: "ssh",
                host_id: params.host_id,
                ssh_host: params.host,
                ssh_port: params.port,
                ssh_user: params.user,
                ssh_auth_method: params.auth_method
            };
        }
        else {
            subscriptionParams = {
                channel: channelName,
                mode: "local"
            };
        }
        this.setStatus("Connecting...");
        if (this.hasConnectBtnTarget) {
            this.connectBtnTarget.disabled = true;
        }
        const themeName = this.getSelectedThemeName();
        const theme = this.getTheme(themeName);
        this.term = new Terminal({
            fontSize: 14,
            fontFamily: "'JetBrains Mono', 'Fira Code', " +
                "'Cascadia Code', monospace",
            cursorBlink: true,
            cursorStyle: "bar",
            scrollback: 10000,
            theme
        });
        this.term.open(this.containerTarget);
        this.fitAddon = new FitAddon();
        this.term.loadAddon(this.fitAddon);
        this.fitAddon.fit();
        this.fitAddon.observeResize();
        this.setPageBackground(theme.background);
        const currentTerm = this.term;
        const currentFit = this.fitAddon;
        this.channel =
            this.consumer.subscriptions.create(subscriptionParams, {
                connected: () => {
                    this.showTerminal();
                    this.setStatus("");
                    if (this.hasConnectBtnTarget) {
                        this.connectBtnTarget.disabled =
                            false;
                    }
                    currentTerm.focus();
                    const dims = currentFit.proposeDimensions();
                    if (dims) {
                        this.channel.send({
                            type: "resize",
                            cols: dims.cols,
                            rows: dims.rows
                        });
                    }
                },
                disconnected: () => {
                    currentTerm.write("\r\n\x1b[31m[Disconnected]" +
                        "\x1b[0m\r\n");
                    if (this.hasConnectBtnTarget) {
                        this.connectBtnTarget.disabled =
                            false;
                    }
                    if (this.hasConnectionFormTarget) {
                        this.showForm();
                    }
                },
                rejected: () => {
                    this.setStatus("Connection rejected by server", true);
                    if (this.hasConnectBtnTarget) {
                        this.connectBtnTarget.disabled =
                            false;
                    }
                    currentTerm.write("\r\n\x1b[31m[Connection " +
                        "rejected]\x1b[0m\r\n");
                    this.showTerminal();
                },
                received: (data) => {
                    if (data.type === "output" &&
                        data.data) {
                        currentTerm.write(data.data);
                    }
                    else if (data.type === "exit") {
                        currentTerm.write("\r\n\x1b[33m[Session ended]" +
                            "\x1b[0m\r\n");
                    }
                }
            });
        currentTerm.onData((data) => {
            this.channel?.send({
                type: "input", data
            });
        });
        currentTerm.onResize(({ cols, rows }) => {
            this.channel?.send({
                type: "resize", cols, rows
            });
        });
    }
    disconnectTerminal() {
        this.teardownSession();
        if (this.hasConnectionFormTarget) {
            this.showForm();
        }
        this.setStatus("");
        if (this.hasConnectBtnTarget) {
            this.connectBtnTarget.disabled = false;
        }
    }
    // -- Private helpers ----------------------------
    getSelectedThemeName() {
        return this.savedThemeValue || DEFAULT_THEME;
    }
    getTheme(name) {
        return THEMES[name] || THEMES[DEFAULT_THEME];
    }
    readSshParams() {
        // When form targets exist, read from the form
        if (this.hasHostTarget) {
            const host = this.hostTarget.value?.trim();
            if (!host) {
                this.setStatus("Host is required", true);
                this.hostTarget.focus();
                return null;
            }
            return {
                host,
                host_id: "",
                port: this.hasPortTarget
                    ? parseInt(this.portTarget.value || "22", 10)
                    : 22,
                user: this.hasUserTarget
                    ? (this.userTarget.value?.trim() ||
                        "root")
                    : "root",
                auth_method: this.hasAuthMethodTarget
                    ? this.authMethodTarget.value
                    : "key"
            };
        }
        // Auto-connect mode: read from Stimulus
        // values
        const host = this.sshHostValue?.trim();
        if (!host) {
            this.setStatus("Host is required", true);
            return null;
        }
        return {
            host,
            host_id: this.hostIdValue || "",
            port: parseInt(this.sshPortValue || "22", 10),
            user: this.sshUserValue || "root",
            auth_method: this.sshAuthMethodValue || "key"
        };
    }
    setPageBackground(color) {
        if (color) {
            if (this.hasPageTarget) {
                this.pageTarget.style.backgroundColor =
                    color;
            }
            if (this.hasContentTarget) {
                this.contentTarget
                    .classList.remove("bg-background");
                this.contentTarget.style.backgroundColor =
                    color;
            }
        }
        else {
            if (this.hasPageTarget) {
                this.pageTarget.style.backgroundColor = "";
            }
            if (this.hasContentTarget) {
                this.contentTarget
                    .classList.add("bg-background");
                this.contentTarget.style.backgroundColor =
                    "";
            }
        }
    }
    setStatus(msg, isError = false) {
        if (!this.hasStatusTarget)
            return;
        this.statusTarget.textContent = msg;
        this.statusTarget.className = isError
            ? "text-sm text-danger"
            : "text-sm text-text-muted";
    }
    showForm() {
        if (this.hasContainerTarget) {
            this.containerTarget.classList.add("hidden");
        }
        if (this.hasConnectionFormTarget) {
            this.connectionFormTarget
                .classList.remove("hidden");
        }
        if (this.hasSubtitleActionsTarget) {
            this.subtitleActionsTarget
                .classList.add("hidden");
        }
    }
    showTerminal() {
        if (this.hasContainerTarget) {
            this.containerTarget
                .classList.remove("hidden");
        }
        if (this.hasConnectionFormTarget) {
            this.connectionFormTarget
                .classList.add("hidden");
        }
        if (this.hasSubtitleActionsTarget) {
            this.subtitleActionsTarget
                .classList.remove("hidden");
        }
    }
    teardownSession() {
        this.channel?.unsubscribe();
        this.channel = null;
        this.term?.dispose();
        this.term = null;
        this.fitAddon = null;
        this.setPageBackground(null);
    }
}
TerminalController.targets = [
    "authMethod",
    "connectBtn",
    "connectionForm",
    "container",
    "content",
    "disconnectBtn",
    "host",
    "page",
    "password",
    "passwordGroup",
    "port",
    "status",
    "subtitleActions",
    "user"
];
TerminalController.values = {
    autoConnect: {
        type: Boolean, default: false
    },
    channelName: {
        type: String, default: DEFAULT_CHANNEL
    },
    hostId: { type: String, default: "" },
    mode: { type: String, default: "local" },
    savedTheme: {
        type: String, default: DEFAULT_THEME
    },
    sshAuthMethod: {
        type: String, default: "key"
    },
    sshHost: { type: String, default: "" },
    sshPort: { type: String, default: "22" },
    sshUser: { type: String, default: "root" }
};
export default TerminalController;
