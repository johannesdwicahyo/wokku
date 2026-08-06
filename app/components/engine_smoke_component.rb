# Phase 1b engine smoke: a ViewComponent defined in the engine, used to prove
# (a) engine components autoload and render, and (b) Tailwind scans engine
# template paths — the marker class must survive the production CSS purge.
class EngineSmokeComponent < ViewComponent::Base
end
