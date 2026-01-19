#!/usr/bin/env -S nvim -l

vim.env.LAZY_STDPATH = ".tests"

load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

require("lazy.minit").setup({
	spec = {
		{ dir = vim.uv.cwd() },
	},
})

-- Silence vim.notify during tests to the standard output
vim.notify = function() end
