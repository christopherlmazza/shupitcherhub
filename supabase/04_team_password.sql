-- SHUpitcherhub update 4: team default password, accounts created by the coach, no emails needed.
-- The default password itself is never stored in this file or the site's code: the coach types it in Setup,
-- and it is kept in a table no browser can read. Players can change theirs at any time; the coach can reset
-- anyone back to the team password. Passwords are only ever stored hashed (bcrypt), so nobody can read them.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.secrets (key text primary key, value text);
alter table public.secrets enable row level security;   -- no policies: unreadable from the site

create or replace function public.set_team_password(pw text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_coach() then raise exception 'Only coaches can do this'; end if;
  if length(coalesce(pw,'')) < 8 then raise exception 'Use at least 8 characters'; end if;
  insert into public.secrets(key,value) values ('team_password', pw) on conflict (key) do update set value = excluded.value;
end $$;

create or replace function public.team_password_is_set() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_coach() and exists (select 1 from public.secrets where key = 'team_password');
$$;

-- Internal: create the login for one email, or reset it to the team password.
create or replace function public._apply_team_password(target text, force boolean) returns text
language plpgsql security definer set search_path = public, auth, extensions as $$
declare pw text; uid uuid; meta jsonb;
begin
  select value into pw from public.secrets where key = 'team_password';
  if pw is null then raise exception 'Set the team password in Setup first'; end if;
  target := lower(trim(target));
  if exists (select 1 from public.staff where lower(email) = target) then return 'coach (skipped)'; end if;
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
  if not force and (meta->>'pw_changed') = 'true' then return 'kept (he chose his own)'; end if;
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
revoke all on function public._apply_team_password(text, boolean) from public, anon, authenticated;

-- Coach: give every rostered pitcher with an email a login (doesn't touch anyone who chose his own password).
create or replace function public.provision_roster() returns table(email text, result text)
language plpgsql security definer set search_path = public as $$
declare a record;
begin
  if not public.is_coach() then raise exception 'Only coaches can do this'; end if;
  for a in select lower(trim(x.email)) as em from public.athletes x where coalesce(trim(x.email),'') <> '' loop
    email := a.em; result := public._apply_team_password(a.em, false); return next;
  end loop;
end $$;

-- Coach: put one pitcher back on the team password (works even if he changed it).
create or replace function public.reset_to_team_password(target text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_coach() then raise exception 'Only coaches can do this'; end if;
  if not exists (select 1 from public.athletes where lower(email) = lower(trim(target))) then raise exception 'That email is not on the roster'; end if;
  return public._apply_team_password(target, true);
end $$;

-- Coach: who has a login, who is still on the team password, last sign-in. Never returns passwords.
create or replace function public.account_status() returns table(email text, has_login boolean, on_team_password boolean, last_sign_in timestamptz)
language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_coach() then raise exception 'Only coaches can do this'; end if;
  return query select lower(x.email), u.id is not null, coalesce((u.raw_user_meta_data->>'default_pw')::boolean, false), u.last_sign_in_at
    from public.athletes x left join auth.users u on lower(u.email) = lower(x.email) where coalesce(trim(x.email),'') <> '';
end $$;

grant execute on function public.set_team_password(text), public.team_password_is_set(), public.provision_roster(),
  public.reset_to_team_password(text), public.account_status() to authenticated;
