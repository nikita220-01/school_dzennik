-- =============================================================================
--  ШКОЛЬНЫЙ ДНЕВНИК — ЗАПУСТИТЬ ВСЁ ОДНИМ ФАЙЛОМ
--
--  Этот файл склеен из 6 частей (создан автоматически, порядок важен):
--    1) migrations/20260101000000_00_extensions_and_types.sql   — расширения и ENUM
--    2) migrations/20260101000001_01_core_tables.sql            — 15 таблиц и индексы
--    3) migrations/20260101000002_02_functions_and_triggers.sql — функции и триггеры
--    4) migrations/20260101000003_03_rls_policies.sql           — права доступа (RLS)
--    5) migrations/20260101000004_04_views.sql                  — 5 представлений (VIEW)
--    6) seed.sql                                                — демо-данные: школа, четверти, 11 предметов, класс 7А
--    7) promote_teacher.sql                                     — назначение роли «учитель» (ничего не изменит,
--                                                                 пока вы не замените e-mail внутри)
--
--  КАК ЗАПУСКАТЬ
--    1. Supabase → ваш проект → SQL Editor → New query.
--    2. Откройте этот файл, выделите всё (Ctrl+A), скопируйте (Ctrl+C) и вставьте в редактор.
--    3. Нажмите Run (Ctrl+Enter). Ожидаемый результат: «Success. No rows returned».
--    4. Проверка в новом запросе:
--         select table_name from information_schema.tables where table_schema = 'public' order by 1;
--         select count(*) from public.subjects;   -- предметы
--         select name from public.classes;        -- 7А
--
--  ФАЙЛ ИДЕМПОТЕНТНЫЙ: повторный запуск безопасен (if not exists / create or replace /
--  drop ... if exists), поэтому его можно прогнать ещё раз, если проект «поехал».
--  Хотите по шагам и с остановками — запускайте исходные файлы по одному из папки supabase/migrations.
-- =============================================================================

-- >>>>>>>>>>>>>>>>>>>>>> НАЧАЛО: supabase\migrations\20260101000000_00_extensions_and_types.sql >>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
--  Школьный дневник — шаг 00. Расширения и перечисления (ENUM)
--  Файл идемпотентный: его можно запускать повторно без ошибок.
--  Порядок применения: 00 -> 01 -> 02 -> 03 -> 04 -> seed.sql
-- =============================================================================

-- Схема для расширений (в Supabase она уже есть, в локальной проверке создаём сами)
create schema if not exists extensions;

-- pgcrypto: gen_random_uuid(), а также crypt()/gen_salt() для демо-аккаунтов
create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
--  Перечисления
-- -----------------------------------------------------------------------------
do $do$
begin
  -- Роль пользователя
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'user_role' and n.nspname = 'public'
  ) then
    create type public.user_role as enum ('admin', 'teacher', 'student', 'parent');
  end if;

  -- Посещаемость урока
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'attendance_status' and n.nspname = 'public'
  ) then
    create type public.attendance_status as enum ('present', 'absent', 'late', 'excused');
  end if;

  -- Тип оценки
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'grade_kind' and n.nspname = 'public'
  ) then
    create type public.grade_kind as enum ('current', 'homework', 'test', 'oral', 'project', 'final');
  end if;

  -- Статус выполнения домашнего задания
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'homework_status' and n.nspname = 'public'
  ) then
    create type public.homework_status as enum ('assigned', 'in_progress', 'done', 'partial', 'not_done');
  end if;
end
$do$;

comment on type public.user_role is
  'Роль пользователя: admin — администрация/завуч, teacher — учитель, student — ученик, parent — родитель';
comment on type public.attendance_status is
  'Посещаемость: present — был, absent — отсутствовал, late — опоздал, excused — уважительная причина';
comment on type public.grade_kind is
  'Тип оценки: current — текущая, homework — за домашнюю, test — контрольная, oral — устный ответ, project — проект, final — итоговая';
comment on type public.homework_status is
  'Статус домашнего задания: assigned — задано, in_progress — в работе, done — выполнено, partial — частично, not_done — не выполнено';

-- <<<<<<<<<<<<<<<<<<<<<< КОНЕЦ: supabase\migrations\20260101000000_00_extensions_and_types.sql <<<<<<<<<<<<<<<<<<<<<<

-- >>>>>>>>>>>>>>>>>>>>>> НАЧАЛО: supabase\migrations\20260101000001_01_core_tables.sql >>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
--  Школьный дневник — шаг 01. Основные таблицы и индексы
--  Файл идемпотентный (create table if not exists).
-- =============================================================================

-- -----------------------------------------------------------------------------
--  Школа
-- -----------------------------------------------------------------------------
create table if not exists public.schools (
  id         uuid primary key default gen_random_uuid(),
  name       text        not null,
  address    text,
  phone      text,
  email      text,
  created_at timestamptz not null default now()
);

comment on table  public.schools is 'Учебное заведение. В MVP обычно одна строка.';
comment on column public.schools.name is 'Полное название школы, например «МБОУ СОШ №1 г. Москвы»';

-- -----------------------------------------------------------------------------
--  Профили пользователей (1:1 с auth.users)
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  school_id  uuid references public.schools (id) on delete set null,
  role       public.user_role not null default 'student',
  full_name  text    not null default '',
  email      text,
  phone      text,
  avatar_url text,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_full_name_check check (char_length(full_name) <= 200)
);

comment on table  public.profiles is 'Публичный профиль пользователя; создаётся автоматически при регистрации';
comment on column public.profiles.role is 'Роль: admin / teacher / student / parent. Меняет только администратор.';

-- -----------------------------------------------------------------------------
--  Учебные четверти (периоды)
-- -----------------------------------------------------------------------------
create table if not exists public.terms (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools (id) on delete cascade,
  name       text not null,
  short_name text,
  starts_on  date not null,
  ends_on    date not null,
  sort_order smallint not null default 1,
  constraint terms_dates_check check (ends_on >= starts_on),
  unique (school_id, name)
);

comment on table public.terms is 'Учебные периоды (четверти / триместры / полугодия)';

-- -----------------------------------------------------------------------------
--  Классы
-- -----------------------------------------------------------------------------
create table if not exists public.classes (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid not null references public.schools (id) on delete cascade,
  name             text not null,
  grade_level      smallint,
  academic_year    text not null default '2025/2026',
  room             text,
  class_teacher_id uuid references public.profiles (id) on delete set null,
  invite_code      text not null default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)),
  created_at       timestamptz not null default now(),
  constraint classes_grade_level_check check (grade_level is null or grade_level between 1 and 11),
  unique (school_id, name, academic_year)
);

