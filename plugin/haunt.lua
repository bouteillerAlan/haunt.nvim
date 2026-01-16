-- haunt.nvim plugin loader
-- This file is automatically sourced by Neovim when the plugin is installed

-- Prevent loading twice
if vim.g.loaded_haunt == 1 then
  return
end
vim.g.loaded_haunt = 1

-- Optional: Auto-setup with defaults for zero-config usage
-- Users can still call require('haunt').setup() with custom config to override
vim.defer_fn(function()
  -- Only auto-setup if user hasn't already called setup
  local haunt = require('haunt')

  -- Check if haunt has a flag indicating setup was called
  -- We'll add this check to the init.lua module
  local config = haunt.get_config()

  -- If config is still default (no user setup), initialize with defaults
  if config then
    -- User can still override by calling setup() in their config
    -- This just ensures basic functionality works out of the box
    haunt.setup()
  end
end, 0)
