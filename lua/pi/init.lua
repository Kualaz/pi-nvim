local config = require("pi.config")
local commands = require("pi.commands")
local context = require("pi.context")
local events = require("pi.events")
local sessions = require("pi.ui.sessions")
local transport = require("pi.transport")

local M = {}

M.config = config.options

M.get_sessions = transport.get_sessions
M.get_socket_path = transport.get_socket_path
M.send_raw = transport.send_raw

M.subscribe_events = events.subscribe_events
M.close_events = events.close

M.capture_selection = context.capture_selection

M.ask = commands.ask
M.send_all = commands.send_all
M.send_prompt = commands.send_prompt
M.list_sessions = sessions.list_sessions
M.setup = commands.setup

package.loaded["pi_nvim"] = M
package.loaded["pi-nvim"] = M

return M
