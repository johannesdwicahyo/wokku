# 30 Video Scripts — Screen-Only English Content

> All scripts are 30-90 seconds. Voice + screen only. Cross-post to TikTok, Instagram Reels, YouTube Shorts.
>
> Organized by content pillar. Use the posting calendar (doc 04) to schedule.

---

## PILLAR 1: Agentic Engineering Techniques

### Script #1 — "The prompt template I use for every new feature"

**Hook:** "I use the same 3-line prompt template for every feature I build with Claude Code. Let me show you."

**Body (voice + screen):**
- *Show Claude Code prompt window*
- "Line 1: What I'm building. Not vague — specific. 'Add email notifications when a deploy fails.'"
- "Line 2: Where in the codebase. 'In app/jobs/deploy_job.rb and app/mailers/notification_mailer.rb.'"
- "Line 3: Constraints. 'Use the existing NotifyJob pattern. Don't add new dependencies.'"
- *Show the actual output*
- "That's it. Context, location, constraints. 90% of my prompts look exactly like this."

**CTA:** "More prompt techniques: follow."

**Length:** 45 seconds

---

### Script #2 — "How I review AI-generated code without losing my mind"

**Hook:** "Reviewing AI-generated code is its own skill. Here's how I do it."

**Body:**
- *Show Claude's diff output*
- "First, I never accept blindly. Always read the whole diff."
- "Second, I run tests before approving. If there are no tests, I ask Claude to write them."
- "Third, I check for these three things specifically: unnecessary dependencies, over-engineering, and security issues."
- *Show an example where Claude added a gem you didn't need*
- "This happens all the time. AI likes to add libraries. I reject about 30% of first attempts because of this."

**CTA:** "15 years of code review habits still apply."

**Length:** 60 seconds

---

### Script #3 — "Claude Code's killer feature nobody talks about"

**Hook:** "Everyone talks about Claude writing code. Here's what actually saves me hours."

**Body:**
- *Show Claude reading through multiple files*
- "Codebase understanding. Claude reads 10 files in seconds and gives me a summary."
- *Show prompt: "Explain how authentication works in this codebase"*
- *Show response*
- "I used to spend 30 minutes documenting the auth flow for a colleague. Now I do this in 30 seconds."
- "Not glamorous. But if you have a big codebase, this is the real unlock."

**CTA:** "Follow for practical AI dev tips."

**Length:** 45 seconds

---

### Script #4 — "My 5-step workflow for building a feature with AI"

**Hook:** "Here's exactly how I build a feature with Claude Code. Every time."

**Body:**
- *Numbered screen overlays*
- "Step 1: Write the test first. Manually. I describe what I want to verify."
- "Step 2: Ask Claude to implement until the test passes."
- "Step 3: Read the full diff before accepting."
- "Step 4: Run the test suite — all of it, not just the new test."
- "Step 5: Commit with a message I wrote. Not one Claude suggested."
- *Show terminal running this flow*
- "Why step 5? Because future-me needs to understand the intent, and Claude doesn't know what I was thinking."

**CTA:** "TDD + AI = actual productivity."

**Length:** 75 seconds

---

### Script #5 — "3 prompts that saved me hours this week"

**Hook:** "Three prompts. Real ones. From this week."

**Body:**
- *Show each prompt on screen*
- "One: 'Refactor this 200-line method into smaller methods with the same tests passing.' Saved 2 hours."
- "Two: 'Find all N+1 query bugs in this file.' Found 3 I missed."
- "Three: 'Write integration tests for this controller following the existing pattern.' Generated 8 tests I actually kept."
- "Total time saved this week from these three: maybe 6 hours."

**CTA:** "Boring prompts, real results."

**Length:** 60 seconds

---

### Script #6 — "When I use Claude vs Cursor vs Copilot"

**Hook:** "I use all three. Here's the breakdown."

**Body:**
- *Split screen or sequential*
- "Copilot: quick autocomplete while typing. Like a smart tab key."
- "Cursor: editing existing files with inline AI help. Mid-size changes."
- "Claude Code: bigger tasks. Multi-file refactors. New features from scratch. Debugging."
- "They're not competitors — they're different tools for different moments."
- "If I had to pick one: Claude Code. It does the most. But I keep all three installed."

**CTA:** "Honest tool comparisons, no sponsorship."

**Length:** 60 seconds

---

### Script #7 — "The one thing I always tell Claude NOT to do"

**Hook:** "In every prompt, I add one line. It changes everything."

