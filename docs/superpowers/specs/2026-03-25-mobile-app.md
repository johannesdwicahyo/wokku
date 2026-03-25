# Wokku Mobile App — Product Specification

## Vision

**"Deploy and manage your cloud from your pocket."**

A native mobile app (iOS + Android) that gives Wokku users full control over their apps, databases, and servers — from deploying a Waha instance while waiting for coffee, to checking deploy logs during a commute, to restarting a crashed app at 2am from bed.

No competitor offers this. It's Wokku's biggest differentiator.

## Target Users

1. **Hobbyist deployers** — Want to spin up n8n, Waha, Ghost from their phone. Zero CLI knowledge.
2. **Developers on the go** — Need to check deploy status, view logs, restart apps when away from laptop.
3. **Ops/on-call** — Get push notification about crash, investigate and fix from phone.

## Tech Stack

| Component | Choice | Why |
|---|---|---|
| **Framework** | React Native + Expo | Single codebase, easy App/Play Store deploy, large ecosystem |
| **Navigation** | React Navigation 7 | Standard for RN, tab + stack navigation |
| **State** | Zustand | Lightweight, simple, no boilerplate |
| **API** | Fetch + React Query | Caching, background refresh, optimistic updates |
| **WebSocket** | ActionCable client (@rails/actioncable) | Match existing Rails WebSocket |
| **Terminal** | react-native-terminal-ui or custom | For log streaming (not full SSH terminal in MVP) |
| **Push Notifications** | Expo Notifications + FCM/APNs | Cross-platform push |
| **Auth** | Secure keychain storage (expo-secure-store) | Token persistence |
| **Theme** | Wokku dark theme (#0B1120, green-500) | Match dashboard exactly |

## Repository

- **Repo:** `johannesdwicahyo/wokku-mobile` (private, EE)
- **Structure:** Expo managed workflow
- **Monorepo?** No — separate repo, communicates via REST API

## API Requirements

The mobile app uses the **existing Wokku REST API** (`/api/v1/`). Current endpoints already cover most needs:

| Endpoint | Mobile Use | Exists? |
|---|---|---|
| `POST /api/v1/auth/login` | Login | Yes |
| `GET /api/v1/auth/whoami` | Session check | Yes |
| `GET /api/v1/apps` | App list | Yes |
| `GET /api/v1/apps/:id` | App detail | Yes |
| `POST /api/v1/apps/:id/restart` | Restart | Yes |
| `POST /api/v1/apps/:id/stop` | Stop | Yes |
| `POST /api/v1/apps/:id/start` | Start | Yes |
| `GET /api/v1/apps/:id/logs` | Logs | Yes |
| `GET /api/v1/apps/:id/config` | Env vars | Yes |
| `PUT /api/v1/apps/:id/config` | Update env vars | Yes |
| `GET /api/v1/apps/:id/domains` | Domains | Yes |
| `GET /api/v1/servers` | Server list | Yes |
| `GET /api/v1/servers/:id/status` | Server health | Yes |
| `GET /api/v1/databases` | Database list | Yes |
| `GET /api/v1/notifications` | Notifications | Yes |
| **NEW: `GET /api/v1/templates`** | Template gallery | **Need to add** |
| **NEW: `POST /api/v1/templates/deploy`** | Deploy template | **Need to add** |
| **NEW: `POST /api/v1/devices`** | Register push token | **Need to add** |
| **NEW: `GET /api/v1/apps/:id/deploys`** | Deploy history | **Need to add** |
| **NEW: `GET /api/v1/billing/usage`** | Billing summary (EE) | **Need to add** |

### New API Endpoints Needed (before mobile development)

```ruby
# Templates API
GET  /api/v1/templates              # List all templates
GET  /api/v1/templates/:slug        # Template detail
POST /api/v1/templates/deploy       # Deploy a template { slug, app_name, server_id }

# Deploy history
GET  /api/v1/apps/:id/deploys       # List deploys for an app
GET  /api/v1/apps/:id/deploys/:id   # Deploy detail with log

# Push notification device registration
POST   /api/v1/devices              # Register { token, platform }
DELETE /api/v1/devices/:token       # Unregister

# Billing (EE)
GET /api/v1/billing/usage           # Current cycle usage summary
```

## Screens & Navigation

### Tab Bar (bottom)

```
[Apps]  [Templates]  [Servers]  [Activity]  [Settings]
```

### Screen Hierarchy

```
Tab: Apps
├── Apps List (home screen)
│   ├── App Detail
│   │   ├── Overview (status, domains, last deploy)
│   │   ├── Logs (live streaming)
│   │   ├── Config (env vars, edit)
│   │   ├── Domains (list, SSL status)
│   │   ├── Deploys (history, tap to see log)
│   │   │   └── Deploy Log (streaming output)
│   │   └── Actions (restart, stop, start, delete)
│   └── Create App (name, server)

Tab: Templates
├── Template Gallery (search, categories)
│   └── Template Detail
│       └── Deploy Form (name, server) → Deploy Log

Tab: Servers
├── Server List (health badges)
│   └── Server Detail
│       ├── Apps on this server
│       ├── Databases
│       └── Backups

Tab: Activity
└── Activity Feed (recent actions, pull-to-refresh)

Tab: Settings
├── Profile
├── Billing (EE) — usage, payment method
├── Notifications (push preferences)
├── API Tokens
└── Logout
```

## Screen Designs (Dark Theme)

### Color Palette

```
Background:     #0B1120
Card:           #1E293B (60% opacity)
Border:         #334155 (50% opacity)
Primary:        #22C55E (green-500)
Primary Hover:  #16A34A (green-600)
Text Primary:   #FFFFFF
Text Secondary: #94A3B8 (gray-400)
Text Muted:     #64748B (gray-500)
Danger:         #EF4444
Warning:        #EAB308
Info:           #3B82F6
```

### Typography

```
Headings:    IBM Plex Sans, 600-700 weight
Body:        IBM Plex Sans, 400-500 weight
Code/Mono:   JetBrains Mono, 400-500 weight
```

### Key Screen Specs

#### Apps List
- Pull-to-refresh
- Search bar at top
- Cards: app name (mono), status dot (green/red/gray), server name, domain
- Tap → App Detail
- FAB (floating action button) → "+" to create app or deploy template

#### App Detail
- Header: app name, status badge, server
- Quick actions row: Restart / Stop / Start (icon buttons)
- Tabs: Overview | Logs | Config | Domains | Deploys
- **Logs tab:** Auto-scrolling monospace text, green on dark, streaming via WebSocket
- **Config tab:** List of KEY=VALUE, tap to edit, swipe to delete
- **Deploys tab:** List of deploys with status badges, tap for log

#### Template Gallery
- Search bar
- Category pills (horizontal scroll)
- Grid of template cards (2 columns)
- Card: icon emoji + name + description + addon badges
- Tap → Template Detail → Deploy Form

#### Deploy Form
- Template info card at top
- App name input (mono font, lowercase validation)
- Server picker (dropdown)
- "Deploy" button (green, full width)
- → Redirects to Deploy Log screen with live streaming

#### Deploy Log
- Terminal-style output (monospace, dark background)
- Status badge at top (Building → Succeeded/Failed)
- Auto-scroll
- Duration counter

## Push Notifications

### Events

| Event | Notification Title | Body |
|---|---|---|
| `deploy_succeeded` | Deploy Succeeded | {app} deployed successfully ({commit}) |
| `deploy_failed` | Deploy Failed | {app} deploy failed |
| `app_crashed` | App Crashed | {app} has crashed on {server} |
| `backup_completed` | Backup Complete | {database} backed up successfully |
| `backup_failed` | Backup Failed | {database} backup failed |
| `health_check_failed` | Server Unreachable | {server} is not responding |
| `ssl_expiring` | SSL Expiring | {domain} SSL expires in 7 days |

### Implementation

1. App registers device token on login via `POST /api/v1/devices`
2. Server stores `{ user_id, device_token, platform (ios/android) }`
3. `NotifyJob` sends push via Expo Push API alongside existing channels
4. User configures which events trigger push in Settings

### Server-Side Changes (CE)

```ruby
# New model: DeviceToken
class DeviceToken < ApplicationRecord
  belongs_to :user
  validates :token, presence: true, uniqueness: true
  validates :platform, inclusion: { in: %w[ios android] }
end

# New migration
create_table :device_tokens do |t|
  t.references :user, null: false
  t.string :token, null: false
  t.string :platform, null: false
  t.timestamps
end

# Updated NotifyJob — add push notification channel
when "push"
  send_push(notification, deploy, event)
```

## Offline & Performance

- **Caching:** React Query caches API responses; show stale data while refreshing
- **Offline banner:** Show "No connection" banner, disable mutations
- **Optimistic updates:** Restart/stop/start show new status immediately, revert on failure
- **Background refresh:** Auto-refresh app list every 30 seconds when visible
- **Image caching:** Template icons cached locally

## Authentication Flow

```
1. App launch → Check secure keychain for stored token
2. If token exists → Verify with GET /api/v1/auth/whoami
   - Valid → Navigate to home (Apps list)
   - Invalid → Navigate to Login
3. Login screen:
   - Email + Password form
   - "Sign in with GitHub" button (OAuth via in-app browser)
   - "Sign in with Google" button
4. On success → Store token in secure keychain
5. Biometric unlock:
   - After first login, prompt "Enable Face ID / Touch ID?"
   - On subsequent launches, verify biometric → auto-login with stored token
```

## Build & Release

```
Expo EAS Build
├── iOS → TestFlight → App Store
└── Android → Internal Testing → Play Store

CI/CD: GitHub Actions
├── On push to main → EAS Build (preview)
├── On tag v* → EAS Build (production) → Submit to stores
```

### App Store Metadata

```
Name: Wokku
Subtitle: Deploy Apps from Your Pocket
Category: Developer Tools / Utilities
Keywords: deploy, hosting, dokku, paas, cloud, server, devops
```

## Development Phases

### Phase 1 — MVP (2 weeks)
- Login (email/password)
- Apps list + detail
- Restart/stop/start
- Template gallery + deploy
- Live deploy logs
- Push notifications (deploy success/failure)

### Phase 2 — Full Feature (2 weeks)
- Log streaming
- Config management (view/edit env vars)
- Domain management
- Deploy history
- Server health dashboard
- GitHub OAuth login
- Biometric unlock

### Phase 3 — Polish (1 week)
- Billing overview (EE)
- Database management + backup trigger
- iOS widget (app status)
- Android quick-tile (recent app shortcuts)
- Haptic feedback on destructive actions
- Deep linking (open deploy from push notification)

## File Structure

```
wokku-mobile/
├── app/                          # Expo Router file-based routing
│   ├── (tabs)/                   # Tab navigator
│   │   ├── index.tsx             # Apps list
│   │   ├── templates.tsx         # Template gallery
│   │   ├── servers.tsx           # Server list
│   │   ├── activity.tsx          # Activity feed
│   │   └── settings.tsx          # Settings
│   ├── apps/
│   │   └── [id].tsx              # App detail
│   ├── templates/
│   │   └── [slug].tsx            # Template detail + deploy
│   ├── deploys/
│   │   └── [id].tsx              # Deploy log
│   ├── servers/
│   │   └── [id].tsx              # Server detail
│   └── login.tsx                 # Auth screen
├── components/
│   ├── AppCard.tsx
│   ├── TemplateCard.tsx
│   ├── StatusBadge.tsx
│   ├── DeployLog.tsx
│   ├── LogViewer.tsx
│   └── ...
├── lib/
│   ├── api.ts                    # API client (fetch + auth headers)
│   ├── websocket.ts              # ActionCable client for streaming
│   ├── auth.ts                   # Secure storage, biometric
│   ├── push.ts                   # Push notification registration
│   └── theme.ts                  # Colors, fonts, spacing
├── stores/
│   ├── auth.ts                   # Zustand auth store
│   └── apps.ts                   # Zustand app state
├── app.json                      # Expo config
├── eas.json                      # EAS Build config
└── package.json
```

## API Endpoints to Add Before Mobile Development

These endpoints need to be added to the CE API before starting mobile:

### 1. Templates API

```ruby
# app/controllers/api/v1/templates_controller.rb
module Api::V1
  class TemplatesController < BaseController
    def index
      registry = TemplateRegistry.new
      templates = if params[:q].present?
        registry.search(params[:q])
      elsif params[:category].present?
        registry.by_category(params[:category])
      else
        registry.all
      end
      render json: { templates: templates, categories: registry.categories }
    end

    def show
      registry = TemplateRegistry.new
      template = registry.find(params[:id])
      return render json: { error: "Not found" }, status: :not_found unless template
      render json: template
    end

    def deploy
      registry = TemplateRegistry.new
      template = registry.find(params[:slug])
      return render json: { error: "Template not found" }, status: :not_found unless template

      server = current_user.teams.flat_map(&:servers).find { |s| s.id == params[:server_id].to_i }
      return render json: { error: "Server not found" }, status: :not_found unless server

      app = AppRecord.create!(
        name: params[:app_name].parameterize,
        server: server, team: server.team, creator: current_user,
        deploy_branch: "main", status: :deploying
      )
      deploy = app.deploys.create!(status: :pending, description: "Template: #{template[:name]}")

      TemplateDeployJob.perform_later(
        template_slug: template[:slug], app_name: app.name,
        server_id: server.id, user_id: current_user.id, deploy_id: deploy.id
      )

      render json: { app: app, deploy: deploy }, status: :created
    end
  end
end
```

### 2. Deploy History API

```ruby
# app/controllers/api/v1/deploys_controller.rb
module Api::V1
  class DeploysController < BaseController
    def index
      app = AppRecord.find(params[:app_id])
      authorize app, :show?
      deploys = app.deploys.order(created_at: :desc).limit(20)
      render json: deploys
    end

    def show
      app = AppRecord.find(params[:app_id])
      authorize app, :show?
      deploy = app.deploys.find(params[:id])
      render json: deploy
    end
  end
end
```

### 3. Device Token API

```ruby
# app/controllers/api/v1/devices_controller.rb
module Api::V1
  class DevicesController < BaseController
    def create
      token = current_user.device_tokens.find_or_initialize_by(token: params[:token])
      token.platform = params[:platform]
      token.save!
      render json: { registered: true }
    end

    def destroy
      current_user.device_tokens.find_by(token: params[:id])&.destroy
      render json: { unregistered: true }
    end
  end
end
```

### Routes to Add

```ruby
namespace :api do
  namespace :v1 do
    resources :templates, only: [:index, :show] do
      collection do
        post :deploy
      end
    end
    resources :apps do
      resources :deploys, only: [:index, :show]
    end
    resources :devices, only: [:create, :destroy]
  end
end
```

## Success Metrics

| Metric | 3-Month Target |
|---|---|
| App Store downloads | 500+ |
| Play Store downloads | 1,000+ |
| Monthly active users | 200+ |
| App Store rating | 4.5+ |
| Push notification opt-in | 80%+ |
| Template deploys from mobile | 100+/month |

## Timeline

| Week | Milestone |
|---|---|
| Pre-work | Add missing API endpoints to CE |
| Week 1 | Expo setup, auth, app list, app detail |
| Week 2 | Templates, deploy, deploy logs, push notifications |
| Week 3 | Servers, activity, config management, domains |
| Week 4 | Polish, biometric, offline, widgets |
| Week 5 | TestFlight/Internal Testing, bug fixes |
| Week 6 | App Store/Play Store submission |
