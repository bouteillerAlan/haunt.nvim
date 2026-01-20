---@toc_entry Sidekick
---@tag haunt-sidekick
---@text
--- # Sidekick ~
---
--- Integration with sidekick.nvim (https://github.com/folke/sidekick.nvim).
--- Provides bookmark locations in a format compatible with sidekick's location system.
---

---@private
local M = {}

---@class SidekickOpts
---@field current_buffer? boolean If true, return only bookmarks for the current buffer (default: false)
---@field append_annotations? boolean If true, append annotation text to each location (default: true)

---@private
--- Convert an absolute path to a relative path from the cwd
---@param absolute_path string The absolute file path
---@return string relative_path The path relative to cwd
local function to_relative_path(absolute_path)
	local relative = vim.fn.fnamemodify(absolute_path, ":.")
	-- If the path couldn't be made relative (e.g., different drive on Windows),
	-- return the original path
	if relative == "" then
		return absolute_path
	end
	return relative
end

--- Get bookmark locations formatted for sidekick.nvim.
---
--- Returns bookmarks in sidekick-compatible format:
--- `- @/{path} :L{line} - "{note}"`
---
---@param opts? SidekickOpts Options for filtering and formatting
---@return string # Formatted bookmark locations, one per line
---
---@usage >lua
---   -- Get all bookmarks
---   local sidekick = require('haunt.sidekick')
---   local locations = sidekick.get_locations()
---
---   -- Get only current buffer bookmarks
---   local current = sidekick.get_locations({ current_buffer = true })
---<
function M.get_locations(opts)
	opts = opts or {}

	-- Default append_annotations to true
	local append_annotations = opts.append_annotations
	if append_annotations == nil then
		append_annotations = true
	end

	local current_buffer = opts.current_buffer or false

	-- Get all bookmarks from the API
	local api = require("haunt.api")
	local bookmarks = api.get_bookmarks()

	-- If no bookmarks, return empty string
	if #bookmarks == 0 then
		return ""
	end

	-- Filter to current buffer if requested
	if current_buffer then
		local current_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
		local filtered = {}
		for _, bookmark in ipairs(bookmarks) do
			if bookmark.file == current_file then
				table.insert(filtered, bookmark)
			end
		end
		bookmarks = filtered
	end

	-- If no bookmarks after filtering, return empty string
	if #bookmarks == 0 then
		return ""
	end

	-- Sort bookmarks by file path, then by line number
	table.sort(bookmarks, function(a, b)
		if a.file == b.file then
			return a.line < b.line
		end
		return a.file < b.file
	end)

	-- Format each bookmark
	local lines = {}
	for _, bookmark in ipairs(bookmarks) do
		local relative_path = to_relative_path(bookmark.file)
		local line_str = string.format("- @/%s :L%d", relative_path, bookmark.line)

		-- Append annotation if requested and exists
		if append_annotations and bookmark.note and bookmark.note ~= "" then
			line_str = line_str .. string.format(' - "%s"', bookmark.note)
		end

		table.insert(lines, line_str)
	end

	return table.concat(lines, "\n")
end

---@class QuickfixItem
---@field filename string
---@field lnum integer
---@field col integer
---@field text string

--- Get bookmark locations as quickfix items.
---
---@param opts? SidekickOpts Options for filtering and formatting
---@return QuickfixItem[] items Quickfix items
function M.get_quickfix_items(opts)
	opts = opts or {}

	-- Default append_annotations to true
	local append_annotations = opts.append_annotations
	if append_annotations == nil then
		append_annotations = true
	end

	local current_buffer = opts.current_buffer or false

	local api = require("haunt.api")
	local bookmarks = api.get_bookmarks()

	if #bookmarks == 0 then
		return {}
	end

	-- Filter to current buffer
	if current_buffer then
		local current_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
		local filtered = {}
		for _, bookmark in ipairs(bookmarks) do
			if bookmark.file == current_file then
				table.insert(filtered, bookmark)
			end
		end
		bookmarks = filtered
	end

	if #bookmarks == 0 then
		return {}
	end

	-- Sort bookmarks by path, then by line number
	-- Optional, decide you want them sorted
	table.sort(bookmarks, function(a, b)
		if a.file == b.file then
			return a.line < b.line
		end
		return a.file < b.file
	end)

	local items = {}
	for _, bookmark in ipairs(bookmarks) do
		local text = "Haunt bookmark"
		if append_annotations and bookmark.note and bookmark.note ~= "" then
			text = bookmark.note
		end

		table.insert(items, {
			filename = bookmark.file, -- absolute path is ideal for quickfix
			lnum = bookmark.line,
			col = 1,
			text = text,
		})
	end

	return items
end

--- Populate the quickfix list with haunt bookmarks.
---
---@param opts? SidekickOpts Options for filtering and formatting
function M.to_quickfix(opts)
	local items = M.get_quickfix_items(opts)
	vim.fn.setqflist({}, " ", {
		title = (opts and opts.current_buffer) and "Haunt (buffer)" or "Haunt",
		items = items,
	})
end

return M
