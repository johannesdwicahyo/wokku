---
title: "Launching a PaaS in 2026: Why I'm Betting on Indonesia"
date: 2026-04-01
author: Johannes Dwicahyo
description: "Market analysis, pricing strategy, and unit economics for an Indonesian-first PaaS."
tags: ["business", "indonesia", "launch"]
---

*The third in my Wokku series. This one's about the managed cloud at wokku.dev — the business decisions, the market bet, and what it actually costs to run a Heroku alternative.*

---

## The first two articles were about the technology. This one is about the business.

If you've read the first two posts, you know that Wokku is an open-source Heroku alternative. The software is AGPL-3.0, it uses Dokku as its deployment engine, and anyone can self-host it on a VPS. That's the Community Edition, and it's done. It works. You can clone the repo right now, run `docker compose up -d`, and have a Heroku-like PaaS running on your own server inside ten minutes.

But open source doesn't pay rent. I've had businesses in the past that other people now run for me, I have a wife, I have five Pomeranians who expect to be fed on schedule, and the sustained existence of Wokku depends on whether I can turn the open source project into a sustainable business. The managed cloud at [wokku.dev](https://wokku.dev) is how I'm trying to do that.

This post is about the decisions that went into wokku.dev: who I'm targeting, how I priced it, which payment processors I chose, what it actually costs me to run, and why I'm betting heavily on the Indonesian market in a space dominated by Silicon Valley.

I'll be specific with numbers, because I hate vague business posts that talk about "unit economics" without ever showing a single unit.

---

## The launch context

Here's the landscape wokku.dev is launching into:

**Heroku** is still the gold standard for PaaS UX, but Salesforce gutted the free tier in 2022 and the pricing has crept up every year since. A basic Postgres + dyno setup now runs $25+/month for the smallest useful configuration. Heroku is also US-centric: their cheapest regions are US-East and EU, and they don't have data centers in Asia at all, which means 200ms latency for my users in Jakarta.

**Railway** is the fashionable choice right now. Beautiful product. Well-funded. Decent pricing, but it's a VC-backed company and the math eventually demands higher margins. I love Railway, but I've seen this movie before — the early-stage pricing never lasts.

**Render** is solid, mature, works well. Priced similarly to Railway. Same VC-funded trajectory. Not a lot of regional presence outside the US.

**Fly.io** is interesting because of the edge model, but the networking is complex and I've seen enough "Fly.io broke my app" stories from friends that I don't trust it for production workloads.

**Coolify** is the closest competitor philosophically. Open source. Self-host or managed cloud. Great product. They're also well ahead of me in the market. They don't have an Indonesian payment processor and they don't have a Claude Code plugin, which are my two biggest differentiators.

**DigitalOcean App Platform** exists. It's fine. Nobody I know loves it.

**AWS Elastic Beanstalk** and **Google App Engine** exist. People who use them in 2026 mostly inherited the decision from someone else.

My positioning, in one sentence: **the lowest-priced Heroku-alternative with a real Indonesian payment option and a Claude Code integration that nobody else has.**

That's a narrow wedge, but narrow wedges are how you enter a market.

---

## Why Indonesia

I live in Indonesia. I've run businesses here. I understand the market. Those are the honest reasons.

Here are the strategic reasons:

**1. The developer population is huge and growing fast.** Indonesia has the fourth-largest population in the world (280+ million). There are more professional software developers in Jakarta than in most European capitals. The government has a major push toward digital transformation. The number of Indonesian startups has roughly doubled in the last five years.

**2. The payment infrastructure is fragmented and terrible for foreign SaaS.** Here's something that doesn't make headlines in English-language tech media: most Indonesian developers can't easily pay for Heroku, Railway, or Render. Credit card penetration in Indonesia is under 5%. Foreign SaaS services that only accept credit cards are effectively inaccessible to most developers. The ones who do have cards often have monthly spending limits that make $50+ PaaS subscriptions painful.

What Indonesians actually use is QRIS (the national QR-based payment standard), bank transfers, and virtual accounts. No foreign PaaS I'm aware of accepts any of these. This is a huge unserved market.

**3. Price sensitivity is high.** The median developer salary in Indonesia is roughly 10-15% of the equivalent US salary. A $25/month Heroku bill is the equivalent of $200-250/month for a US developer. Indonesian developers are not going to pay that for a side project.

Wokku at $1-4/month for comparable resources isn't just "cheaper" in the abstract — it's the difference between "I can't afford this" and "I can afford this with my lunch money."

**4. The timing is right.** Indonesian tech is at an inflection point. A few years ago the ecosystem was dominated by marketplaces and fintech. Now there's a wave of small B2B SaaS, indie developer projects, and AI-adjacent startups that all need hosting. They've been cobbling together VPS setups because the managed options weren't accessible. I think they'll take a proper PaaS if it's priced for them.

**5. I can actually serve them.** This is the obvious point but I need to say it. I speak Bahasa Indonesia. I understand the payment systems. I know the local dev community. I can do customer support in the timezone. A US-based PaaS serving Indonesia has an uphill battle on all of these. I don't.

The counter-argument is: "Why not start with the US market, where the spending power is higher?" Because the US market is saturated. Railway, Render, Vercel, Netlify, and Heroku are all fighting for the same customers with massive war chests. Indonesia has one credible competitor (Coolify, and they don't have local payments). I'd rather be the best option in a smaller market than the fifth option in a bigger one.

---

## Who Wokku.dev is actually for

Let me be concrete about who I'm building this for, because "serve Indonesia" is too vague to be useful.

The two target groups are **hobbyists** and **UMKM** (Usaha Mikro, Kecil, dan Menengah — micro, small, and medium enterprises, which is the Indonesian term for small businesses). These groups overlap heavily in Indonesia because many UMKM owners are themselves the technical person running their own infrastructure.

### The hobbyist

A hobbyist is a developer who wants to run side projects without thinking about servers. They have a portfolio site, a Telegram bot they built for fun, a weather dashboard for their apartment, maybe a small tool they made for their team at work that they maintain in their spare time.

They currently run these on:
- A Raspberry Pi under the desk (unreliable, breaks during power outages)
- A shared hosting provider for $2-3/month (Wordpress only, no custom apps)
- A VPS they manually configure with Nginx and systemd (works, but every deploy is a chore)
- Heroku's free tier back when it existed, then nothing, because the alternatives cost too much

For them, Wokku.dev is the thing that gives them the Heroku experience at Raspberry Pi prices. $1.50/month for a Basic container is less than a cup of coffee. You can run a small Node.js app, a Telegram bot, or a personal dashboard indefinitely for pocket change. The free tier is enough for prototypes and demos.

### The UMKM

This is the market I'm most excited about, and the one nobody in Silicon Valley is paying attention to.

Indonesian small businesses — a warung, a local retail shop, a small agency, a hair salon, a coffee shop, a dental clinic — increasingly need software to run. Not "enterprise software." Practical tools. The three I see over and over again:

- **[Waha](https://waha.devlike.pro/)** — a WhatsApp HTTP API that lets small businesses build chatbots and automations on top of WhatsApp, which is how everyone in Indonesia actually communicates with their customers
- **[n8n](https://n8n.io)** — a workflow automation platform (think Zapier, but self-hosted and way cheaper) that UMKM owners use to sync data between WhatsApp, Google Sheets, their POS system, and their accounting software
- **[NocoDB](https://nocodb.com)** or **[Baserow](https://baserow.io)** — open-source Airtable alternatives for tracking inventory, customers, orders, and schedules without paying foreign SaaS fees in dollars

These tools are free and open source. They're exactly what a small Indonesian business needs. The problem is that running them requires a server, a database, reverse proxy config, SSL certificates, backup scripts, and enough Linux knowledge to put it all together. Most UMKM owners can't do that and can't afford to hire someone who can.

Wokku solves this in one click. On the templates page, the owner picks Waha or n8n, selects a server, clicks Deploy, and three minutes later they have a working URL. They pay $5-10/month for container + database + domain + SSL + daily backups. They get WhatsApp to the edge without touching SSH. That's life-changing for a small business that's been running everything through personal phone numbers and manual spreadsheets.

This is the part that gets me out of bed. I'm not trying to build the next unicorn. I'm trying to make it possible for a coffee shop in Bandung to run n8n and automate their ordering flow without hiring a developer. That's a market nobody's serving because the math doesn't work for a VC-backed PaaS — you can't build a billion-dollar company charging $5/month to UMKM. But you *can* build a sustainable business, and you can actually help people.

### Who Wokku.dev is NOT for (right now)

To be clear about positioning:

- **Production enterprise workloads** — we're in beta. Not yet.
- **Apps with strict SLA requirements** — same reason
- **Users who want multi-region edge deployment** — Fly.io is better for this
- **Users who need managed Kubernetes** — use a real managed K8s service
- **Very large apps needing dozens of containers** — the sweet spot is 1-10 containers per app

If you're building the next Gojek, Wokku.dev isn't the right tool. If you're building a WhatsApp automation for a UMKM client, or running a side project, or hosting a small internal tool, it's exactly the right tool.

---

## The pricing model

I spent more time on pricing than on any single technical feature. This is probably the most important decision in the entire project.

Here's what I landed on:

### App Containers

Billed per hour, capped at the monthly maximum. This is Heroku's hourly model.

| Tier | RAM | vCPU | Hourly | Max/month |
|------|-----|------|--------|-----------|
| Free | 256 MB | 0.15 | $0.000 | $0 |
| Basic | 512 MB | 0.3 | ~$0.002 | $1.50 |
| Standard | 1 GB | 0.5 | ~$0.005 | $4 |
| Performance | 2 GB | 1.0 | ~$0.011 | $8 |
| Performance 2x | 4 GB | 2.0 | ~$0.021 | $15 |

The Free tier sleeps after 30 minutes of inactivity, same as Heroku's old Eco dynos. This is how I keep free users from eating my server capacity.

### Databases

Also hourly with monthly caps, same pattern:

| Tier | Storage | Connections | Backups | Retention | Max/month |
|------|---------|-------------|---------|-----------|-----------|
| Mini | 1 GB | 20 | Manual (2 max) | 1 day | $0 |
| Basic | 4 GB | 50 | Daily auto | 7 days | $1 |
| Standard | 16 GB | 120 | Daily auto | 14 days | $4 |

The backup retention is the part I spent the most time calculating, because backups are the part that can quietly destroy my margins.

### The math, with real numbers

Let me show you the economics of one resource, because nobody ever does this and it's the most useful part of a pricing post.

**Standard database, $4/month, 16 GB storage, 14-day retention.**

My cost breakdown per user per month:

- Server CPU/RAM for the database container: roughly $0.80 (based on my Contabo VPS costs of $96/mo for 96 GB RAM, 18 vCPU, divided across the containers I can fit)
- Storage on the VPS for the live database: ~$0.15 (16 GB worst case, NVMe)
- Backup storage on Cloudflare R2 (16 GB × 14 days × 30% gzip compression = 67 GB): $1.00
- Bandwidth for backups: $0 (R2 has no egress fees)
- Payment processing fees (iPaymu): ~$0.12 (3% of $4)
- Email notifications, monitoring, misc: ~$0.10

**Total cost: ~$2.17**
**Revenue: $4.00**
**Margin: 46%**

That's the worst case. A more typical user runs a database at 2-5 GB, which cuts backup storage dramatically:

- Server: $0.80
- Storage: $0.05
- Backups (5 GB × 14 × 0.3 = 21 GB): $0.32
- Payment fees: $0.12
- Misc: $0.10

**Total: $1.39**
**Margin: 65%**

Free tier users cost me almost nothing because they're sleeping most of the time and their databases are tiny. Basic and Standard paid users produce 50-70% margins.

**The Performance tiers have worse margins** because the server cost scales linearly with RAM/CPU allocation. A Performance 2x dyno at 4 GB RAM costs me around $3 in server capacity, against $15 revenue. 80% margin, but that's because most of the price is paying for raw capacity I'm reserving.

The blended margin across all paid tiers, assuming a realistic distribution (lots of Basic, some Standard, a few Performance), works out to about 60-65%. That's healthy for a PaaS.

### Why hourly with monthly cap

I could have priced this as a flat monthly fee — "pay $4 and get a Standard database for the month." Cleaner, simpler to understand.

I went with hourly pricing because:

1. **Users often run resources for part of the month.** If you deploy a staging environment for a week of testing, you shouldn't pay the same as someone running it for 30 days. Hourly makes this fair.

2. **Upgrades and downgrades are painless.** With flat pricing, switching from Basic to Standard mid-month is a billing nightmare. With hourly pricing, you pay the old rate until the hour you switch, then the new rate after.

3. **It's what Heroku does.** Users understand this model already.

4. **The monthly cap removes the anxiety.** The main downside of hourly pricing is "will I accidentally rack up a huge bill?" The cap prevents that. You know the maximum you can pay. It's always the shown price.

---

## Payment processing: the most important decision

This is the part where most foreign PaaS attempts fail in Indonesia, so I'm going to be specific.

### iPaymu for local payments

I integrated iPaymu as the primary payment processor for Indonesian users. iPaymu supports:

- QRIS (the national QR payment standard — works with GoPay, OVO, Dana, all the major e-wallets)
- Bank transfer (automated via BI-FAST)
- Virtual accounts (BCA, Mandiri, BNI, BRI)
- Credit card (but this is the smallest channel)

The integration was surprisingly straightforward. iPaymu has a REST API that lets you create a payment, receive a webhook when it's completed, and get back a reference ID. I wired it into a standard Rails webhook controller that verifies the signature and updates the invoice status. About 200 lines of code.

The fees are higher than Stripe (3% vs 2.9% + 30 cents), but for small transactions under $5, iPaymu is actually cheaper because there's no flat fee component.

### Stripe for international

For users outside Indonesia, I also support Stripe (credit card + international payment methods). This is important because:

1. Some Indonesian users prefer to pay with international cards for business accounts
2. The Community Edition is available globally, and I want to serve self-hosters who want to contribute financially
3. The Claude Code plugin is going to attract users globally, not just in Indonesia

The dual-processor setup makes the code more complex. I have a `BillingCalculator` service that generates invoices, and separate `IpaymuClient` and `StripeBillingService` classes that handle the payment creation. The invoice model tracks which processor was used so refunds and reporting work.

### Why not just Stripe

Stripe works fine in Indonesia technically. Many Indonesian businesses use it. The problem is the end-user experience: Stripe's default flow asks for a credit card, and most Indonesian users don't have one. You can enable local payment methods in Stripe, but they don't work as smoothly as iPaymu's native integration.

iPaymu's conversion rate for Indonesian transactions is dramatically higher than Stripe's for the same customer base. I'll take the higher fees for the conversion lift any day.

---

## The infrastructure cost reality

Let me walk through what it actually costs me to run wokku.dev, because I've seen too many PaaS posts that gloss over this.

### Current setup

- **Compute:** 1 Contabo VPS. 18 vCPU, 96 GB RAM, 700 GB NVMe. $96/month.
- **Backups:** Cloudflare R2 for database backups. No egress fees. Pay per GB stored ($0.015/GB/month). Currently ~$5/month.
- **CDN + DNS:** Cloudflare (free tier). DNS, basic DDoS protection, SSL.
- **Email:** Resend for transactional email (deploy notifications, billing, password resets). $20/month for their base plan.
- **Error tracking:** Sentry. $26/month for the team plan.
- **Monitoring:** Built into the app itself. Solid Queue handles job metrics, custom Stimulus dashboards for server health.
- **Domain:** wokku.dev is $24/year from Namesilo. Negligible.

**Total monthly fixed costs: ~$148**

### Capacity at this setup

The 96 GB RAM server can run roughly:

- 150-200 free tier apps (they sleep most of the time, so effective RAM usage is low)
- 30-40 Basic/Standard paid apps (active use)
- 50-80 databases of various tiers
- The Wokku control plane itself (Rails app, background jobs, Postgres for the control plane)

That's enough capacity for about 200 active users. When I hit that, I add a second server.

### Break-even analysis

Fixed costs are $148/month. The blended margin on paid users is ~60%. To break even, I need paid user revenue of $148 / 0.60 = **$247/month**.

At an average of $4/user/month (a realistic mix of Basic and Standard tiers), that's **62 paying users**. I think I can get to 62 paying users in 3-6 months with moderate marketing and word-of-mouth in the Indonesian dev community.

At 150 paying users I'm generating about $600/month, of which $300-400 is profit after infrastructure. That's enough to justify continued development but not a salary. At 500 paying users I'm generating about $2000/month which is enough to pay someone to handle customer support.

I'm not trying to build a unicorn. I'm trying to build a sustainable small business that serves a market that's currently underserved. The math for that is very different from the math for a VC-backed startup.

---

## The unit economics of free users

This is the part nobody talks about but everyone worries about. "What if all your users are on the free tier and you go broke?"

Here's how free users cost me:

- **Compute:** Essentially free. Eco dynos sleep after 30 minutes. Cold start wakes them up, they serve the request, they go back to sleep. A free dyno uses maybe 30 seconds of CPU per day. On a 96 GB server, I can host thousands of sleeping free dynos.

- **Database storage:** Each free tier database is 1 GB max. Most use 100-500 MB. A thousand free tier databases would use 100-500 GB of disk, which is at the edge of my current server's capacity but not impossible.

- **Backup storage:** Free tier gets manual backups only, max 2 stored, 1-day retention. A thousand free users doing one manual backup each = 500 MB to 1 GB of R2 storage. Negligible cost.

- **Bandwidth:** No egress fees on R2 for backups, no bandwidth fees on Contabo for normal traffic, Cloudflare handles the edge.

- **Support:** Free users occasionally ask questions. This is where costs can spiral if I'm not careful. I've set up a community Discord and a FAQ page to handle most questions without direct intervention.

The bottom line: free users cost me a few cents each per month in variable costs, plus whatever support time I invest. A thousand free users costs me maybe $20-30/month in infrastructure. That's sustainable as long as a reasonable fraction of them eventually upgrade.

The conversion lever I'm relying on: **free tier limits**. You get 1 free container, 1 free database, 1 free cache. When you hit those limits, you're prompted to upgrade. This is Heroku's model and it works — the friction of hitting a limit converts users more reliably than marketing.

---

## The Claude Code plugin as distribution strategy

Here's a thing I didn't plan on but ended up being important.

I built the MCP server and Claude Code plugin for Wokku because I thought it was cool. "Manage your apps by talking to Claude" — that's a fun demo. I wrote four guided skills (deploy, troubleshoot, GitHub setup, add database) and published the plugin on my own GitHub marketplace.

Then I submitted it to the official Claude Code plugin marketplace. Vercel is there. Firebase is there. Supabase is there. AWS has one. All of them bundle their official MCP server with some skills for common workflows.

If Wokku gets into the official marketplace, every Claude Code user who types `/plugin` sees Wokku listed alongside Vercel. That's distribution I can't buy.

It's also a differentiation I can't replicate easily. Being first to market with a high-quality Claude Code plugin for PaaS deployment is a moat while it lasts. Railway, Render, Fly — none of them have one yet. Heroku has no interest in building one.

The other angle is developer marketing. Every AI-forward developer is experimenting with Claude Code right now. If their first experience with "deploy with Claude" is Wokku, that's a powerful association. They'll remember which PaaS "just worked" with their AI workflow, and that's the one they'll recommend.

I'm betting pretty hard on this angle.

---

## What could kill this

I've been thinking about failure modes, because every business plan sounds great until reality shows up.

**1. I don't grow.** The biggest risk. I build the product, launch, and nobody uses it because I don't have a distribution channel that works. Marketing is the weakest part of my plan. I'm a builder, not a marketer. I'll need to learn.

**2. The Contabo server blows up.** I'm running everything on one VPS right now. If that server dies — hardware failure, data center issue, Contabo going out of business — I lose everything. I need redundancy before I scale, which means a second server plus replication, which adds cost and complexity. This is the next big technical investment.

**3. iPaymu has an outage or policy change.** Payment processor risk is real. If iPaymu changes their fees, policies, or reliability, my Indonesian revenue takes a hit immediately. I mitigate by also supporting Stripe, so users can switch processors if needed.

**4. Heroku or Railway decides to compete on price.** If Heroku announced "new hobby tier for $2/month" tomorrow, my pricing advantage evaporates. I think this is unlikely because their cost structures are much higher than mine (bigger teams, US-based operations, investor pressure), but it's possible.

**5. The AGPL license scares away enterprise adopters.** AGPL is less permissive than MIT, and some enterprises are allergic to it. If a big customer wants to embed Wokku's Community Edition in a closed-source product, AGPL blocks that. I think this is fine — the point of AGPL is to prevent exactly that — but it's a lever I can't pull later without breaking my commitments to existing CE users.

**6. A single security incident.** A PaaS that gets hacked loses customer trust instantly. I'm obsessive about security — API tokens are hashed, SSH keys are encrypted at rest, secrets never appear in logs, pre-commit hooks scan for credentials — but I'm one person. The attack surface is larger than I can fully audit. I'll need a formal security review before I have any serious customers.

**7. My own burnout.** I've been building this at a sustainable pace so far, but I've also been lucky — my wife has been patient, the dogs haven't staged a revolt, no fires I had to put out personally. If any of that changes, Wokku could stall for weeks or months.

None of these are showstoppers, but they're all real. I'm watching each of them.

---

## What I want from launch

Here's what I'm hoping happens in the first 90 days after launch:

- **100 signups** from organic channels (mostly the Indonesian dev community, plus whatever I can get from this blog series and Hacker News)
- **10 paying customers** converted from the free tier
- **5 Dokku servers** connected across different cloud providers (proving the multi-provider story)
- **1 Claude Code plugin install** from a user I don't personally know (proving the distribution angle)
- **$50 in monthly recurring revenue** (tiny, but it's the first dollar that proves the model works)
- **Zero security incidents**
- **Zero downtime incidents longer than 10 minutes**

That's the realistic goal. If I hit all of those, I'll know the product has legs and I should keep going. If I don't, I'll know something's wrong and I need to diagnose what.

If I hit twice those numbers, I'll start thinking about hiring someone part-time for support.

---

## The broader bet

Zooming way out: I think the managed cloud infrastructure market is going to look very different in five years than it does today.

The incumbents — AWS, Google Cloud, Azure — have won the enterprise layer and will continue to dominate it for decades. The middle tier — Heroku, Railway, Render, Vercel, Netlify — is going to get progressively squeezed as VC demands higher margins and users demand better pricing.

The bottom tier, which is where I'm playing, is wide open. Developers who want a Heroku experience at a price that makes sense for side projects, indie hacking, and small businesses don't have a great option today. There are pieces of the solution scattered across Dokku, Coolify, CapRover, and dozens of smaller projects, but nothing that puts it all together in a way that's accessible to non-experts.

Wokku is my attempt to put it all together. The technical pieces are proven — Dokku works, Rails works, SSH works, the combination works. What hasn't been proven yet is that there's a sustainable business here. That's what the next 12 months will test.

If it works, I'll have built a thing I'm proud of that serves a population I care about. If it doesn't, I'll have learned a lot and open-sourced a lot of code that other people can build on.

Either way, it's time to launch.

---

## If you want to try it

[wokku.dev](https://wokku.dev) is live (in public beta). Sign up is free, no credit card. Deploy a template in under a minute.

If you're a **hobbyist** with a side project: this is exactly what you're looking for. $1.50/month for a small container, free tier to get started, one-click templates for the usual suspects.

If you run a **UMKM or small business** that needs to self-host tools like Waha, n8n, NocoDB, Vaultwarden, Uptime Kuma, or any of the 100+ templates we ship: this is the product I built for you. You don't need to know SSH, you don't need to configure a server, you don't need to pay in dollars. Try deploying Waha or n8n from the templates page — three minutes and you have a working URL.

If you're a **developer anywhere** and you have a side project Heroku is overcharging you for: try it. Let me know what you think. File issues. Tell me what's broken.

If you're an **open source maintainer** and you'd like Wokku to have a one-click deploy button for your project: I'd love to add it. The template format is a standard Docker Compose file. Open a PR to the repo.

And if you build AI tools or are in the Claude Code ecosystem: I'd love your feedback on the MCP plugin. It's at [github.com/johannesdwicahyo/wokku-plugin](https://github.com/johannesdwicahyo/wokku-plugin). The skills are markdown files, easy to contribute to.

---

**This is the third and final post in the "Building Wokku" series.** The first two are about the "why" and the "how." This one was about the business. If you liked this, the other two are on my Medium.

If you want to follow the ongoing build, I post on [Twitter](https://twitter.com/johannesdwi) most days. I'll write more after launch about what worked, what didn't, and what I had to change.

Thanks for reading. Now I'm going to go ship.

*Published on Medium by Johannes Dwicahyo. Building [Wokku](https://wokku.dev), the open-source Heroku alternative. AGPL-3.0. Based in Indonesia, serving the world.*
