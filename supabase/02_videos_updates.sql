-- SHUpitcherhub update 2: who wrote each log, pitcher videos, private video storage.
alter table public.logs add column if not exists author text;

create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  athlete_id text references public.athletes(id) on delete cascade,
  title text, date date, notes text, url text, path text, coach_note text, author text,
  created_at timestamptz default now(), updated_at timestamptz default now());
alter table public.videos enable row level security;
drop policy if exists videos_read on public.videos;
drop policy if exists videos_insert on public.videos;
drop policy if exists videos_update on public.videos;
drop policy if exists videos_delete on public.videos;
create policy videos_read   on public.videos for select to authenticated using (public.is_coach() or athlete_id = public.my_athlete_id());
create policy videos_insert on public.videos for insert to authenticated with check (public.is_coach() or athlete_id = public.my_athlete_id());
create policy videos_update on public.videos for update to authenticated using (public.is_coach() or athlete_id = public.my_athlete_id()) with check (public.is_coach() or athlete_id = public.my_athlete_id());
create policy videos_delete on public.videos for delete to authenticated using (public.is_coach() or athlete_id = public.my_athlete_id());

insert into storage.buckets (id, name, public, file_size_limit) values ('videos', 'videos', false, 52428800) on conflict (id) do nothing;
drop policy if exists shu_videos_read on storage.objects;
drop policy if exists shu_videos_insert on storage.objects;
drop policy if exists shu_videos_delete on storage.objects;
create policy shu_videos_read   on storage.objects for select to authenticated using (bucket_id = 'videos' and (public.is_coach() or (storage.foldername(name))[1] = public.my_athlete_id()));
create policy shu_videos_insert on storage.objects for insert to authenticated with check (bucket_id = 'videos' and (public.is_coach() or (storage.foldername(name))[1] = public.my_athlete_id()));
create policy shu_videos_delete on storage.objects for delete to authenticated using (bucket_id = 'videos' and (public.is_coach() or (storage.foldername(name))[1] = public.my_athlete_id()));
