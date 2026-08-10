local targets = require("pi.context.targets")
local util = require("pi.util")

local M = {}

local function active_visual_mode()
	local mode = vim.api.nvim_get_mode().mode
	if mode == "v" or mode == "V" or mode == "\22" then
		return mode
	end
	return nil
end

local function pos_before_or_equal(a, b)
	if a[2] ~= b[2] then
		return a[2] < b[2]
	end
	return a[3] <= b[3]
end

function M.capture_selection()
	local mode = active_visual_mode()
	local start_pos
	local end_pos
	local selection_type

	if mode then
		-- While a visual-mode mapping is running, '< and '> may still refer to
		-- the previous selection. Use the live visual anchor/current cursor.
		start_pos = vim.fn.getpos("v")
		end_pos = vim.fn.getpos(".")
		selection_type = mode
	else
		start_pos = vim.fn.getpos("'<")
		end_pos = vim.fn.getpos("'>")
		selection_type = vim.fn.visualmode()
		if selection_type == "" then
			selection_type = "v"
		end
	end

	if start_pos[2] == 0 and end_pos[2] == 0 then
		return nil
	end

	if not pos_before_or_equal(start_pos, end_pos) then
		start_pos, end_pos = end_pos, start_pos
	end

	local ok, lines = pcall(vim.fn.getregion, start_pos, end_pos, { type = selection_type })
	if not ok or not lines or #lines == 0 then
		return nil
	end

	local text = table.concat(lines, "\n")
	if text == "" then
		return nil
	end

	return {
		text = text,
		file = util.relative_file(0),
		start_line = start_pos[2],
		end_line = end_pos[2],
		ft = vim.bo.filetype,
	}
end

function M.render_prompt(prompt_text, ctx)
	local found = {}
	for _, name in ipairs(targets.match_order) do
		local start = 1
		while true do
			local from, to = prompt_text:find(name, start, true)
			if not from then
				break
			end
			table.insert(found, { name = name, from = from })
			start = to + 1
		end
	end

	if #found == 0 then
		return prompt_text, nil
	end

	table.sort(found, function(a, b)
		return a.from < b.from
	end)

	local cleaned_prompt = prompt_text
	for _, name in ipairs(targets.match_order) do
		cleaned_prompt = cleaned_prompt:gsub(util.escape_pattern(name), "")
	end
	cleaned_prompt = util.clean_prompt_text(cleaned_prompt)

	local rendered = {}
	local seen = {}
	for _, item in ipairs(found) do
		if not seen[item.name] then
			seen[item.name] = true
			local target = targets.definitions[item.name]
			local output, err = target.render(ctx)
			if err then
				return nil, err
			end
			if output and output ~= "" then
				table.insert(rendered, output)
			end
		end
	end

	local context = table.concat(rendered, "\n\n")
	if cleaned_prompt == "" then
		return string.format("Context:\n%s", context), nil
	end

	return string.format("%s\n\nContext:\n%s", cleaned_prompt, context), nil
end

return M
