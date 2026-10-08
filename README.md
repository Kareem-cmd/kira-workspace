# Kira Workspace

Arabic, RTL studio CRM with a React frontend for GitHub Pages and shared PostgreSQL storage and authentication through Supabase.

## Deployment

1. Create a Supabase project. Run `supabase/migrations/202610080001_kira_workspace.sql`, then `supabase/company-finance.sql` in its SQL editor. These have already been applied to the linked Kira project; do not rerun them there.
2. Replace the placeholders in `supabase/bootstrap-owner.sql` with the administrator's email and name, then run it once. There is no automatic first-user administrator.
3. Keep email confirmation enabled in Supabase Auth. Set the Site URL and allowed redirect URL to `https://Kareem-cmd.github.io/kira-workspace/`.
4. `public-config.json` contains the linked project's public URL and publishable key. To target a different project, override them with GitHub Actions variables `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`. Never use a service-role or secret key.
5. Enable Pages with GitHub Actions as the source. The included workflow tests the database rules, checks configuration, builds, and deploys on pushes to `main`.
6. The administrator signs up with the exact seeded email and confirms it. Add team members in the workspace before they sign up.

GitHub Free requires a public repository for Pages. A private repository requires a supporting GitHub plan. A private source repository does not itself make a Pages website private: CRM data is protected separately by Supabase authentication and server permissions.

## Local development

Copy `.env.example` to `.env.local`, fill in the public Supabase configuration, then run `npm ci` and `npm run dev`. For local authentication redirects, allow `http://127.0.0.1:5174/kira-workspace/` in Supabase.

Run `npm test` for PostgreSQL permission and business-rule checks and `npm run build` for type checking and the production bundle.

## Data and access

All shared records live in Supabase, not in the repository or browser local storage. Direct table access is denied; authenticated RPC functions enforce membership, role, client ownership, record versions, document snapshots, and payment limits. Administrators manage membership; sales, delivery, and finance roles have different access.

Issued documents are immutable. Payment entries cannot exceed an invoice's remaining total. Updates use version checks to avoid silently overwriting another team member's changes. Refresh the workspace to retrieve the latest changes.

The included database tests use an isolated embedded PostgreSQL database with synthetic users; they never connect to production.

## Existing workspace

This is a separate deployment copy. It does not transfer records from the existing Sites-hosted workspace automatically. Keep that workspace available and export its data before planning a verified migration. The legacy import screen supports the older Glitch clients and deals format; it is not a full backup restore facility.

## Fonts

## Company finance and interface

Company finance is restricted to active administrators and finance members, enforced inside the database. It stores editable income, expense, payroll, and asset entries with version checks. Payroll is one entry per employee per pay period and does not repeat automatically. Cancelled entries remain recorded but are excluded from totals.

Operating result uses invoice totals before tax plus manual income less expenses and payroll by entry date. Cash movement uses actual payment dates and includes asset purchases. Receivables include outstanding invoices and pending manual income across all periods. Currencies are never combined. This is a management estimate, excluding depreciation and tax adjustments, not a complete accounting ledger or bank balance. Do not duplicate invoice payments as manual income.

Sales cards support drag-and-drop, a touch drag handle, and an accessible stage selector. Lost opportunities request a reason before saving. Dashboard metrics open detail lists. Four local device themes and reduced-motion-aware animations are available.

## Font licensing

Cairo is distributed under the SIL Open Font License; the license is included in `public`.
