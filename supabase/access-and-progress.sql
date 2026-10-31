-- Referencia del esquema aplicado por la migración app_access_progress_admin.
-- La asignación inicial de administradores se realiza por un operador autorizado,
-- nunca desde el navegador. No volver a ejecutar sobre una base ya configurada.
begin;
create schema if not exists private;
revoke all on schema private from public,anon;
grant usage on schema private to authenticated;
create table private.app_admins(user_id uuid primary key references auth.users(id) on delete cascade);
alter table private.app_admins enable row level security;
revoke all on private.app_admins from public,anon,authenticated;
create table public.user_access(
 user_id uuid primary key references auth.users(id) on delete cascade,
 email text not null,
 status text not null default 'pending' check(status in ('pending','approved','blocked')),
 premium boolean not null default false,
 created_at timestamptz not null default now()
);
alter table public.user_access enable row level security;
revoke all on public.user_access from public,anon,authenticated;
grant select on public.user_access to authenticated;
grant update(status,premium) on public.user_access to authenticated;
create function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
select auth.uid() is not null and exists(select 1 from private.app_admins where user_id=auth.uid())
$$;
create function private.is_approved() returns boolean language sql stable security definer set search_path='' as $$
select auth.uid() is not null and exists(select 1 from public.user_access where user_id=auth.uid() and status='approved')
$$;
revoke all on function private.is_admin(),private.is_approved() from public,anon;
grant execute on function private.is_admin(),private.is_approved() to authenticated;
create policy access_read on public.user_access for select to authenticated using(user_id=(select auth.uid()) or (select private.is_admin()));
create policy access_admin_update on public.user_access for update to authenticated using((select private.is_admin()) and user_id<>(select auth.uid())) with check((select private.is_admin()) and user_id<>(select auth.uid()));
create function private.register_access() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.user_access(user_id,email) values(new.id,coalesce(new.email,'')) on conflict(user_id) do update set email=excluded.email;
 return new;
end $$;
revoke all on function private.register_access() from public,anon,authenticated;
create trigger register_app_access after insert or update of email on auth.users for each row execute function private.register_access();
insert into public.user_access(user_id,email,status) select id,coalesce(email,''),'approved' from auth.users;
create table public.game_settings(
 game_id smallint primary key check(game_id between 0 and 4),
 name text not null,
 enabled boolean not null default true,
 premium_required boolean not null default false
);
alter table public.game_settings enable row level security;
revoke all on public.game_settings from public,anon,authenticated;
grant select on public.game_settings to authenticated;
grant update(enabled,premium_required) on public.game_settings to authenticated;
insert into public.game_settings(game_id,name,premium_required) values
(0,'Saltos al cielo',false),(1,'Carrera turbo',false),(2,'Torre de bloques',false),(3,'Laberinto del tesoro',true),(4,'Guardián del portal',true);
create policy games_read on public.game_settings for select to authenticated using(true);
create policy games_admin_update on public.game_settings for update to authenticated using((select private.is_admin())) with check((select private.is_admin()));
create function private.can_play(g smallint) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
 select 1 from public.user_access a join public.game_settings s on s.game_id=g
 where a.user_id=auth.uid() and a.status='approved' and s.enabled
 and (not s.premium_required or a.premium or private.is_admin()))
$$;
revoke all on function private.can_play(smallint) from public,anon;
grant execute on function private.can_play(smallint) to authenticated;
create table public.game_progress(
 user_id uuid not null references auth.users(id) on delete cascade,
 game_id smallint not null references public.game_settings(game_id),
 unlocked smallint not null default 1 check(unlocked between 1 and 10),
 completed smallint not null default 0 check(completed between 0 and 10),
 best_score integer not null default 0 check(best_score between 0 and 200),
 attempts integer not null default 0 check(attempts between 0 and 100000),
 updated_at timestamptz not null default now(),
 primary key(user_id,game_id),
 check(completed<=unlocked)
);
alter table public.game_progress enable row level security;
revoke all on public.game_progress from public,anon,authenticated;
grant select,insert,update on public.game_progress to authenticated;
create policy progress_read on public.game_progress for select to authenticated using((user_id=(select auth.uid()) and (select private.is_approved())) or (select private.is_admin()));
create policy progress_insert on public.game_progress for insert to authenticated with check(user_id=(select auth.uid()) and private.can_play(game_id));
create policy progress_update on public.game_progress for update to authenticated using(user_id=(select auth.uid()) and private.can_play(game_id)) with check(user_id=(select auth.uid()) and private.can_play(game_id));
create function public.complete_level(p_game smallint,p_level smallint,p_score integer,p_attempts integer)
returns setof public.game_progress language plpgsql security invoker set search_path='' as $$
declare existing public.game_progress;
begin
 if auth.uid() is null or not private.can_play(p_game) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_level not between 1 and 10 or p_score not between 0 and 200 or p_attempts not between 0 and 100000 then raise exception 'Invalid result'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':'||p_game::text,0));
 select * into existing from public.game_progress where user_id=auth.uid() and game_id=p_game;
 if p_level>coalesce(existing.unlocked,1) then raise exception 'Level locked'; end if;
 return query insert into public.game_progress(user_id,game_id,unlocked,completed,best_score,attempts,updated_at)
 values(auth.uid(),p_game,least(10,p_level+1),p_level,p_score,p_attempts,now())
 on conflict(user_id,game_id) do update set
 unlocked=greatest(public.game_progress.unlocked,excluded.unlocked),
 completed=greatest(public.game_progress.completed,excluded.completed),
 best_score=greatest(public.game_progress.best_score,excluded.best_score),
 attempts=public.game_progress.attempts+excluded.attempts,updated_at=now()
 returning *;
end $$;
revoke all on function public.complete_level(smallint,smallint,integer,integer) from public,anon;
grant execute on function public.complete_level(smallint,smallint,integer,integer) to authenticated;
create table public.admin_events(
 id bigint generated always as identity primary key,
 actor uuid references auth.users(id) on delete set null,
 action text not null,
 target text not null,
 details jsonb not null,
 created_at timestamptz not null default now()
);
alter table public.admin_events enable row level security;
revoke all on public.admin_events from public,anon,authenticated;
grant select on public.admin_events to authenticated;
create policy audit_admin_read on public.admin_events for select to authenticated using((select private.is_admin()));
create function private.audit_admin_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.is_admin() then raise exception 'Admin required' using errcode='42501'; end if;
 insert into public.admin_events(actor,action,target,details) values(auth.uid(),tg_table_name,case when tg_table_name='user_access' then to_jsonb(new)->>'user_id' else to_jsonb(new)->>'game_id' end,jsonb_build_object('before',to_jsonb(old),'after',to_jsonb(new)));
 return new;
end $$;
revoke all on function private.audit_admin_change() from public,anon,authenticated;
create trigger audit_access after update of status,premium on public.user_access for each row execute function private.audit_admin_change();
create trigger audit_games after update on public.game_settings for each row execute function private.audit_admin_change();
create view public.my_app_access with(security_invoker=true) as select a.*,exists(select 1 from private.app_admins d where d.user_id=a.user_id) as is_admin from public.user_access a where a.user_id=auth.uid();
-- Use a self-scoped helper to avoid exposing administrator membership.
drop view public.my_app_access;
create view public.my_app_access with(security_invoker=true) as select a.*,(select private.is_admin()) as is_admin from public.user_access a where a.user_id=(select auth.uid());
revoke all on public.my_app_access from public,anon;
grant select on public.my_app_access to authenticated;
create policy profiles_approved on public.profiles as restrictive for all to authenticated using((select private.is_approved())) with check((select private.is_approved()));
commit;