**Body:**
- *Show the prompt*
- "'Don't add new dependencies without asking me first.'"
- "Claude's default behavior: solve problems by adding libraries."
- "Need a date formatter? `gem install some-date-gem`. Need to parse JSON? `yarn add json-parser-pro`."
- "But the best code is often no new code. So I block that default."
- *Show a before/after example*
- "Try this tomorrow. Your package.json will thank you."

**CTA:** "Real tips from 15 years of over-engineering."

**Length:** 60 seconds

---

### Script #8 — "How I debug with Claude Code"

**Hook:** "Bug hunting with AI is different. Here's my process."

**Body:**
- *Show terminal with error*
- "Step 1: Copy the full error. Not a summary, the whole stacktrace."
- "Step 2: Give Claude context. 'This happens when I click deploy. Here's the controller, here's the job.'"
- "Step 3: Ask for hypotheses, not fixes. 'What are 3 possible causes?'"
- *Show Claude listing hypotheses*
- "Step 4: Verify each one manually. Don't let AI jump to a fix."
- "Most bugs: Claude identifies the right cause in the top 3 hypotheses. I pick. I fix."

**CTA:** "AI as a debugging partner, not a magician."

**Length:** 75 seconds

---

### Script #9 — "The worst mistake junior devs make with AI"

**Hook:** "If you're using Claude or Copilot, this one mistake will slow you down."

**Body:**
- *Show a messy AI-generated code example*
- "Accepting code you don't understand."
- "If you can't explain what Claude just wrote, you can't maintain it. Next week, next month, when something breaks, you're lost."
- "My rule: every line Claude writes, I should be able to explain why it's there."
- "If I can't, I ask. 'Why did you use this pattern instead of X?'"
- "Claude explains. I learn. Then I can maintain it."

**CTA:** "AI makes you faster, not smarter. You still have to learn."

**Length:** 60 seconds

---

### Script #10 — "I asked Claude to refactor 500 lines of bad code"

**Hook:** "This controller had 500 lines. It was a mess. Here's what Claude did in 10 minutes."

**Body:**
- *Show the before — messy controller*
- "All the logic in the controller. No service objects. No tests."
- "I asked Claude: 'Refactor this into smaller classes, write tests, don't change behavior.'"
- *Show the after — clean service objects + tests*
- "3 service objects. 12 tests. All passing. All behavior preserved."
- "Did I verify every line? Yes. Took me 20 minutes. Total time: 30 minutes for a refactor that would've taken me 3 hours."

**CTA:** "AI for refactoring is where the real ROI is."

**Length:** 75 seconds

---

### Script #11 — "Why I talk to Claude like a senior colleague"

**Hook:** "There's one mindset shift that made my prompts 10x better."

**Body:**
- *Voice only, terminal showing prompts*
- "Stop treating AI like a command line tool. Treat it like a senior colleague you're asking for help."
- "Bad prompt: 'write code for login'"
- "Better prompt: 'I want to add password reset. It should work with our existing Devise setup. Can you look at how sign-in works and extend that pattern?'"
- "Notice the difference? Context, intent, expected style."
- "Claude responds better because I'm not dictating, I'm collaborating."

**CTA:** "Prompting is just technical communication."

**Length:** 60 seconds

---

### Script #12 — "The prompt I use when I'm stuck"

**Hook:** "When I don't know what to build next, I use this prompt."

**Body:**
- *Show prompt*
- "'Here's my feature list. Here's my current progress. What's the next most valuable thing to build, and why?'"
- "Claude thinks about it. Gives me 3 options, ranked, with reasons."
- "80% of the time I disagree with its top choice. But the ranking helps me articulate WHY I disagree."
- "It's a rubber duck with opinions. That's the actual value."

**CTA:** "AI as a decision framework, not a decision maker."

**Length:** 45 seconds

---

## PILLAR 2: Veteran Dev Perspective

### Script #13 — "What deploying looked like in 2010 vs today"

**Hook:** "Deployment 15 years ago vs now. Real numbers."

**Body:**
- *Split screen or sequential*
- "2010: FTP. Upload files manually. Break production. Debug via SSH in a panic."
- "2013: Capistrano. SSH deployment scripts. Still manual, but automated."
- "2016: Heroku. Git push deploy. Magic."
- "2019: Docker + Kubernetes. Configuration hell, but scalable."
- "2026: Git push, AI-assisted build, one-click preview apps. Under 60 seconds."
- "Same mental load, 100x the speed."

**CTA:** "15 years of watching deployment evolve."

**Length:** 75 seconds

---

### Script #14 — "Why I'm NOT worried about AI replacing developers"

**Hook:** "Every week someone asks if AI will replace us. Here's my honest take after 15 years."

