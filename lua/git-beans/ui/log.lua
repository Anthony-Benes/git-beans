local M = {}

function M.open_git_log()
    local core = require('git-beans.core')
    local source_buf = vim.api.nvim_get_current_buf()
    local buf = core.window.push_window("Fetching Log...", { filetype = "git_beans" })
    local output = core.git.run_git("log --graph --all --color=always --abbrev-commit --decorate --date=relative --pretty=medium --oneline", source_buf)
    if output.stdout then
        local lines = vim.split(output.stdout, "\n", {trimempty = true })
        if vim.api.nvim_buf_is_valid(buf) then
            core.highlights.apply_ansi_color(buf, lines)
        end
    end
end

return M
