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
