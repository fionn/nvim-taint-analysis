local M = {}

local ns = vim.api.nvim_create_namespace("taint")

vim.api.nvim_set_hl(ns, "@taint.assignment", {bg = "#707000", default = true})
vim.api.nvim_set_hl(ns, "@taint.scope", {bg = "#102030", default = true})
vim.api.nvim_set_hl(ns, "@taint.input", {bg = "#204090", default = true})
vim.api.nvim_set_hl(ns, "@taint.definition", {bg = "#905000", default = true})
vim.api.nvim_set_hl(ns, "@taint.symbol", {bg = "#0050f0", default = true})
vim.api.nvim_set_hl(ns, "@taint.virt_text", {fg = "#306090", default = true})

-- Helper to extmark a node.
---@param node TSNode
---@param type string
---@param virtual_text string?
---@return integer id
---@see vim.api.nvim_buf_set_extmark
local function extmark(node, type, virtual_text)
    local virt_text = nil
    if virtual_text then
        virt_text = {{virtual_text, "@taint.virt_text"}}
    end

    local start_row, start_col, end_row, end_col = node:range()
    ---@type vim.api.keyset.set_extmark
    local extmark_opts = {
        end_col = end_col,
        end_row = end_row,
        hl_group = type,
        virt_text = virt_text
    }

    return vim.api.nvim_buf_set_extmark(0, ns, start_row, start_col, extmark_opts)
end

---@param node TSNode
---@param types string[]
---@param decendants TSNode[]?
---@return TSNode[]
local function decendants_of_types(node, types, decendants)
    ---@type TSNode[]
    decendants = decendants or {}

    for child in node:iter_children() do
        if vim.list_contains(types, child:type()) then
            table.insert(decendants, child)
        else
            decendants_of_types(child, types, decendants)
        end
    end

    return decendants
end

-- Query for references, scopes and definitions.
---@param root TSNode
---@param parser vim.treesitter.LanguageTree
---@return Captures
---@nodiscard
local function build_captures(root, parser)
    local query = assert(vim.treesitter.query.get(parser:lang(), "locals"))

    ---@class (exact) Captures
    ---@field scopes TSNode[]
    ---@field definitions TSNode[]
    local captured = {
        scopes = {},
        definitions = {}
    }

    -- For documentation on local queries, see
    -- https://github.com/nvim-treesitter/nvim-treesitter/blob/main/CONTRIBUTING.md#locals,
    -- https://tree-sitter.github.io/tree-sitter/3-syntax-highlighting.html#local-variables.
    for id, node in query:iter_captures(root, 0) do
        local capture = query.captures[id]
        if capture == "local.scope" then
            -- This node introduces a new local scope.
            table.insert(captured.scopes, node)
        elseif vim.startswith(capture, "local.definition") then
            -- This node contains the name of a definition within the local
            -- scope.
            table.insert(captured.definitions, node)
        end
    end

    return captured
end

-- For a given node and list of scopes, find the "smallest" scope containing the
-- node.
---@param node TSNode
---@param scopes TSNode[]
---@return TSNode scope The smallest containing scope
---@nodiscard
local function closest_scope(node, scopes)
    while node do
        if vim.tbl_contains(scopes, node) then
            return node
        end

        -- This assertion is safe, since the root will always be defining a
        -- scope, assuming we included it in the given list of scopes.
        node = assert(node:parent())
    end

    -- We throw here rather than returning the root ("defining errors out of
    -- existence") because we expect to return the root above, in the worst case
    -- scenario, so treat this as an assertion.
    error("Failed to find closest scope")
end

-- Find the scope in the given map that the node is defined in, if it exists.
---@param node TSNode
---@param scope_definitions_map { [string]: TSNode[] }
---@return TSNode? scope, TSNode? definition
---@nodiscard
local function defining_scope(node, scope_definitions_map)
    local text = vim.treesitter.get_node_text(node, 0)

    ---@type TSNode?
    local scope = node
    while scope do
        -- Check if the symbol is a scope by seeing if it's in our map. If so,
        -- we'll iterate over the definitions it contains. If not, we'll select
        -- its parent as a candidate scope and try again.
        local definitions = scope_definitions_map[scope:id()]
        if definitions then
            for _, definition in ipairs(definitions) do
                if vim.treesitter.get_node_text(definition, 0) == text then
                    return scope, definition
                end
            end
        end

        scope = scope:parent()
    end

    -- For symbols that aren't defined anywhere, e.g. struct fields or language
    -- builtins like "true", there's nothing sensible to return.
    return nil, nil
end

-- For a given scope node, find all assignments within it.
---@param node TSNode
---@param accumulator TSNode[]?
---@return TSNode[] assignments
local function assignments_in_scope(node, accumulator)
    local assignment_types = {"assignment_statement", "short_var_declaration"}
    accumulator = accumulator or {}

    if vim.list_contains(assignment_types, node:type()) then
        table.insert(accumulator, node)
    end

    for child in node:iter_children() do
        assignments_in_scope(child, accumulator)
    end

    return accumulator
end

M.clear = function()
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

M.main = function()
    M.clear()
    vim.api.nvim_win_set_hl_ns(0, ns)

    local parser = assert(vim.treesitter.get_parser())
    -- We parse the whole tree first, just in case. See
    -- https://neovim.io/doc/user/treesitter/#vim.treesitter.get_node().
    assert(parser:parse())

    local node = assert(vim.treesitter.get_node())
    local node_row, node_col = node:range()
    local root = node:tree():root()
    local captures = build_captures(root, parser)

    -- A map from a scope ID to definitions it contains.
    ---@type { [string]: TSNode[] }
    local definitions_in_scope_id = {}
    for _, def in ipairs(captures.definitions) do
        local scope_id = closest_scope(def, captures.scopes):id()
        definitions_in_scope_id[scope_id] = definitions_in_scope_id[scope_id] or {}
        table.insert(definitions_in_scope_id[scope_id], def)
    end

    local scope, definition = defining_scope(node, definitions_in_scope_id)
    -- If no scope, it's maybe imported or similar, so just abort.
    if scope == nil then return end
    assert(definition)

    ---@type TSNode[], TSNode[]
    local assignees, inputs = {}, {}
    for _, assignment in ipairs(assignments_in_scope(scope)) do
        local assignment_row, assignment_col = assignment:range()
        if assignment_row <= node_row and not (assignment_row == node_row and assignment_col > node_col) then
            local left = assignment:field("left")[1]
            for i = 0, left:named_child_count() - 1 do
                local left_child = assert(left:named_child(i))
                if left_child:type() == "identifier" then
                    local _, child_definition = defining_scope(left_child, definitions_in_scope_id)
                    if child_definition and child_definition:id() == definition:id() then
                        table.insert(assignees, left_child)
                        for right_child in assignment:field("right")[1]:iter_children() do
                            for _, identifier in ipairs(decendants_of_types(right_child, {"identifier"})) do
                                if not node:equal(identifier) then
                                    table.insert(inputs, identifier)
                                end
                            end
                        end
                        break
                    end
                end
            end
        end
    end

    for _, assignee in ipairs(assignees) do
        extmark(assignee, "@taint.assignment", "Assignment")
    end

    for _, input in ipairs(inputs) do
        extmark(input, "@taint.input")
    end

    extmark(scope, "@taint.scope")
    extmark(definition, "@taint.definition", "Definition")
    extmark(node, "@taint.symbol", "Symbol")
end

return M
