-- init.lua

-- set vim options
require "options"

-- load lazy
require "setup-lazy"

-- define keymaps
require "keymaps"

-- configure plugins
require "config.editor"
require "config.lualine"
require "config.ghola"
require("config.snippets").setup()

require "config.terminal"
