local M = {}

local function refresh_status(state)
    local core = require('git-beans.core')
    state.status.lines = core.git.status_list(state.status.buf)
    state.status.visual_lines = core.git.status_list_visual(state.lines, state.status.buf)
    vim.api.nvim_set_option_value("modifiable", true, { buf = state.status.buf })
    vim.api.nvim_buf_set_lines(state.status.buf, 0, -1, false, state.status.visual_lines.lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = state.status.buf })
end

local function get_file_context(row, visual_lines)
    local staged, unstaged, untracked = nil, nil, nil
    for index, value in ipairs(visual_lines.lines) do
        if value == "Staged:" then
            staged = index
            if unstaged ~= nil and untracked ~= nil then break end
        end
        if value == "Unstaged:" then
            unstaged = index
            if staged ~= nil and untracked ~= nil then break end
        end
        if value == "Not Tracked:" then
            untracked = index
            if unstaged ~= nil and staged ~= nil then break end
        end
    end
    local path = visual_lines.paths[row]
    if not path or path == "" then return nil
    end
    path = path:gsub(".*", "")
    if staged and unstaged and row > staged and row < unstaged then
        return { path = path, section = "staged", }
    elseif unstaged and untracked and row > unstaged and row < untracked then
        return { path = path, section = "unstaged", }
    elseif untracked and row > untracked then
        return { path = path, section = "untracked", }
    end
    return nil
end

local function setup_status_buffer(state)
    local core = require('git-beans.core')
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        buffer = state.status.buf,
        callback = function()
            state.active = "status"
            if not vim.api.nvim_buf_is_valid(state.diff.buf) then return end
            local cursor = vim.api.nvim_win_get_cursor(0)
            local row = cursor[1]
            local context = get_file_context(row, state.status.visual_lines)
            if context then
                state.selected_context = context
                local diff = require('git-beans.core.diff')
                local diff_lines = diff.get_diff(context.path, context.section)
                vim.api.nvim_set_option_value("modifiable", true, { buf = state.diff.buf })
                vim.api.nvim_buf_set_lines(state.diff.buf, 0, -1, false, diff.get_lines(diff_lines))
                vim.api.nvim_set_option_value("modifiable", false, { buf = state.diff.buf })
            else
                vim.api.nvim_set_option_value("modifiable", true, { buf = state.diff.buf })
                vim.api.nvim_buf_set_lines(state.diff.buf, 0, -1, false, { "No file selected" })
                vim.api.nvim_set_option_value("modifiable", false, { buf = state.diff.buf })
            end
        end,
    })

    vim.keymap.set("n", "<Space>", function ()
        local row = vim.api.nvim_win_get_cursor(state.status.win)[1]
        local context = get_file_context(row, state.status.visual_lines)
        if not context then
            return
        end
        if context.section == "staged" then
            core.git.run_git({"restore", "--staged", "--", context.path}, state.status.buf)
        elseif context.section == "unstaged" then
            core.git.run_git({"add", "--", context.path}, state.status.buf)
        elseif context.section == "untracked" then
            core.git.run_git({"add", "--", context.path}, state.status.buf)
        end
        refresh_status(state)
    end, { buffer = state.status.buf, desc = "Stage/Unstage file", silent = true, })
end

local function setup_diff_buffer(state)
    --local core = require('git-beans.core')
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        buffer = state.diff.buf,
        callback = function()
            state.active = "diff"
        end,
    })
    vim.keymap.set("n", "<Space>", function ()
        if state.active ~= "diff" then return end
        if not state.selected_context then return end
        print("Would stage selection for:", state.selected_context)
    end, { buffer = state.diff.buf, desc = "Stage/Unstage hunk", silent = true, })
end

