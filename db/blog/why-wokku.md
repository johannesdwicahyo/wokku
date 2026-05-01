---
title: "I Rebuilt Heroku in Six Weeks. Here's Why."
date: 2026-03-15
author: Johannes Dwicahyo
description: "How a 15-year senior dev teamed up with an AI to build an open-source Platform-as-a-Service."
tags: ["architecture", "open-source", "dokku"]
---

*Or: how a 15-year senior dev teamed up with an AI to build a Platform-as-a-Service in a fraction of the time it should have taken.*

---

## The moment I decided to do this

I was moving a side project off Heroku. Again.

For the fourth time that year, I was staring at a bill that didn't make sense. Two small apps, one Postgres, and a Redis for session storage. $73 a month. For something that served maybe 200 requests a day.

I'd done the migration dance before — to Railway when Heroku killed free dynos, to Render when Railway's pricing changed, to Fly.io when I wanted global edge, back to Railway when Fly's networking broke my app. Each move took a weekend. Each one required learning a new dashboard, a new CLI, a new set of environment quirks.

And every time, I'd think: *this is insane. Heroku got it right in 2011. Everything since has been worse in some way.*

The moment that actually made me start building was when Heroku announced they were transitioning to a "sustaining engineering model." If you don't speak corporate, "sustaining engineering" is what companies say when a product is going into maintenance mode. No new features. No meaningful investment. Bug fixes maybe, if they feel like it. The team gets shrunk. The product coasts.

Heroku — *Heroku*, the company that invented the modern PaaS experience, that shaped how an entire generation of developers thinks about deploying web apps — was being quietly put into the drawer. The thing I'd grudgingly kept paying for all those years because the UX was still the best in the market was now officially not going to get better.

That was the moment. Not the bill. Not the migrations. The announcement that Heroku was done pretending to care about individual developers. If the original was going into maintenance, somebody had to build the spiritual successor. Not for enterprise. For us — the side-project people, the indie hackers, the freelancers running five small client apps, the weekend hackers with a portfolio site and a Postgres.

What I actually wanted was simple: push code, get URL, type `rails console` when things broke. The Heroku experience. But without Heroku's pricing, without Heroku's vendor lock-in, and without the creeping dread that my hosting provider might pivot away from individual developers next quarter.

The obvious answer was Dokku. Self-hosted, open source, works like Heroku. I've been running Dokku on a VPS since 2018. It's fantastic.

It also has the worst web interface on the planet, because it doesn't have one.

Dokku is a CLI tool. Every action — deploying an app, adding a database, pointing a domain — is an SSH command. I was fine with that because I'm a terminal person. But whenever I tried to onboard a non-developer friend, the conversation went like this:

> "Can I deploy my WordPress site on your server?"
>
> "Sure, just SSH in and run `dokku apps:create myblog`."
>
> "I don't know what SSH is."
>
> "Ah."

So one morning in March 2026, I opened a new Rails project and typed `rails new wokku`. Not because I had time to build a platform-as-a-service. I run two businesses, I have a family, and I sleep as much as a healthy adult needs to. But because I was tired of watching great open-source infrastructure stay inaccessible to everyone who can't type SSH commands.

This is the story of what I built, what I chose, and why.

---

## What Wokku actually is

Wokku is a web UI for Dokku.

That sentence undersells it. Let me try again: Wokku is a platform-as-a-service that uses Dokku as its deployment engine. You connect one or more Dokku servers (cheap VPSes from anywhere), and Wokku gives you a Heroku-like experience on top: a dashboard, an API, a CLI, a mobile app, and yes, a Claude Code plugin.

The architectural bet is this: **Dokku already solved the hard problem.** It knows how to build buildpack apps. It knows how to manage Docker containers. It knows how to run Postgres with persistent volumes, renew Let's Encrypt certificates, and handle zero-downtime deploys. Every one of those is a rabbit hole I did not want to fall into.

