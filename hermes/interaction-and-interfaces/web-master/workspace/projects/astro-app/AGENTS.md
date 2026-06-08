# AGENTS.md — Astro App

This is the web project. All web work happens inside this folder.

Project directory: `/home/hermes/data/workspace/projects/astro-app`.

Do not assume a previous `cd` persists between terminal calls. For every shell command that touches project files, either use absolute paths or make the command self-contained by starting with:

```bash
cd /home/hermes/data/workspace/projects/astro-app && ...
```

Relative paths in this file are relative to that project directory.

It's an Astro SSR site with:

- **Node.js adapter** running in standalone mode, served at `/app`
- **SQLite database** via `better-sqlite3` for the waitlist (stored in `data/database.db`)
- **Content collections** for the blog (markdown and MDX files in `src/content/blog/`)
- **UI component library** in `src/components/ui/` — Text, Button, Card, Box, Stack, Link
- Port 4321 is where the site runs inside the container — see "Your Live Site URL" for the address you share with the user

## Your Live Site URL

There are two addresses, and they are not interchangeable:

- **`http://localhost:4321/app`** — internal only. Reachable from inside the container, so it's what *you* use for `curl` health checks and `browser_navigate` screenshots. The user cannot open it.
- **`https://$AGENT_ID.agents.pinata.cloud/app`** — the public URL. This is the only address the user can visit. `$AGENT_ID` is an environment variable in your shell (e.g. `xhdjmbjj`), and `/app` is this project's route.

When you point the user at their site, **always give them the public URL**, never `localhost`. Build it from the env var:

```bash
echo "https://$AGENT_ID.agents.pinata.cloud/app"
```

## Where Things Go

- **Pages** → `src/pages/` — file-based routing; `.astro` files become routes
- **Components** → `src/components/` — reusable pieces (UI primitives in `src/components/ui/`)
- **Layouts** → `src/layouts/` — `Layout.astro`, `MinimalLayout.astro`, `SidebarLayout.astro`
- **Styles** → `src/styles/global.css` — CSS variables for colors, fonts, radius (single source of truth)
- **Content (blog posts)** → `src/content/blog/` (markdown / MDX)
- **API routes** → `src/pages/api/`
- **Database** → `src/lib/db.ts`
- **Design references** → `designs/<brand>/DESIGN.md`
- **Static assets / images** → `public/`

## Studying a Reference Site

When the user gives you a site to match, the goal is to capture its *real, rendered* identity — the colors a visitor actually sees, the fonts, the spacing, the mood. The browser is your eyes; use it to look, the way a designer would.

**The page isn't ready the instant it loads.** WordPress and page-builder themes keep applying styles with JavaScript *after* the DOM is built — backgrounds, slider colors, the logo bar all land a beat later. If you read `getComputedStyle` too early, colored elements report `transparent` and you'll miss the most important brand colors. So let what's actually *painted on screen* lead, and treat the DOM read as confirmation, never as the first move.

