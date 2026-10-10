-- =============================================================================
--  10. ДОМАШНЕЕ ЗАДАНИЕ ПО ДНЯМ (класс — предмет — дата — текст)
--
--  Вкладка «Домашнее задание»: учитель пишет задание в клетку дня,
--  ученики и родители читают.
--
--  ВАЖНО: таблица называется day_homework, а не homework, потому что
--  таблица public.homework уже занята схемой 01_core_tables
--  (lesson_id, description, due_date — её читают представления).
--  Идемпотентно: повторный запуск безопасен.
-- =============================================================================

create table if not exists public.day_homework (
  id            uuid primary key default gen_random_uuid(),
  class_id      uuid not null references public.classes (id) on delete cascade,
  subject_id    uuid not null references public.subjects (id) on delete cascade,
  homework_date date not null,
  text          text not null default '',
  updated_at    timestamptz not null default now(),
  unique (class_id, subject_id, homework_date)
);

comment on table public.day_homework
  is 'Домашнее задание по дням: класс — предмет — дата — текст';

create index if not exists day_homework_class_subject_date_idx
  on public.day_homework (class_id, subject_id, homework_date);

alter table public.day_homework enable row level security;

-- Читают все вошедшие
drop policy if exists day_homework_select on public.day_homework;
create policy day_homework_select on public.day_homework
  for select to authenticated using (true);

-- Пишет только учитель/админ
drop policy if exists day_homework_insert on public.day_homework;
create policy day_homework_insert on public.day_homework
  for insert to authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('teacher', 'admin')
    )
  );

drop policy if exists day_homework_update on public.day_homework;
create policy day_homework_update on public.day_homework
  for update to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('teacher', 'admin')
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('teacher', 'admin')
    )
  );

-- Удалять (очищать клетку) может только учитель/админ (у DELETE только USING)
drop policy if exists day_homework_delete on public.day_homework;
create policy day_homework_delete on public.day_homework
  for delete to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('teacher', 'admin')
    )
  );