comment on table  public.classes is 'Класс, например 7А в 2025/2026 учебном году';
comment on column public.classes.class_teacher_id is 'Классный руководитель';
comment on column public.classes.invite_code is 'Код для самостоятельного присоединения ученика к классу (RPC join_class)';

-- -----------------------------------------------------------------------------
--  Предметы
-- -----------------------------------------------------------------------------
create table if not exists public.subjects (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools (id) on delete cascade,
  name       text not null,
  short_name text,
  color      text not null default '#6366f1',
  created_at timestamptz not null default now(),
  unique (school_id, name)
);

comment on table public.subjects is 'Справочник предметов школы';

-- -----------------------------------------------------------------------------
--  Кто какой предмет ведёт в классе (назначения учителей)
-- -----------------------------------------------------------------------------
create table if not exists public.class_subjects (
  id         uuid primary key default gen_random_uuid(),
  class_id   uuid not null references public.classes (id) on delete cascade,
  subject_id uuid not null references public.subjects (id) on delete cascade,
  teacher_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (class_id, subject_id)
);

comment on table public.class_subjects is 'Назначение учителя на предмет в конкретном классе';

-- -----------------------------------------------------------------------------
--  Ученики (профиль + класс)
-- -----------------------------------------------------------------------------
create sequence if not exists public.student_card_seq start with 100000;

