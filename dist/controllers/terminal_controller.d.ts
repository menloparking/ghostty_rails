import { Controller } from "@hotwired/stimulus";
export default class TerminalController extends Controller {
    static targets: string[];
    static values: {
        autoConnect: {
            type: BooleanConstructor;
            default: boolean;
        };
        channelName: {
            type: StringConstructor;
            default: string;
        };
        hostId: {
            type: StringConstructor;
            default: string;
        };
        mode: {
            type: StringConstructor;
            default: string;
        };
        savedTheme: {
            type: StringConstructor;
            default: string;
        };
        sshAuthMethod: {
            type: StringConstructor;
            default: string;
        };
        sshHost: {
            type: StringConstructor;
            default: string;
        };
        sshPort: {
            type: StringConstructor;
            default: string;
        };
        sshUser: {
            type: StringConstructor;
            default: string;
        };
    };
    authMethodTarget: HTMLSelectElement;
    connectBtnTarget: HTMLButtonElement;
    connectionFormTarget: HTMLElement;
    containerTarget: HTMLElement;
    contentTarget: HTMLElement;
    disconnectBtnTarget: HTMLButtonElement;
    hostTarget: HTMLInputElement;
    pageTarget: HTMLElement;
    passwordTarget: HTMLInputElement;
    passwordGroupTarget: HTMLElement;
    portTarget: HTMLInputElement;
    statusTarget: HTMLElement;
    subtitleActionsTarget: HTMLElement;
    userTarget: HTMLInputElement;
    hasAuthMethodTarget: boolean;
    hasConnectBtnTarget: boolean;
    hasConnectionFormTarget: boolean;
    hasContainerTarget: boolean;
    hasContentTarget: boolean;
    hasDisconnectBtnTarget: boolean;
    hasHostTarget: boolean;
    hasPageTarget: boolean;
    hasPasswordTarget: boolean;
    hasPasswordGroupTarget: boolean;
    hasPortTarget: boolean;
    hasStatusTarget: boolean;
    hasSubtitleActionsTarget: boolean;
    hasUserTarget: boolean;
    autoConnectValue: boolean;
    channelNameValue: string;
    hostIdValue: string;
    modeValue: string;
    savedThemeValue: string;
    sshAuthMethodValue: string;
    sshHostValue: string;
    sshPortValue: string;
    sshUserValue: string;
    private channel;
    private term;
    private fitAddon;
    private consumer;
    private ghosttyReady;
    connect(): Promise<void>;
    disconnect(): void;
    refitTerminal(): void;
    changeAuthMethod(): void;
    submitOnEnter(event: KeyboardEvent): void;
    connectTerminal(): Promise<void>;
    disconnectTerminal(): void;
    private getSelectedThemeName;
    private getTheme;
    private readSshParams;
    private setPageBackground;
    private setStatus;
    private showForm;
    private showTerminal;
    private teardownSession;
}
