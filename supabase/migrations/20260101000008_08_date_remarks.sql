-- =============================================================================
--  08. ЗАМЕЧАНИЯ ПО ДАТАМ (дата — замечание — просьба)
--
--  Нижний блок экрана «Отметки»/«Дневник»: учитель фиксирует событие дня
--  и просьбу, ученики и родители видят список за неделю.
--  Идемпотентно: повторный запуск безопасен.
-- =============================================================================

create table if not exists public.date_remarks (
  id          uuid primary key default gen_random_uuid(),
  class_id    uuid not null references public.classes (id) on delete cascade,
  remark_date date not null,
  remark      text not null default '',
  request     text not null default '',
  created_by  uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

comment on table public.date_remarks
  is 'Замечания по датам: дата — замечание — просьба';

create index if not exists date_remarks_class_date_idx
  on public.date_remarks (class_id, remark_date);

alter table public.date_remarks enable row level security;

-- Видят все вошедшие (журнал не хранит секретов)
drop policy if exists date_remarks_select on public.date_remarks;
create policy date_remarks_select on public.date_remarks
  for select to authenticated using (true);

-- Добавлять может только учитель/админ (по роли в профиле)
drop policy if exists date_remarks_insert on public.date_remarks;
create policy date_remarks_insert on public.date_remarks
  for insert to authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('teacher', 'admin')
    )
  );

-- Удалять может только учитель/админ (у DELETE разрешён только USING — WITH CHECK запрещён)
drop policy if exists date_remarks_delete on public.date_remarks;
create policy date_remarks_delete on public.date_remarks
  for delete to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('teacher', 'admin')
    )
  );