local m_config = {
    git = "git",
    gitlog = "git log --graph --abbrev-commit --decorate --date=relative --all",
}

local M = {}

function M.initialize()
    M.setup()
end

---@type Config
M.config = m_config

M.execute = function()
    vim.api.nvim_create_user_command("Hello", function()
        print("Hello World")
    end, {})

    vim.api.nvim_create_user_command("GitBeans", function()
        M.open_hello_window()
    end, {})
end

local function GitLog()
    local result = vim.fn.systemlist(M.config.gitlog)
    if vim.v.shell_error ~= 0 then
        result = { "Error running git log.", unpack(result) }
    elseif #result == 0 then
        result = { "No git history found." }
    end
    return result
end

function M.open_hello_window(message)
    local buf = vim.api.nvim_create_buf(false, true)
    local log = GitLog()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, log)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "filetype", "git")
    local height = math.min(#log, 20)
    local width = 100
    local ui = vim.api.nvim_list_uis()[1]
    local row = math.floor((ui.height - height) / 2)
    local col = math.floor((ui.width - width) / 2)
    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
    }
    local win = vim.api.nvim_open_win(buf, true, win_opts)
    vim.keymap.set("n", 'q', function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true })
end

M.setup = function(args)
    M.config = vim.tbl_deep_extend("force", M.config, args or {})
    M.execute()
end

return M
