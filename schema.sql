-- ============================================================
--  Cousins Track — Supabase schema, security & storage
--  Paste this ENTIRE file into the Supabase SQL Editor and Run.
--  Safe to re-run (idempotent).
-- ============================================================

-- 1) TABLES ---------------------------------------------------

create table if not exists public.boards (
  id          text primary key,
  owner       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name        text not null default 'Untitled board',
  data        jsonb not null default '{}'::jsonb,   -- groups / columns / statuses / tasks
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.board_members (
  board_id  text not null references public.boards(id) on delete cascade,
  email     text not null,
  name      text,
  color     text,
  role      text not null default 'editor' check (role in ('admin','editor','viewer')),
  primary key (board_id, email)
);

create table if not exists public.templates (
  id     text primary key,
  owner  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name   text not null default 'Template',
  data   jsonb not null default '{}'::jsonb          -- { color, tasks: [...] }
);

create index if not exists board_members_email_idx on public.board_members (lower(email));

-- 2) HELPER FUNCTIONS ----------------------------------------
-- SECURITY DEFINER lets these read board_members without tripping
-- the RLS policies that reference them (avoids infinite recursion).

create or replace function public.current_email()
returns text language sql stable as $$
  select lower(coalesce((auth.jwt() ->> 'email'), ''))
$$;

create or replace function public.board_role(bid text)
returns text language sql stable security definer set search_path = public as $$
  select role from public.board_members
   where board_id = bid and lower(email) = public.current_email()
   limit 1
$$;

-- When a board is created, add its creator as an admin member.
create or replace function public.add_owner_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.board_members (board_id, email, role)
  values (new.id, public.current_email(), 'admin')
  on conflict (board_id, email) do nothing;
  return new;
end $$;

drop trigger if exists trg_add_owner_member on public.boards;
create trigger trg_add_owner_member
  after insert on public.boards
  for each row execute function public.add_owner_member();

-- keep updated_at fresh
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists trg_touch_boards on public.boards;
create trigger trg_touch_boards before update on public.boards
  for each row execute function public.touch_updated_at();

-- 3) ROW LEVEL SECURITY --------------------------------------

alter table public.boards        enable row level security;
alter table public.board_members enable row level security;
alter table public.templates     enable row level security;

-- boards
drop policy if exists boards_select on public.boards;
create policy boards_select on public.boards for select to authenticated
  using (owner = auth.uid() or public.board_role(id) is not null);

drop policy if exists boards_insert on public.boards;
create policy boards_insert on public.boards for insert to authenticated
  with check (owner = auth.uid());

drop policy if exists boards_update on public.boards;
create policy boards_update on public.boards for update to authenticated
  using      (owner = auth.uid() or public.board_role(id) in ('admin','editor'))
  with check (owner = auth.uid() or public.board_role(id) in ('admin','editor'));

drop policy if exists boards_delete on public.boards;
create policy boards_delete on public.boards for delete to authenticated
  using (owner = auth.uid() or public.board_role(id) = 'admin');

-- board_members: members can read the roster; admins/owner manage it
drop policy if exists members_select on public.board_members;
create policy members_select on public.board_members for select to authenticated
  using (
    public.board_role(board_id) is not null
    or exists (select 1 from public.boards b where b.id = board_id and b.owner = auth.uid())
  );

drop policy if exists members_write on public.board_members;
create policy members_write on public.board_members for all to authenticated
  using (
    public.board_role(board_id) = 'admin'
    or exists (select 1 from public.boards b where b.id = board_id and b.owner = auth.uid())
  )
  with check (
    public.board_role(board_id) = 'admin'
    or exists (select 1 from public.boards b where b.id = board_id and b.owner = auth.uid())
  );

-- templates: private to their owner
drop policy if exists templates_all on public.templates;
create policy templates_all on public.templates for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

-- 4) DATA API GRANTS -----------------------------------------
-- Ensures the auto-generated REST API can reach these tables even
-- under Supabase's newer "explicit grant" behaviour. RLS still
-- decides which ROWS each user can see.
grant usage on schema public to authenticated;
grant select, insert, update, delete
  on public.boards, public.board_members, public.templates
  to authenticated;

-- 5) STORAGE (file attachments) ------------------------------
-- Private bucket; files live at  <board_id>/<task_id>/<filename>.
insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', false)
on conflict (id) do nothing;

drop policy if exists att_read on storage.objects;
create policy att_read on storage.objects for select to authenticated
  using (bucket_id = 'attachments'
         and public.board_role((storage.foldername(name))[1]) is not null);

drop policy if exists att_insert on storage.objects;
create policy att_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'attachments'
              and public.board_role((storage.foldername(name))[1]) in ('admin','editor'));

drop policy if exists att_delete on storage.objects;
create policy att_delete on storage.objects for delete to authenticated
  using (bucket_id = 'attachments'
         and public.board_role((storage.foldername(name))[1]) in ('admin','editor'));

-- Done.
