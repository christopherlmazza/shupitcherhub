-- SHUpitcherhub update 5: spoken logs. Keeps the transcript and the bulleted breakdown with each day's log.
alter table public.logs add column if not exists transcript text;
alter table public.logs add column if not exists summary jsonb;
