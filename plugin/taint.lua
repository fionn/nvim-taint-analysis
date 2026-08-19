if vim.g.loaded_taint_analysis then
    return
end

vim.g.loaded_taint_analysis = true

vim.keymap.set("n", "T", function() require("taint").main() end, {desc = "Taint and mark source"})
