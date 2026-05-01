---
title: "Six Weeks to Build a PaaS: What Actually Happened"
date: 2026-03-22
author: Johannes Dwicahyo
description: "A day-by-day account of building Wokku — the mistakes, the architecture, and the 47-feature list."
tags: ["engineering", "behind-the-scenes"]
---

*A day-by-day account of building Wokku from empty directory to a managed cloud with 100+ templates, 57 MCP tools, and a Claude Code plugin. The clean version is the other article. This one is the real version.*

---

## The first commit

The first commit was on March 12, 2026. The commit message was literally `initial commit`, which is the first time I've ever written that without `feat:` in front of it.

I'd been turning the idea over in my head for about a week. I had a rough sketch on paper — dashboard, git push deploys, a REST API. I had a name I wasn't sure about. I had a clear picture of what I didn't want (microservices, React, webpack) and only a vague idea of what I did want.

I opened a terminal, ran `rails new wokku -d postgresql --css tailwind`, and started.

The first thing I built was the Server model. Not the User model, not the App model. The Server. Because Wokku is fundamentally a thing that talks to other servers, and if I couldn't talk to a Dokku server from my Rails app, nothing else mattered.

```ruby
class Server < ApplicationRecord
  encrypts :ssh_private_key

  validates :host, presence: true
  validates :name, presence: true, uniqueness: true

  def ssh_client
    Net::SSH.start(host, ssh_user || "deploy",
      key_data: [ssh_private_key],
      non_interactive: true,
      timeout: 10)
  end
end
```

That's it. The first useful commit was maybe 30 lines of code. I opened a Dokku server I had lying around, added it through a rails console, and ran `Server.first.ssh_client.exec!("dokku version")`. It returned "0.35.7". I laughed out loud. Rails was talking to Dokku.

Everything after that was elaboration.

---

## Week 1: The bones

I'm going to skip ahead through the boring stuff, because week 1 was mostly boring. I set up Devise for authentication. I built the dashboard layout. I added a Server model and a view to create one. I added an AppRecord model (I called it AppRecord because "App" is too generic in a Rails app and conflicts with Rails' own Application class).

The first real decision came on day three: how do I represent Dokku operations in Ruby? Do I shell out directly, or do I build an abstraction?

I went with an abstraction because I knew I'd be calling Dokku commands from dozens of places. The result was `Dokku::Client`, a class that wraps `Net::SSH` and knows how to run Dokku commands:

```ruby
class Dokku::Client
  def initialize(server)
    @server = server
  end

  def run(command)
    @server.ssh_client do |ssh|
      ssh.exec!(command.to_s)
    end
  end

  def apps
    Dokku::Apps.new(self)
  end

  def databases
    Dokku::Databases.new(self)
  end
end
```

Then I had `Dokku::Apps`, `Dokku::Databases`, `Dokku::Domains`, `Dokku::Processes`, each with methods like `create`, `destroy`, `list`, `restart`. Each method was a one-liner that called `@client.run("dokku <verb>:<noun> ...")` and parsed the output.

By end of week 1, I could create an app from the dashboard, point a domain at it, deploy it via git push, and see it running. It was ugly. It had two tests. It had zero security. But it worked.

---

## Week 2: The shape of the product

Week 2 was when I realized how big the product was actually going to be.

Here's what I learned: a PaaS is not one feature. A PaaS is fifty features held together by the pretense of one experience. Heroku has git push deploys, environment variables, add-ons, domains, SSL, logs, metrics, releases, rollbacks, scaling, health checks, teams, permissions, API tokens, OAuth, buildpacks, review apps, pipelines, and like thirty other things I'm forgetting. You think of it as "Heroku" but it's actually a universe of features that cohere because they share a design language and a common workflow.

I made a list. It was 47 items long. I stared at it for a while.

Then I did what you're supposed to do but rarely actually do: I prioritized ruthlessly. I picked the twelve features that, together, would make something usable. Everything else went into a "later" pile.

The twelve:

