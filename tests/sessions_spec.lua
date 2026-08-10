local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(script_path))
vim.opt.runtimepath:prepend(root)

local uv = vim.uv or vim.loop
local commands = require("pi.commands")
local config = require("pi.config")
local events = require("pi.events")
local sessions_ui = require("pi.ui.sessions")
local transport = require("pi.transport")

local function assert_equal(actual, expected, message)
	assert(actual == expected, string.format("%s: expected %s, got %s", message, vim.inspect(expected), vim.inspect(actual)))
end

local temp_root = vim.fn.tempname()
local sockets_dir = temp_root .. "/sockets"
vim.fn.mkdir(sockets_dir, "p")
config.setup({ sockets_dir = sockets_dir, socket_path = nil, events = false })

local function create_session(name, cwd, mtime)
	local socket = sockets_dir .. "/" .. name .. ".sock"
	vim.fn.writefile({ "" }, socket, "b")
	vim.fn.writefile({
		vim.json.encode({
			cwd = cwd,
			pid = mtime,
			startedAt = "2026-01-01T00:00:00.000Z",
		}),
	}, socket .. ".info")
	assert(uv.fs_utime(socket, mtime, mtime), "socket mtime should be set")
	return socket
end

local nvim_cwd = temp_root .. "/projects/repo/app"
local parent_cwd = temp_root .. "/projects/repo"
local sibling_old_cwd = temp_root .. "/projects/repo/lib"
local sibling_new_cwd = temp_root .. "/projects/repo/test"
local other_cwd = temp_root .. "/projects/other"
for _, cwd in ipairs({ nvim_cwd, sibling_old_cwd, sibling_new_cwd, other_cwd }) do
	vim.fn.mkdir(cwd, "p")
end
local exact = create_session("exact", nvim_cwd, 100)
local parent = create_session("parent", parent_cwd, 500)
local sibling_old = create_session("sibling-old", sibling_old_cwd, 100)
local sibling_new = create_session("sibling-new", sibling_new_cwd, 200)
local other = create_session("other", other_cwd, 900)

assert_equal(transport.directory_distance(nvim_cwd, nvim_cwd), 0, "exact directory distance")
assert_equal(transport.directory_distance(nvim_cwd, parent_cwd), 1, "parent distance")
assert_equal(transport.directory_distance(nvim_cwd, sibling_old_cwd), 2, "sibling distance")

local sessions = transport.get_sessions({ cwd = nvim_cwd })
assert_equal(#sessions, 5, "discovered session count")
assert_equal(sessions[1].socket, exact, "exact directory sorts first")
assert_equal(sessions[1].distance, 0, "exact session distance")
assert_equal(sessions[2].socket, parent, "parent sorts second")
assert_equal(sessions[2].distance, 1, "parent session distance")
assert_equal(sessions[3].socket, sibling_new, "newer equidistant session wins tie")
assert_equal(sessions[4].socket, sibling_old, "older equidistant session follows")
assert_equal(sessions[5].socket, other, "more distant session sorts last")

assert_equal(transport.get_socket_path({ quiet = true }), nil, "session is not selected automatically")
config.options.socket_path = parent
assert_equal(transport.get_socket_path({ quiet = true }), parent, "explicitly selected session resolves")
config.options.socket_path = nil

local original_cwd = vim.fn.getcwd()
local original_notify = vim.notify
local original_select = vim.ui.select
local selected_session = nil
vim.cmd("cd " .. vim.fn.fnameescape(nvim_cwd))
vim.notify = function() end
vim.ui.select = function(items, _, callback)
	callback(items[1])
end
sessions_ui.select_session({
	on_select = function(session)
		selected_session = session
	end,
})
assert(selected_session, "finder should return the selected session")
assert_equal(selected_session.socket, exact, "finder should present the nearest session first")
assert_equal(config.options.socket_path, selected_session.socket, "finder should remember its selection")
vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
vim.notify = original_notify
vim.ui.select = original_select

local original_get_socket_path = transport.get_socket_path
local original_send_raw = transport.send_raw
local original_select_session = sessions_ui.select_session
local original_subscribe_events = events.subscribe_events
local has_selection = false
local finder_calls = 0
local send_calls = 0
local subscribe_calls = 0

transport.get_socket_path = function()
	return has_selection and exact or nil
end
transport.send_raw = function(message)
	assert_equal(message.type, "prompt", "sent message type")
	send_calls = send_calls + 1
end
sessions_ui.select_session = function(opts)
	finder_calls = finder_calls + 1
	has_selection = true
	opts.on_select({ socket = exact })
end
events.subscribe_events = function()
	subscribe_calls = subscribe_calls + 1
end

commands.send_prompt("first prompt")
assert_equal(finder_calls, 1, "first prompt opens the finder")
assert_equal(send_calls, 1, "first prompt sends after selection")
commands.send_prompt("second prompt")
assert_equal(finder_calls, 1, "later prompts reuse the selected session")
assert_equal(send_calls, 2, "later prompt sends directly")
assert_equal(subscribe_calls, 2, "each send ensures event subscription")

transport.get_socket_path = original_get_socket_path
transport.send_raw = original_send_raw
sessions_ui.select_session = original_select_session
events.subscribe_events = original_subscribe_events
vim.fn.delete(temp_root, "rf")
