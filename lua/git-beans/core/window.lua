local M = {}

---@class GitBeansWindowOptions
---@field modifiable boolean
---@field bufhidden string
---@field filetype string
---@field relative string
---@field width integer
---@field height integer
---@field row integer
---@field col integer
---@field style string
---@field border string|string[]
---@field title string
---@field title_pos string

---@type GitBeansWindowOptions
local default_win = {
    modifiable = true,
    bufhidden = "wipe",
    filetype = "git_beans",
    relative = "editor",
    width = 0,
    height = 0,
    col = 0,
    row = 0,
    style = "minimal",
    border = vim.g.git_beans.border_chars,
    title = "",
    title_pos = "center",
}

---@param content string|string[]
---@param args? Partial<GitBeansWindowOptions>
---@param force? boolean
---@return integer bufnr
function M.push_window(content, args, force)
    if type(content) == "string" then
        content = vim.split(content, "\n", { trimempty = true })
    end
    local opts = vim.tbl_deep_extend("force", default_win, args or {})
    local window_props = {
        relative = opts.relative,
        width = opts.width,
        height = opts.height,
        col = opts.col,
        row = opts.row,
        style = opts.style,
        border = opts.border,
    }
    if opts.title ~= "" then
        window_props.title = opts.title
        window_props.title_pos = opts.title_pos
    end
    ---@type integer|nil
    local buffer = nil
    ---@type integer|nil
    local existing_win = nil
    buffer = vim.iter(vim.api.nvim_list_bufs())
        :filter(function(buf) return vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == opts.filetype end)
        :next()
    if buffer then
        existing_win = vim.iter(vim.api.nvim_list_wins())
            :filter(function(win) return vim.api.nvim_win_get_buf(win) == buffer end)
            :next()
    end

    if window_props.width == 0 then
        window_props.width = math.floor((vim.o.columns - window_props.col) * 0.8)
        if window_props.col == 0 then
            window_props.col = math.floor((vim.o.columns - window_props.width) / 2)
        end
    end
    if window_props.height == 0 then
        window_props.height = math.floor((vim.o.lines - window_props.row) * 0.6)
        if window_props.row == 0 then
            window_props.row = math.floor((vim.o.lines - window_props.height) / 2)
        end
    end

    if buffer and existing_win and vim.api.nvim_win_is_valid(existing_win) then
        -- Buffer/window exists
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, content or {})
        vim.api.nvim_set_current_win(existing_win)
        if force then
            vim.api.nvim_win_set_config(existing_win, window_props)
            vim.api.nvim_set_option_value("modifiable", opts.modifiable, { buf = buffer })
            vim.api.nvim_set_option_value("bufhidden", opts.bufhidden, { buf = buffer })
        end
    else
        -- Create scratch buffer
        buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, content or {})
        vim.api.nvim_set_option_value("modifiable", opts.modifiable, { buf = buffer })
        vim.api.nvim_set_option_value("bufhidden", opts.bufhidden, { buf = buffer })
        vim.api.nvim_set_option_value("filetype", opts.filetype, { buf = buffer })
        vim.api.nvim_open_win(buffer, true, window_props)
    end
    return buffer
end

return M
