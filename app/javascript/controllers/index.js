// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
// Lazy-load: each controller module is fetched only when an element with its
// data-controller appears in the DOM, instead of eager-loading all ~42 on
// every page. The landing used only 3 of 42 yet downloaded all of them
// (49 of 58 requests). Paired with `preload: false` on the controllers pin
// in config/importmap.rb so they're not module-preloaded either.
lazyLoadControllersFrom("controllers", application)
