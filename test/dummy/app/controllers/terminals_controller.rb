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
           class="max-w-5xl mx-auto p-4"
           style="height: 600px;">

        <div class="flex items-center justify-between mb-4"
             data-terminal-fullscreen-target="meta"
             data-terminal-target="content">
          <h1 class="text-xl font-bold">Terminal</h1>
          <div class="flex items-center gap-2">
            <span data-terminal-target="status"></span>
            <button data-terminal-fullscreen-target="btn"
                    data-action="terminal-fullscreen#toggle"
                    aria-label="Enter fullscreen"
                    class="p-1 rounded hover:bg-gray-200">
              FS
            </button>
          </div>
        </div>

        <div data-terminal-target="page"
             data-terminal-target="content"
             style="height: calc(100% - 48px);">
          <div id="terminal-container"
               data-terminal-target="container"
               data-terminal-fullscreen-target="terminalWrap"
               style="height: 100%; width: 100%;"></div>
        </div>
      </div>
    HTML
  end
end
