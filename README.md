# pi-nvim

Neovim client for the Pi Neovim bridge package.

This plugin connects to the Pi-side Unix socket bridge (`/tmp/pi-nvim-sockets`) and lets Neovim send prompts plus editor context to an active Pi session.

## Setup

With lazy.nvim:

```lua
return {
  "Kualaz/pi-nvim",
  name = "pi-nvim",
  lazy = false,
  config = function()
    local pi = require("pi")
    pi.setup()

    vim.keymap.set("n", "<leader>aa", function()
      pi.ask({ initial_text = "@this " })
    end, { desc = "Ask Pi (@this = current line)" })
    vim.keymap.set("x", "<leader>aa", function()
      pi.ask({ selection = pi.capture_selection(), initial_text = "@this " })
    end, { desc = "Ask Pi (@this = selection)" })
    vim.keymap.set("n", "<leader>ab", function()
      pi.send_all()
    end, { desc = "Ask Pi with buffer" })
    vim.keymap.set("n", "<leader>ap", function()
      pi.list_sessions()
    end, { desc = "Pick Pi session" })
  end,
}
```

The Pi-side extension package lives separately in [`pi-toolkit/pi-nvim`](https://github.com/Kualaz/pi-toolkit/tree/main/pi-nvim).

## Commands

- `:Pi` — toggle the Ask Pi dialog.
- `:PiSendAll` — toggle Ask Pi with `@buffer ` prefilled.
- `:PiSessions` — open the session finder and choose the active Pi session socket.

## Session selection

The plugin never silently binds to an exact-cwd, newest, or default Pi session. When the first prompt is submitted without a selected session, it opens `vim.ui.select`; after selection, that socket is reused for the lifetime of the Neovim instance. Use `:PiSessions` to switch explicitly.

Finder entries are ordered by path-tree hops from Neovim's current working directory. An exact match is 0 hops, a parent is 1 hop, and sibling paths include the steps up to and down from their common ancestor. Newer sessions sort first when distances are equal. Setting `socket_path` in `setup()` counts as an explicit selection and bypasses the finder.

## Keymaps

The plugin does not install global keymaps by default. Configure them in your Neovim plugin spec so your local mappings stay explicit.

The prompt follows normal Vim mode behavior: `<Esc>` leaves insert mode but keeps the prompt open. Press `<CR>` from insert or normal mode to send it. Run `:Pi` again (or repeat the mapping that called `pi.ask()`) to close the prompt without sending.

The setup example above uses:

| Key | Action |
| --- | --- |
| `<leader>aa` | Ask Pi (`@this` = current line/selection) |
| `<leader>ab` | Ask Pi with `@buffer` prefilled |
| `<leader>ap` | Pick active Pi session |

## Context placeholders

Typing `@` in the prompt opens native insert completion for:

- `@this`
- `@buffer`
- `@diagnostics`

Placeholder tokens are removed from the typed prompt before sending. Rendered context is appended under a `Context:` heading.

| Target | Behavior |
| --- | --- |
| `@this` in normal mode | `path/from/cwd.ext:L42` |
| `@this` in visual mode | selected text in a fenced code block, followed by `path/from/cwd.ext:L42-L50` |
| `@this` in file mode | `path/from/cwd.ext` |
| `@buffer` | whole buffer in a fenced code block, followed by `path/from/cwd.ext` |
| `@diagnostics` | current buffer diagnostics as line references |

## Buffer reload events

The plugin keeps a subscription socket open for Pi `file.changed` events. When the Pi extension reports a successful `edit` or `write`, Neovim runs `:checktime` so open buffers can notice disk changes.

## Development

Run the headless regression tests with:

```sh
nvim --headless -u NONE -l tests/ask_spec.lua
nvim --headless -u NONE -l tests/sessions_spec.lua
```
