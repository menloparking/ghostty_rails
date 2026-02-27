class TerminalsController <
    ActionController::Base
  def show
    render inline: <<~HTML, layout: 'application'
      <div id="terminal-page"
           data-controller="terminal terminal-fullscreen"
           data-terminal-fullscreen-target="wrapper"
           data-terminal-mode-value="local"
           data-terminal-auto-connect-value="true"
           data-action="terminal-fullscreen:changed->terminal#refitTerminal keydown->terminal-fullscreen#handleKeydown"
           style="position: relative;
                  height: 290px;
                  max-width: 64rem;
                  margin: 0 auto;
                  border-radius: 0.5rem;
                  overflow: hidden;">

        <button data-terminal-fullscreen-target="btn"
                data-action="terminal-fullscreen#toggle"
                aria-label="Enter fullscreen"
                style="position: absolute;
                       top: 8px;
                       right: 8px;
                       z-index: 10;
                       padding: 4px 8px;
                       border: none;
                       border-radius: 4px;
                       background: rgba(255,255,255,0.1);
                       color: #7aa2f7;
                       font-family: monospace;
                       font-size: 12px;
                       cursor: pointer;
                       opacity: 0.7;
                       transition: opacity 0.15s;">
          FS
        </button>

        <div data-terminal-target="page"
             data-terminal-target="content"
             data-terminal-fullscreen-target="meta"
             style="height: 100%;">
          <div id="terminal-container"
               data-terminal-target="container"
               data-terminal-fullscreen-target="terminalWrap"
               style="height: 100%;
                      width: 100%;"></div>
        </div>
      </div>
    HTML
  end
end
