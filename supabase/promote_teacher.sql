-- =============================================================================
--  Школьный дневник — назначение роли «Учитель» (teacher)
--
--  ПОЧЕМУ НЕ ХВАТАЕТ ОБЫЧНОГО UPDATE:
--  в схеме есть триггер trg_profiles_protect_fields (before update on profiles),
--  который разрешает менять role только администратору (public.is_admin()).
--  В SQL Editor JWT отсутствует, auth.uid() = NULL, поэтому любой прямой
--  UPDATE profiles SET role = ... падает с ошибкой:
--      P0001: Менять роль или активность профиля может только администратор
--  Этот скрипт на время смены роли отключает защитный триггер и всегда
--  включает его обратно (даже если внутри произошла ошибка).
--
--  КОГО НАЗНАЧАЕМ (e-mail вводить не нужно):
--    • всех, кто регистрировался как учитель (в метаданных role = teacher/учитель);
--    • если таких нет — самый новый зарегистрированный аккаунт.
--  Если профиля у пользователя ещё нет, он создаётся (INSERT не защищён триггером).
--
--  КАК ЗАПУСКАТЬ: Supabase → SQL Editor → New query → вставить файл целиком → Run.
--  Файл идемпотентный: повторный запуск безопасен. Нужен админ? Замените
--  'teacher' на 'admin' в двух местах блока «Шаг 2».
-- =============================================================================

-- -----------------------------------------------------------------------------
--  Шаг 1. Посмотреть, кто есть (ничего не меняет)
-- -----------------------------------------------------------------------------
select u.email,
       u.created_at,
       coalesce(p.role::text, 'НЕТ СТРОКИ В profiles') as profile_role,
       coalesce(u.raw_user_meta_data ->> 'role', '—') as meta_role,
       coalesce(p.full_name, u.raw_user_meta_data ->> 'full_name', '—') as full_name
  from auth.users u
  left join public.profiles p on p.id = u.id
 order by u.created_at;

-- -----------------------------------------------------------------------------
--  Шаг 2. Назначить роль (сама работа)
-- -----------------------------------------------------------------------------
do $$
declare
  v_ids uuid[];
  v_n   int := 0;
begin
  select array_agg(distinct s.id)
    into v_ids
    from (
      select u.id
        from auth.users u
       where lower(coalesce(u.raw_user_meta_data ->> 'role', '')) in ('teacher', 'учитель')
      union all
      (select u.id from auth.users u order by u.created_at desc limit 1)
    ) s;

  if v_ids is null then
    -- Не ошибка: файл можно запускать до регистрации (например, внутри apply_all.sql).
    raise notice 'В проекте пока нет пользователей. Зарегистрируйтесь на сайте и запустите файл снова.';
    return;
  end if;

  -- Профиля может не быть (регистрация была до установки схемы) — создаём.
  insert into public.profiles (id, role, full_name, email, is_active)
  select u.id,
         'teacher',
         coalesce(nullif(u.raw_user_meta_data ->> 'full_name', ''), split_part(u.email, '@', 1)),
         u.email,
         true
    from auth.users u
   where u.id = any (v_ids)
     and not exists (select 1 from public.profiles p where p.id = u.id);

  -- Смена роли защищена триггером — временно отключаем.
  execute 'alter table public.profiles disable trigger trg_profiles_protect_fields';

  begin
    update public.profiles
       set role = 'teacher',
           updated_at = now()
     where id = any (v_ids)
       and role <> 'teacher';
    get diagnostics v_n = row_count;
  exception when others then
    execute 'alter table public.profiles enable trigger trg_profiles_protect_fields';
    raise;
  end;

  execute 'alter table public.profiles enable trigger trg_profiles_protect_fields';

  raise notice 'Готово. Обновлено профилей: %, кандидатов: %', v_n, array_length(v_ids, 1);
end
$$;

-- -----------------------------------------------------------------------------
--  Шаг 3. Дублируем роль в метаданные auth (их читает приложение)
-- -----------------------------------------------------------------------------
update auth.users u
   set raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb)
                            || jsonb_build_object('role', 'teacher'),
       updated_at = now()
 where exists (select 1 from public.profiles p where p.id = u.id and p.role = 'teacher')
   and coalesce(u.raw_user_meta_data ->> 'role', '') <> 'teacher'
returning u.email, u.raw_user_meta_data ->> 'role' as meta_role;

-- -----------------------------------------------------------------------------
--  Шаг 4. Проверка: ожидаем profile_role = teacher и meta_role = teacher
-- -----------------------------------------------------------------------------
select u.email,
       coalesce(p.role::text, '—') as profile_role,
       coalesce(u.raw_user_meta_data ->> 'role', '—') as meta_role,
       coalesce(p.full_name, '—') as full_name
  from auth.users u
  left join public.profiles p on p.id = u.id
 order by u.created_at;

-- -----------------------------------------------------------------------------
--  Полезное на будущее
-- -----------------------------------------------------------------------------
-- Назначить администратора: в блоке «Шаг 2» замените 'teacher' на 'admin'
--   (две замены: в INSERT и в UPDATE) и в «Шаге 3» тоже.
-- Вернуть аккаунт в ученики: тот же блок со значением 'student'.
-- Эквивалент вручную, если нужен один конкретный аккаунт:
--   alter table public.profiles disable trigger trg_profiles_protect_fields;
--   update public.profiles set role = 'teacher', updated_at = now()
--    where id = (select id from auth.users where email = 'кто-то@example.com');
--   alter table public.profiles enable  trigger trg_profiles_protect_fields;
-- ВАЖНО: обновлять role через Table Editor не получится — триггер сработает
-- и там (у запросов панели тоже нет JWT). Только SQL Editor.
