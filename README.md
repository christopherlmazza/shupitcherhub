# SHUpitcherhub

Throwing programs, daily check-ins, workload and TrackMan data for the Sacred Heart pitching staff.

- `index.html` — the app. Coaches get the staff overview, program builder, roster/invites and setup. Pitchers sign in with an emailed link and land on their Today screen.
- `hub.html` — the existing SHUpitcherhub TrackMan/charting page, unchanged except its back link. It keeps syncing to the same team cloud row, so all fall data is still there.
- `supabase/setup.sql` — creates the throwing-program tables and access rules in the team's Supabase project.

## One-time setup

1. **Database.** Supabase → SQL Editor → paste `supabase/setup.sql`, replace `COACH_EMAIL_HERE` on the last line with the coach's email, run it.
2. **Sign-in links.** Supabase → Authentication → URL Configuration: set the Site URL to this site's GitHub Pages address and add it under Redirect URLs.
3. **Email sending.** Supabase's built-in mailer only sends a handful of emails per hour. For invites to the whole staff, add an email provider under Authentication → Emails → SMTP (Resend, SendGrid, or a Gmail app password all work).
4. **Import the Drive data.** Sign in as the coach → Setup → Import from Google Drive → choose `shu-seed.json` (kept out of this repo on purpose because it holds athletes' health notes).
5. **Invite pitchers.** Roster & invites → add each email → Send invite.

## Workload rules

Same as the Google Sheets: points per day type (Rest 0, Recovery 5, Hybrid B 8, Hybrid A 12, Bullpen 15, Velo 18, Live/Game 25, editable in Setup). Weekly load is the sum; the ratio is this week ÷ the average of up to the last 4 weeks, flagged outside 0.8–1.3. A day the pitcher logged as a different type counts as what he actually did.

Note: the sheets' formula looked up day types in a table that was shifted one column, so Live/Game days counted as 0 there. The app counts them at 25, so fall weeks with a live outing read higher here than in the sheets.
