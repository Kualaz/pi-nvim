local context = require("pi.context")
local targets = require("pi.context.targets")
local util = require("pi.util")

local M = {}

local active_prompt = nil

function M.is_open()
	return active_prompt ~= nil
end

function M.close()
	if not active_prompt then
		return false
	end

	active_prompt.close()
	return true
end

function M.ask(opts)
	-- `ask` doubles as the prompt toggle. Repeating the command or mapping that
	-- opened the prompt closes it without needing a special cancel key.
	if M.close() then
		return false
	end

	opts = opts or {}
	local selection = opts.selection
	local initial_text = opts.initial_text or ""
	local on_submit = opts.on_submit
	local source_buf = vim.api.nvim_get_current_buf()
	local source_file = util.relative_file(source_buf)
	local source_line = vim.api.nvim_win_get_cursor(0)[1]
	local prompt_context = {
		mode = opts.mode or (selection and "selection" or "line"),
		bufnr = source_buf,
		file = source_file,
		line = source_line,
		selection = selection,
		ft = vim.bo[source_buf].filetype,
	}

	local max_input_height = 6
	local width = math.min(72, math.max(1, math.floor(vim.o.columns * 0.55)))
	width = math.min(width, math.max(1, vim.o.columns - 4))
	local top_row = math.max(0, math.floor((vim.o.lines - (max_input_height + 2)) / 2))
	local col = math.max(0, math.floor((vim.o.columns - width - 2) / 2))

	local accent_hl = vim.api.nvim_get_hl(0, { name = "Function", link = false })
	local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	vim.api.nvim_set_hl(0, "PiNvimBorder", { fg = accent_hl.fg, bg = normal_hl.bg })
	vim.api.nvim_set_hl(0, "PiNvimTitle", { fg = accent_hl.fg, bg = normal_hl.bg })

	local input_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[input_buf].buftype = "nofile"
	vim.bo[input_buf].filetype = "pi-nvim-prompt"
	vim.bo[input_buf].completeopt = "menuone,noinsert,noselect"

	local initial_lines = vim.split(initial_text, "\n", { plain = true })
	vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, initial_lines)

	local input_win = vim.api.nvim_open_win(input_buf, true, {
		relative = "editor",
		width = width,
		height = 1,
		row = top_row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " pi prompt ",
		title_pos = "center",
		zindex = 50,
		noautocmd = true,
	})
	vim.wo[input_win].winhl = "NormalFloat:Normal,FloatBorder:PiNvimBorder,FloatTitle:PiNvimTitle"
	vim.wo[input_win].wrap = true
	vim.api.nvim_win_set_cursor(input_win, { #initial_lines, #initial_lines[#initial_lines] })

	local current_height = 1
	local function resize_input()
		if not vim.api.nvim_win_is_valid(input_win) or not vim.api.nvim_buf_is_valid(input_buf) then
			return
		end

		local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
		local visual_rows = 0
		for _, line in ipairs(lines) do
			local display_width = vim.fn.strdisplaywidth(line)
			visual_rows = visual_rows + math.max(1, math.ceil(display_width / width))
		end

		local new_height = math.max(1, math.min(max_input_height, visual_rows))
		if new_height == current_height then
			return
		end

		current_height = new_height
		vim.api.nvim_win_set_height(input_win, new_height)
	end

	local selection_ns = nil
	if selection and vim.api.nvim_buf_is_valid(source_buf) then
		selection_ns = vim.api.nvim_create_namespace("pi_nvim_selection")
		for lnum = selection.start_line, selection.end_line do
			vim.api.nvim_buf_add_highlight(source_buf, selection_ns, "Visual", lnum - 1, 0, -1)
		end
	end

	local closed = false

	local function close()
		if closed then
			return
		end
		closed = true

		if active_prompt and active_prompt.buf == input_buf then
			active_prompt = nil
		end
		if selection_ns and vim.api.nvim_buf_is_valid(source_buf) then
			vim.api.nvim_buf_clear_namespace(source_buf, selection_ns, 0, -1)
		end
		pcall(vim.api.nvim_win_close, input_win, true)
		pcall(vim.api.nvim_buf_delete, input_buf, { force = true })
	end

	active_prompt = {
		buf = input_buf,
		win = input_win,
		close = close,
	}

	local function send()
		local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
		local prompt_text = vim.fn.trim(table.concat(lines, "\n"))
		local message, expand_error = context.render_prompt(prompt_text, prompt_context)

		if expand_error then
			util.notify(expand_error, vim.log.levels.WARN)
			return
		end
		if not message or vim.fn.trim(message) == "" then
			util.notify("Nothing to send", vim.log.levels.WARN)
			return
		end

		close()
		if on_submit then
			on_submit(message)
		end
	end

	local function feedkeys(keys)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "n", false)
	end

	local function target_completion_items()
		local items = {}
		for _, name in ipairs(targets.menu_order) do
			local target = targets.definitions[name]
			table.insert(items, {
				word = name,
				abbr = name,
				menu = target.menu(prompt_context),
				info = target.info(prompt_context),
			})
		end
		return items
	end

	local function complete_target()
		if closed or not vim.api.nvim_win_is_valid(input_win) or not vim.api.nvim_buf_is_valid(input_buf) then
			return
		end

		vim.api.nvim_win_call(input_win, function()
			vim.api.nvim_put({ "@" }, "c", true, true)
			resize_input()
			local start_col = math.max(1, vim.fn.col(".") - 1)
			pcall(vim.fn.complete, start_col, target_completion_items())
		end)
	end

	local function confirm_completion_or_send()
		if vim.fn.pumvisible() == 1 then
			local complete_info = vim.fn.complete_info({ "selected" })
			feedkeys(complete_info.selected == -1 and "<C-n><C-y>" or "<C-y>")
			return
		end
		send()
	end

	local key_opts = { buffer = input_buf, noremap = true, silent = true }
	vim.keymap.set("i", "<CR>", confirm_completion_or_send, key_opts)
	vim.keymap.set("n", "<CR>", send, key_opts)
	vim.keymap.set("i", "@", complete_target, key_opts)

	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = input_buf,
		callback = resize_input,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(input_win),
		once = true,
		callback = close,
	})

	resize_input()
	vim.cmd("noautocmd startinsert!")
	return true
end

return M