local function create_status_ui()
    local layout = {
        tabpage = nil,
        status = {
            buf = nil,
            win = nil,
        },
        diff = {
            buf = nil,
            win = nil,
        },
    }
    local core = require('git-beans.core')
    local ui = vim.api.nvim_list_uis()[1]
    if vim.g.git_beans.status_new_tab then
        -- Create tab layout
        vim.cmd.tabnew()
        layout.tabpage = vim.api.nvim_get_current_tabpage()
        layout.status.buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_option_value("buftype", "nofile", { buf = layout.status.buf })
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = layout.status.buf })
        vim.api.nvim_set_option_value("swapfile", false, { buf = layout.status.buf })
        vim.api.nvim_set_option_value("filetype", "git_beans", { buf = layout.status.buf })
        vim.api.nvim_win_set_buf(0, layout.status.buf)
        layout.status.win = vim.api.nvim_get_current_win()
        vim.cmd.vsplit()
        layout.diff.buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_option_value("buftype", "nofile", { buf = layout.diff.buf })
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = layout.diff.buf })
        vim.api.nvim_set_option_value("swapfile", false, { buf = layout.diff.buf })
        vim.api.nvim_set_option_value("filetype", "diff", { buf = layout.diff.buf })
        vim.api.nvim_win_set_buf(0, layout.diff.buf)
        layout.diff.win = vim.api.nvim_get_current_win()
        vim.api.nvim_set_current_win(layout.status.win)
        local max_width = math.floor(ui.width)
        local status_width = math.floor(max_width * 0.3)
        vim.api.nvim_win_set_width(layout.status.win, status_width)
    else
        -- Create floating window layout
        local max_width = math.floor(ui.width * 0.8)
        local max_height = math.floor(ui.height * 0.8)
        local status_width = math.floor(max_width * 0.3)
        local row = math.floor((ui.height - max_height) / 2)
        local col = math.floor((ui.width - max_width) / 2)
        local status_opts = {
            filetype = "git_beans",
            width = status_width,
            height = max_height,
            col = col,
            row = row,
            title = " Git Status ",
        }
        layout.status.buf = core.window.push_window("Fetching Status...", status_opts)
        layout.diff.buf = core.window.push_window("Select a file to see diff", {
            filetype = "diff",
            width = max_width - status_width - 1,
            height = max_height,
            col = col + status_width + 1,
            row = row,
            title = " Diff Preview ",
        })
        layout.status.win = vim.fn.bufwinid(layout.status.buf)
        layout.diff.win = vim.fn.bufwinid(layout.diff.buf)
    end
    return layout
end

function M.open_git_status()
    local state = {
        active = "status",
        selected_context = nil,
        tabpage = nil,
        status = {
            buf = nil,
            win = nil,
            lines = nil,
            visual_lines = nil,
        },
        diff = {
            buf = nil,
            win = nil,
            patch = nil,
        },
    }
    state.status.buf = vim.api.nvim_get_current_buf()
    local layout = create_status_ui()
    state.status.buf = layout.status.buf
    state.status.win = layout.status.win
    state.diff.buf = layout.diff.buf
    state.diff.win = layout.diff.win
    state.tabpage = vim.api.nvim_get_current_tabpage()

    local function close_if_valid(win)
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end
    if vim.g.git_beans.status_new_tab then
        local function close_tab()
            if state.tabpage and vim.api.nvim_tabpage_is_valid(state.tabpage) then
                vim.schedule(function()
                    if vim.api.nvim_tabpage_is_valid(state.tabpage) then
                        vim.api.nvim_set_current_tabpage(state.tabpage)
                        vim.cmd.tabclose()
                    end
                end)
            end
        end
        vim.api.nvim_create_autocmd("WinClosed", {
            pattern = tostring(state.status.win),
            callback = close_tab,
            desc = "Close tab when status is closed",
        })
        vim.api.nvim_create_autocmd("WinClosed", {
            pattern = tostring(state.diff.win),
            callback = close_tab,
            desc = "Close tab when diff is closed",
        })
    else
        vim.api.nvim_create_autocmd("WinClosed", {
            pattern = tostring(state.status.win),
            callback = function()
                close_if_valid(state.diff.win)
            end,
            desc = "Close diff window when status is closed",
        })
        vim.api.nvim_create_autocmd("WinClosed", {
            pattern = tostring(state.diff.win),
            callback = function()
                close_if_valid(state.status.win)
            end,
            desc = "Close status window when diff is closed",
        })
    end
    vim.api.nvim_set_current_win(state.status.win)
    refresh_status(state)
    setup_status_buffer(state)
    setup_diff_buffer(state)
    vim.api.nvim_set_current_win(state.status.win)
end

return M