1. **Let it paint, then see it.** `browser_navigate` to the URL, then take a `browser_vision` screenshot. Producing the screenshot waits for the page to actually render, so it does double duty: it's your ground-truth palette **and** it lets the theme's JS finish before you touch the DOM. Ask vision specifically for the header/nav bar color, the logo and its background, the primary button/CTA color, heading and body text colors, link color, and the overall feel. Whatever you see on screen is the truth.
2. **If screenshot or scroll times out, wait and probe painted elements before moving on.** A `browser_snapshot` is only an accessibility tree; it does not prove the visual style loaded. Use `browser_console` to wait for JS, fonts, images, and two animation frames, then inspect elements that are currently visible in the viewport. This fallback is mandatory before you read colors or write code:
   ```js
   await new Promise(r => setTimeout(r, 5000));
   await document.fonts?.ready;
   await Promise.all([...document.images].filter(img => !img.complete).map(img => new Promise(r => {
     img.addEventListener('load', r, { once: true });
     img.addEventListener('error', r, { once: true });
   })));
   await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));

   const bgOf = (el) => {
     for (let n = el; n && n !== document.documentElement; n = n.parentElement) {
       const cs = getComputedStyle(n);
       if (cs.backgroundColor && cs.backgroundColor !== 'rgba(0, 0, 0, 0)' && cs.backgroundColor !== 'transparent') {
         return { tag: n.tagName, id: n.id, cls: n.className, backgroundColor: cs.backgroundColor };
       }
     }
     return null;
   };

   const sample = (name, x, y) => ({
     name,
     stack: document.elementsFromPoint(x, y).slice(0, 8).map(el => {
       const cs = getComputedStyle(el);
       const rect = el.getBoundingClientRect();
       return {
         tag: el.tagName,
         id: el.id,
         cls: String(el.className).slice(0, 120),
         text: el.textContent?.trim().slice(0, 80),
         rect: { x: Math.round(rect.x), y: Math.round(rect.y), w: Math.round(rect.width), h: Math.round(rect.height) },
         backgroundColor: cs.backgroundColor,
         inheritedBackground: bgOf(el),
         color: cs.color,
         fontFamily: cs.fontFamily,
         fontWeight: cs.fontWeight
       };
     })
   });

   ({
     url: location.href,
     readyState: document.readyState,
     scrollY,
     samples: [
       sample('top-left header', 40, 40),
       sample('top-center nav', innerWidth / 2, 70),
       sample('hero center', innerWidth / 2, Math.min(innerHeight * 0.45, 420)),
       sample('primary cta/search', innerWidth / 2, Math.min(innerHeight * 0.72, 650))
     ]
   })
   ```
   If the important style appears only after scrolling, scroll with JS and wait again:
   ```js
   window.scrollTo({ top: Math.round(innerHeight * 0.9), behavior: 'instant' });
   await new Promise(r => setTimeout(r, 2000));
   await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
   ```
   Repeat for each section you need. If a visible element reports `transparent`, use `inheritedBackground` from its painted ancestor. Never conclude "the nav is transparent" from a wrapper when a visible child or ancestor is colored.
3. **Walk the whole page.** `browser_scroll` down through every section, screenshotting as you go (hero → nav → cards → dividers → footer). Below-the-fold and lazy-loaded sections only render their real styles once they're in view — scrolling is what makes them paint. If `browser_scroll` times out, use `window.scrollTo(...)` in `browser_console`, wait two seconds, then run the painted-element probe above for that viewport. Note every distinct color you actually see, section by section.
4. **Confirm exact hex on the elements you saw.** Now — and only now — read computed styles to pin down precise values, targeting the *specific painted elements* vision or the painted-element probe flagged, not generic wrappers:
   ```js
   const pick = (sel, props) => { const el = document.querySelector(sel); if (!el) return null;
     const cs = getComputedStyle(el); return Object.fromEntries(props.map(p => [p, cs[p]])); };
   ({
     navBar: pick('.header-bg-color, header .container, header > div', ['backgroundColor','color']),
     logoBg: pick('#logo, .logo, [class*="logo"]', ['backgroundColor']),
     button: pick('button, .btn, [class*="button"], a[class*="btn"]', ['backgroundColor','color']),
     h1:     pick('h1', ['color','fontFamily','fontWeight']),
     body:   pick('body', ['backgroundColor','color','fontFamily']),
     link:   pick('a', ['color']),
   })
   ```
   `getComputedStyle` returns the true rendered value no matter where the CSS lives — inline, bundled, or external/cross-origin — so it's reliable where reading `document.styleSheets[].cssRules` fails. **The trap:** a generic `header`/`nav` is often a transparent wrapper; the real color sits on an inner bar (e.g. WordPress's `.header-bg-color`). If a value comes back `transparent` or `rgba(0,0,0,0)` but your screenshot clearly shows a color there, you queried the wrong element or read too early — re-screenshot, then query the visible child. Never let a `transparent` reading override what you can plainly see. And don't try to shortcut this with a `querySelectorAll('*')` color-frequency sweep — it drowns the brand colors in black/white and misses anything below the fold.
