local util = require("pi.util")

local M = {}

local function buffer_text(bufnr)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return nil
	end
	return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

local severity_names = {
	[vim.diagnostic.severity.ERROR] = "ERROR",
	[vim.diagnostic.severity.WARN] = "WARN",
	[vim.diagnostic.severity.INFO] = "INFO",
	[vim.diagnostic.severity.HINT] = "HINT",
}

M.definitions = {
	["@this"] = {
		menu = function(ctx)
			if ctx.mode == "selection" then
				return "current visual selection"
			end
			if ctx.mode == "file" then
				return "current file"
			end
			if ctx.mode == "none" then
				return "not available in this prompt"
			end
			return "current line"
		end,
		info = function(ctx)
			if ctx.mode == "selection" then
				return "Selected text, then cwd-relative file and line range"
			end
			if ctx.mode == "file" then
				return "Cwd-relative file reference"
			end
			return "Cwd-relative file and current line"
		end,
		render = function(ctx)
			if ctx.mode == "selection" then
				local selection = ctx.selection
				if not selection then
					return nil, "@this requires an active visual selection"
				end

				local ref = util.line_reference(selection.file, selection.start_line, selection.end_line)
				if not ref then
					return nil, "@this requires a file-backed buffer"
				end

				return string.format("%s\n\n%s", util.fenced_code(selection.ft, selection.text), ref)
			end

			if ctx.mode == "file" then
				if not ctx.file or ctx.file == "" then
					return nil, "@this requires a file-backed buffer"
				end
				return ctx.file
			end

			if ctx.mode == "none" then
				return nil, "@this is not available for this prompt"
			end

			local ref = util.line_reference(ctx.file, ctx.line)
			if not ref then
				return nil, "@this requires a file-backed buffer"
			end
			return ref
		end,
	},
	["@buffer"] = {
		menu = function()
			return "current buffer"
		end,
		info = function()
			return "Buffer text, then cwd-relative file reference"
		end,
		render = function(ctx)
			if not ctx.file or ctx.file == "" then
				return nil, "@buffer requires a file-backed buffer"
			end

			local text = buffer_text(ctx.bufnr)
			if not text or vim.fn.trim(text) == "" then
				return nil, "@buffer requires a non-empty buffer"
			end

			return string.format("%s\n\n%s", util.fenced_code(ctx.ft, text), ctx.file)
		end,
	},
	["@diagnostics"] = {
		menu = function()
			return "current buffer diagnostics"
		end,
		info = function()
			return "Diagnostics for the current buffer"
		end,
		render = function(ctx)
			local file = ctx.file or "(unnamed buffer)"
			local diagnostics = vim.diagnostic.get(ctx.bufnr)
			if #diagnostics == 0 then
				return string.format("No diagnostics for %s", file)
			end

			table.sort(diagnostics, function(a, b)
				if a.lnum ~= b.lnum then
					return a.lnum < b.lnum
				end
				if a.col ~= b.col then
					return a.col < b.col
				end
				return (a.severity or 99) < (b.severity or 99)
			end)

			local lines = {}
			for _, diagnostic in ipairs(diagnostics) do
				local severity = severity_names[diagnostic.severity] or "UNKNOWN"
				local ref = util.line_reference(file, diagnostic.lnum + 1) or file
				local message = tostring(diagnostic.message or ""):gsub("\n", " ")
				table.insert(lines, string.format("- %s %s: %s", severity, ref, message))
			end

			return table.concat(lines, "\n")
		end,
	},
}

M.menu_order = { "@this", "@buffer", "@diagnostics" }
M.match_order = vim.tbl_keys(M.definitions)
table.sort(M.match_order, function(a, b)
	return #a > #b
end)

return M
