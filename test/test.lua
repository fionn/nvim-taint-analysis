vim.opt.rtp:prepend(".")
vim.cmd.filetype("on")
local taint = require("taint")

local exit_code = 0

---@param name string
---@param fn fun()
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print(name .. ": ok")
    else
        print(name .. ": failed with " .. err)
        exit_code = math.min(exit_code + 1, 255)
    end
end

---@param path string
---@return integer, integer
local function load_buffer(path)
    assert(vim.uv.fs_stat(path))
    vim.cmd.edit(path)
    return vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
end

test("symbol_and_scope", function()
    local buf, win = load_buffer("test/fixtures/go/a.go")
    assert(vim.bo[buf].filetype == "go")

    -- Place the cursor on the final "b" in the return statement.
    local cursor = {
        word = "b",
        index = {6, 13}
    }
    vim.api.nvim_win_set_cursor(win, cursor.index)
    local word = vim.fn.expand("<cword>")
    assert(word == cursor.word)

    taint.main()

    local extmarks = vim.api.nvim_buf_get_extmarks(buf, taint.ns, 0, -1, {details = true, type = "highlight"})
    local scopes = {}
    local symbols = {}
    for _, extmark in ipairs(extmarks) do
        if assert(extmark[4]).hl_group == "@taint.symbol" then table.insert(symbols, extmark) end
        if assert(extmark[4]).hl_group == "@taint.scope" then table.insert(scopes, extmark) end
    end

    assert(#symbols == 1)
    ---@type vim.api.keyset.get_extmark_item
    local symbol = symbols[1]
    assert(#scopes == 1)
    ---@type vim.api.keyset.get_extmark_item
    local scope = scopes[1]

    -- Sanity-check that the symbol location matches the cursor.
    assert(symbol[2] == cursor.index[1] - 1)
    assert(symbol[3] == cursor.index[2] - 1)
    assert(assert(symbol[4]).end_row == cursor.index[1] - 1)
    assert(assert(symbol[4]).end_col == cursor.index[2])

    assert(scope[2] == 2)
    assert(scope[3] == 15)
    assert(assert(scope[4]).end_row == 6)
    assert(assert(scope[4]).end_col == 1)

    vim.api.nvim_buf_delete(buf, {})
end)

os.exit(exit_code)
