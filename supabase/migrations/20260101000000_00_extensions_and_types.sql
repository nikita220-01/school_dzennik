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