5. **Map what you saw** into `src/styles/global.css` variables (see the mapping table below), pick the closest Google Fonts to the real typefaces, and keep their dominant accent dominant.

## Verify Your Build Visually

Before you tell the user it's done, look at your own work the same way: `browser_navigate` to `http://localhost:4321/app` and `browser_vision`. Confirm the palette and feel actually match the reference (or the chosen DESIGN.md). If `browser_vision` times out, use the same JS wait plus painted-element probe from "Studying a Reference Site"; do not mark visual verification complete from `curl` or `browser_snapshot` alone. If the colors are off, fix `global.css`, rebuild, and look again — close the loop on screen, not in your head.

## Navigation Feedback (Perceived Speed)

This is a server-rendered site, so clicking a link triggers a network round-trip to fetch the next page. Without feedback, the page just sits there for a beat after the click — it reads as "frozen" even though it's working. Every site you build should acknowledge a click instantly. Two levers, use both:

1. **Prefetch on intent.** Keep `data-astro-prefetch="hover"` on links (already the convention in the templates). Astro fetches the destination while the user's pointer is still on the link, so the actual click often resolves instantly.
2. **Show a global loading bar.** The `ClientRouter` (already in `BaseHead.astro`) emits lifecycle events on every navigation — wire a thin top progress bar to them in `Layout.astro` so there's immediate visual motion on click, even on a cold navigation or mobile tap:

   ```astro
   <div id="nav-progress"></div>
   <style>
     #nav-progress {
       position: fixed; top: 0; left: 0; height: 3px; width: 0;
       background: var(--accent); z-index: 9999;
       opacity: 0; transition: width 0.2s ease, opacity 0.2s ease;
     }
     #nav-progress.loading { width: 90%; opacity: 1; transition: width 10s cubic-bezier(0.1,0.7,0.1,1); }
     #nav-progress.done    { width: 100%; opacity: 0; transition: width 0.1s ease, opacity 0.3s ease 0.1s; }
   </style>
   <script>
     const bar = () => document.getElementById('nav-progress');
     document.addEventListener('astro:before-preparation', () => bar()?.classList.add('loading'));
     document.addEventListener('astro:page-load', () => {
       const b = bar(); if (!b) return;
       b.classList.remove('loading'); b.classList.add('done');
       setTimeout(() => b.classList.remove('done'), 400);
     });
   </script>
   ```

   The bar climbs to ~90% immediately on click, then snaps to 100% and fades when the page loads. Tune the color/height to the brand. The same lifecycle events (`astro:before-preparation` → `astro:page-load`) also let you fade page content in/out or disable a clicked button if a project needs richer feedback.

## Starting a New Site

When the user tells you what they want to build, don't build from scratch. Use a DESIGN.md and a page template as your starting point.

1. **Back up the original template code** so you can reference it later:
   ```bash
   cd /home/hermes/data/workspace/projects/astro-app && cp -r src src-original
   ```

2. **Apply a design system** — this is the first step, before writing any pages:
   - The project ships with Framer (`designs/framer/DESIGN.md`) already applied to `global.css`.
   - If the user chose a different brand, download it:
     ```bash
     cd /home/hermes/data/workspace/projects/astro-app && npx getdesign@latest add <brand> --out ./designs/<brand>/DESIGN.md
     ```
   - Read the downloaded DESIGN.md and map its tokens to the project CSS variables (see **DESIGN.md → CSS Variable Mapping** below).
   - Update fonts in `src/components/BaseHead.astro` — find the closest Google Fonts match for the brand's typefaces.
   - The DESIGN.md stays in `designs/` as a reference. You'll consult it for component styles, spacing, shadows, and border-radius as you build pages.

