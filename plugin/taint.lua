if vim.g.loaded_taint_analysis then
    return
end

vim.g.loaded_taint_analysis = true

vim.keymap.set("n", "T", function() require("taint").main() end, {desc = "Taint and mark sources and sinks"})

vim.api.nvim_create_user_command("TaintClear", function(_) require("taint").clear() end, {desc = "Clear taint analysis highlights"})
