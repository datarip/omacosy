-- omacosy-theme.lua — Neovim follows omacosy's custom theme.
--
-- `omacosy-term-auto-theme on` links this file into ~/.config/nvim/lua/plugins/,
-- and `off` removes the link. While a custom theme is on screen, omacosy
-- writes ~/.config/omacosy/nvim/palette.lua, and this builds a base16
-- colourscheme from it with mini.base16. On a stock theme that file is gone
-- and your own colourscheme comes back. An open Neovim follows both, because
-- the folder is watched.
--
-- palette.lua is plain data. A config that does not use lazy.nvim can read it
-- with dofile() and use the colours however it likes.

local dir = vim.fn.expand("~/.config/omacosy/nvim")
local file = dir .. "/palette.lua"

-- the colourscheme that was on before ours, so it can come back
local own

local function load()
  local ok, p = pcall(dofile, file)
  if ok and type(p) == "table" and type(p.base16) == "table" then return p end
end

local function apply()
  local p = load()
  if not p then
    if vim.g.colors_name == "omacosy" then
      vim.cmd("hi clear")
      pcall(vim.cmd.colorscheme, own or "default")
    end
    return
  end
  if vim.g.colors_name ~= "omacosy" then own = vim.g.colors_name end
  vim.cmd("hi clear")
  vim.o.background = p.dark and "dark" or "light"
  require("mini.base16").setup({ palette = p.base16, use_cterm = true })
  -- The editor's own background is the terminal's, so its transparency shows
  -- through as it does in the shell. A terminal draws a painted colour solid.
  -- Popups, the status line and selections keep their colour, to stay readable.
  for _, g in ipairs({ "Normal", "NormalNC", "SignColumn", "EndOfBuffer", "LineNr", "FoldColumn" }) do
    local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
    hl.bg = nil
    hl.ctermbg = nil
    vim.api.nvim_set_hl(0, g, hl)
  end
  vim.g.colors_name = "omacosy"
  -- a :terminal inside Neovim wears the same 16 colours as the one outside
  for i, c in ipairs(p.ansi) do vim.g["terminal_color_" .. (i - 1)] = c end
end

-- omacosy replaces the file with a rename, so a watch on the FILE would stop
-- after the first switch. The folder is watched instead, and the burst of
-- events one write makes is folded into one reload.
local function watch()
  vim.fn.mkdir(dir, "p")
  local ev, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
  if not ev or not timer then return end
  ev:start(dir, {}, function()
    timer:stop()
    timer:start(100, 0, vim.schedule_wrap(apply))
  end)
end

return {
  {
    "nvim-mini/mini.base16",
    lazy = false,
    priority = 1000,
    config = function()
      watch()
      -- after VimEnter, so the colourscheme your config sets comes first and
      -- is the one remembered
      vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = apply })
    end,
  },
}
