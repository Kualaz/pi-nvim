local config = require("pi.config")
local context = require("pi.context")
local events = require("pi.events")
local transport = require("pi.transport")
local ask_ui = require("pi.ui.ask")
local sessions_ui = require("pi.ui.sessions")
local util = require("pi.util")

local M = {}

local function handle_prompt_response(err, response)
	if err then
		util.notify(err, vim.log.levels.ERROR)
		return
	end

	if response and response.ok then
		util.notify("Pi " .. util.delivery_label(response.delivery), vim.log.levels.INFO)
	else
		util.notify("Pi error: " .. (response and response.error or "unknown"), vim.log.levels.ERROR)
	end
end

function M.send_prompt(message)
	if not message or vim.fn.trim(message) == "" then
		util.notify("Nothing to send", vim.log.levels.WARN)
		return
	end

	local function send_to_selected_session()
		events.subscribe_events({ quiet = true })
		transport.send_raw({ type = "prompt", message = message }, handle_prompt_response)
	end

	if transport.get_socket_path({ quiet = true }) then
		send_to_selected_session()
		return
	end

	sessions_ui.select_session({
		on_select = function(session)
			if session then
				send_to_selected_session()
			end
		end,
	})
end

function M.ask(opts)
	local ask_opts = vim.tbl_extend("force", {}, opts or {})
	ask_opts.on_submit = ask_opts.on_submit or M.send_prompt
	return ask_ui.ask(ask_opts)
end

function M.send_all()
	M.ask({
		mode = "file",
		initial_text = "@buffer ",
	})
end

function M.list_sessions()
	sessions_ui.list_sessions()
end

function M.setup(opts)
	config.setup(opts)

	local group = vim.api.nvim_create_augroup("PiNvim", { clear = true })

	if config.options.events then
		vim.defer_fn(function()
			events.subscribe_events({ quiet = true })
		end, 250)
	else
		events.close()
	end

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		once = true,
		callback = events.close,
	})

	vim.api.nvim_create_user_command("Pi", function(args)
		local selection = nil
		if args.range == 2 then
			selection = context.capture_selection()
		end
		M.ask({ selection = selection })
	end, { range = true, desc = "Toggle the Pi prompt (@this = current line/selection)" })

	vim.api.nvim_create_user_command("PiSendAll", function()
		M.send_all()
	end, { desc = "Ask Pi with the current buffer" })

	vim.api.nvim_create_user_command("PiSessions", function()
		M.list_sessions()
	end, { desc = "Pick a Pi session" })
end

return M
