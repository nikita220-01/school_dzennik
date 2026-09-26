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
