local uv = vim.uv or vim.loop

local M = {}

function M.notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "pi" })
end

function M.fs_stat(path)
	if not path or path == "" then
		return nil
	end
	return uv.fs_stat(path)
end

function M.read_json(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok or not lines or not lines[1] then
		return nil
	end

	local parsed_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
	if parsed_ok then
		return decoded
	end
	return nil
end

function M.relative_file(bufnr)
	local absolute = vim.api.nvim_buf_get_name(bufnr or 0)
	if absolute == "" then
		return nil
	end

	local relative = vim.fn.fnamemodify(absolute, ":.")
	return relative ~= "" and relative or absolute
end

function M.line_reference(file, start_line, end_line)
	if not file or file == "" then
		return nil
	end

	if end_line and end_line ~= start_line then
		return string.format("%s:L%d-L%d", file, start_line, end_line)
	end

	return string.format("%s:L%d", file, start_line)
end

local function longest_backtick_run(text)
	local longest = 0
	for run in tostring(text or ""):gmatch("`+") do
		longest = math.max(longest, #run)
	end
	return longest
end

function M.fenced_code(ft, text)
	local lang = ft and ft ~= "" and ft or ""
	local fence = string.rep("`", math.max(3, longest_backtick_run(text) + 1))
	return string.format("%s%s\n%s\n%s", fence, lang, text, fence)
end

function M.delivery_label(delivery)
	if delivery == "steer" then
		return "steered"
	end
	if delivery == "followUp" then
		return "queued as follow-up"
	end
	return "sent"
end

function M.short_time(iso)
	if type(iso) ~= "string" then
		return ""
	end
	local h, m = iso:match("%d+%-%d+%-%d+T(%d+):(%d+):%d+")
	if h and m then
		return string.format("%s:%s", h, m)
	end
	return iso
end

function M.clean_prompt_text(text)
	local cleaned = text:gsub("[ \t]+\n", "\n"):gsub("\n[ \t]+", "\n"):gsub("[ \t][ \t]+", " ")
	return vim.fn.trim(cleaned)
end

function M.escape_pattern(text)
	return text:gsub("([^%w])", "%%%1")
end

return M
