-- SHUpitcherhub update 3: pitchers can edit their own program days (never anyone else's).
drop policy if exists programs_athlete_update on public.programs;
drop policy if exists programs_athlete_insert on public.programs;
create policy programs_athlete_update on public.programs for update to authenticated using (athlete_id = public.my_athlete_id()) with check (athlete_id = public.my_athlete_id());
create policy programs_athlete_insert on public.programs for insert to authenticated with check (athlete_id = public.my_athlete_id());
