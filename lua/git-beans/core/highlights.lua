local M = {}

---@param bufnr integer
---@param lines string[]
function M.apply_ansi_color(bufnr, lines)
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

return M
