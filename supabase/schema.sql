-- Duoduo Fitness cloud persistence (Supabase/Postgres)
-- Run this in the Supabase SQL editor once.

create table if not exists public.fitness_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  schema_version integer not null default 1
);

alter table public.fitness_snapshots enable row level security;

drop policy if exists "Users can read own fitness snapshot" on public.fitness_snapshots;
create policy "Users can read own fitness snapshot"
on public.fitness_snapshots for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert own fitness snapshot" on public.fitness_snapshots;
create policy "Users can insert own fitness snapshot"
on public.fitness_snapshots for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own fitness snapshot" on public.fitness_snapshots;
create policy "Users can update own fitness snapshot"
on public.fitness_snapshots for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create or replace function public.touch_fitness_snapshot_updated_at()
returns trigger
language plpgsql
security invoker
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_fitness_snapshot_updated_at on public.fitness_snapshots;
create trigger trg_fitness_snapshot_updated_at
before update on public.fitness_snapshots
for each row execute function public.touch_fitness_snapshot_updated_at();

-- Optional storage bucket for future progress photos/meal photos.
insert into storage.buckets (id, name, public)
values ('fitness-private', 'fitness-private', false)
on conflict (id) do nothing;

-- A user can only access objects stored under their own auth UID prefix.
drop policy if exists "Users can read own fitness files" on storage.objects;
create policy "Users can read own fitness files"
on storage.objects for select
using (bucket_id = 'fitness-private' and auth.uid()::text = (storage.foldername(name))[1]);

drop policy if exists "Users can upload own fitness files" on storage.objects;
create policy "Users can upload own fitness files"
on storage.objects for insert
with check (bucket_id = 'fitness-private' and auth.uid()::text = (storage.foldername(name))[1]);

drop policy if exists "Users can update own fitness files" on storage.objects;
create policy "Users can update own fitness files"
on storage.objects for update
using (bucket_id = 'fitness-private' and auth.uid()::text = (storage.foldername(name))[1])
with check (bucket_id = 'fitness-private' and auth.uid()::text = (storage.foldername(name))[1]);

drop policy if exists "Users can delete own fitness files" on storage.objects;
create policy "Users can delete own fitness files"
on storage.objects for delete
using (bucket_id = 'fitness-private' and auth.uid()::text = (storage.foldername(name))[1]);
