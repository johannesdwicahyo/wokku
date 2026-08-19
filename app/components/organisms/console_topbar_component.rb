module Organisms
  # Slim mobile-only topbar (Twenty-style rail redesign, P0, 2026-08-18).
  # Desktop chrome — workspace switcher, search, notifications, theme,
  # locale, deploy, user menu — all moved into Organisms::ConsoleSidebarComponent.
  # All that's left here is the hamburger that opens the off-canvas rail on
  # mobile (via the existing mobile-nav Stimulus controller) plus the logo,
  # since the rail itself is off-screen on small viewports.
  class ConsoleTopbarComponent < ApplicationComponent
  end
end
