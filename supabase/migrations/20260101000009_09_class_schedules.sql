-- =============================================================================
--  09. РАСПИСАНИЕ КЛАССОВ (день недели — урок — предмет)
--
--  Вкладка «Расписание»: учитель заполняет сетку по дням для каждого класса,
--  ученики и родители видят. Идемпотентно: повторный запуск безопасен.
-- =============================================================================

create table if not exists public.class_schedules (
  id            uuid primary key default gen_random_uuid(),
  class_id      uuid not null references public.classes (id) on delete cascade,
  weekday       smallint not null check (weekday between 1 and 6),
  lesson_number smallint not null check (lesson_number between 1 and 12),
  subject_id    uuid not null references public.subjects (id) on delete cascade,
  updated_at    timestamptz not null default now(),
  unique (class_id, weekday, lesson_number)
);

comment on table public.class_schedules
  is 'Расписание класса: день недели (1=Пн…6=Сб) — номер урока — предмет';

create index if not exists class_schedules_class_idx
  on public.class_schedules (class_id);

alter table public.class_schedules enable row level security;

-- Видят все вошедшие
drop policy if exists class_schedules_select on public.class_schedules;
create policy class_schedules_select on public.class_schedules
  for select to authenticated using (true);

-- Заполнять может только учитель/админ
drop policy if exists class_schedules_insert on public.class_schedules;
create policy class_schedules_insert on public.class_schedules
  for insert to authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('teacher', 'admin')
    )
  );

drop policy if exists class_schedules_update on public.class_schedules;
create policy class_schedules_update on public.class_schedules
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

-- Убирать предмет может только учитель/админ (у DELETE только USING)
drop policy if exists class_schedules_delete on public.class_schedules;
create policy class_schedules_delete on public.class_schedules
  for delete to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('teacher', 'admin')
    )
  );