What Dokku doesn't have is presentation, multi-server orchestration, team management, billing, monitoring, templates, a mobile app, or an AI integration. Those are all surface-level concerns that a Rails app can handle beautifully. So I wrote the surface, and I let Dokku do the deep work.

The result: Wokku Community Edition is open source (AGPL-3.0) and runs on any VPS. Wokku.dev is the managed cloud, with pay-per-resource pricing, optimized for the Indonesian market I'm based in.

And here's the part I'm most proud of: **you can host Wokku on Wokku.** The Community Edition ships as a standard Docker Compose app, which means it deploys to Wokku the same way any other web app does. So if you want to run your own Wokku instance but don't want to manage a VPS yourself, you can deploy Wokku on Wokku.dev for about $5/month — a Performance container plus a Basic Postgres tier.

Think about that for a second. The open-source Community Edition — the full thing, all the features, everything — runs on my managed cloud as just another app for the price of a cup of coffee. You get the dashboard, the CLI, the API, the MCP plugin, the whole experience, hosted for you, and the $5 you pay directly supports continued development of the open source project. You're not paying for a "hosted CE" special tier. You're just deploying a Rails app, same as anyone deploying a Rails app, and that app happens to be a PaaS.

This is the purest expression of the business model I could imagine: use the managed cloud if you want convenience, self-host if you want full control, or self-host *on* the managed cloud if you want both. The money goes to the same place either way.

---

## Architectural decisions that mattered

When you build a product fast, every decision compounds. A bad choice in week one costs you weeks in week four. I'm going to walk through the five decisions that made the biggest difference, because most of them went against what I'd have told you was "the right way" five years ago.

### 1. Rails 8.1, not microservices

I've built microservices at scale. I know the arguments. I know when they're worth it. For a product at this stage, they are emphatically not worth it.

Wokku is a monolithic Rails app. One codebase, one database, one deploy. When I need to add a new feature — say, log drains to forward to external services — I don't need to update three services, four queues, and a service mesh config. I add a model, a controller, a job, a view. Twenty minutes, ship.

Rails 8.1 specifically was important because of what I'm going to call next.

### 2. Solid Queue instead of Sidekiq

This one surprised me.

For a decade, Sidekiq has been the default answer for background jobs in Rails. It's rock solid. I've used it on every Rails app I've ever built. But Sidekiq requires Redis, and Redis becomes a whole thing — backups, memory limits, replication, monitoring.

Solid Queue, shipped in Rails 8, uses PostgreSQL as its job store. That's it. No Redis. No separate service. The same database that holds your users and apps also holds your job queue. It's slower than Sidekiq for pure throughput, but "slower" here means "processes thousands of jobs per second instead of tens of thousands." For Wokku's workloads — deploys, backups, health checks, metric polling — it's more than fast enough.

The operational simplification is massive. One less moving part. One less thing to monitor. One less thing for users who self-host to configure. When they do `docker compose up -d`, the job queue is already running because the database is already running.

### 3. Hotwire (Turbo + Stimulus) instead of React

I like React. I've shipped React apps to millions of users. It's fine.

But React would have doubled the size of Wokku for no meaningful benefit. The Wokku dashboard is full of tables, forms, and live updates. Those are exactly what Hotwire is good at. Turbo Streams handle real-time updates — when a deploy finishes, the status chip in the header updates without a page reload and without me writing a single line of JavaScript. Stimulus handles the small interactive bits: dropdowns, tab switchers, search autocomplete. Each controller is 30-50 lines.

The dashboard has about 30 Stimulus controllers total. If I'd written it in React, that would be 30 components plus state management plus an API client plus build tooling. And none of it would be faster, because the bottleneck is the SSH latency to the Dokku server, not the frontend framework.

### 4. Importmap, not bundler

Rails 8 ships with importmaps as the default asset approach. No webpack, no esbuild, no npm install. You pin JavaScript dependencies directly from CDN and the browser's native module loader does the rest.

