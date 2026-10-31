-- Ejecutar una vez en el proyecto Supabase de esta app.
begin;
create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '' check (char_length(name) <= 90),
  email text not null default '' check (char_length(email) <= 150),
  phone text not null default '' check (char_length(phone) <= 35),
  city text not null default '' check (char_length(city) <= 80),
  bio text not null default '' check (char_length(bio) <= 280)
);
alter table public.profiles enable row level security;
revoke all on public.profiles from anon;
revoke all on public.profiles from authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
create policy "Read own profile" on public.profiles for select to authenticated using ((select auth.uid()) = user_id);
create policy "Insert own profile" on public.profiles for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Update own profile" on public.profiles for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Delete own profile" on public.profiles for delete to authenticated using ((select auth.uid()) = user_id);
commit;
