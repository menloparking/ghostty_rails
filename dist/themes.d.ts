export interface TerminalTheme {
    background: string;
    foreground: string;
    cursor: string;
    cursorAccent?: string;
    selectionBackground?: string;
    selectionForeground?: string;
    black: string;
    red: string;
    green: string;
    yellow: string;
    blue: string;
    magenta: string;
    cyan: string;
    white: string;
    brightBlack: string;
    brightRed: string;
    brightGreen: string;
    brightYellow: string;
    brightBlue: string;
    brightMagenta: string;
    brightCyan: string;
    brightWhite: string;
}
export declare const DEFAULT_THEME = "Tokyo Night";
export declare const THEMES: Record<string, TerminalTheme>;
