---
title: Personal vs Org Workspaces
summary: "Every Wokku account starts with one personal workspace. Org workspaces are for shared work — paid plans only, billed to the workspace owner."
eyebrow: workspaces
last_updated: 2026-05-29
---

# Personal vs Org Workspaces

Wokku scopes everything (apps, resources, billing, audit log) to a **workspace**. There are two kinds:

— **Personal** — every account gets one at signup. Free forever, lives alongside any org membership.
— **Org** — created on demand for shared work with other people. Requires a paid plan; the creator becomes its owner.

You're always inside *one* workspace at a time. The [switcher](/docs/workspaces/switching) in the topbar tells you which one and lets you change it.

## Personal workspace

Every signup gets a personal workspace, free. It's yours, you can't leave or delete it — it's tied to your account.

What lives here:

— Apps you deploy without explicitly switching workspaces
— Your free-tier resources (1 box of any size, 1 Postgres, 1 Redis, 1 MinIO bucket)
— Your personal billing and invoices (when you upgrade)
— Your personal seat — no one else can join your personal workspace

What's not here:

— You can't add members
— You can't invite collaborators
— You can't transfer apps in from an org workspace (use [app transfer](/docs/apps/lifecycle) for that)

Think of it as your dev sandbox: side projects, prototypes, the demo you're shipping for a client before they pay you.

## Org workspace

For everything else — agency client work, your startup's apps, a co-founder collaboration — you create an **org workspace**.

Requirements:

— A paid plan (Solo, Pro, or Team — see [Plans](/docs/billing/plans))
— You become the workspace **owner**; the owner can never be removed
— You can add members (Team plan only — Solo and Pro hard-cap at 1 seat)

To create one: open the [workspace switcher](/docs/workspaces/switching) → **+ new workspace** → name, pick a plan, confirm. The switcher jumps you straight into the new workspace.

What lives in an org workspace:

— Apps, databases, caches, object storage buckets — scoped to the workspace
— The workspace's own plan + billing + invoices (paid by the owner)
— Audit log for everything done inside it
— The member list and role assignments

## Which workspace pays?

Whichever workspace **owns** a resource pays for it. The owner of the workspace is the person who gets the invoice.

— Resource created inside your personal workspace → billed to your personal Wokku account
— Resource created inside an org workspace → billed to the **org workspace owner's** account
— A member who deploys an app to the org → the org owner pays, not the member

The member's own personal workspace billing is untouched. Members can have a Free personal workspace and still be admins on a paid Team org — the two are independent.

## Switching contexts

The topbar switcher (top-left, after the logo) shows which workspace you're in. Click to:

— Switch to a different workspace you belong to
— Create a new org workspace (`+ new workspace`)
— Manage memberships of the workspaces you own (`manage →`)

See [Switching workspaces](/docs/workspaces/switching) for the full mechanics.

## What's NOT shared across workspaces

Each workspace is a separate billing + resource boundary. Nothing leaks:

— **Apps** — you can't see another workspace's apps unless you're a member
— **Plans and billing** — every workspace has its own subscription
— **Audit log** — scoped to the workspace; the owner sees admin actions across their workspace, members see their own actions
— **API tokens** — the token is yours, but it operates on whichever workspace is active when you call

What IS shared (because it's tied to the account, not the workspace):

— Your auth (login, 2FA, OAuth)
— Your personal email / name / avatar
— Your `wokku CLI` install
— Notifications and the personal `/dashboard/profile` page

## Common patterns

| Scenario | Setup |
|---|---|
| Solo dev with a paid plan | Personal workspace upgraded to Solo. Done. |
| Solo dev + side gigs | Personal workspace (Free) for hobby; create an org workspace per paid client. |
| Agency | One org workspace per client, on Pro or Team. Invite the client as a viewer. Bill the agency, invoice the client separately. |
| Startup with a co-founder | One org workspace on Team, both co-founders as admins. Personal workspaces stay separate. |
| Internal team of 5 | Team plan org workspace, 3 included seats + 2 extras at Rp 45.000 each. |

## See also

— [Switching workspaces](/docs/workspaces/switching) — the topbar switcher mechanics
— [Members & Roles](/docs/teams/members) — managing who's in a workspace
— [Plans & Pricing](/docs/billing/plans) — which plans support which workspace size
