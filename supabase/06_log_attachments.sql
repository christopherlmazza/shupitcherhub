-- SHUpitcherhub update 6: photos, videos and files on a day's log. Files live in the private "videos" storage bucket
-- under the pitcher's own folder, so only he and the coaches can open them.
alter table public.logs add column if not exists attachments jsonb default '[]'::jsonb;
