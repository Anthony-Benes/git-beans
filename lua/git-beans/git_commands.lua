---@class GitCommands
local C = {}

---Get current working directory or path of current file.
---@param use_root? boolean
---@return string
function C.get_cwd(use_root)
    return use_root and vim.fn.getcwd() or vim.fn.expand("%:p:h")
end

---Run a Git command using `vim.system`.
---@param args string|string[] Git arguments (string or list of strings)
---@param callback fun(output: string)|nil Callback function receiving Git output
---@param async? boolean Run command with async
---@return string result Command result if not async, do not use if async.
function C.run_git(args, callback, async)
  if type(args) == "string" then
      args = vim.split(args, "%s+")
  end
  local command = vim.iter({ "git", args }):flatten():totable()
  local options = { text = true, cwd = C.get_cwd() }
  local function handle_result(result)
    local output = result.stdout or result.stderr or "No output from git"
    if result.code ~= 0 then
        output = "Not a Git repository"
    end
    if callback then
        callback(output)
    end
    return output
  end
  if async == false then
    local result = vim.system(command, options):wait()
    return handle_result(result)
  else
    vim.system(command, options, function(result)
      vim.schedule(function()
        handle_result(result)
      end)
    end)
    return "RUNNING IN ASYNC"
  end
end

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
local def_win = {
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
function C.push_window(content, args, force)
    if type(content) == "string" then
        content = vim.split(content, "\n", { trimempty = true })
    end
    local opts = vim.tbl_deep_extend("force", def_win, args or {})
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

---@param bufnr integer
---@param lines string[]
function C.apply_ansi_color(bufnr, lines)
    ---@type table<string, string>
    local ansi_to_rgb = {
        ["30"] = "#181C17",
        ["31"] = "#BF4040",
        ["32"] = "#55BF40",
        ["33"] = "#BFB940",
        ["34"] = "#4055BF",
        ["35"] = "#9F40BF",
        ["36"] = "#40BBBF",
        ["37"] = "#D6DDD5",
        ["90"] = "#536250",
        ["91"] = "#D27979",
        ["92"] = "#88D279",
        ["93"] = "#D2CE79",
        ["94"] = "#7988D2",
        ["95"] = "#BC79D2",
        ["96"] = "#79CFD2",
        ["97"] = "#F1F4F1",
    }
    ---@type table<string, boolean>
    local defined_highlights = {}
    ---@param code string
    ---@param styles { bold: boolean, italic: boolean, underline: boolean, strikethrough: boolean }
    ---@return string
    local function get_hl_group(code, styles)
        local name = code
        if styles.bold then name = name .. "_bold" end
        if styles.italic then name = name .. "_italic" end
        if styles.underline then name = name .. "_under" end
        if styles.strikethrough then name = name .. "_strike" end
        if not defined_highlights[name] then
            vim.api.nvim_set_hl(0, name, {
                fg = ansi_to_rgb[code],
                bold = styles.bold or false,
                italic = styles.italic or false,
                underline = styles.underline or false,
                strikethrough = styles.strikethrough or false,
            })
            defined_highlights[name] = true
        end
        return name
    end
    local ESC = string.char(27)
    local esc_pattern = ESC .. "%[([0-9;]*)m"
    for lnum, raw_line in ipairs(lines) do
        ---@type { text: string, color: string?, style: table }[]
        local segments = {}
        local pos = 1
        local current_color = nil
        local current_style = { bold = false, italic = false, underline = false, strikethrough = false, }
        while pos <= #raw_line do
            local s, e, codes = raw_line:find(esc_pattern, pos)
            if s then
                if s > pos then
                    table.insert(segments, {
                        text = raw_line:sub(pos, s - 1),
                        color = current_color,
                        style = vim.deepcopy(current_style),
                    })
                end
                for code in codes:gmatch("%d+") do
                    if code == "0" then
                        current_color = nil
                        current_style = { bold = false, italic = false, underline = false, strikethrough = false, }
                    elseif code == "1" then
                        current_style.bold = true
                    elseif code == "3" then
                        current_style.italic = true
                    elseif code == "4" then
                        current_style.underline = true
                    elseif code == "9" then
                        current_style.strikethrough = true
                    elseif ansi_to_rgb[code] then
                        current_color = code
                    end
                end
                pos = e + 1
            else
                table.insert(segments, {
                    text = raw_line:sub(pos),
                    color = current_color,
                    style = vim.deepcopy(current_style),
                })
                break
            end
        end
        local clean_line = ""
        for _, seg in ipairs(segments) do
            clean_line = clean_line .. seg.text
        end
        lines[lnum] = clean_line
        vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { clean_line })
        local col = 0
        for _, seg in ipairs(segments) do
            local len = #seg.text
            if seg.color then
                local hl_group = get_hl_group(seg.color, seg.style)
                vim.api.nvim_buf_add_highlight(bufnr, -1, hl_group, lnum - 1, col, col + len)
            end
            col = col + len
        end
    end
end

---@return string
function C.status_short()
    local result = C.run_git({ "status", "--porcelain=v2", "--branch" }, nil, false)
    return result
end

---@return table
function C.status_list()
    local status = vim.split(C.status_short(), "\n", { trimempty = true })
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
end

---@param data? table
---@return string[]
function C.status_list_visual(data)
    local status = data or C.status_list()
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
end

return C
