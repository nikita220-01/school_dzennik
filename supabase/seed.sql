-- =============================================================================
--  Школьный дневник — демо-данные (справочники)
--  Запускать ПОСЛЕ миграций. Файл идемпотентный: повторный запуск безопасен.
-- =============================================================================

-- -----------------------------------------------------------------------------
--  1. Школа
-- -----------------------------------------------------------------------------
insert into public.schools (name, address, phone, email)
select 'МБОУ СОШ №1', 'г. Москва, ул. Школьная, д. 1', '+7 (495) 000-00-00', 'school@example.com'
where not exists (select 1 from public.schools);

-- -----------------------------------------------------------------------------
--  2. Учебные четверти 2025/2026
-- -----------------------------------------------------------------------------
insert into public.terms (school_id, name, short_name, starts_on, ends_on, sort_order)
select sc.id, v.name, v.short_name, v.starts_on::date, v.ends_on::date, v.sort_order
from (select id from public.schools order by created_at limit 1) sc
cross join (values
  ('I четверть',   'I',   '2025-09-01', '2025-10-26', 1),
  ('II четверть',  'II',  '2025-11-05', '2025-12-28', 2),
  ('III четверть', 'III', '2026-01-12', '2026-03-22', 3),
  ('IV четверть',  'IV',  '2026-04-01', '2026-05-29', 4)
) as v (name, short_name, starts_on, ends_on, sort_order)
on conflict (school_id, name) do nothing;

-- -----------------------------------------------------------------------------
--  3. Предметы
-- -----------------------------------------------------------------------------
insert into public.subjects (school_id, name, short_name, color)
select sc.id, v.name, v.short_name, v.color
from (select id from public.schools order by created_at limit 1) sc
cross join (values
  ('Алгебра',            'Алг.',    '#6366f1'),
  ('Геометрия',          'Геом.',   '#8b5cf6'),
  ('Русский язык',       'Рус. яз.','#ef4444'),
  ('Литература',         'Лит-ра',  '#f97316'),
  ('История',            'Ист.',    '#f59e0b'),
  ('Обществознание',     'Общ.',    '#eab308'),
  ('Физика',             'Физ.',    '#10b981'),
  ('Химия',              'Хим.',    '#14b8a6'),
  ('Биология',           'Биол.',   '#22c55e'),
  ('География',          'Геогр.',  '#06b6d4'),
  ('Английский язык',    'Англ.',   '#3b82f6'),
  ('Информатика',        'Инф.',    '#0ea5e9'),
  ('Физическая культура','Физ-ра',  '#84cc16'),
  ('Основы безопасности','ОБЗР',    '#a855f7'),
  ('Технология',         'Техн.',   '#ec4899')
) as v (name, short_name, color)
on conflict (school_id, name) do nothing;

-- -----------------------------------------------------------------------------
--  4. Класс 7А
-- -----------------------------------------------------------------------------
insert into public.classes (school_id, name, grade_level, academic_year, room, invite_code)
select sc.id, '7А', 7, '2025/2026', '201', '7A2025'
from (select id from public.schools order by created_at limit 1) sc
on conflict (school_id, name, academic_year) do nothing;
