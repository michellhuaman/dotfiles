return {
  {
    "f-person/auto-dark-mode.nvim",
    opts = {
      update_interval = 3000, -- ms between checks
      fallback = "dark",      -- used over SSH or on a TTY
    },
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      flavour = "auto",
      background = { light = "latte", dark = "mocha" },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "catppuccin-nvim" },
  },
}
