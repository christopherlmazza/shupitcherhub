-- SHUpitcherhub update 7: add coaches the same way as pitchers.
-- Adding a coach puts their email on the staff list and creates their login on the team password.
-- They're asked to pick their own password after first signing in. Passwords stay bcrypt-hashed; nobody can read them.

-- Internal: create a login on the team password, or reset one (no staff check, so it also works for coaches).
create or replace function public._team_login(target text, force boolean) returns text
language plpgsql security definer set search_path = public, auth, extensions as $$
declare pw text; uid uuid; meta jsonb;
begin
  select value into pw from public.secrets where key = 'team_password';
  if pw is null then raise exception 'Set the team password in Setup first'; end if;
  target := lower(trim(target));
  select id, coalesce(raw_user_meta_data,'{}'::jsonb) into uid, meta from auth.users where lower(email) = target;
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', target,
      extensions.crypt(pw, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{"pw_set":true,"default_pw":true}'::jsonb, now(), now(),
      '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text, jsonb_build_object('sub', uid::text, 'email', target, 'email_verified', true), 'email', now(), now(), now());
    return 'created';
  end if;
  if not force and (meta->>'pw_changed') = 'true' then return 'kept (chose their own)'; end if;
  update auth.users set encrypted_password = extensions.crypt(pw, extensions.gen_salt('bf')),
    email_confirmed_at = coalesce(email_confirmed_at, now()),
    raw_user_meta_data = meta || '{"pw_set":true,"default_pw":true,"pw_changed":false}'::jsonb,
    updated_at = now()
  where id = uid;
  if not exists (select 1 from auth.identities where user_id = uid and provider = 'email') then
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text, jsonb_build_object('sub', uid::text, 'email', target, 'email_verified', true), 'email', now(), now(), now());
  end if;
  return 'set to team password';
end $$;
revoke all on function public._team_login(text, boolean) from public, anon, authenticated;

-- Coach: add another coach (or re-send to one). Never touches the signed-in coach's own password.
create or replace function public.add_coach(target text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_coach() then raise exception 'Only coaches can do this'; end if;
  target := lower(trim(target));
  if target !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'That doesn''t look like an email'; end if;
  insert into public.staff(email) values (target) on conflict do nothing;
  if target = lower(auth.jwt() ->> 'email') then return 'that''s you'; end if;
  return public._team_login(target, false);
end $$;

-- Coach: put another coach back on the team password.
create or replace function public.reset_coach_password(target text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_coach() then raise exception 'Only coaches can do this'; end if;
  target := lower(trim(target));
  if target = lower(auth.jwt() ->> 'email') then raise exception 'Use the Password button to change your own'; end if;
  if not exists (select 1 from public.staff where lower(email) = target) then raise exception 'Not on the coach list'; end if;
  return public._team_login(target, true);
end $$;

-- Coach: take a coach off the list (their login stays but sees nothing unless they're also on the roster).
create or replace function public.remove_coach(target text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_coach() then raise exception 'Only coaches can do this'; end if;
  if lower(trim(target)) = lower(auth.jwt() ->> 'email') then raise exception 'You can''t remove yourself'; end if;
  delete from public.staff where lower(email) = lower(trim(target));
end $$;

-- Coach: the coach list with login status. Never returns passwords.
create or replace function public.coach_status() returns table(email text, has_login boolean, on_team_password boolean, last_sign_in timestamptz)
language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_coach() then raise exception 'Only coaches can do this'; end if;
  return query select lower(s.email), u.id is not null, coalesce((u.raw_user_meta_data->>'default_pw')::boolean, false), u.last_sign_in_at
    from public.staff s left join auth.users u on lower(u.email) = lower(s.email) order by 1;
end $$;

grant execute on function public.add_coach(text), public.reset_coach_password(text), public.remove_coach(text), public.coach_status() to authenticated;
