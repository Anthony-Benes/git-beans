local cmds = {
    git = "git",
    gitlog = "git log --oneline --graph --abbrev-commit --decorate --date=relative --all",
}

local M = {}

---@class GitBeansCommand
---@field impl fun(args:string[], opts: table)
---@field complete? fun(arg_lead: string): string[] (optional)

---@type table<string, GitBeansCommand>
M.command = {
    Hello = {
        impl = function(args, opts)
            M.open_hello_window()
        end,
    },
    Status = {
        impl = function(args, opts)
            M.open_git_status()
        end,
    },
    Log = {
        impl = function(args, opts)
            M.open_git_log()
        end,
    },
}

local function GitLog()
    local result = vim.fn.systemlist(cmds.gitlog)
    if vim.v.shell_error ~= 0 then
        result = { "Error running git log.", unpack(result) }
    elseif #result == 0 then
        result = { "No git history found." }
    end
    return result
end

function M.open_hello_window()
    local log = GitLog()
    local height = math.min(#log, 20)
    local width = 100
    local ui = vim.api.nvim_list_uis()[1]
    local row = math.floor((ui.height - height) / 2)
    local col = math.floor((ui.width - width) / 2)
    local win_opts = {
        modifiable = false,
        width = width,
        height = height,
        row = row,
        col = col,
        title = " Git Log ",
        title_pos = "center",
    }
    local buf = require('git-beans.git_commands').push_window(log, win_opts)
    local win = vim.iter(vim.api.nvim_list_wins())
            :filter(function(win) return vim.api.nvim_win_get_buf(win) == buf end)
            :next()
    vim.keymap.set("n", 'q', function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true })
end

function M.open_git_status()
    local git_cmd = require('git-beans.git_commands')
    local ui = vim.api.nvim_list_uis()[1]
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
    local status_buf = git_cmd.push_window("Fetching Status...", status_opts)
    local diff_buf = git_cmd.push_window("Select a file to see diff", {
        filetype = "git_beans_diff",
        width = max_width - status_width - 1,
        height = max_height,
        col = col + status_width + 1,
        row = row,
        title = " Diff Preview ",
    })
    vim.api.nvim_set_option_value("modifiable", false, { buf = status_buf })
    vim.api.nvim_set_option_value("modifiable", false, { buf = diff_buf })
    local status_win = vim.fn.bufwinid(status_buf)
    local diff_win = vim.fn.bufwinid(diff_buf)
    local function close_if_valid(win)
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end
    vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(status_win),
        callback = function()
            close_if_valid(diff_win)
        end,
        desc = "Close diff window when status is closed",
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(diff_win),
        callback = function()
            close_if_valid(status_win)
        end,
        desc = "Close status window when diff is closed",
    })
    vim.schedule(function ()
        local lines = git_cmd.status_list()
        local visual_lines = git_cmd.status_list_visual(lines)
        vim.api.nvim_set_option_value("modifiable", true, { buf = status_buf })
        git_cmd.push_window(visual_lines.lines, status_opts, true)
        vim.api.nvim_set_option_value("modifiable", false, { buf = status_buf })

        vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
            buffer = status_buf,
            callback = function()
                local cursor = vim.api.nvim_win_get_cursor(0)
                local row = cursor[1]
                local path = visual_lines.paths[row]
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
                if path and path ~= "" then
                    path = path:gsub(".*", "")
                    local diff_cmd
                    if row > staged and row < unstaged then
                        diff_cmd = { "diff", "--cached", "--", path }
                    elseif row > unstaged and row < untracked then
                        diff_cmd = { "diff", "--", path }
                    else
                        return
                    end
                    git_cmd.run_git(diff_cmd, function(output)
                        vim.api.nvim_set_option_value("modifiable", true, { buf = diff_buf })
                        local diff_lines = vim.split(output, "\n", { trimempty = true })
                        if output == "" then diff_lines = { "File not tracked" } end
                        vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, diff_lines)
                        vim.api.nvim_set_option_value("modifiable", false, { buf = diff_buf })
                    end)
                else
                    vim.api.nvim_set_option_value("modifiable", true, { buf = diff_buf })
                    vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, { "No file selected" })
                    vim.api.nvim_set_option_value("modifiable", false, { buf = diff_buf })
                end
            end,
        })
    end)
end

function M.open_git_log()
    local git_cmd = require('git-beans.git_commands')
    local buf = git_cmd.push_window("Fetching Log...", { filetype = "git_beans" })
    git_cmd.run_git("log --graph --all --color=always --abbrev-commit --decorate --date=relative --pretty=medium --oneline", function(output)
        local lines = vim.split(output, "\n", {trimempty = true })
        if vim.api.nvim_buf_is_valid(buf) then
            git_cmd.apply_ansi_color(buf, lines)
        end
    end)
end
return M
