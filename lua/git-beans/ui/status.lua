local M = {}

function M.open_git_status()
    local core = require('git-beans.core')
    local source_buf = vim.api.nvim_get_current_buf()
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
    local status_buf = core.window.push_window("Fetching Status...", status_opts)
    local diff_buf = core.window.push_window("Select a file to see diff", {
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
        local lines = core.git.status_list(source_buf)
        local visual_lines = core.git.status_list_visual(lines, source_buf)
        vim.api.nvim_set_option_value("modifiable", true, { buf = status_buf })
        core.window.push_window(visual_lines.lines, status_opts, true)
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
                    core.git.run_git(diff_cmd, function(output)
                        vim.api.nvim_set_option_value("modifiable", true, { buf = diff_buf })
                        local diff_lines = vim.split(output, "\n", { trimempty = true })
                        if output == "" then diff_lines = { "File not tracked" } end
                        vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, diff_lines)
                        vim.api.nvim_set_option_value("modifiable", false, { buf = diff_buf })
                    end, nil, source_buf)
                else
                    vim.api.nvim_set_option_value("modifiable", true, { buf = diff_buf })
                    vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, { "No file selected" })
                    vim.api.nvim_set_option_value("modifiable", false, { buf = diff_buf })
                end
            end,
        })
    end)
end

return M