1. Apps (create, list, destroy)
2. Servers (connect a Dokku server via SSH)
3. Git push deploys (with a receiver on port 2222)
4. Environment variables (set, unset, view)
5. Domains (add, remove, SSL)
6. Databases (create, link, unlink — Postgres only at first)
7. Logs (view, stream)
8. Health checks (path, timeout, attempts)
9. Deploys (history, status)
10. Restart / stop / start
11. Users and OAuth (GitHub login)
12. A dashboard that tied it all together

I built these twelve features in week 2 and half of week 3. Most of them followed the same shape: Rails model, policy for authorization, controller, Stimulus controller for the client bits, and a job for anything that touched SSH (because SSH can take seconds and you don't want that blocking the web request).

The job queue became the single most important part of the architecture. Everything interesting happens asynchronously. A user clicks "Deploy" and the dashboard shows "Deploying..." immediately. In the background, a DeployJob opens an SSH connection, runs the build, streams output to ActionCable, updates the deploy record, and triggers a notification. The user sees live build logs appear in their browser via Turbo Streams.

This async pattern is lifted directly from Heroku. It's the right pattern. Long operations need to be asynchronous, and the user needs real-time feedback, and the feedback needs to work even if they navigate away and come back.

---

## Week 3: Templates, or the accidental core feature

Week 3 started with a realization: nobody cares about a blank PaaS. They care about what they can deploy on it.

Heroku's "Deploy to Heroku" button was their best marketing for years. You'd be on a GitHub README, see the button, click it, and thirty seconds later you'd have a running app. I wanted that. Specifically, I wanted that without requiring template authors to write special metadata files.

The approach I landed on: store templates as raw `docker-compose.yml` files in a directory inside the Wokku repo. Parse them at request time. Each template is a folder like `app/templates/ghost/` with a `docker-compose.yml` that describes the services. No template-specific schema. If you can write a Docker Compose file, you can contribute a Wokku template.

I spent two days writing the first five templates: Ghost, WordPress, Uptime Kuma, n8n, Umami. Each one took longer than expected because I had to understand what the app actually needed (persistent volumes, which env vars, default credentials, health check path). By the fifth template, I had a pattern.

Then I spent a weekend writing a validation script and bulk-adding templates. I'd find a popular open-source project, look at their Docker Compose example, adapt it to Wokku's conventions, test it, commit it. The goal was 50. I shipped 99 on day one of the template push, plus Excalidraw as the 100th to hit the round number.

**Lesson from the template work:** When you're building a platform, the platform itself is not the product. The things users can do with the platform are the product. I could have spent week 3 adding more features. Instead I spent it making sure the platform had things to deploy. That was a better use of time by a factor of ten.

---

## Week 4: The CLI, API, and MCP

By week 4, the dashboard was usable. You could sign up, connect a server, deploy templates, manage domains, scale dynos. It was a product.

Then I remembered that "the dashboard" is only one of the ways people actually use a PaaS.

I use the Heroku CLI more than I use the Heroku dashboard. I bet you do too. The CLI is faster, scriptable, copy-pasteable. Any PaaS without a good CLI is a toy. So I wrote one.

The Wokku CLI is a Ruby gem built with Thor. It has about 40 commands. `wokku apps`, `wokku apps:create NAME --server ID`, `wokku config:set APP KEY=VALUE`, `wokku logs APP --tail`, all the usual stuff. It talks to the REST API.

Which meant I needed a REST API. I'd been putting it off because "the dashboard controllers can be the API too, right?" No, they can't. APIs need different auth (Bearer tokens, not cookies), different response formats (JSON, not HTML), different error shapes, different versioning. I built a parallel `Api::V1::` namespace with its own base controller, its own tokens, its own error handling. 67 endpoints by the time I was done.

Having built the API, I realized something else: there's another channel I should expose. Claude Code's MCP (Model Context Protocol) lets you give an AI agent tools. If you write an MCP server, Claude Code can call those tools on behalf of the user. I thought: what if you could manage your Wokku apps by just *talking* to Claude?

I wrote an MCP server in pure Ruby (stdlib only, no gems, so it can be distributed as a single file). It exposes 57 tools — one for each API endpoint. The tools just forward to the REST API using an API token. "Create app", "set config", "list logs", "scale dynos", "rollback release." All callable from Claude Code.

Then I did the thing that made me proudest that week: I upgraded the MCP server to a full Claude Code plugin with guided skills. A skill is a markdown file Claude reads when invoked. I wrote four:

1. `deploy-new-app` — walks through creating an app, setting config, linking a database, and running `git push`
2. `troubleshoot` — systematic debugging using logs, health checks, deploy history
3. `setup-github-deploy` — connect a GitHub repo for auto-deploy
4. `add-database` — create and link a database with the right env vars

The plugin is published on GitHub as a marketplace. Install it with two lines:

```bash
claude plugin marketplace add johannesdwicahyo/wokku-plugin
claude plugin install wokku@wokku
```

Then you can say things like *"Deploy this project to Wokku as my-app"* and Claude does the whole workflow. It's the most Heroku-feeling thing I've ever built, and Heroku can't do it because Heroku doesn't have an MCP server.

---

## Week 5: The open-core mistake

Week 5 was when I hit my biggest architectural mistake.

I'd decided early on to split Wokku into a public Community Edition and a private Enterprise Edition. Standard open-core stuff. The implementation I chose was two git repositories — `wokku` (public, AGPL) and `wokku-ee` (private, proprietary) — where the EE repo got cloned into an `ee/` subdirectory at Docker build time using a secret token.

This was the model GitLab used for years before they moved to a single repo. I chose it because it sounded clean: CE is public, EE is private, nothing leaks, simple conceptual model.

It was not clean. It was a disaster.

The problems showed up immediately:

**Problem 1: Drift.** I'd develop a feature in the CE repo, test it, ship it. Then three days later I'd realize it touched an EE concern and I needed to update the EE repo too. But I was in the CE directory, the EE repo was a different directory, I was tired, I'd forget. The EE repo started getting stale within the first week.

**Problem 2: The Docker build dance.** The Dockerfile had a conditional clone that used the EE token as a build arg. Build args in Docker are baked into the image layers, which means anyone who pulled my Docker image could extract the token. I had to fix this with `--mount=type=secret`, which works but adds complexity. And every time I rotated the token (which I had to do after one leaked to the CE repo by accident — GitHub push protection caught it, but barely), builds broke.

**Problem 3: The merge pain.** The EE repo had concerns that were injected into CE models via Rails autoloading. Want to add a `subscriptions` association to User? Update the `EeUser` concern in the EE repo, update `config/initializers/ee.rb` to include it, test that the autoloading still works, hope Zeitwerk doesn't break. Every EE feature touched three files across two repos.

**Problem 4: Documentation chaos.** Where do the docs for billing live? Billing is EE-only. So they should be in EE. But the docs system itself is in CE. So when a user visits wokku.dev/docs/billing, which repo served that? (The CE one, loaded from `docs/content/billing/plans.md` that shouldn't exist in CE because it describes EE features.)

I spent two days on week 5 migrating to what I should have done from the start: **a private fork of the CE repo**. Not separate repos. A fork.

The wokku.dev repo is now a private clone of the wokku repo, with an `upstream` remote pointing back. I develop on the fork. When I want to ship something to CE, I cherry-pick or push to upstream. When CE has community contributions, I merge them from upstream into the fork.

All the EE code — billing controllers, Stripe integration, dyno tier enforcement, mobile push notifications — lives in the fork, in normal Rails directories. No `ee/` subdirectory. No conditional loading. No concern injection. No Dockerfile token dance. The deployed application at wokku.dev is just the fork, deployed via Kamal, with the same Rails directory structure you'd have in any normal app.

**Lesson:** When two repositories contain the same codebase, the problem is always that there are two repositories.

This pivot cost me two days. It should have cost me zero, because I should have done it at the start. But I had to live with the pain to understand why the pain existed. That's a thing I've noticed about architecture decisions: you can read about why X is a bad idea, but you don't *know* until you've felt it.

---

## Week 6: The documentation system

By week 6, I had a product that worked. I had a dashboard, a CLI, an API, an MCP plugin, and 100 templates. I had payments via iPaymu. I had backups to S3-compatible storage.

What I didn't have was documentation.

This is a classic engineer mistake: I'd built all the features but had essentially no docs. The only "documentation" was a single HTML file at `/docs` that had hardcoded sections for "Getting Started," "CLI," "API," etc. Each section was about 15 lines long.

A user visiting that page would have no idea what Wokku could do. The MCP plugin wasn't mentioned. Databases weren't explained. Templates had one paragraph. It was embarrassing.

So I built a docs system. I wanted something like Docusaurus — sidebar navigation, nested pages, search, syntax highlighting — but without introducing a separate tool. I wanted everything in Rails.

The solution was a `DocsController` that reads Markdown files from `docs/content/**/*.md` and renders them via CommonMarker + Rouge for syntax highlighting. I wrote a custom preprocessor that handles a `:::tabs` block:

```markdown
:::tabs
::web-ui
Go to **Apps → New App** and click Create.

::cli
\`\`\`bash
wokku apps:create my-app --server my-server
\`\`\`

::api
\`\`\`bash
curl -X POST https://wokku.dev/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name": "my-app", "server_id": 1}'
\`\`\`

::mcp
Ask Claude: *"Create an app called my-app on server 1"*

::mobile
Tap **+** on the Apps screen, enter a name, tap Create.
:::
```

This renders as a tabbed block where the user can pick their preferred channel (Web UI, CLI, API, Claude Code, Mobile). Their choice persists across pages via localStorage. Every page in the docs uses these tabs so a CLI user sees consistent CLI examples throughout, and a mobile user sees mobile examples.

The sidebar is a YAML file. The TOC is auto-generated from H2/H3 headings. Search is a client-side JSON index rebuilt on deploy. Prev/next navigation comes from the sidebar order. Total implementation: about 300 lines of Ruby and 150 lines of Stimulus.

Then I wrote 36 pages of content. It took a day. Half of them are detailed walkthroughs, half are placeholder "Documentation coming soon" that I'll fill in as I go. The sidebar has 14 sections: Getting Started, Apps, Templates, Domains & SSL, Databases, Scaling, Monitoring, Teams, CLI, API, Claude Code, Mobile, Billing, Troubleshooting.

I'm not sure why I'd built everything else before building documentation. I'll know better next time.

---

## The things I broke along the way

Here are the bugs that cost me the most time, in case it helps you:

**The rubocop auto-fix that deleted 50 lines of code.** I ran `rubocop -a` on a branch and it "corrected" several `%w[]` arrays by removing what it thought were unused elements. They weren't unused. I caught it in code review, but if I hadn't been paying attention, I'd have shipped a broken release.

**The Gemfile.lock platform issue.** Rails was frozen to `arm64-darwin` because I develop on a Mac. The Kamal deploy builds on a Linux server. Bundler failed with "You have deleted from the Gemfile" errors that made no sense because I hadn't deleted anything. Fix: `bundle lock --add-platform x86_64-linux`. This cost me half a day.

**The git push protection leak.** I committed `config/deploy.yml` with a GitHub PAT in it. GitHub's secret scanning caught it, blocked the push, and I had to do a full `git filter-repo` rewrite to scrub the token from history. Moved the token to `.kamal/secrets` (gitignored). Added a pre-commit hook to scan for secrets going forward.

**The 10-second SSH timeout.** When I deployed wokku.dev to a new server, all API calls started returning 500 errors with `Net::SSH::ConnectionTimeout`. It wasn't a code bug — the Dokku server was unreachable from the Wokku server because my Linode account had a payment issue and they'd firewalled me. Took me an hour to realize it wasn't my code.

**The docs heading regex.** I wrote a regex to wrap H2/H3 headings with anchor links. It worked on my test Markdown. It broke catastrophically on real content because CommonMarker v2 generates its own anchor structure, and my regex was fighting it. Fix: work *with* CommonMarker's output format instead of *against* it.

**The SimpleCov threshold.** My CI required 60% line coverage. The docs tests ran only the docs controller, which made coverage look like 7%. CI failed. I stared at it for ten minutes before realizing "oh right, I'm only running one controller's tests." Fixed by running the full suite in CI.

None of these were disasters. All of them slowed me down by an hour or more. The moral: when you're moving fast, you make mistakes at a faster rate, and you need rigorous CI and code review to catch them, because your brain is busy making decisions and doesn't have spare capacity to also catch bugs.

---

## How I measure what I built

Six weeks. One person. I had help from Claude Code but I wrote the plan for every feature and reviewed every commit.

Here's what exists now:

- **28 Rails models** (User, Server, AppRecord, Release, Deploy, Domain, Backup, etc.)
- **66 controllers** (dashboard, API v1, webhooks, auth)
- **26 background jobs** (deploys, backups, health checks, metrics, SSL renewal)
- **100 one-click templates** (databases, CMS, monitoring, productivity tools)
- **40 CLI commands** (auth, apps, config, domains, logs, scaling, templates)
- **67 API endpoints** (all resources CRUD + specialized actions)
- **57 MCP tools** (100% API coverage)
- **4 Claude Code skills** (deploy, troubleshoot, github, database)
- **36 documentation pages** (getting started, features, reference, troubleshooting)
- **13 database migrations** for EE billing (plans, subscriptions, invoices, usage)
- **~3700 lines of tests** (unit, integration, system)
- **1 mobile app** (Expo, push notifications via Expo SDK)

I want to be clear: this is not code quality measured by LoC. It's a rough shape of the surface area. The actual quality is in the patterns, the tests, the review process, the architecture. LoC is just "what got shipped."

---

## What I'd do differently

If I were starting over tomorrow, knowing what I know now, here's what I'd change:

1. **Single repo with a fork from day one.** The two-repo model cost me a week of migration pain. Start as a private fork of the public repo. You can always separate later; you can never un-separate easily.

2. **Write docs as you build features, not at the end.** Not because "docs are important" in some abstract sense. Because writing docs forces you to use the feature from the user's perspective, and you catch UX problems early. I found three bugs in the first hour of writing docs.

3. **Start with the API, not the dashboard.** The API is the source of truth. The dashboard, CLI, MCP, and mobile app are all just different shells on the same API. If you build the dashboard first, you'll bake assumptions into your controllers that don't translate to the API cleanly. Build the API first and the dashboard becomes a thin client.

4. **Don't optimize prematurely, but don't skip indexes.** I shipped without database indexes on a few hot paths and got away with it because my test server has five apps in it. In production, this will break immediately. Run `rails db:migrate:status` and `EXPLAIN` on your hot queries before launch.

5. **Test the AI pair-programming workflow early.** Claude Code is a different tool than GitHub Copilot or traditional IDE autocomplete. The "ask Claude to implement a whole feature from a spec" workflow is more productive than "ask Claude to fill in a function." I figured this out in week 3 when I should have figured it out in week 1.

---

## The part where I say what this means

Six weeks is fast. It's not *magic* fast — plenty of people have shipped impressive solo projects quickly. But six weeks for a PaaS with this much surface area is faster than I'd have been able to move five years ago.

The difference isn't that I became a better engineer in six weeks. The difference is that AI pair programming is real, the tools got good, and I figured out how to use them. I spent 80% of week 6 making decisions and reviewing code, not typing. That's the future of senior engineering work, and if you haven't tried it yet, you're about to get very surprised at how much faster the job feels.

There's a reflex in the senior developer community to resist this framing. "AI generates garbage code." "The examples in demos are toy problems." "I'll be laid off." I understand those reflexes. I had them. But after six weeks of actually doing this work, I can tell you that the first two are wrong and the third is only true if you don't adapt.

Wokku isn't an AI story. It's a platform story. But it wouldn't exist without AI pair programming, because I wouldn't have had the six weeks to spare.

---

**Next in this series:** I'll write about wokku.dev specifically — the managed cloud, the decisions around pricing and billing, the Indonesian market focus, and what it means to launch a PaaS in 2026 when the competition is well-funded and established.

**If you want to follow along:** [wokku.dev](https://wokku.dev) is live. [github.com/johannesdwicahyo/wokku](https://github.com/johannesdwicahyo/wokku) is the open source repo. I post build updates on [Twitter](https://twitter.com/johannesdwi).

*Published on Medium by Johannes Dwicahyo. Building [Wokku](https://wokku.dev).*