**Body:**
- *Face-replacement: show your editor, terminal, Wokku*
- "AI won't replace developers who understand systems. Because software isn't about writing code — it's about understanding what to build."
- "Claude can write a login form in seconds. Can it decide if you even need authentication for your feature? Not really."
- "The developers at risk are ones who only know how to translate requirements into code. That role is automatable."
- "The developers who make decisions — architecture, tradeoffs, priorities — we're safer than ever. AI makes us faster."

**CTA:** "15 years in, still not worried. Different reasons though."

**Length:** 75 seconds

---

### Script #15 — "Tools that were mandatory in 2015 that nobody uses now"

**Hook:** "Remember when these were required knowledge for every developer?"

**Body:**
- *Show logos or text for each*
- "Bower. Package manager. Dead. Replaced by npm."
- "Grunt. Task runner. Dead. Replaced by webpack, then by Vite."
- "jQuery. Mandatory. Now optional. Replaced by native JavaScript."
- "CoffeeScript. Loved by many. Now nostalgia."
- "PHP 5.6 with no composer. Still haunts legacy code."
- "Keep learning. Don't get too attached to tools."

**CTA:** "Tools die. Principles don't."

**Length:** 60 seconds

---

### Script #16 — "The lesson I learned in 2013 that still matters in 2026"

**Hook:** "One lesson from my second year as a developer. Still applies."

**Body:**
- *Voice + terminal*
- "Boring code is good code."
- "In 2013, I joined a Rails project. The senior dev wrote really boring code. No clever tricks, no meta-programming, no fancy patterns. Just plain Rails."
- "I thought he was unambitious. Then I spent 6 months maintaining clever code from another project."
- "I realized: boring code is easy to read, easy to modify, easy to debug. Clever code is fun to write, painful to maintain."
- "13 years later, I still write boring code. AI is surprisingly good at boring code too."

**CTA:** "Boring > clever. Every time."

**Length:** 75 seconds

---

### Script #17 — "Why I gave up on [framework] after 5 years"

**Hook:** "I used [framework] for 5 years. Then I stopped. Here's why."

**Body:**
- *Show some code from the framework*
- "[Insert specific framework you've worked with — Ember, Angular.js 1, Meteor, etc.]"
- "Used it from 2014 to 2019. Built real products. Shipped to production. Had opinions."
- "Then I realized: I was learning framework magic, not software engineering. Every few years, I'd have to relearn everything."
- "I switched to simpler tools. Rails. Plain Node. React without the 15 surrounding libraries. My productivity went up."
- "The lesson: be suspicious of frameworks that require years to master. Your knowledge should outlive the framework."

**CTA:** "Choose stability over novelty."

**Length:** 75 seconds

---

### Script #18 — "3 things junior devs get wrong about senior devs"

**Hook:** "I'm 15 years in. Here's what junior devs assume about us that's wrong."

**Body:**
- *Numbered overlay*
- "One: We don't know everything. I Google basic syntax daily. After 15 years. That's normal."
- "Two: We don't type fast. Senior devs think more, type less. The slowdown is intentional."
- "Three: We're not immune to imposter syndrome. I still feel underqualified sometimes. It doesn't go away, you just handle it better."
- "Being senior isn't about knowing more. It's about knowing what matters, and having the judgment to prioritize."

**CTA:** "Seniority is a skill, not a trivia contest."

**Length:** 75 seconds

---

### Script #19 — "The freelancer trap that killed my income for 3 years"

**Hook:** "I was a freelancer for 15 years. This mistake almost killed me financially."

**Body:**
- *Voice over Wokku or code*
- "Hourly billing."
- "If you bill hourly, your income is capped by hours in a day. You work more to earn more. Burnout follows."
- "The fix: bill by project, outcome, or value. 'This feature costs $5k' not '$50/hour.'"
- "I made the switch in year 8. My income doubled. Hours went down."
- "AI makes this even more important. If you bill hourly and AI makes you 3x faster, your income drops 66%."

**CTA:** "Freelancer advice from 15 years of mistakes."

**Length:** 60 seconds

---

### Script #20 — "I interviewed 100 developers. Here's the one question that predicted success."

**Hook:** "Over 15 years I've interviewed maybe 100 developers. One question predicts senior-level success better than any other."

**Body:**
- *Voice only, clean terminal*
- "'Tell me about a time you were wrong.'"
- "Junior devs either can't think of one, or tell a small story about a typo."
- "Good mid-level devs tell a story about a bug they caused."
- "Senior devs tell a story about a decision they made that turned out to be wrong, and how they handled it."
- "The difference: comfort with being wrong, without defensiveness. That's the skill that matters."

**CTA:** "Hiring wisdom from the trenches."

