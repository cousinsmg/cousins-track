# Cousins Track

A Monday-style task tracker — boards, groups, tasks, statuses, owners, due dates,
comments, file attachments, an audit trail, recurring tasks, group templates, an
overdue view, and a per-person workload view. Auth and data run on **Supabase**;
the app is a single static `index.html` you can host on **GitHub Pages**.

## Why GitHub Pages (static) and not Vercel

Everything that needs a backend — sign-in, the database, file storage, even
scheduled recurrence — lives inside Supabase. The browser talks to Supabase
directly using the **publishable** key, and Row Level Security decides who can
read or write each row. That key is meant to be public, so there are no server
secrets to hide and **no server functions are required**. A static host is enough.
(You could deploy the same file to Vercel for preview deploys or a custom domain;
you'd only *need* a server later if you add something that uses the secret key —
e.g. programmatic email invites via the service role, or Stripe webhooks.)

---

## Setup (about 15 minutes)

### 1. Create the Supabase project
1. Go to supabase.com → **New project**. Pick a name and a strong DB password.
2. When it's ready, open **SQL Editor**, paste the entire contents of
   **`schema.sql`**, and click **Run**. This creates the tables, security
   policies, the creator-becomes-admin trigger, and the `attachments` storage bucket.

### 2. Turn on email magic-link auth
1. **Authentication → Providers → Email**: make sure it's enabled.
   (Magic links are on by default; you don't need passwords.)
2. **Authentication → URL Configuration**:
   - **Site URL** → your GitHub Pages URL, e.g. `https://psattler911.github.io/cousins-track/`
   - **Redirect URLs** → add the same URL, and `http://localhost:3000` (or whatever
     you use locally) so testing works too.

### 3. Get your keys and paste them in
1. **Project Settings → API**. Copy the **Project URL** and the
   **publishable key** (`sb_publishable_…`).
2. Open `index.html`, find the `CONFIG` block near the top, and fill them in:
   ```js
   window.CONFIG = {
     SUPABASE_URL: "https://YOUR-PROJECT-ref.supabase.co",
     SUPABASE_PUBLISHABLE_KEY: "sb_publishable_XXXXXXXX"
   };
   ```
   Both are safe to commit — they're designed to live in the browser.
   **Never** put the *secret* key (`sb_secret_…`) in this file or the repo.

### 4. Push to GitHub
```bash
git init
git add index.html schema.sql README.md
git commit -m "Cousins Track on Supabase"
git branch -M main
git remote add origin https://github.com/psattler911/cousins-track.git
git push -u origin main
```

### 5. Turn on GitHub Pages
Repo → **Settings → Pages** → Source: **Deploy from a branch** → Branch: `main`,
folder `/ (root)` → Save. Your URL appears in a minute. Make sure it matches the
Site URL you set in step 2.

---

## Using it

- **Sign in**: enter your email, click the magic link we send you.
- **First board**: click **＋ New board** — you're automatically its admin.
- **Invite people**: open a board's **⚙ Settings**, add their email, pick a role
  (admin / editor / viewer). Next time they sign in with that email, the board
  appears for them with exactly that access — enforced server-side by RLS.
- **Files** attach to tasks and are stored privately in Supabase Storage.
- **Recurring tasks**: set **Repeat** in a task's Details tab; completing one
  spawns the next occurrence.

## Notes & next steps

- **Board ordering** (drag-to-reorder in the sidebar) is per-session for now;
  add a `sort_order` column if you want it saved per user.
- **True scheduled recurrence** (a task appearing every Monday on its own,
  without anyone completing the prior one) can be added later with Supabase
  **pg_cron** or an **Edge Function** — still no server of your own.
- **Realtime**: to have two people see each other's edits live, subscribe to
  Postgres changes on `boards` with `supabase.channel(...)` and re-render on update.
- The current save model writes the whole board row (debounced). Fine for a small
  team; if boards get very large you can normalize tasks/comments into their own
  tables later without changing the UI.
