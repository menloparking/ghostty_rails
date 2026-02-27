import { Controller } from "@hotwired/stimulus";
export default class TerminalFullscreenController extends Controller {
    static targets: string[];
    wrapperTarget: HTMLElement;
    btnTarget: HTMLElement;
    hasMaximizeIconTarget: boolean;
    maximizeIconTarget: HTMLElement;
    hasMinimizeIconTarget: boolean;
    minimizeIconTarget: HTMLElement;
    hasMetaTarget: boolean;
    metaTarget: HTMLElement;
    hasTerminalWrapTarget: boolean;
    terminalWrapTarget: HTMLElement;
    private isFullscreen;
    private savedClasses;
    private savedStyles;
    private savedMetaClasses;
    private savedTerminalStyles;
    private savedTerminalClasses;
    private savedBodyOverflow;
    connect(): void;
    toggle(): void;
    handleKeydown(event: KeyboardEvent): void;
    disconnect(): void;
    private enterFullscreen;
    private exitFullscreen;
    private setButtonLabel;
}