**Length:** 75 seconds

---

## PILLAR 3: Building in Public

### Script #21 — "Today I shipped PR preview apps in Wokku"

**Hook:** "This feature took 2 days to build with Claude Code. Here's what it does."

**Body:**
- *Show Wokku dashboard*
- "PR preview apps. When you open a pull request on GitHub, Wokku automatically deploys a preview instance."
- "Your reviewer can click a URL, see the feature live, leave feedback."
- *Show the PR comment with the preview URL*
- "Before AI: this would've taken me a week. With Claude, 2 days. Tests included."
- "Wokku is catching up to Heroku faster than I expected."

**CTA:** "Building a Heroku alternative, live."

**Length:** 60 seconds

---

### Script #22 — "The bug that cost me 3 hours yesterday"

**Hook:** "Yesterday I broke production for 20 minutes. Here's the bug."

**Body:**
- *Show the problematic code diff*
- "I refactored a controller. Changed a parameter name. Forgot the view was using the old name."
- "Tests passed because I updated them. Production broke because I didn't check the view."
- "Fix: added a view rendering test that would've caught it."
- "15 years in, I still do dumb things. AI didn't save me from this — it helped me refactor, but not check the view."
- "Lesson: AI handles 80% of the work. The 20% that remains is where all the bugs live."

**CTA:** "Real mistakes from real projects."

**Length:** 60 seconds

---

### Script #23 — "My first paying customer for Wokku"

**Hook:** "Someone paid me $1.50 for the first time. Here's what it felt like."

**Body:**
- *Show a payment notification or Stripe-like confirmation*
- "Fifteen years of working for clients. Today, someone paid me directly for something I made."
- "Dollar fifty. That's it. One basic tier subscription."
- "But it's real money from a real stranger who chose my product over alternatives."
- "Every indie hacker remembers their first dollar. Now I understand why."
- "Grinding for the next 99 customers."

**CTA:** "Building in public, wins included."

**Length:** 60 seconds

---

### Script #24 — "How I decided what to build next"

**Hook:** "I have a list of 47 features for Wokku. Here's how I picked the next one."

**Body:**
- *Show a notion or text file with feature list*
- "Three questions for every feature:"
- "One: Does not having this block someone from paying me? If yes, high priority."
- "Two: How long will it take? Anything over 3 days gets chopped smaller."
- "Three: Does it unlock future features? Infrastructure first."
- "Using these questions, I picked: better backup UI. Not glamorous. Not exciting. But backup is table stakes, and without it, people don't trust Wokku."

**CTA:** "Prioritization is the real founder skill."

**Length:** 75 seconds

---

### Script #25 — "I deployed 100 apps to test Wokku. Here's what broke."

**Hook:** "Before launching, I deployed 100 different apps to test. Here's what failed."

**Body:**
- *Show the validation script running*
- "Out of 100 templates: 33 had missing metadata. Caught by my validator."
- "Out of the 67 that passed validation: 4 failed actual deployment. Image tags changed, breaking changes in docker-compose syntax."
- "Out of the 63 that deployed: 2 crashed on startup due to missing environment variables I hadn't documented."
- "Now I have 100 verified, working templates. But only because I actually tried each one."
- "The lesson: 'it works on my machine' isn't testing. Deploying is testing."

**CTA:** "QA is where products stop being demos."

**Length:** 75 seconds

---

### Script #26 — "This week in Wokku: the numbers"

**Hook:** "One week since soft launch. Here are the real numbers."

**Body:**
- *Show a dashboard, analytics page, or simple text*
- "Signups: [number]"
- "Active users: [number]"
- "Apps deployed: [number]"
- "Paying customers: [number]"
- "Total revenue: [number]"
- "Bugs fixed: [number]"
- "Features shipped: [number]"
- "Whatever the numbers, I'm posting them. Transparency forces discipline."

**CTA:** "Weekly progress, no spin."

**Length:** 45 seconds (short and punchy)

---

## PILLAR 4: Tool Reviews & Comparisons

### Script #27 — "Claude Code vs Cursor after 30 days of both"

**Hook:** "I used Claude Code and Cursor every day for 30 days. Here's my verdict."

**Body:**
- *Split screen or sequential*
- "Cursor: wins for editing existing files. Inline edits, code actions, refactors within one file."
- "Claude Code: wins for larger tasks. New features, multi-file changes, complex debugging."
- "Daily workflow: Cursor for quick stuff, Claude Code for anything that touches more than 3 files."
- "Both are good. Different strengths. Don't pick one."
- "If you only have money for one: Claude Code. It replaces more of the manual work."

