-- lua/telescope/_extensions/mentat.lua

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")
local Path = require("plenary.path")
-- local json = require("plenary.json")
local json = vim.json

-- Chat state and history management
local M = {}

M.chat_state = {
  messages = {},
  current_message = "",
  is_processing = false,
  session_id = nil
}

-- Ensure .mentat directory exists and return history file path
local function get_history_file()
  local cwd = vim.fn.getcwd()
  local mentat_dir = Path:new(cwd) / ".mentat"
  local history_file = mentat_dir / "chat_history.json"

  if not mentat_dir:exists() then
    mentat_dir:mkdir()
  end

  return history_file
end

-- Load chat history from file
local function load_chat_history()
  local history_file = get_history_file()
  if history_file:exists() then
    local content = history_file:read()
    -- Handle empty file case
    if content == "" then
      return {}
    end
    return json.decode(content)
  end
  return {}
end

-- Save chat history to file
local function save_chat_history(history)
  local history_file = get_history_file()
  history_file:write(json.encode(history), 'w')
end

-- Generate new session ID
local function generate_session_id()
  local date = os.date("%Y-%m-%d_%H-%M-%S")
  return string.format("chat_%s", date)
end

-- Create a custom previewer that handles chat history
local ChatPreviewer = previewers.new_buffer_previewer({
  title = "Chat",
  define_preview = function(self, entry)
    vim.api.nvim_buf_set_option(self.state.bufnr, 'modifiable', true)

    local lines = {}
    for _, msg in ipairs(M.chat_state.messages) do
      table.insert(lines, string.format("[%s]", msg.role))
      table.insert(lines, "────────────────────")
      for line in msg.content:gmatch("[^\n]+") do
        table.insert(lines, line)
      end
      table.insert(lines, "")
    end

    if M.chat_state.current_message ~= "" then
      table.insert(lines, "[You]")
      table.insert(lines, "────────────────────")
      table.insert(lines, M.chat_state.current_message)
    end

    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

    -- Set up buffer-local keymaps for navigation
    local opts = { buffer = self.state.bufnr, noremap = true, silent = true }
    vim.keymap.set('n', 'j', 'j', opts)
    vim.keymap.set('n', 'k', 'k', opts)
    vim.keymap.set('n', '<C-d>', '<C-d>', opts)
    vim.keymap.set('n', '<C-u>', '<C-u>', opts)
    vim.keymap.set('n', 'G', 'G', opts)
    vim.keymap.set('n', 'gg', 'gg', opts)
    vim.keymap.set('v', 'y', 'y', opts)

    vim.api.nvim_buf_set_option(self.state.bufnr, 'modifiable', false)
  end,
})

-- Create the history picker
local function history_picker(opts)
  opts = opts or {}

  local history = load_chat_history()
  local history_entries = {}
  for session_id, session in pairs(history) do
    table.insert(history_entries, {
      id = session_id,
      display = string.format("%s (%d messages)", session_id, #session.messages),
      messages = session.messages
    })
  end

  -- Sort entries by session ID (which includes timestamp)
  table.sort(history_entries, function(a, b) return a.id > b.id end)

  local history_previewer = previewers.new_buffer_previewer({
    title = "Chat History",
    define_preview = function(self, entry)
      local lines = {}
      for _, msg in ipairs(entry.messages) do
        table.insert(lines, string.format("[%s]", msg.role))
        table.insert(lines, "────────────────────")
        for line in msg.content:gmatch("[^\n]+") do
          table.insert(lines, line)
        end
        table.insert(lines, "")
      end
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
    end,
  })

  pickers.new(opts, {
    prompt_title = "Chat History",
    finder = finders.new_table({
      results = history_entries,
      entry_maker = function(entry)
        return {
          value = entry.id,
          display = entry.display,
          ordinal = entry.display,
          messages = entry.messages,
        }
      end,
    }),
    previewer = history_previewer,
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        M.chat_state.session_id = selection.value
        M.chat_state.messages = selection.messages
        -- Open chat window with selected history
        M.open_chat()
      end)
      return true
    end,
  }):find()
end

-- Function to add a message to chat history
local function add_message(role, content)
  table.insert(M.chat_state.messages, { role = role, content = content })

  -- Save to history file
  local history = load_chat_history()
  history[M.chat_state.session_id] = {
    messages = M.chat_state.messages
  }
  save_chat_history(history)
end

-- Create the main chat picker with only preview
function M.open_chat()
  if not M.chat_state.session_id then
    M.chat_state.session_id = generate_session_id()
    M.chat_state.messages = {}
  end

  local picker = pickers.new({}, {
    prompt_title = "Consult Your Mentat",
    finder = finders.new_table({
      results = {""},
      entry_maker = function(entry)
        return {
          value = entry,
          ordinal = entry,
        }
      end,
    }),
    previewer = ChatPreviewer,
    sorter = conf.generic_sorter({}),
    layout_config = {
      preview_cutoff = 0,  -- Always show preview
      width = 0.8,
      height = 0.8,
      preview_width = 1,  -- Make preview take full width
    },
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local content = action_state.get_current_line()
        if content and #content > 0 and not M.chat_state.is_processing then
          M.chat_state.is_processing = true
          add_message("You", content)
          -- TODO: Call LLM API here
          add_message("Assistant", "This is where the LLM response will go.\nWe'll implement the actual API call next.")
          M.chat_state.is_processing = false
          vim.api.nvim_buf_set_lines(prompt_bufnr, 0, -1, false, {""})
          action_state.get_current_picker(prompt_bufnr):refresh()
        end
      end)

      map('i', '<C-c>', function()
        actions.close(prompt_bufnr)
      end)

      map('i', '<C-u>', function()
        vim.api.nvim_buf_set_lines(prompt_bufnr, 0, -1, false, {""})
      end)

      return true
    end,
  })

  picker.prompt_prefix = "🤖 > "
  picker:find()
end

-- Register the extension
return require("telescope").register_extension({
  exports = {
    mentat = M.open_chat,
    history = history_picker
  }
})
