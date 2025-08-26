local M = {}

---Get current working directory or path of current file.
---@param use_root? boolean
---@return string
function M.get_cwd(use_root, bufnr)
    local root = vim.g.git_beans.use_root or false
    if use_root ~= nil then root = use_root end
    if root then
        return vim.fn.getcwd()
    else
        bufnr = bufnr or 0
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        if bufname == "" then
            return vim.fn.getcwd()
        else
            return vim.fn.fnamemodify(bufname, ":h")
        end
    end
end

M.run_git = vim.async.wrap(function(args, bufnr, cb)
  if type(args) == "string" then
      args = vim.split(args, "%s+")
  end
  local command = vim.iter({ "git", args }):flatten():totable()
  local options = { text = true, cwd = M.get_cwd(nil, bufnr) }
    vim.system(command, options, function(result)
        cb(result)
    end)
end, 3)

function M.add_file(file_list, callback, bufnr)
    vim.async.void(function()
        local file_set = vim.iter({"add", file_list}):flatten():totable()
        local result = await(M.run_git(file_set, bufnr, callback))
        print(result.stdout)
    end)()
end

---@param bufnr? number Number of buffer command is run from
---@return string
M.status_short = vim.async.fn(function(bufnr)
    local result = await(M.run_git({ "status", "--porcelain=v2", "--branch" }, bufnr))
    local output = result.stdout or result.stderr or "No output from git"
    if result.code ~= 0 then output = "Not a Git repository" end
    return output
end)

---@param bufnr? number Number of buffer command is run from
---@return table
M.status_list = vim.async.fn(function(bufnr)
    local output = await(M.status_short(bufnr))
    local status = vim.split(output.stdout or "", "\n", { trimempty = true })
    local data = {
        branch = {
            head = nil,
            upstream = nil,
            oid = nil,
            ahead = 0,
            behind = 0,
        },
        staged = {},
        unstaged = {},
        untracked = {},
    }
    for _, line in ipairs(status) do
        local first_char = line:sub(1,1)
        if first_char == "1" or first_char == "2" then
            local xy = line:sub(3,4)
            local filename = line:match("%S+$")
            if first_char == "2" then
                local parts = vim.split(line, " ")
                filename = parts[#parts] .. "" .. parts[#parts - 1]
            end
            if xy:sub(1,1) ~= "." then
                table.insert(data.staged, xy:sub(1,1) .. " " .. filename)
            end
            if xy:sub(2,2) ~= "." then
                table.insert(data.unstaged, xy:sub(2,2) .. " " .. filename)
            end
        elseif first_char == "?" then
            local filename = line:sub(3)
            table.insert(data.untracked, "? " .. filename)
        elseif first_char == "#" then
            local key, value = line:match("# ([^ ]+) (.+)")
            if key == "branch.head" then
                data.branch.head = value
            elseif key == "branch.upstream" then
                data.branch.upstream = value
            elseif key == "branch.oid" then
                data.branch.oid = value:sub(1, 8)
            elseif key == "branch.ab" then
                local ahead, behind = value:match("%+(%d+) %-(%d+)")
                data.branch.ahead = tonumber(ahead)
                data.branch.behind = tonumber(behind)
            end
        end
    end
    return data
end)

---@param data? table
---@param bufnr? number Number of buffer command is run from
---@return string[]
M.status_list_visual = vim.async.fn(function(data, bufnr)
    local status = data or await(M.status_list(bufnr)).stdout
    local xyChar = {
        ['M'] = '󰏫',
        ['T'] = '󰤌',
        ['A'] = '',
        ['D'] = '󰧧',
        ['R'] = '',
        ['C'] = '',
        ['U'] = '',
        ['?'] = '',
    }
    local result = {
        lines = {},
        paths = {},
    }
    local function append_line(line, path)
        path = path or ""
        table.insert(result.lines, line)
        table.insert(result.paths, path)
    end
    local function build_tree(items)
        local tree = {}
        for _, entry in ipairs(items) do
            local icon, path = entry:match("^(.-) (.+)$")
            local parts = vim.split(path, "/")
            local node = tree
            for i = 1, #parts - 1 do
                node[parts[i]] = node[parts[i]] or {}
                node = node[parts[i]]
            end
            if type(node[parts[#parts]]) ~= "table" or not node[parts[#parts]].label then
                node[parts[#parts]] = {
                    label = xyChar[icon] .. " " .. parts[#parts],
                    full_path = path,
                }
            end
        end
        return tree
    end
    local function render_tree(tree, indent, parent_path)
        indent = indent or 0
        parent_path = parent_path or ""
        local tree_lines = {}
        local tree_paths = {}
        local sorted_keys = vim.tbl_keys(tree)
        table.sort(sorted_keys)
        for _, key in ipairs(sorted_keys) do
            local value = tree[key]
            local current_path = parent_path .. key .. "/"
            if type(value) == "table" and value.label and value.full_path then
                table.insert(tree_lines, string.rep("  ", indent) .. value.label)
                table.insert(tree_paths, value.full_path)
            elseif type(value) == "table" then
                table.insert(tree_lines, string.rep("  ", indent) .. " " .. key)
                table.insert(tree_paths, current_path)
                local sub_lines, sub_paths = render_tree(value, indent + 1, current_path)
                vim.list_extend(tree_lines, sub_lines)
                vim.list_extend(tree_paths, sub_paths)
            end
        end
        return tree_lines, tree_paths
    end
    local function format_section(name, entries)
        local section_lines = { name .. ":"}
        local section_paths = {""}
        if #entries > 0 then
            local tree = build_tree(entries)
            local tree_lines, tree_paths = render_tree(tree)
            vim.list_extend(section_lines, tree_lines)
            vim.list_extend(section_paths, tree_paths)
        end
        return section_lines, section_paths
    end
    if status.branch.head then
        if status.branch.head == "(detached)" then
            append_line("DETACHED HEAD" .. (status.branch.oid or ""), "")
        else
            local line = status.branch.head
            if status.branch.upstream then
                line = line .. " (" .. status.branch.upstream .. ")"
            end
            if status.branch.oid then
                line = line .. " " .. status.branch.oid
            end
            append_line(line, "")
        end
    end
    if status.branch.ahead > 0 or status.branch.behind > 0 then
        local ab_line = "⇅"
        if status.branch.ahead > 0 then ab_line = ab_line .. " ↑" .. status.branch.ahead end
        if status.branch.behind > 0 then ab_line = ab_line .. " ↓" .. status.branch.behind end
        append_line(ab_line, "")
    end
    append_line("")
    local staged_lines, staged_paths = format_section("Staged", status.staged)
    vim.list_extend(result.lines, staged_lines)
    vim.list_extend(result.paths, staged_paths)
    append_line("")
    local unstaged_lines, unstaged_paths = format_section("Unstaged", status.unstaged)
    vim.list_extend(result.lines, unstaged_lines)
    vim.list_extend(result.paths, unstaged_paths)
    append_line("")
    local untracked_lines, untracked_paths = format_section("Not Tracked", status.untracked)
    vim.list_extend(result.lines, untracked_lines)
    vim.list_extend(result.paths, untracked_paths)
    return result
end)

return M
