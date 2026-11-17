begin;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  email text not null,
  phone text not null,
  role text not null default 'user' check (role in ('admin', 'user')),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now()
);

create index profiles_status_created_at_idx
  on public.profiles (status, created_at, id);

create function public.create_profile_on_signup()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.is_anonymous is not true and new.email is not null then
    insert into public.profiles (id, full_name, email, phone)
    values (
      new.id,
      btrim(coalesce(new.raw_user_meta_data ->> 'full_name', '')),
      new.email,
      btrim(coalesce(new.raw_user_meta_data ->> 'phone', ''))
    );
  end if;
  return new;
end;
$$;

revoke all on function public.create_profile_on_signup()
  from public, anon, authenticated;

create trigger waiting_room_create_profile
after insert on auth.users
for each row execute function public.create_profile_on_signup();

-- Les comptes email déjà présents doivent eux aussi être validés.
insert into public.profiles (id, full_name, email, phone, created_at)
select id, btrim(coalesce(raw_user_meta_data ->> 'full_name', '')), email,
       btrim(coalesce(raw_user_meta_data ->> 'phone', '')), created_at
from auth.users
where is_anonymous is not true and email is not null;

create function public.is_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin' and status = 'approved'
  );
$$;

create function public.is_approved()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and status = 'approved'
  );
$$;

revoke all on function public.is_admin(), public.is_approved()
  from public, anon, authenticated;
grant execute on function public.is_admin(), public.is_approved()
  to authenticated;

alter table public.profiles enable row level security;
revoke all on table public.profiles from public, anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (full_name, email, phone, role, status)
  on table public.profiles to authenticated;

create policy profiles_read_self_or_admin on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

create policy profiles_update_admin on public.profiles
  for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- Remplacer les anciennes règles permissives de la file et retirer
-- l'exécution des anciennes signatures de la RPC d'ajout.
do $$
declare
  old_policy record;
  old_rpc record;
begin
  for old_policy in
    select policyname from pg_catalog.pg_policies
    where schemaname = 'public' and tablename = 'clients'
  loop
    execute format('drop policy %I on public.clients', old_policy.policyname);
  end loop;

  for old_rpc in
    select p.oid::regprocedure as signature
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'register_queue_client'
      and p.prokind = 'f'
  loop
    execute format('revoke all on function %s from public, anon, authenticated',
                   old_rpc.signature);
  end loop;
end;
$$;

alter table public.clients enable row level security;
revoke all on table public.clients from public, anon, authenticated;
grant select, insert, delete on table public.clients to authenticated;

create policy clients_read_approved on public.clients
  for select to authenticated using ((select public.is_approved()));

create policy clients_insert_approved on public.clients
  for insert to authenticated
  with check ((select public.is_approved()) and length(btrim(name)) > 0);

create policy clients_delete_admin on public.clients
  for delete to authenticated using ((select public.is_admin()));

drop function if exists public.register_queue_client(
  uuid, text, double precision, double precision, double precision, timestamptz
);

create function public.register_queue_client(
  p_id uuid, p_name text, p_lat double precision, p_lng double precision,
  p_accuracy double precision, p_created_at timestamptz
)
returns void
language plpgsql security invoker set search_path = ''
as $$
begin
  if not public.is_approved() then
    raise exception 'Compte non approuvé' using errcode = '42501';
  end if;
  insert into public.clients (id, name, lat, lng, location_accuracy_m, created_at)
  values (p_id, btrim(p_name), p_lat, p_lng, p_accuracy, coalesce(p_created_at, now()))
  on conflict (id) do nothing;
end;
$$;

revoke all on function public.register_queue_client(
  uuid, text, double precision, double precision, double precision, timestamptz
) from public, anon, authenticated;
grant execute on function public.register_queue_client(
  uuid, text, double precision, double precision, double precision, timestamptz
) to authenticated;

-- p_expected_id protège contre une file modifiée après l'affichage.
create function public.next_client(p_expected_id uuid)
returns uuid
language plpgsql security invoker set search_path = ''
as $$
declare
  first_id uuid;
  deleted_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Action réservée à un administrateur' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(78210561);
  select id into first_id
  from public.clients
  order by created_at asc nulls last, id asc
  limit 1;

  if first_id is null or first_id is distinct from p_expected_id then
    raise exception 'La file a changé. Actualisez avant de réessayer.'
      using errcode = 'P0001';
  end if;

  delete from public.clients where id = first_id returning id into deleted_id;
  if deleted_id is null then
    raise exception 'La file a changé. Actualisez avant de réessayer.'
      using errcode = 'P0001';
  end if;
  return deleted_id;
end;
$$;

revoke all on function public.next_client(uuid) from public, anon, authenticated;
grant execute on function public.next_client(uuid) to authenticated;

do $$
begin
  if exists (select 1 from pg_catalog.pg_publication
             where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_catalog.pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public'
         and tablename = 'clients'
     ) then
    alter publication supabase_realtime add table public.clients;
  end if;
end;
$$;

commit;