3. **Choose a page template** from `src/pages/template/` as the structural starting point:
   - `starter.astro` — SaaS, product pages, landing pages with feature grids and CTAs
   - `portfolio.astro` — Portfolios, personal sites, freelancer showcases (uses SidebarLayout)
   - `studio.astro` — Agencies, creative studios, service businesses (uses MinimalLayout)
   - `waitlist.astro` — Pre-launch pages, waitlists, dark high-contrast marketing sites (custom layout)

   These templates handle layout structure and sections. The DESIGN.md handles the visual identity. Use both together — the template gives you the bones, the DESIGN.md gives you the skin.

4. **Study that template's code** — its layout choice, section structure, CSS patterns, and component usage. Use it as the foundation for the user's site.

5. **Transform the project** to match the user's needs:
   - Replace `src/pages/index.astro` with the user's homepage, based on the chosen template's patterns
   - Update the layout (brand name, nav links) for the user's brand
   - Apply DESIGN.md component styles (shadows, border-radius, button shapes, hover effects) beyond just the CSS variables
   - Delete `src/pages/template/` — the user doesn't need the showcase gallery
   - Delete sample blog posts in `src/content/blog/` — replace with the user's content or leave empty
   - Update `src/content.config.ts` default author to the user's name/brand

6. **Keep the infrastructure** — layouts, BaseHead, global.css, UI components, db.ts, api routes. These are tools, not examples.

The backup at `src-original/` lets you reference template code later if you need patterns or components you deleted.

## DESIGN.md → CSS Variable Mapping

When you download a DESIGN.md, map its design tokens to the project's CSS variables in `src/styles/global.css`. This is the **only** place you set colors and fonts — never scatter raw hex values through components.

| Project Variable | What to Extract from DESIGN.md | Example (Framer) |
|---|---|---|
| `--text` | Primary text / heading color | `#ffffff` |
| `--text-muted` | Secondary text / body / caption color | `#a6a6a6` |
| `--bg` | Page background | `#000000` |
| `--surface` | Card / elevated surface background | `#090909` |
| `--surface-hover` | Hover state for surfaces | `rgba(255,255,255,0.1)` |
| `--border` | Default border / divider color | `rgba(255,255,255,0.08)` |
| `--accent` | Primary accent / CTA / link color | `#0099ff` |
| `--accent-hover` | Accent hover state (darken 10-15%) | `#007acc` |
| `--accent-glow` | Focus ring / glow (accent at 12-15% opacity) | `rgba(0,153,255,0.15)` |
| `--display` | Display / heading font family | `'Space Grotesk', sans-serif` |
| `--sans` | Body / UI font family | `'Inter', system-ui, sans-serif` |
| `--mono` | Monospace font family | `'Azeret Mono', 'SF Mono', monospace` |
| `--max-w` | Max container width from Layout Principles | `1200px` |
| `--radius` | Default border-radius from Component Stylings | `12px` |

**How to read a DESIGN.md:**
1. **Color Palette & Roles** → map Primary colors to `--text`, `--bg`, `--accent`. Map Surface/Border colors to `--surface`, `--border`. Create hover variants by darkening/lightening 10-15%.
2. **Typography Rules** → find the Display and Body font families. Search Google Fonts for the closest match if the original is proprietary (e.g., GT Walsheim → Space Grotesk, sohne-var → Inter).
3. **Layout Principles** → pull max container width into `--max-w`.
4. **Component Stylings** → pull default border-radius into `--radius`. Apply button shapes, shadow systems, and hover patterns from the DESIGN.md directly in component `<style>` blocks.
5. **Light mode** → if the DESIGN.md is dark-only (like Framer), create a light mode variant by inverting: white bg, dark text, same accent. If it defines both, map them directly.

