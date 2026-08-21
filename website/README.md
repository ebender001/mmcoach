# M & M Coach Website

Public landing page for M & M Coach. Static HTML/CSS/JS -- no build step,
no framework, no npm packages.

```text
website/
├── index.html            # landing page markup
├── privacy-policy.html    # privacy policy (App Store / GDPR / CCPA)
├── terms-of-use.html      # terms of use (includes Apple's required minimum EULA terms)
├── support.html            # FAQ + contact (also the App Store Connect "Support URL")
├── styles.css              # all styles (CSS custom properties for theme values)
├── script.js                # mobile nav toggle, smooth scroll, footer year
└── assets/                  # hero illustration (cropped from docs/launch.png) + favicons
```

## Run locally

Any static file server works, e.g.:

```bash
cd website
python3 -m http.server 8000
# open http://localhost:8000
```

## Deploy

Deploy the `website/` directory as-is -- no build command, no output
directory remapping needed.

**Vercel**: set the project's Root Directory to `website/`, leave the
Framework Preset as "Other", and leave Build Command / Output Directory
blank (or Output Directory `.`).

**Cloudflare Pages**: set the Build output directory to `website`, and
leave the Build command blank.

## Before going live

- Replace the placeholder App Store links (`data-placeholder="app-store"`
  in `index.html`) with the real App Store URL once the app is listed.
- Footer/header "Support" and "Contact" links now point at the real
  `support.html` (and `support.html#contact-us`), alongside
  `privacy-policy.html` / `terms-of-use.html`. No placeholder links
  remain in the nav/footer except the App Store download button.
- `privacy-policy.html` and `terms-of-use.html`'s Contact sections are
  filled in (Bender Apps, LLC / support@benderapps.dev, email only, no
  mailing address). The policy was drafted from this app's actual data
  flows (Parse/Back4App, OpenAI, on-device PHI screening, Apple Speech,
  PubMed) -- have it reviewed by counsel familiar with GDPR/CCPA and
  any other regions you operate in before relying on it.
- `terms-of-use.html`'s "Governing law and disputes" section is filled
  in (Missouri law, Missouri venue). It also includes Apple's required
  minimum EULA terms (App Store Review Guideline 3.1.2 / Apple's
  Licensed Application End User License Agreement) since the app isn't
  using Apple's standard EULA -- if you set a custom EULA in App Store
  Connect instead, that section can be trimmed. No binding arbitration
  / class-action waiver clause is included. Have this reviewed by
  counsel alongside the privacy policy.
- **`terms-of-use.html`'s "Subscriptions" section (and the matching
  support.html FAQ) describe the confirmed model — first case free,
  then an auto-renewing subscription for additional cases — with
  Apple's required auto-renewal disclosure language, but no specific
  price or billing period yet** (monthly vs. annual, price point).
  Fill those in once the subscription product is configured in App
  Store Connect, and make sure the in-app purchase screen's own
  disclosure text matches this page.
- The iOS app now supports in-app account deletion (Account →
  "Delete Account", App Store Review Guideline 5.1.1(v)) — permanently
  deletes the account and all of its cases via `mmDeleteAccount`.
  `privacy-policy.html`'s account-deletion section still only describes
  the "contact us" path; update it to mention the in-app option too.