create table if not exists public.students (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null unique references public.profiles (id) on delete cascade,
  class_id    uuid not null references public.classes (id) on delete cascade,
  card_number text not null unique default nextval('public.student_card_seq')::text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table  public.students is 'Ученик: связка профиля пользователя с классом';
comment on column public.students.card_number is 'Номер карты: по нему родитель привязывает ребёнка (RPC link_child)';

-- -----------------------------------------------------------------------------
--  Родители -> дети
-- -----------------------------------------------------------------------------
create table if not exists public.parent_students (
  parent_id  uuid not null references public.profiles (id) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  relation   text not null default 'parent',
  created_at timestamptz not null default now(),
  primary key (parent_id, student_id)
);

comment on table public.parent_students is 'Связь «родитель — ученик». Один родитель может иметь нескольких детей.';

-- -----------------------------------------------------------------------------
--  Расписание (недельный шаблон)
-- -----------------------------------------------------------------------------
create table if not exists public.schedule (
  id            uuid primary key default gen_random_uuid(),
  class_id      uuid not null references public.classes (id) on delete cascade,
  subject_id    uuid not null references public.subjects (id) on delete cascade,
  teacher_id    uuid references public.profiles (id) on delete set null,
  weekday       smallint not null,
  lesson_number smallint not null,
  starts_at     time,
  ends_at       time,
  room          text,
  created_at    timestamptz not null default now(),
  constraint schedule_weekday_check check (weekday between 1 and 6),
  constraint schedule_lesson_number_check check (lesson_number between 1 and 10),
  constraint schedule_time_check check (ends_at is null or starts_at is null or ends_at > starts_at),
  unique (class_id, weekday, lesson_number)
);

comment on table  public.schedule is 'Постоянное расписание класса: weekday 1 = понедельник … 6 = суббота';
comment on column public.schedule.lesson_number is 'Номер урока в дне (1..10)';

-- -----------------------------------------------------------------------------
--  Уроки (фактические занятия по датам)
-- -----------------------------------------------------------------------------
create table if not exists public.lessons (
  id            uuid primary key default gen_random_uuid(),
  class_id      uuid not null references public.classes (id) on delete cascade,
  subject_id    uuid not null references public.subjects (id) on delete cascade,
  teacher_id    uuid references public.profiles (id) on delete set null,
  lesson_date   date not null,
  lesson_number smallint not null,
  topic         text,
  homework_text text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint lessons_lesson_number_check check (lesson_number between 1 and 10),
  unique (class_id, lesson_date, lesson_number)
);

comment on table  public.lessons is 'Проведённый (или запланированный) урок: тема + краткое домашнее задание';
comment on column public.lessons.homework_text is 'Быстрая запись ДЗ; для подробного ДЗ со сроком используйте таблицу homework';

-- -----------------------------------------------------------------------------
--  Оценки
-- -----------------------------------------------------------------------------
create table if not exists public.grades (
  id         uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  subject_id uuid not null references public.subjects (id) on delete cascade,
  teacher_id uuid references public.profiles (id) on delete set null,
  lesson_id  uuid references public.lessons (id) on delete set null,
  term_id    uuid references public.terms (id) on delete set null,
  grade_date date not null default current_date,
  value      smallint not null,
  kind       public.grade_kind not null default 'current',
  weight     numeric(3,1) not null default 1.0,
  comment    text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint grades_value_check check (value between 1 and 5),
  constraint grades_weight_check check (weight > 0)
);

comment on table  public.grades is 'Оценки по 5-балльной шкале; weight нужен для взвешенного среднего';
comment on column public.grades.term_id is 'Четверть; заполняется триггером по дате оценки, если не указана';

-- -----------------------------------------------------------------------------
--  Посещаемость
-- -----------------------------------------------------------------------------
create table if not exists public.attendance (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references public.students (id) on delete cascade,
  class_id      uuid not null references public.classes (id) on delete cascade,
  lesson_id     uuid references public.lessons (id) on delete set null,
  attend_date   date not null default current_date,
  lesson_number smallint not null,
  status        public.attendance_status not null default 'present',
  reason        text,
  marked_by     uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  constraint attendance_lesson_number_check check (lesson_number between 1 and 10),
  unique (student_id, attend_date, lesson_number)
);

comment on table public.attendance is 'Отметки посещаемости по урокам; status=excused требует reason';

-- -----------------------------------------------------------------------------
--  Домашние задания
-- -----------------------------------------------------------------------------
create table if not exists public.homework (
  id             uuid primary key default gen_random_uuid(),
  lesson_id      uuid references public.lessons (id) on delete cascade,
  class_id       uuid not null references public.classes (id) on delete cascade,
  subject_id     uuid not null references public.subjects (id) on delete cascade,
  teacher_id     uuid references public.profiles (id) on delete set null,
  title          text,
  description    text not null,
  assigned_on    date not null default current_date,
  due_date       date,
  attachment_url text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint homework_dates_check check (due_date is null or due_date >= assigned_on)
);

comment on table public.homework is 'Домашнее задание класса по предмету (может быть привязано к уроку)';

-- -----------------------------------------------------------------------------
--  Статус выполнения ДЗ учеником
-- -----------------------------------------------------------------------------
create table if not exists public.homework_statuses (
  id          uuid primary key default gen_random_uuid(),
  homework_id uuid not null references public.homework (id) on delete cascade,
  student_id  uuid not null references public.students (id) on delete cascade,
  status      public.homework_status not null default 'assigned',
  comment     text,
  updated_at  timestamptz not null default now(),
  unique (homework_id, student_id)
);

comment on table public.homework_statuses is 'Отметка ученика/родителя о выполнении домашнего задания';

-- -----------------------------------------------------------------------------
--  Объявления
-- -----------------------------------------------------------------------------
create table if not exists public.announcements (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null references public.schools (id) on delete cascade,
  class_id     uuid references public.classes (id) on delete cascade,
  author_id    uuid references public.profiles (id) on delete set null,
  title        text not null,
  body         text not null,
  published_at timestamptz not null default now(),
  created_at   timestamptz not null default now()
);

comment on table public.announcements is 'Объявления: class_id = null — объявление для всей школы';

-- -----------------------------------------------------------------------------
--  Индексы под типовые запросы дневника
-- -----------------------------------------------------------------------------
create index if not exists idx_profiles_role          on public.profiles (role);
create index if not exists idx_profiles_school        on public.profiles (school_id);
create index if not exists idx_classes_school         on public.classes (school_id, academic_year);
create index if not exists idx_class_subjects_teacher on public.class_subjects (teacher_id);
create index if not exists idx_students_class         on public.students (class_id);
create index if not exists idx_parent_students_child  on public.parent_students (student_id);
create index if not exists idx_schedule_class_day     on public.schedule (class_id, weekday);
create index if not exists idx_lessons_class_date     on public.lessons (class_id, lesson_date);
create index if not exists idx_lessons_teacher_date   on public.lessons (teacher_id, lesson_date);
create index if not exists idx_grades_student_subject on public.grades (student_id, subject_id);
create index if not exists idx_grades_date            on public.grades (grade_date);
create index if not exists idx_grades_lesson          on public.grades (lesson_id);
create index if not exists idx_attendance_student     on public.attendance (student_id, attend_date);
create index if not exists idx_homework_class_due     on public.homework (class_id, due_date);
create index if not exists idx_homework_lesson        on public.homework (lesson_id);
create index if not exists idx_hw_statuses_student    on public.homework_statuses (student_id);
create index if not exists idx_announcements_class    on public.announcements (class_id, published_at desc);

-- <<<<<<<<<<<<<<<<<<<<<< КОНЕЦ: supabase\migrations\20260101000001_01_core_tables.sql <<<<<<<<<<<<<<<<<<<<<<

-- >>>>>>>>>>>>>>>>>>>>>> НАЧАЛО: supabase\migrations\20260101000002_02_functions_and_triggers.sql >>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
--  Школьный дневник — шаг 02. Функции, хелперы доступа и триггеры
--
--  Важно: все функции проверки прав — security definer. Они читают таблицы
--  от имени владельца схемы (postgres), поэтому НЕ вызывают рекурсию RLS,
--  когда используются внутри политик.
-- =============================================================================

-- -----------------------------------------------------------------------------
--  Служебные функции
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $fn$
begin
  new.updated_at := now();
  return new;
end
$fn$;

comment on function public.set_updated_at() is 'Триггер: проставляет updated_at = now()';

create or replace function public.iso_dow(p_date date)
returns smallint
language sql
immutable
as $fn$
  select (extract(isodow from p_date))::smallint;
$fn$;

comment on function public.iso_dow(date) is 'День недели по ISO: 1 = понедельник ... 7 = воскресенье';

create or replace function public.term_for_date(p_date date, p_school_id uuid default null)
returns uuid
language sql
stable
as $fn$
  select t.id
  from public.terms t
  where p_date between t.starts_on and t.ends_on
    and (p_school_id is null or t.school_id = p_school_id)
  order by t.sort_order
  limit 1;
$fn$;

comment on function public.term_for_date(date, uuid) is 'Четверть, в которую попадает дата';

-- -----------------------------------------------------------------------------
--  Контекст текущего пользователя
-- -----------------------------------------------------------------------------
create or replace function public.my_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
    and p.is_active;
$fn$;

comment on function public.my_role() is 'Роль текущего пользователя (null, если не вошёл или заблокирован)';

create or replace function public.my_school_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select p.school_id
  from public.profiles p
  where p.id = auth.uid();
$fn$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select coalesce(public.my_role() = 'admin', false);
$fn$;

comment on function public.is_admin() is 'true, если текущий пользователь — администрация школы';

create or replace function public.owns_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select exists (
           select 1 from public.students s
           where s.id = p_student_id and s.profile_id = auth.uid()
         )
      or exists (
           select 1 from public.parent_students ps
           where ps.student_id = p_student_id and ps.parent_id = auth.uid()
         );
$fn$;

comment on function public.owns_student(uuid) is 'true, если ученик — это сам пользователь или его ребёнок';

-- -----------------------------------------------------------------------------
--  Проверки «учитель ведёт класс»
-- -----------------------------------------------------------------------------
create or replace function public.teaches_class(p_class_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select exists (
           select 1 from public.classes c
           where c.id = p_class_id and c.class_teacher_id = auth.uid()
         )
      or exists (
           select 1 from public.class_subjects cs
           where cs.class_id = p_class_id and cs.teacher_id = auth.uid()
         )
      or exists (
           select 1 from public.schedule sc
           where sc.class_id = p_class_id and sc.teacher_id = auth.uid()
         )
      or exists (
           select 1 from public.lessons l
           where l.class_id = p_class_id and l.teacher_id = auth.uid()
         );
$fn$;

comment on function public.teaches_class(uuid) is
  'true, если пользователь — классный руководитель или ведёт уроки в этом классе';

create or replace function public.can_view_class(p_class_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select public.is_admin()
      or public.teaches_class(p_class_id)
      or exists (
           select 1 from public.students s
           where s.class_id = p_class_id and s.profile_id = auth.uid()
         )
      or exists (
           select 1
           from public.parent_students ps
           join public.students s on s.id = ps.student_id
           where ps.parent_id = auth.uid()
             and s.class_id = p_class_id
         );
$fn$;

comment on function public.can_view_class(uuid) is
  'true, если пользователь вправе видеть данные класса (админ, учитель класса, ученик класса, родитель ученика класса)';

create or replace function public.can_view_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select public.is_admin()
      or public.owns_student(p_student_id)
      or exists (
           select 1 from public.students s
           where s.id = p_student_id and public.teaches_class(s.class_id)
         );
$fn$;

comment on function public.can_view_student(uuid) is
  'true, если пользователь вправе видеть дневник ученика (сам ученик, его родитель, учитель класса, админ)';

create or replace function public.can_grade_student(p_student_id uuid, p_subject_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select public.is_admin()
      or exists (
           select 1
           from public.students s
           join public.class_subjects cs
             on cs.class_id = s.class_id
            and cs.subject_id = p_subject_id
           where s.id = p_student_id
             and cs.teacher_id = auth.uid()
         );
$fn$;

comment on function public.can_grade_student(uuid, uuid) is
  'true, если пользователь ведёт этот предмет в классе ученика (может ставить оценки)';

-- -----------------------------------------------------------------------------
--  Видимость профилей
-- -----------------------------------------------------------------------------
create or replace function public.can_view_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select p_profile_id = auth.uid()
      or public.is_admin()
      -- одноклассники
      or exists (
           select 1
           from public.students me
           join public.students other on other.class_id = me.class_id
           where me.profile_id = auth.uid()
             and other.profile_id = p_profile_id
         )
      -- учитель видит своих учеников
      or exists (
           select 1 from public.students s
           where s.profile_id = p_profile_id and public.teaches_class(s.class_id)
         )
      -- родитель видит профиль ребёнка
      or exists (
           select 1
           from public.parent_students ps
           join public.students s on s.id = ps.student_id
           where ps.parent_id = auth.uid()
             and s.profile_id = p_profile_id
         )
      -- учитель видит коллег по своим классам
      or exists (
           select 1 from public.classes c
           where c.class_teacher_id = p_profile_id and public.teaches_class(c.id)
         )
      or exists (
           select 1 from public.class_subjects cs
           where cs.teacher_id = p_profile_id and public.teaches_class(cs.class_id)
         )
      -- учитель видит родителей своих учеников
      or exists (
           select 1
           from public.parent_students ps
           join public.students s on s.id = ps.student_id
           where ps.parent_id = p_profile_id and public.teaches_class(s.class_id)
         );
$fn$;

comment on function public.can_view_profile(uuid) is 'true, если профиль виден текущему пользователю';

-- -----------------------------------------------------------------------------
--  Триггеры updated_at
-- -----------------------------------------------------------------------------
do $do$
declare
  t text;
begin
  foreach t in array array['profiles', 'students', 'lessons', 'grades', 'homework', 'homework_statuses']
  loop
    execute format('drop trigger if exists trg_%1$s_updated_at on public.%1$I', t);
    execute format(
      'create trigger trg_%1$s_updated_at before update on public.%1$I
         for each row execute function public.set_updated_at()', t);
  end loop;
end
$do$;

-- -----------------------------------------------------------------------------
--  Защита служебных полей профиля
--  Роль / школа / активность меняются только администратором.
-- -----------------------------------------------------------------------------
create or replace function public.protect_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  if public.is_admin() then
    return new;
  end if;

  if new.id is distinct from old.id
     or new.role is distinct from old.role
     or new.is_active is distinct from old.is_active then
    raise exception 'Менять роль или активность профиля может только администратор';
  end if;

  if new.school_id is distinct from old.school_id then
    -- Исключение: ученик присоединяется к классу через RPC join_class().
    -- Разрешаем только если новая школа совпадает со школой его класса.
    if not exists (
      select 1
      from public.students s
      join public.classes c on c.id = s.class_id
      where s.profile_id = new.id
        and c.school_id = new.school_id
    ) then
      raise exception 'Менять школу профиля может только администратор';
    end if;
  end if;

  return new;
end
$fn$;

drop trigger if exists trg_profiles_protect_fields on public.profiles;
create trigger trg_profiles_protect_fields
  before update on public.profiles
  for each row execute function public.protect_profile_fields();

-- -----------------------------------------------------------------------------
--  Автозаполнение полей: оценки
-- -----------------------------------------------------------------------------
create or replace function public.prepare_grade()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_school_id uuid;
begin
  if new.teacher_id is null then
    new.teacher_id := auth.uid();
  end if;

  if new.term_id is null then
    select c.school_id into v_school_id
    from public.students s
    join public.classes c on c.id = s.class_id
    where s.id = new.student_id;

    new.term_id := public.term_for_date(new.grade_date, v_school_id);
  end if;

  return new;
end
$fn$;

drop trigger if exists trg_grades_prepare on public.grades;
create trigger trg_grades_prepare
  before insert or update on public.grades
  for each row execute function public.prepare_grade();

-- -----------------------------------------------------------------------------
--  Автозаполнение полей: посещаемость
-- -----------------------------------------------------------------------------
create or replace function public.prepare_attendance()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_class_id uuid;
begin
  if new.class_id is null then
    select s.class_id into v_class_id from public.students s where s.id = new.student_id;
    new.class_id := v_class_id;
  end if;

  if new.lesson_id is null then
    select l.id into new.lesson_id
    from public.lessons l
    where l.class_id = new.class_id
      and l.lesson_date = new.attend_date
      and l.lesson_number = new.lesson_number;
  end if;

  if new.marked_by is null then
    new.marked_by := auth.uid();
  end if;

  if new.status = 'excused' and new.reason is null then
    raise exception 'Для уважительной причины нужно заполнить поле reason';
  end if;

  return new;
end
$fn$;

drop trigger if exists trg_attendance_prepare on public.attendance;
create trigger trg_attendance_prepare
  before insert or update on public.attendance
  for each row execute function public.prepare_attendance();

-- -----------------------------------------------------------------------------
--  Автозаполнение полей: домашние задания
-- -----------------------------------------------------------------------------
create or replace function public.prepare_homework()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_class_id   uuid;
  v_subject_id uuid;
begin
  if new.lesson_id is not null then
    select l.class_id, l.subject_id into v_class_id, v_subject_id
    from public.lessons l
    where l.id = new.lesson_id;

    if v_class_id is not null then
      new.class_id := coalesce(new.class_id, v_class_id);
      new.subject_id := coalesce(new.subject_id, v_subject_id);
    end if;
  end if;

  if new.teacher_id is null then
    new.teacher_id := auth.uid();
  end if;

  return new;
end
$fn$;

drop trigger if exists trg_homework_prepare on public.homework;
create trigger trg_homework_prepare
  before insert or update on public.homework
  for each row execute function public.prepare_homework();

-- -----------------------------------------------------------------------------
--  Автозаполнение полей: урок (teacher_id = текущий учитель)
-- -----------------------------------------------------------------------------
create or replace function public.prepare_lesson()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  if new.teacher_id is null then
    new.teacher_id := auth.uid();
  end if;

  return new;
end
$fn$;

drop trigger if exists trg_lessons_prepare on public.lessons;
create trigger trg_lessons_prepare
  before insert or update on public.lessons
  for each row execute function public.prepare_lesson();

-- -----------------------------------------------------------------------------
--  Автозаполнение полей: объявление (author_id = текущий пользователь)
-- -----------------------------------------------------------------------------
create or replace function public.prepare_announcement()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  if new.author_id is null then
    new.author_id := auth.uid();
  end if;

  return new;
end
$fn$;

drop trigger if exists trg_announcements_prepare on public.announcements;
create trigger trg_announcements_prepare
  before insert or update on public.announcements
  for each row execute function public.prepare_announcement();

-- -----------------------------------------------------------------------------
--  Автосоздание профиля после регистрации в Supabase Auth
--  Роль из метаданных принимается только student / parent.
--  Учителя и администраторы назначаются вручную (профиль.role).
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_role_text text := lower(coalesce(new.raw_user_meta_data ->> 'role', 'student'));
  v_role      public.user_role := 'student';
  v_full_name text;
  v_school_id uuid;
begin
  if v_role_text in ('student', 'parent') then
    v_role := v_role_text::public.user_role;
  end if;

  v_full_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '');
  if v_full_name is null then
    v_full_name := coalesce(nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'Пользователь');
  end if;

  begin
    v_school_id := nullif(new.raw_user_meta_data ->> 'school_id', '')::uuid;
  exception when others then
    v_school_id := null;
  end;

  insert into public.profiles (id, email, full_name, role, school_id)
  values (new.id, new.email, v_full_name, v_role, v_school_id)
  on conflict (id) do nothing;

  return new;
end
$fn$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
--  RPC: ученик присоединяется к классу по коду
-- -----------------------------------------------------------------------------
create or replace function public.join_class(p_invite_code text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_role  public.user_role;
  v_class public.classes;
begin
  if v_uid is null then
    raise exception 'Требуется вход в систему';
  end if;

  select p.role into v_role from public.profiles p where p.id = v_uid;
  if v_role is null then
    raise exception 'Профиль не найден';
  end if;
  if v_role <> 'student' then
    raise exception 'Присоединиться к классу может только ученик (текущая роль: %)', v_role;
  end if;

  if coalesce(trim(p_invite_code), '') = '' then
    raise exception 'Не указан код класса';
  end if;

  select c.* into v_class
  from public.classes c
  where upper(c.invite_code) = upper(trim(p_invite_code));

  if v_class.id is null then
    raise exception 'Класс с таким кодом не найден';
  end if;

  insert into public.students (profile_id, class_id)
  values (v_uid, v_class.id)
  on conflict (profile_id) do update
    set class_id = excluded.class_id;

  update public.profiles
     set school_id = v_class.school_id
   where id = v_uid
     and school_id is distinct from v_class.school_id;

  return v_class.id;
end
$fn$;

comment on function public.join_class(text) is
  'RPC: переводит текущего ученика в класс по invite_code. Пример: rpc("join_class", { p_invite_code: "AB12CD" })';

-- -----------------------------------------------------------------------------
--  RPC: родитель привязывает ребёнка по номеру карты
-- -----------------------------------------------------------------------------
create or replace function public.link_child(p_card_number text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_uid        uuid := auth.uid();
  v_role       public.user_role;
  v_student_id uuid;
begin
  if v_uid is null then
    raise exception 'Требуется вход в систему';
  end if;

  select p.role into v_role from public.profiles p where p.id = v_uid;
  if v_role <> 'parent' then
    raise exception 'Привязать ребёнка может только пользователь с ролью «родитель» (текущая роль: %)',
      coalesce(v_role::text, 'нет');
  end if;

  select s.id into v_student_id
  from public.students s
  where s.card_number = trim(p_card_number);

  if v_student_id is null then
    raise exception 'Ученик с номером карты % не найден', p_card_number;
  end if;

  insert into public.parent_students (parent_id, student_id)
  values (v_uid, v_student_id)
  on conflict (parent_id, student_id) do nothing;

  return v_student_id;
end
$fn$;

comment on function public.link_child(text) is
  'RPC: привязывает ребёнка к текущему родителю по students.card_number';

create or replace function public.unlink_child(p_student_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  if auth.uid() is null then
    raise exception 'Требуется вход в систему';
  end if;

  delete from public.parent_students
  where parent_id = auth.uid()
    and student_id = p_student_id;
end
$fn$;

comment on function public.unlink_child(uuid) is 'RPC: отвязывает ребёнка от текущего родителя';

-- <<<<<<<<<<<<<<<<<<<<<< КОНЕЦ: supabase\migrations\20260101000002_02_functions_and_triggers.sql <<<<<<<<<<<<<<<<<<<<<<

-- >>>>>>>>>>>>>>>>>>>>>> НАЧАЛО: supabase\migrations\20260101000003_03_rls_policies.sql >>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
--  Школьный дневник — шаг 03. Row Level Security (RLS) и гранты
--
--  Логика доступа:
--    * admin     — видит и меняет всё в своей школе;
--    * teacher   — видит свои классы/учеников, ставит оценки и ДЗ по своим предметам;
--    * student   — видит себя, свой класс, своё расписание и свои оценки;
--    * parent    — видит своих детей, их дневник, ДЗ и расписание класса;
--    * anon      — доступ закрыт полностью (только вход через Supabase Auth);
--    * service_role — обходит RLS (используется только серверными скриптами).
--
--  Файл можно запускать повторно: политики пересоздаются.
-- =============================================================================

-- Пересоздаём только «наши» политики, чужие не трогаем
do $do$
declare
  r record;
begin
  for r in
    select tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = any (array[
        'schools', 'profiles', 'terms', 'classes', 'subjects', 'class_subjects',
        'students', 'parent_students', 'schedule', 'lessons', 'grades',
        'attendance', 'homework', 'homework_statuses', 'announcements'
      ])
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end
$do$;

-- Включаем RLS на всех таблицах
do $do$
declare
  t text;
begin
  foreach t in array array[
    'schools', 'profiles', 'terms', 'classes', 'subjects', 'class_subjects',
    'students', 'parent_students', 'schedule', 'lessons', 'grades',
    'attendance', 'homework', 'homework_statuses', 'announcements'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end
$do$;

-- -----------------------------------------------------------------------------
--  schools — справочник школ: читают все вошедшие, меняет админ
-- -----------------------------------------------------------------------------
create policy schools_select on public.schools
  for select to authenticated
  using (true);

create policy schools_insert on public.schools
  for insert to authenticated
  with check (public.is_admin());

create policy schools_update on public.schools
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy schools_delete on public.schools
  for delete to authenticated
  using (public.is_admin());

-- -----------------------------------------------------------------------------
--  profiles
-- -----------------------------------------------------------------------------
create policy profiles_select on public.profiles
  for select to authenticated
  using (public.can_view_profile(id));

create policy profiles_insert_self on public.profiles
  for insert to authenticated
  with check (id = auth.uid());

create policy profiles_update_self_or_admin on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

create policy profiles_delete_admin on public.profiles
  for delete to authenticated
  using (public.is_admin());

-- -----------------------------------------------------------------------------
--  terms — четверти: читают все вошедшие, меняет админ
-- -----------------------------------------------------------------------------
create policy terms_select on public.terms
  for select to authenticated
  using (true);

create policy terms_write_admin on public.terms
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- -----------------------------------------------------------------------------
--  classes — видит только «свой» класс
-- -----------------------------------------------------------------------------
create policy classes_select on public.classes
  for select to authenticated
  using (public.can_view_class(id));

create policy classes_insert_admin on public.classes
  for insert to authenticated
  with check (public.is_admin());

create policy classes_update_admin_or_teacher on public.classes
  for update to authenticated
  using (public.is_admin() or class_teacher_id = auth.uid())
  with check (public.is_admin() or class_teacher_id = auth.uid());

create policy classes_delete_admin on public.classes
  for delete to authenticated
  using (public.is_admin());

-- -----------------------------------------------------------------------------
--  subjects — справочник предметов
-- -----------------------------------------------------------------------------
create policy subjects_select on public.subjects
  for select to authenticated
  using (true);

create policy subjects_write_admin on public.subjects
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- -----------------------------------------------------------------------------
--  class_subjects — назначения учителей
-- -----------------------------------------------------------------------------
create policy class_subjects_select on public.class_subjects
  for select to authenticated
  using (public.can_view_class(class_id));

create policy class_subjects_write_admin on public.class_subjects
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- -----------------------------------------------------------------------------
--  students
--  Прямая вставка/правка запрещена (кроме админа): ученик попадает в класс
--  через RPC join_class(), которая работает как security definer.
-- -----------------------------------------------------------------------------
create policy students_select on public.students
  for select to authenticated
  using (public.can_view_student(id));

create policy students_insert_admin on public.students
  for insert to authenticated
  with check (public.is_admin());

create policy students_update_admin on public.students
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy students_delete_admin on public.students
  for delete to authenticated
  using (public.is_admin());

-- -----------------------------------------------------------------------------
--  parent_students
--  Вставка только через RPC link_child() — иначе родитель смог бы привязать
--  любого ученика, зная только его id.
-- -----------------------------------------------------------------------------
create policy parent_students_select on public.parent_students
  for select to authenticated
  using (parent_id = auth.uid() or public.can_view_student(student_id));

create policy parent_students_insert_admin on public.parent_students
  for insert to authenticated
  with check (public.is_admin());

create policy parent_students_delete on public.parent_students
  for delete to authenticated
  using (parent_id = auth.uid() or public.is_admin());

-- -----------------------------------------------------------------------------
--  schedule — расписание класса
-- -----------------------------------------------------------------------------
create policy schedule_select on public.schedule
  for select to authenticated
  using (public.can_view_class(class_id));

create policy schedule_write_admin_or_class_teacher on public.schedule
  for all to authenticated
  using (
    public.is_admin()
    or exists (
         select 1 from public.classes c
         where c.id = class_id and c.class_teacher_id = auth.uid()
       )
  )
  with check (
    public.is_admin()
    or exists (
         select 1 from public.classes c
         where c.id = class_id and c.class_teacher_id = auth.uid()
       )
  );

-- -----------------------------------------------------------------------------
--  lessons — уроки (тема + краткое ДЗ)
-- -----------------------------------------------------------------------------
create policy lessons_select on public.lessons
  for select to authenticated
  using (public.can_view_class(class_id));

create policy lessons_insert on public.lessons
  for insert to authenticated
  with check (
    public.is_admin()
    or (
      teacher_id = auth.uid()
      and public.teaches_class(class_id)
    )
    or exists (
         select 1 from public.classes c
         where c.id = class_id and c.class_teacher_id = auth.uid()
       )
  );

create policy lessons_update on public.lessons
  for update to authenticated
  using (
    public.is_admin()
    or teacher_id = auth.uid()
    or exists (
         select 1 from public.classes c
         where c.id = class_id and c.class_teacher_id = auth.uid()
       )
  )
  with check (
    public.is_admin()
    or teacher_id = auth.uid()
    or exists (
         select 1 from public.classes c
         where c.id = class_id and c.class_teacher_id = auth.uid()
       )
  );

create policy lessons_delete on public.lessons
  for delete to authenticated
  using (
    public.is_admin()
    or teacher_id = auth.uid()
    or exists (
         select 1 from public.classes c
         where c.id = class_id and c.class_teacher_id = auth.uid()
       )
  );

-- -----------------------------------------------------------------------------
--  grades — оценки. Ставит только учитель-предметник этого класса (или админ)
-- -----------------------------------------------------------------------------
create policy grades_select on public.grades
  for select to authenticated
  using (public.can_view_student(student_id));

create policy grades_insert on public.grades
  for insert to authenticated
  with check (
    public.is_admin()
    or (
      teacher_id = auth.uid()
      and public.can_grade_student(student_id, subject_id)
    )
  );

create policy grades_update on public.grades
  for update to authenticated
  using (
    public.is_admin()
    or (
      teacher_id = auth.uid()
      and public.can_grade_student(student_id, subject_id)
    )
  )
  with check (
    public.is_admin()
    or (
      teacher_id = auth.uid()
      and public.can_grade_student(student_id, subject_id)
    )
  );

create policy grades_delete on public.grades
  for delete to authenticated
  using (
    public.is_admin()
    or (
      teacher_id = auth.uid()
      and public.can_grade_student(student_id, subject_id)
    )
  );

-- -----------------------------------------------------------------------------
--  attendance — посещаемость (отмечает учитель класса или админ)
-- -----------------------------------------------------------------------------
create policy attendance_select on public.attendance
  for select to authenticated
  using (public.can_view_student(student_id));

create policy attendance_insert on public.attendance
  for insert to authenticated
  with check (public.is_admin() or public.teaches_class(class_id));

create policy attendance_update on public.attendance
  for update to authenticated
  using (public.is_admin() or public.teaches_class(class_id))
  with check (public.is_admin() or public.teaches_class(class_id));

create policy attendance_delete on public.attendance
  for delete to authenticated
  using (public.is_admin() or public.teaches_class(class_id));

-- -----------------------------------------------------------------------------
--  homework — домашние задания
-- -----------------------------------------------------------------------------
create policy homework_select on public.homework
  for select to authenticated
  using (public.can_view_class(class_id));

create policy homework_insert on public.homework
  for insert to authenticated
  with check (
    public.is_admin()
    or (
      teacher_id = auth.uid()
      and public.teaches_class(class_id)
    )
  );

create policy homework_update on public.homework
  for update to authenticated
  using (public.is_admin() or teacher_id = auth.uid())
  with check (
    public.is_admin()
    or (
      teacher_id = auth.uid()
      and public.teaches_class(class_id)
    )
  );

create policy homework_delete on public.homework
  for delete to authenticated
  using (public.is_admin() or teacher_id = auth.uid());

-- -----------------------------------------------------------------------------
--  homework_statuses — отметки о выполнении ДЗ (ученик или его родитель)
-- -----------------------------------------------------------------------------
create policy homework_statuses_select on public.homework_statuses
  for select to authenticated
  using (public.can_view_student(student_id));

create policy homework_statuses_insert on public.homework_statuses
  for insert to authenticated
  with check (public.is_admin() or public.owns_student(student_id));

create policy homework_statuses_update on public.homework_statuses
  for update to authenticated
  using (public.is_admin() or public.owns_student(student_id))
  with check (public.is_admin() or public.owns_student(student_id));

create policy homework_statuses_delete on public.homework_statuses
  for delete to authenticated
  using (public.is_admin() or public.owns_student(student_id));

-- -----------------------------------------------------------------------------
--  announcements — объявления
-- -----------------------------------------------------------------------------
create policy announcements_select on public.announcements
  for select to authenticated
  using (class_id is null or public.can_view_class(class_id));

create policy announcements_insert on public.announcements
  for insert to authenticated
  with check (
    public.is_admin()
    or (
      author_id = auth.uid()
      and exists (
           select 1 from public.classes c
           where c.id = class_id and c.class_teacher_id = auth.uid()
         )
    )
  );

create policy announcements_update on public.announcements
  for update to authenticated
  using (public.is_admin() or author_id = auth.uid())
  with check (public.is_admin() or author_id = auth.uid());

create policy announcements_delete on public.announcements
  for delete to authenticated
  using (public.is_admin() or author_id = auth.uid());

-- =============================================================================
--  Гранты на уровне Postgres.
--  RLS работает только поверх выданных прав, поэтому выдаём их явно.
-- =============================================================================
grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- service_role — для серверных скриптов (например, создание демо-аккаунтов)
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- Анонимный доступ к данным закрыт полностью
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;

-- <<<<<<<<<<<<<<<<<<<<<< КОНЕЦ: supabase\migrations\20260101000003_03_rls_policies.sql <<<<<<<<<<<<<<<<<<<<<<

-- >>>>>>>>>>>>>>>>>>>>>> НАЧАЛО: supabase\migrations\20260101000004_04_views.sql >>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
--  Школьный дневник — шаг 04. Представления (views) для фронтенда
--
--  Все view создаются с security_invoker = on, то есть подчиняются RLS
--  таблиц, на которых построены. Требуется PostgreSQL 15+ (в Supabase так и есть).
-- =============================================================================

-- -----------------------------------------------------------------------------
--  Дневник ученика: один ряд = один урок с оценками, ДЗ и посещаемостью
--  Пример: select * from v_student_diary where student_id = :id and lesson_date = current_date;
-- -----------------------------------------------------------------------------
create or replace view public.v_student_diary
with (security_invoker = on) as
select
  s.id                                        as student_id,
  c.id                                        as class_id,
  c.name                                      as class_name,
  l.id                                        as lesson_id,
  l.lesson_date,
  l.lesson_number,
  sub.id                                      as subject_id,
  sub.name                                    as subject_name,
  sub.short_name                              as subject_short_name,
  sub.color                                   as subject_color,
  t.id                                        as teacher_id,
  t.full_name                                 as teacher_name,
  l.topic,
  hw.id                                       as homework_id,
  coalesce(nullif(hw.title, ''), hw.description) as homework,
  hw.description                              as homework_description,
  hw.due_date                                 as homework_due_date,
  hs.status                                   as homework_status,
  coalesce(g.grades, '{}'::smallint[])        as grades,
  g.average                                   as grades_average,
  a.status                                    as attendance_status,
  a.reason                                    as attendance_reason,
  sch.starts_at,
  sch.ends_at,
  sch.room
from public.students s
join public.classes c
  on c.id = s.class_id
join public.lessons l
  on l.class_id = s.class_id
join public.subjects sub
  on sub.id = l.subject_id
left join public.profiles t
  on t.id = l.teacher_id
left join lateral (
  select
    array_agg(gr.value order by gr.grade_date, gr.created_at) as grades,
    round(avg(gr.value)::numeric, 2)                          as average
  from public.grades gr
  where gr.student_id = s.id
    and (
      gr.lesson_id = l.id
      or (gr.lesson_id is null and gr.subject_id = l.subject_id and gr.grade_date = l.lesson_date)
    )
) g on true
left join public.attendance a
  on a.student_id = s.id
 and a.attend_date = l.lesson_date
 and a.lesson_number = l.lesson_number
left join lateral (
  select h.id, h.title, h.description, h.due_date
  from public.homework h
  where h.class_id = l.class_id
    and h.subject_id = l.subject_id
    and (
      h.lesson_id = l.id
      or (h.lesson_id is null and h.assigned_on = l.lesson_date)
    )
  order by h.created_at
  limit 1
) hw on true
left join public.homework_statuses hs
  on hs.homework_id = hw.id
 and hs.student_id = s.id
left join public.schedule sch
  on sch.class_id = l.class_id
 and sch.weekday = public.iso_dow(l.lesson_date)
 and sch.lesson_number = l.lesson_number;

comment on view public.v_student_diary is
  'Дневник: уроки класса ученика с оценками (массив), ДЗ, посещаемостью и временем урока';

-- -----------------------------------------------------------------------------
--  Средний балл ученика по предметам
-- -----------------------------------------------------------------------------
create or replace view public.v_student_subject_averages
with (security_invoker = on) as
select
  g.student_id,
  s.class_id,
  g.subject_id,
  sub.name                                          as subject_name,
  sub.color                                         as subject_color,
  count(*)                                          as grades_count,
  round(avg(g.value)::numeric, 2)                    as average,
  round((sum(g.value * g.weight) / nullif(sum(g.weight), 0))::numeric, 2) as weighted_average,
  min(g.grade_date)                                 as first_grade_date,
  max(g.grade_date)                                 as last_grade_date
from public.grades g
join public.students s
  on s.id = g.student_id
join public.subjects sub
  on sub.id = g.subject_id
group by g.student_id, s.class_id, g.subject_id, sub.name, sub.color;

comment on view public.v_student_subject_averages is
  'Средний (и взвешенный) балл ученика по каждому предмету';

-- -----------------------------------------------------------------------------
--  Список учеников класса
-- -----------------------------------------------------------------------------
create or replace view public.v_class_roster
with (security_invoker = on) as
select
  st.id            as student_id,
  st.class_id,
  c.name           as class_name,
  st.card_number,
  st.is_active,
  p.full_name      as student_name,
  p.avatar_url
from public.students st
join public.profiles p
  on p.id = st.profile_id
join public.classes c
  on c.id = st.class_id;

comment on view public.v_class_roster is 'Ученики класса с ФИО и номером карты';

-- -----------------------------------------------------------------------------
--  Недельное расписание класса
-- -----------------------------------------------------------------------------
create or replace view public.v_week_schedule
with (security_invoker = on) as
select
  sc.id            as schedule_id,
  sc.class_id,
  c.name           as class_name,
  sc.weekday,
  sc.lesson_number,
  sc.starts_at,
  sc.ends_at,
  sc.room,
  sub.id           as subject_id,
  sub.name         as subject_name,
  sub.short_name   as subject_short_name,
  sub.color        as subject_color,
  sc.teacher_id,
  t.full_name      as teacher_name
from public.schedule sc
join public.classes c
  on c.id = sc.class_id
join public.subjects sub
  on sub.id = sc.subject_id
left join public.profiles t
  on t.id = sc.teacher_id;

comment on view public.v_week_schedule is 'Расписание: weekday 1 = понедельник … 6 = суббота';

-- -----------------------------------------------------------------------------
--  Домашние задания по ученикам (с отметкой о выполнении)
-- -----------------------------------------------------------------------------
create or replace view public.v_student_homework
with (security_invoker = on) as
select
  h.id                           as homework_id,
  h.class_id,
  h.subject_id,
  sub.name                       as subject_name,
  sub.color                      as subject_color,
  h.teacher_id,
  h.assigned_on,
  h.due_date,
  h.title,
  h.description,
  h.attachment_url,
  st.id                          as student_id,
  coalesce(hs.status, 'assigned'::public.homework_status) as status,
  hs.comment
from public.homework h
join public.subjects sub
  on sub.id = h.subject_id
join public.students st
  on st.class_id = h.class_id
left join public.homework_statuses hs
  on hs.homework_id = h.id
 and hs.student_id = st.id;

comment on view public.v_student_homework is
  'Домашние задания класса в разрезе учеников и статуса выполнения';

-- =============================================================================
--  Права на представления
-- =============================================================================
grant select on
  public.v_student_diary,
  public.v_student_subject_averages,
  public.v_class_roster,
  public.v_week_schedule,
  public.v_student_homework
to authenticated;

grant all on
  public.v_student_diary,
  public.v_student_subject_averages,
  public.v_class_roster,
  public.v_week_schedule,
  public.v_student_homework
to service_role;

revoke all on
  public.v_student_diary,
  public.v_student_subject_averages,
  public.v_class_roster,
  public.v_week_schedule,
  public.v_student_homework
from anon;

-- <<<<<<<<<<<<<<<<<<<<<< КОНЕЦ: supabase\migrations\20260101000004_04_views.sql <<<<<<<<<<<<<<<<<<<<<<

-- >>>>>>>>>>>>>>>>>>>>>> НАЧАЛО: supabase\seed.sql >>>>>>>>>>>>>>>>>>>>>>

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

-- <<<<<<<<<<<<<<<<<<<<<< КОНЕЦ: supabase\seed.sql <<<<<<<<<<<<<<<<<<<<<<

-- >>>>>>>>>>>>>>>>>>>>>> НАЧАЛО: supabase\promote_teacher.sql >>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
--  Школьный дневник — назначение роли «Учитель» конкретному пользователю
--
--  ЗАЧЕМ: триггер handle_new_user() (миграция 02) при регистрации уважает только
--  роли 'student' и 'parent'. Учителей и админов назначают вручную — этим скриптом.
--
--  КАК ЗАПУСКАТЬ: Supabase → SQL Editor → New query → вставить файл целиком,
--  заменить ЗНАЧЕНИЕ В ПЕРВОЙ СТРОКЕ НИЖЕ на свой e-mail → Run.
--  Файл идемпотентный: повторный запуск безопасен.
--
--  ВАЖНО: в базе роль пишется СТРОЧНЫМИ буквами: 'teacher' (не 'Teacher').
--  В интерфейсе она отображается как «Учитель».
-- =============================================================================

with params as (
  select lower('teacher@example.com')::text as email  -- <-- ЗАМЕНИТЕ на e-mail учителя
),
target as (
  select u.id, u.email, p_params.email
  from auth.users u
  join params p_params on lower(u.email) = p_params.email
)
-- 1. Профиль: роль teacher (профиль создаётся триггером при регистрации)
update public.profiles p
   set role = 'teacher',
       updated_at = now()
  from target t
 where p.id = t.id
   and p.role <> 'teacher';

-- 2. Метаданные пользователя: роль teacher (их видит приложение как запасной источник)
update auth.users u
   set raw_user_meta_data =
         coalesce(u.raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'teacher'),
       updated_at = now()
  from (select lower('teacher@example.com')::text as email) p_params  -- <-- ТОТ ЖЕ e-mail
 where lower(u.email) = p_params.email
   and coalesce(u.raw_user_meta_data ->> 'role', '') <> 'teacher';

-- -----------------------------------------------------------------------------
--  ПРОВЕРКА. Ожидаем: role = teacher, meta_role = teacher
-- -----------------------------------------------------------------------------
select u.email,
       p.role            as profile_role,
       coalesce(p.full_name, u.raw_user_meta_data ->> 'full_name') as full_name,
       u.raw_user_meta_data ->> 'role' as meta_role,
       u.raw_user_meta_data ->> 'class_name' as class_name
  from auth.users u
  left join public.profiles p on p.id = u.id
 where lower(u.email) = lower('teacher@example.com')  -- <-- ТОТ ЖЕ e-mail
 order by u.created_at;

-- -----------------------------------------------------------------------------
--  ПОЛЕЗНОЕ: кто вообще есть в проекте и у кого какая роль
-- -----------------------------------------------------------------------------
-- select u.email, p.role, p.full_name, u.created_at
--   from auth.users u
--   left join public.profiles p on p.id = u.id
--  order by u.created_at desc;

-- -----------------------------------------------------------------------------
--  ПОЛЕЗНОЕ: вернуть пользователя в ученики
-- -----------------------------------------------------------------------------
-- update public.profiles set role = 'student' where id = (select id from auth.users where lower(email) = lower('teacher@example.com'));

-- <<<<<<<<<<<<<<<<<<<<<< КОНЕЦ: supabase\promote_teacher.sql <<<<<<<<<<<<<<<<<<<<<<