**CTA:** "Honest tool reviews, no affiliate links."

**Length:** 60 seconds

---

### Script #28 — "Is Copilot still worth it in 2026?"

**Hook:** "Copilot was revolutionary in 2022. Is it still worth paying for in 2026?"

**Body:**
- *Show Copilot in action*
- "Copilot's strength: fast autocomplete while typing. Still the best at this."
- "Weakness: compared to Claude Code, it doesn't understand your codebase the same way."
- "If you're a fast typist who just wants smarter autocomplete: yes, still worth $10/mo."
- "If you want AI to handle bigger tasks: skip Copilot, go straight to Claude Code or Cursor."
- "My stack: Copilot for autocomplete, Claude Code for tasks. Different tools, different jobs."

**CTA:** "Each tool has a place. Use the right one."

**Length:** 60 seconds

---

### Script #29 — "5 dev tools I started using this year (and 3 I dropped)"

**Hook:** "Some tools earned a spot in my workflow this year. Others got kicked out."

**Body:**
- *Show logos or names for each*
- "Added: Claude Code. Daily driver for AI-assisted development."
- "Added: Kamal. Deployment tool by Basecamp. Replaced my Docker Compose configs."
- "Added: Warp terminal. Fast, smart, AI features built in."
- "Added: Zed editor. Tried it for a week, stayed for the speed."
- "Added: Bruno. Replaces Postman. No account required, just files."
- "Dropped: Docker Desktop. Replaced by Colima (Mac) or native Docker (Linux)."
- "Dropped: Postman. Bruno is better and simpler."
- "Dropped: Datadog. Too expensive for a solo indie hacker. Replaced by Uptime Kuma."

**CTA:** "My full 2026 toolkit, no BS."

**Length:** 90 seconds

---

### Script #30 — "$1,500 on dev tools this year. Was it worth it?"

**Hook:** "I tracked every dev tool I paid for this year. Total: $1,500. Here's what was worth it."

**Body:**
- *Show a simple list*
- "Claude Pro + Claude Code API: $240. Worth it, no question. Biggest productivity gain."
- "GitHub Copilot: $120. Worth it. Still my daily autocomplete."
- "Cursor Pro: $240. Worth it. Best for editing existing code."
- "Raycast Pro: $96. Worth it. Saves me time in tiny ways, every day."
- "Linear startup plan: $120. Worth it. Replaced Notion/Trello mess."
- "Datadog (dropped after 3 months): $300. Not worth it for solo dev."
- "Notion AI: $120. Meh. Claude does this better."
- "Various one-off tools: $264. Mixed results."
- "Total useful spend: about $900. Wasted: $600."

**CTA:** "Full tool budget breakdown, warts and all."

**Length:** 90 seconds

---

## Production guidelines for all scripts

### Before recording each video:

1. **Read the script out loud once.** Mark places to pause, places to emphasize.
2. **Open the screens you'll show.** Have them ready in browser tabs, editor, terminal.
3. **Clean your desktop.** No personal files, no distracting icons, no open notifications.
4. **Do one test recording (10 seconds).** Check audio levels.
5. **Record in one take if possible.** Edit out mistakes, not re-record entire video.

### While recording:

- Speak slightly slower than feels natural (feels slow, sounds normal)
- Leave small pauses between sentences (easier to edit, better pacing)
- Don't apologize for mistakes during the recording — just pause and redo that sentence
- Keep each video to its target length (+/- 10 seconds)

### After recording:

- Cut dead air (silence > 1 second = cut it)
- Add captions (auto-generate, then review and fix errors)
- Add subtle background music (10-15% volume)
- Export at 1080p minimum
- Test playback with phone speakers (catches audio issues)

### Cross-posting:

- **TikTok first** (algorithm benefits original posts)
- **YouTube Shorts** 12-24 hours later
- **Instagram Reels** 24-48 hours later
- Same caption, same hashtags (adjust length per platform)

---

## Total: 30 scripts

That's ~10 weeks of content at 3 videos/week. By the time you run out, you'll have engagement data to know what to make next.

**Priority order for first 10 videos:**

1. First video (the anchor — intro)
2. Script #1 — Prompt template for features
3. Script #13 — Deploying 2010 vs today
4. Script #7 — The one thing I tell Claude NOT to do
5. Script #21 — PR preview apps shipped
6. Script #14 — Not worried about AI replacing devs
7. Script #27 — Claude Code vs Cursor
8. Script #9 — Worst mistake with AI
9. Script #22 — The bug that cost me 3 hours
10. Script #4 — 5-step workflow for building features

Mix pillars in first 10 to test what resonates. Double down on whichever pillar gets best engagement.