I was skeptical. I've lived through too many "revolutionary" asset pipelines that turned out to be painful once you actually shipped anything. Importmaps are not painful. I've added XTerm.js for the terminal emulator, Chart.js for metrics, ActionCable for websockets, and Stimulus for interactions — all without a single build step. When I deploy, the whole JS bundle is a few pinned URLs.

Development builds that used to take 15 seconds now take 0 seconds. The mental tax of "oh right, I need to run the JS bundler" is gone.

### 5. Dokku via SSH, not an agent

Here's the most architecturally consequential decision. When Wokku wants to create an app on a connected Dokku server, it opens an SSH connection, runs `dokku apps:create my-app`, and closes the connection.

No agent installed on the target server. No daemon. No API server. No webhook receiver. Just SSH, the same protocol you already use to administer Linux boxes.

This matters for three reasons:

1. **Zero trust.** You give Wokku an SSH private key. Wokku can do exactly what that SSH key is authorized to do, no more. If you delete the key from `~/.ssh/authorized_keys`, Wokku immediately loses all access. No "please wait 15 minutes for the agent to deregister."

2. **Works anywhere.** Wokku can manage a Dokku server on DigitalOcean, Hetzner, Linode, a Raspberry Pi in your closet, your cousin's laptop under the desk, anywhere that has SSH and Docker. No OS package. No firewall hole-punching.

3. **Debuggable.** When something breaks, I can SSH into the server and run the exact same command Wokku ran. There's no black box. The protocol is literally shell commands over SSH. If you can `ssh dokku@server apps:list`, Wokku can manage that server.

The downside is latency. Every operation takes 50-200ms of SSH handshake time. I handle this by opening persistent SSH connections and multiplexing commands. The user doesn't notice.

---

## The open-core bet

I spent longer thinking about licensing and business model than about any specific feature. This was not time well spent at the time, but I'm glad I did it, because the wrong choice here would have killed the project.

Here's the dilemma: if Wokku is fully open source, I compete with my own hosted version. Anyone who doesn't want to pay can clone the repo and run it on a $5 VPS. Good for them, bad for my ability to fund continued development.

If Wokku is fully proprietary, nobody uses it, because why would they trust a closed-source platform when Coolify, Dokku, and CapRover are right there, free?

The answer that most successful open-core projects have converged on is some version of "the software is open, the service is paid." GitLab does this. PostHog does this. Sentry does it now, more or less.

I went with AGPL-3.0 for the Community Edition. AGPL is often called the "strongest copyleft" because it closes the SaaS loophole — if you run a modified version of AGPL code as a service, you have to release your modifications. This prevents AWS-style "we took your open source project, wrapped it, and now we sell it back to your users" scenarios.

Community Edition includes everything a self-hoster needs: the dashboard, API, CLI, all the templates, all the database engines, git push deploys, health checks, SSL, backups. The feature list is intentionally complete. I don't want anyone to self-host and feel nickel-and-dimed.

Enterprise Edition is private. It adds usage-based billing, payment integration (iPaymu and Stripe), dyno tiers with resource enforcement, auto-placement across servers, and a mobile companion app. These are all things you need to *run* a hosted platform, not things you need to use Wokku for your own projects.

The architectural choice I regret and already fixed: I originally had EE as a separate repository that got cloned into a `ee/` subdirectory at build time. The Dockerfile used a secret token to pull in the EE code during `docker build`. This was fragile. Every time I made a change that touched both editions, I had to sync two repos manually. The EE repo went stale. Docker builds broke when the token rotated.

Six weeks in, I migrated to the fork model. Wokku.dev is now a private fork of Wokku that regularly merges from upstream. EE code lives in normal Rails directories — no `ee/` subdirectory, no conditional loading, no concern injection. The deployment is a simple Kamal push from the fork. CE changes flow downstream via `git merge upstream/main`.

This is what GitLab does now. It's what PostHog does. I should have done it from the start, but I was overthinking it. The lesson: when two repos of the same codebase drift apart, the problem is always the *two repos* part.