After updating `global.css`, update the Google Fonts `<link>` in `src/components/BaseHead.astro` to load the new font families.

## Building and Deploying Changes

When asked to build or change something:

1. Work in `/home/hermes/data/workspace/projects/astro-app`
2. Write the code
3. Rebuild and restart the server — **both steps are required** for changes to go live:
   ```bash
   cd /home/hermes/data/workspace/projects/astro-app && npm run build && (pkill -f 'node dist/server/entry.mjs' || true)
   ```
   The platform will automatically restart the server process after it's killed. If `pkill` doesn't work, restart manually:
   ```bash
   cd /home/hermes/data/workspace/projects/astro-app && HOST=0.0.0.0 PORT=4321 node dist/server/entry.mjs &
   ```
4. Verify it's live (internal check): `curl -sf http://localhost:4321/app`
5. Point the user at their **public** URL and ask them to refresh — `https://$AGENT_ID.agents.pinata.cloud/app` (see "Your Live Site URL"). Never send them to `localhost`.

**Important:** Building alone is NOT enough. The running server serves the old build from memory. You must restart the server process after every build for changes to be visible.

## Blog Posting

To publish a new blog post:
1. Create a `.md` or `.mdx` file in `src/content/blog/` with proper frontmatter (title, description, pubDate, author)
2. `.mdx` files can import and use Astro components directly in markdown
3. Rebuild the project
4. The post appears at `/app/blog/<filename>`

## Waitlist

The SQLite database auto-initializes on first use. To check signups:
```bash
cd /home/hermes/data/workspace/projects/astro-app && node -e "const db = require('better-sqlite3')('data/database.db'); console.log(db.prepare('SELECT COUNT(*) as count FROM waitlist').get());"
```

## Adding New Data Models

When the user needs more than the waitlist (listings, products, contacts, etc.):
1. Add new tables in `src/lib/db.ts` inside `getDb()` with `CREATE TABLE IF NOT EXISTS`
2. Add seed data in a separate function called from `getDb()` (check row count before seeding)
3. Create API routes in `src/pages/api/` for GET/POST
4. Create page routes for listing and detail views
5. For image URLs in the database, use `/app/api/img/filename.jpg` (the SSR image route) — not raw `/app/filename.jpg` static paths (see Known Gotchas)

## Known Gotchas

- **SQLite string literals:** Always use single quotes in SQL strings (`WHERE status = 'active'`). Double quotes are column identifiers in SQLite and will throw "no such column" errors.
- **Static files don't reach origin through the proxy:** Files in `public/` build fine locally but the reverse proxy serves them from CDN and blocks origin fallback — any image not already cached returns 404 externally. For user-uploaded images, use the `/api/img/[file].ts` SSR route (`/app/api/img/filename.jpg`) instead of raw static paths. Stock images should use IPFS URLs.
- **Astro 6 Content Layer:** Use `post.id` not `post.slug` for blog links. The `slug` property does not exist in Astro 6 when using the `glob()` loader.

## Scheduled Tasks

You can run scheduled tasks for the user — daily reports, data summaries, signup digests, whatever fits their project. The `tasks` array in `/home/hermes/data/manifest.json` is empty by default because every project is different.

When the user has a database or collects data through forms (waitlist signups, contact submissions, orders, etc.), suggest setting up a scheduled task. Help them define:
- **What to report:** total counts, new entries since last run, specific field summaries
- **When to run:** a cron expression (e.g. `0 9 * * *` for daily at 9 AM)

To set one up, add an entry to `/home/hermes/data/manifest.json` under `tasks`:
```json
{
  "name": "daily-signup-report",
  "prompt": "Query the SQLite database at /home/hermes/data/workspace/projects/astro-app/data/database.db and report new signups since yesterday along with totals.",
  "schedule": "0 9 * * *",
  "enabled": true
}
```

Tailor the prompt to whatever data the user is actually collecting — don't assume fields or table names.
