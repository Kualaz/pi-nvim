local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(script_path))
vim.opt.runtimepath:prepend(root)

local ask = require("pi.ui.ask")

local function assert_equal(actual, expected, message)
	assert(actual == expected, string.format("%s: expected %s, got %s", message, vim.inspect(expected), vim.inspect(actual)))
end

local original_completeopt = vim.go.completeopt
local original_set_height = vim.api.nvim_win_set_height
local resize_calls = 0
vim.api.nvim_win_set_height = function(...)
	resize_calls = resize_calls + 1
	return original_set_height(...)
end

assert(ask.ask({ initial_text = "first\nsecond", on_submit = function() end }))
assert(ask.is_open(), "prompt should be open")
assert_equal(vim.api.nvim_win_get_height(0), 2, "multiline prompt height")
assert_equal(vim.go.completeopt, original_completeopt, "global completeopt")
assert_equal(resize_calls, 1, "initial resize count")

local input_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_text(input_buf, 0, 5, 0, 5, { "!" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = input_buf })
assert_equal(resize_calls, 1, "unchanged visual height should not resize the window")

vim.api.nvim_buf_set_lines(input_buf, 0, 1, false, { string.rep("x", 100) })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = input_buf })
local resize_calls_after_wrap = resize_calls
assert(resize_calls_after_wrap > 1, "new visual rows should resize the window")
vim.api.nvim_buf_set_text(input_buf, 0, 100, 0, 100, { "x" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = input_buf })
assert_equal(resize_calls, resize_calls_after_wrap, "typing within the same visual row should not resize the window")

vim.api.nvim_input(vim.keycode("<Esc>"))
assert(vim.wait(500, function()
	return vim.api.nvim_get_mode().mode == "n"
end), "Esc should leave insert mode")
assert(ask.is_open(), "Esc should not close the prompt")
assert_equal(
	table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
	string.rep("x", 101) .. "\nsecond",
	"prompt text after Esc"
)

assert(not ask.ask({}), "repeating ask should close the active prompt")
assert(not ask.is_open(), "prompt should be closed after toggling")
vim.api.nvim_win_set_height = original_set_height

local submitted = nil
assert(ask.ask({
	initial_text = "send this",
	on_submit = function(message)
		submitted = message
	end,
}))
vim.api.nvim_input(vim.keycode("<Esc>"))
assert(vim.wait(500, function()
	return vim.api.nvim_get_mode().mode == "n"
end), "Esc should enter normal mode before submission")
vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
assert(vim.wait(500, function()
	return submitted ~= nil
end), "Enter should submit from normal mode")
assert_equal(submitted, "send this", "submitted prompt")
assert(not ask.is_open(), "submitting should close the prompt")
