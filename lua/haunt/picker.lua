---@toc_entry Picker
---@tag haunt-picker
---@text
--- # Picker ~
---
--- The picker provides an interactive interface to browse and manage bookmarks.
--- Uses Snacks.nvim (https://github.com/folke/snacks.nvim) if available,
--- otherwise falls back to vim.ui.select for basic functionality.
---
--- Picker actions (Snacks.nvim only): ~
---   - `<CR>`: Jump to the selected bookmark
---   - `d` (normal mode): Delete the selected bookmark
---   - `a` (normal mode): Edit the bookmark's annotation
---
--- The keybindings can be customized via |HauntConfig|.picker_keys.

---@private
local M = {}

---@private
---@type ApiModule|nil
local api = nil
---@private
---@type HauntModule|nil
local haunt = nil

---@private
local function ensure_modules()
	if not api then
		api = require("haunt.api")
	end
	if not haunt then
		haunt = require("haunt")
	end
end

---@private
--- Execute a callback with buffer context temporarily switched
--- Switches to the target buffer, sets cursor position, executes callback, then safely restores
--- Uses pcall and validation to prevent errors when restoring picker buffer state
---@param bufnr number Target buffer number
---@param line number Line number to set cursor to
---@param callback function Function to execute in the target buffer context
---@return any The return value of the callback
local function with_buffer_context(bufnr, line, callback)
	-- Save current buffer and window
	local current_bufnr = vim.api.nvim_get_current_buf()
	local current_win = vim.api.nvim_get_current_win()
	local cursor_saved = vim.api.nvim_win_get_cursor(current_win)

	-- Ensure target buffer is loaded
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		vim.fn.bufload(bufnr)
	end

	-- Switch to target buffer
	vim.api.nvim_set_current_buf(bufnr)

	-- Move cursor to the bookmark line (with validation)
	-- Clamp line to valid range to avoid "Cursor position outside buffer" error
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local safe_line = math.min(math.max(1, line), line_count)
	pcall(vim.api.nvim_win_set_cursor, current_win, { safe_line, 0 })

	-- Execute the callback
	local result = callback()

	-- Safely restore original buffer with validation
	-- The picker buffer might not be in a valid state to restore, so use pcall
	if vim.api.nvim_buf_is_valid(current_bufnr) and vim.api.nvim_buf_is_loaded(current_bufnr) then
		-- Attempt to restore buffer - use pcall to handle any state errors
		pcall(vim.api.nvim_set_current_buf, current_bufnr)

		-- Only restore cursor if we successfully switched back to the original buffer
		if vim.api.nvim_get_current_buf() == current_bufnr then
			pcall(vim.api.nvim_win_set_cursor, current_win, cursor_saved)
		end
	end

	return result
end

---@private
--- Handle deleting a bookmark from the picker
---@param picker table The Snacks picker instance
---@param item table|nil The selected bookmark item
---@return nil
local function handle_delete(picker, item)
	ensure_modules()
	---@cast api -nil

	if not item then
		return
	end

	-- Delete the bookmark by its ID (no need for buffer context)
	local success = api.delete_by_id(item.id)

	if not success then
		vim.notify("haunt.nvim: Failed to delete bookmark", vim.log.levels.WARN)
		return
	end

	-- Check if there are any bookmarks left
	local remaining = api.get_bookmarks()
	if #remaining == 0 then
		picker:close()
		vim.notify("haunt.nvim: No bookmarks remaining", vim.log.levels.INFO)
		return
	end

	-- Refresh the picker to show updated list
	picker:refresh()
end

---@private
--- Handle editing a bookmark annotation from the picker
---@param picker table The Snacks picker instance
---@param item table|nil The selected bookmark item
---@return nil
local function handle_edit_annotation(picker, item)
	ensure_modules()
	---@cast api -nil

	if not item then
		return
	end

	-- Prompt for new annotation
	local default_text = item.note or ""

	-- Close picker temporarily to show input prompt clearly
	picker:close()

	local annotation = vim.fn.input({
		prompt = "Annotation: ",
		default = default_text,
	})

	-- If user cancelled (ESC), annotation will be empty string
	-- Only proceed if something was entered or if clearing existing annotation
	if annotation == "" and default_text == "" then
		-- User cancelled with no existing annotation, reopen picker
		M.show()
		return
	end

	-- Open the file in a buffer if not already open
	local bufnr = vim.fn.bufnr(item.file)
	if bufnr == -1 then
		bufnr = vim.fn.bufadd(item.file)
		vim.fn.bufload(bufnr)
	end

	-- Use helper to execute annotate in the buffer context
	with_buffer_context(bufnr, item.line, function()
		api.annotate(annotation)
	end)

	-- Reopen the picker with updated data
	M.show()
end

---@private
--- Build picker items from bookmarks
---@param bookmarks Bookmark[]
---@return table[]
local function build_picker_items(bookmarks)
	local items = {}
	for i, bm in ipairs(bookmarks) do
		local text = vim.fn.fnamemodify(bm.file, ":.") .. ":" .. bm.line
		if bm.note and bm.note ~= "" then
			text = text .. " " .. bm.note
		end
		table.insert(items, {
			idx = i,
			score = i,
			file = bm.file,
			pos = { bm.line, 0 },
			text = text,
			note = bm.note,
			id = bm.id,
			line = bm.line,
		})
	end
	return items
end

---@private
--- Fallback picker using vim.ui.select when Snacks.nvim is not available
local function show_fallback_picker()
	ensure_modules()
	---@cast api -nil

	local bookmarks = api.get_bookmarks()
	if #bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks found", vim.log.levels.INFO)
		return
	end

	vim.ui.select(build_picker_items(bookmarks), {
		prompt = "Hauntings",
		format_item = function(item)
			return item.text
		end,
	}, function(choice)
		if not choice then
			return
		end

		local bufnr = vim.fn.bufnr(choice.file)
		if bufnr == -1 then
			vim.cmd("edit " .. vim.fn.fnameescape(choice.file))
		else
			vim.cmd("buffer " .. bufnr)
		end

		vim.api.nvim_win_set_cursor(0, { choice.line, 0 })
		vim.cmd("normal! zz")
	end)
end

--- Open the bookmark picker.
---
--- Displays all bookmarks in an interactive picker powered by Snacks.nvim.
--- Allows jumping to, deleting, or editing bookmark annotations (Snacks.nvim only).
--- Falls back to vim.ui.select if Snacks.nvim is not available.
---
---@usage >lua
---   -- Show the picker
---   require('haunt.picker').show()
---<
---@param opts? snacks.picker.Config Options to pass to Snacks.picker
function M.show(opts)
	ensure_modules()
	---@cast api -nil
	---@cast haunt -nil

	local ok, Snacks = pcall(require, "snacks")
	if not ok then
		show_fallback_picker()
		return
	end

	-- Check if there are any bookmarks
	local initial_bookmarks = api.get_bookmarks()
	if #initial_bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks found", vim.log.levels.INFO)
		return
	end

	-- Get keybinding configuration (config.get() always returns defaults if not set)
	local cfg = haunt.get_config()
	local picker_keys = cfg.picker_keys

	-- Build keys table for Snacks picker in the correct format
	-- Keys need to be in both input and list windows so they work regardless of focus
	local input_keys = {}
	local list_keys = {}

	if picker_keys.delete then
		local key = picker_keys.delete.key or "d"
		local mode = picker_keys.delete.mode or { "n" }
		input_keys[key] = { "delete", mode = mode }
		list_keys[key] = { "delete", mode = mode }
	end

	if picker_keys.edit_annotation then
		local key = picker_keys.edit_annotation.key or "a"
		local mode = picker_keys.edit_annotation.mode or { "n" }
		input_keys[key] = { "edit_annotation", mode = mode }
		list_keys[key] = { "edit_annotation", mode = mode }
	end

	---@type snacks.picker.Config
	local picker_opts = {
		title = "Hauntings",
		-- Use a finder function so picker:refresh() works correctly
		finder = function()
			return build_picker_items(api.get_bookmarks())
		end,
		-- Custom format function for bookmark items
		format = function(item, picker)
			local result = {}

			-- Get path relative to current working directory
			local relpath = vim.fn.fnamemodify(item.file, ":.")
			local filename = vim.fn.fnamemodify(relpath, ":t")
			local dir = vim.fn.fnamemodify(relpath, ":h")
			if dir == "." then
				dir = ""
			else
				dir = dir .. "/"
			end

			-- Format: filename (in directory) :line note
			result[#result + 1] = { filename, "SnacksPickerFile" }
			if dir ~= "" then
				result[#result + 1] = { " " .. dir, "SnacksPickerDir" }
			end
			result[#result + 1] = { ":", "SnacksPickerIcon" }
			result[#result + 1] = { tostring(item.pos[1]), "SnacksPickerMatch" }

			-- Add annotation if present
			if item.note and item.note ~= "" then
				result[#result + 1] = { " " .. item.note, "SnacksPickerComment" }
			end

			return result
		end,
		confirm = function(picker, item)
			if not item then
				return
			end
			picker:close()

			-- Open file
			local bufnr = vim.fn.bufnr(item.file)
			if bufnr == -1 then
				-- File not loaded, open it
				vim.cmd("edit " .. vim.fn.fnameescape(item.file))
			else
				-- File already loaded, switch to it
				vim.cmd("buffer " .. bufnr)
			end

			-- go to line
			vim.api.nvim_win_set_cursor(0, { item.line, 0 })
			vim.cmd("normal! zz")
		end,
		actions = {
			delete = handle_delete,
			edit_annotation = handle_edit_annotation,
		},
		win = {
			input = {
				keys = input_keys,
			},
			list = {
				keys = list_keys,
			},
		},
	}
	picker_opts = vim.tbl_deep_extend("force", picker_opts, opts or {})
	Snacks.picker(picker_opts)
end

return M