---

## The AI collaboration part

I should say this upfront: I built Wokku using Claude Code as my primary collaborator. I've been a professional developer for 15 years. I've spent the last six months learning how to program with an AI agent sitting next to me, and it's the most significant shift in how I write code since I learned Ruby in 2009.

Wokku is not "AI-generated." I made every architectural decision. I reviewed every line of code. I rewrote substantial parts when Claude's first pass was wrong or when a pattern emerged that needed refactoring. But the pace — six weeks from empty directory to a working managed cloud with 100+ deployable templates — was only possible because I had an AI doing the grunt work while I made the judgment calls.

The shift looks like this:

**Before AI:** I'd spend 80% of my time implementing and 20% deciding. A feature like "add log drains to forward app logs to external services" would take me two days. Research the Dokku log drain format, implement the model, write the controller, build the UI, add tests, wire up validation, handle errors.

**With Claude Code:** I spend 80% of my time deciding and 20% implementing. The same feature takes an hour. I tell Claude: "Add log drains. Users should be able to add a syslog or HTTPS endpoint per app. Validate the URL format. Create a job that syncs it to the Dokku server. Write integration tests." Claude writes the code, I review, I correct the 20% that's wrong or not my style, I ship.

The constraint is no longer my typing speed. The constraint is my ability to make good decisions quickly.

This has consequences for how you write code. I'm much more willing to experiment with patterns I wouldn't have tried before, because the cost of abandoning an experiment dropped from "a day of work" to "a conversation." I refactor more aggressively, because refactoring is cheap now. I write tests first, because Claude is good at holding the test requirements in context while implementing.

I also lean heavily on spec-before-plan-before-code. For anything non-trivial, I write a specification document first ("what should this do, for whom, with what constraints"), then Claude writes an implementation plan with numbered tasks, then we execute the plan with checkpoints between each task. This sounds bureaucratic. It's actually liberating — I don't have to hold the whole feature in my head at once. I decide once, Claude holds the context, I check in at each step.

If you're a senior developer and you haven't tried programming with Claude Code for a real project yet: do it. Not because AI is going to replace you. Because the craft of programming just evolved, and the tools in your hands right now are more powerful than what you had a year ago.

---

## What this is, really

Wokku is a bet that the infrastructure layer of the web shouldn't be a rent-seeking oligopoly.

Heroku defined what a modern PaaS should feel like, then Salesforce bought them and turned the dials toward extraction. Railway is doing interesting work but it's VC-funded and the valuation math eventually demands higher prices. Render is solid but it's a closed platform, and closed platforms get enshittified on a predictable schedule.

Meanwhile, Dokku — the thing that actually runs the containers, routes the traffic, manages the databases — has been quietly sitting there since 2013 as an MIT-licensed open source project that does the job almost perfectly. The only reason most developers don't use it is that it requires SSH and a little bit of Linux comfort.

Wokku's bet is that if you put a beautiful interface on top of Dokku, expose it through every channel people actually use (web, CLI, API, mobile, AI), and price it at a fraction of Heroku, you've built something that matters.

We'll see if that bet is right. Launch is in a few weeks. If you're reading this and you host small apps, you're my target audience — I'd love for you to try it. It's free to start, the Community Edition is free forever, and the managed cloud starts at zero.

---

**Next in this series:** I'll walk through the actual build — six weeks of decisions, mistakes, and pivots — in a much more day-by-day way. The architectural post is the clean version. The build post is the messy version, which is more honest.

**If you want to try Wokku:** [wokku.dev](https://wokku.dev) is the managed cloud. [github.com/johannesdwicahyo/wokku](https://github.com/johannesdwicahyo/wokku) is the open source repo. Follow me on [Twitter](https://twitter.com/johannesdwi) for build updates.

*Published on Medium by Johannes Dwicahyo. Building [Wokku](https://wokku.dev), the open-source Heroku alternative.*
