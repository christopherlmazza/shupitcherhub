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

## Program days, drill library, videos

Each program day can carry drills in four sections (Pre-work, Throwing, Med ball, Bullpen / live focus), notes per drill, notes per section and overall day notes. Any drill typed in the builder is saved to the drill library (Setup → Drill library), where it can be renamed, filed under a section and given default cues. Pitchers can post videos (upload up to 50 MB, or a link) with their own notes; the coach adds feedback. Uploads live in a private Supabase Storage bucket readable only by the coach and that pitcher. Run `supabase/02_videos_updates.sql` once to enable this.

The coach home page pops up anything new from pitchers since the coach last looked (logs, check-ins, videos); the Updates button in the top bar reopens it.

## Return to throw

Return-to-throw programs are their own day type with a workload computed per throw, using the elbow-torque model from the published interval-throwing workload study (IJSPT): flat-ground throws by distance, velo-target throws by effort (target ÷ the pitcher's top TrackMan velo), each throw weighted (torque/74 Nm)^1.3 and scaled so 50 catch-play throws ≈ a Hybrid B day and a 75-pitch outing ≈ a Live/Game day. Put a sheet on the calendar from the pitcher's Return to Throw tab; tap any day to adjust throws, velo or distance.

## Workload rules

Same as the Google Sheets: points per day type (Rest 0, Recovery 5, Hybrid B 8, Hybrid A 12, Bullpen 15, Velo 18, Live/Game 25, editable in Setup). Weekly load is the sum; the ratio is this week ÷ the average of up to the last 4 weeks, flagged outside 0.8–1.3. A day the pitcher logged as a different type counts as what he actually did.

Note: the sheets' formula looked up day types in a table that was shifted one column, so Live/Game days counted as 0 there. The app counts them at 25, so fall weeks with a live outing read higher here than in the sheets.
