# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Self-hosted webfonts live under public/fonts/ (NOT app/assets/fonts/)
# because Tailwind v4's CSS doesn't go through propshaft's url() rewriter
# and propshaft only serves fingerprinted URLs. Files in public/ are
# served verbatim. See public/fonts/ + @font-face blocks in
# app/assets/tailwind/application.css.
