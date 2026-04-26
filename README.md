# pi-nvim

Local Neovim client for the Pi Neovim bridge package.

This plugin connects to the Pi-side Unix socket bridge (`/tmp/pi-nvim-sockets`) and lets Neovim send prompts plus editor context to an active Pi session.

## Setup

With lazy.nvim from a local checkout:

```lua
return {
  name = "pi-nvim",
  dir = "/Users/kuala/Documents/Projects/OpenSource/pi-nvim",
  lazy = false,
  config = function()
    require("pi").setup()
  end,
}
```

The Pi-side extension package lives separately in:

```text
/Users/kuala/Documents/Projects/OpenSource/pi-toolkit/pi-nvim
```

## Commands

- `:Pi` — open the Ask Pi dialog.
- `:PiSendAll` — open Ask Pi with `@buffer ` prefilled.
- `:PiSessions` — choose the active Pi session socket.

## Keymaps

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
