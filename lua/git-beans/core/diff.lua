local M = {}

local function read_file_index(path)
    local result = require('git-beans.core').git.run_git({ "show", ":" .. path }, nil)
    if result.stderr and result.stderr ~= "" then return nil end
    return vim.split(result.stdout or "Failed to read", "\n", { trimempty = true })
end

local function read_file(path)
    local core = require('git-beans.core')
    local root = core.git.get_cwd()
    local full_path = root .. "/" .. path
    local fd = io.open(full_path, "r")
    if not fd then return "" end
    local content = fd:read("*a")
    fd:close()
    return content
end

local function setup_hunks(git_patch)
    local hunks = {}
    local current_hunk = nil

    local function hunk_parse(line)
        local hunk = {
            header = line,          -- Used mainly for debugging, can be removed later
            old_start = nil,
            old_count = nil,
            new_start = nil,
            new_count = nil,
            lines = {},
        }
        hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count = line:match("@@%s%-(%d+),?(%d*)%s%+?(%d+),?(%d*)%s@@")
        hunk.old_start = tonumber(hunk.old_start)
        hunk.old_count = tonumber(hunk.old_count ~= "" and hunk.old_count or "1")
        hunk.new_start = tonumber(hunk.new_start)
        hunk.new_count = tonumber(hunk.new_count ~= "" and hunk.new_count or "1")
        return hunk
    end

    local function hunk_line_parse(line, line_num)
        print(line_num)
        local hunk = {
            type = nil,
            text = nil,
            line_num = line_num,
        }
        local first_char = line:sub(1, 1)
        hunk.text = line:sub(2)
        if first_char == "+" then
            hunk.type = "add"
        elseif first_char == "-" then
            hunk.type = "remove"
        elseif first_char == " " then
            hunk.type = "context"
        else
            hunk.type = "meta"
        end
        return hunk
    end

    for _, line in ipairs(git_patch) do
        if line:match("^@@") then
            if current_hunk then
                table.insert(hunks, current_hunk)
            end
            current_hunk = hunk_parse(line)
        elseif current_hunk then
            local last_line_num = 0
            if #current_hunk.lines > 0 then
                local last_line = current_hunk.lines[#current_hunk.lines]
                last_line_num = last_line.type == "remove" and last_line.line_num - 1 or last_line.line_num
            end
            table.insert(current_hunk.lines, hunk_line_parse(line, last_line_num + 1))
        end
    end

    if current_hunk then
        table.insert(hunks, current_hunk)
    end

    return hunks
end

local function setup_regions(hunks, file_lines)
    if not file_lines then return {} end
    local regions = {}
    if #hunks == 0 then
        -- New file, no hunks
        local region = {
            type = "hunk",
            start_line = 1,
            end_line = #file_lines - 1,
            hunk = 1,
        }
        local hunk = {
                old_start = 0,
                old_count = 0,
                new_start = 1,
                new_count = #file_lines - 1,
                lines = {},
        }
        for line_num, line in ipairs(file_lines) do
            table.insert(hunk.lines, { type = "add", text = line, line_num = line_num })
        end
        table.insert(hunks, hunk)
        table.insert(regions, region)
    else
        local current_line = 1
        for hunk_index, hunk in ipairs(hunks) do
            if hunk.new_start > current_line then
                table.insert(regions, {
                    type = "context",
                    start_line = current_line,
                    end_line = hunk.new_start - 1,
                    hunk = nil,
                })
            end
            table.insert(regions, {
                type = "hunk",
                start_line = hunk.new_start,
                end_line = hunk.new_start + hunk.new_count - 1,
                hunk = hunk_index,
            })
            current_line = hunk.new_start + hunk.new_count
        end
        if current_line <= #file_lines - 1 then
            table.insert(regions, {
                type = "context",
                start_line = current_line,
                end_line = #file_lines - 1,
                hunk = nil,
            })
        end
    end
    return regions
end

function M.get_diff(path, section)
    local section = section or "unstaged"
    local core = require('git-beans.core')
    local patch = {
        path = path,
        hunks = nil,
        lines = nil,
        regions = nil,
    }

    if section == "staged" then
        local result = core.git.run_git({ "diff", "--cached", "--", path }, nil)
        if result.stdout then
            local output = vim.split(result.stdout, "\n", { trimempty = true })
            patch.hunks = setup_hunks(output)
        end
        patch.lines = read_file_index(path)
    elseif section == "unstaged" then
        local result = core.git.run_git({ "diff", "--", path }, nil)
        if result.stdout then
            local output = vim.split(result.stdout, "\n", { trimempty = true })
            patch.hunks = setup_hunks(output)
        end
        local content = read_file(path)
        if content then
            patch.lines = vim.split(content, "\n")
        end
    else
        local content = read_file(path)
        if content then
            patch.lines = vim.split(content, "\n")
        end
    end
    if not patch.hunks then patch.hunks = {} end
    patch.regions = setup_regions(patch.hunks, patch.lines)

    return patch
end

local function line_string(line_info, line_number)
    if line_info.type == "add" then
        return "+ " .. tostring(line_number) .. " " .. line_info.text
    elseif line_info.type == "remove" then
        return "- " .. tostring(line_number) .. " " .. line_info.text
    elseif line_info.type == "context" then
        return "  " .. tostring(line_number) .. " " .. line_info.text
    else
        return "? " .. tostring(line_number) .. " " .. line_info.text
    end
end

function M.get_lines(patch)
    if patch.regions and patch.hunks then
        local lines = {}
        local return_good = false
        for _, region in ipairs(patch.regions) do
            return_good = true
            if region.type == "hunk" then
                for _, text in ipairs(patch.hunks[region.hunk].lines) do
                    table.insert(lines, line_string(text, region.start_line + text.line_num - 1))
                end
            elseif region.shown then
                for i = region.start_line, region.end_line do
                    table.insert(lines, patch.lines[i] or "")
                end
            else
                local count = region.end_line - region.start_line + 1
                table.insert(lines, "@@  " .. tostring(count) .. " hidden lines")
            end
        end
        if return_good then return lines end
    end
    if patch.hunks then
        local lines = {}
        for _, hunk in ipairs(patch.hunks) do
            for _, line in ipairs(hunk.lines) do
                table.insert(lines, line.text)
            end
        end
        return lines
    end
    return patch.lines or {}
end

return M
