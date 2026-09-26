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
