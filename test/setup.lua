vim.pack.add({"https://github.com/nvim-treesitter/nvim-treesitter"}, {confirm = false})

---@diagnostic disable-next-line: no-unknown
local ts = require("nvim-treesitter")
ts.install("go"):wait()
