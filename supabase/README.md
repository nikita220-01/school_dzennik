# База данных Supabase — как применить

Все SQL-файлы лежат в репозитории: `nikita220-01/school_dzennik` → папка `supabase`.
Локально (на этом компьютере): `C:\Users\DIGITAL-PC\.cline\school_dzennik\supabase`.

## Что нужно сделать в Supabase (чек-лист)

1. **Применить SQL** — одним файлом (`apply_all.sql`, способ 1) или по шагам (способ 2). Это создаёт таблицы, RLS и данные: 36 классов (3А…11Г), 15 предметов, 4 четверти, школу.
2. **Проверить, что классы появились**: `select count(*) from public.classes;` → должно быть **36** (3А…11Г).
3. **Выдать себе роль** учителя: запустить `promote_teacher.sql` в SQL Editor. Он же назначает учителя на все предметы всех классов — без этого RLS не покажет списки учеников.
4. **Отдать ученикам код класса** (например `7A2025`): код виден учителю в разделе «Отметки». Ученик вводит его при регистрации или позже в блоке «Присоединиться к классу».
5. **Проверить наборы**: 5.1) `select count(*) from public.classes;` → 36; 5.2) `select name, invite_code from public.classes order by grade_level, name;` — сверить коды; 5.3) `select conname, pg_get_constraintdef(oid) from pg_constraint where conname = 'grades_value_check';` → `CHECK (value BETWEEN 1 AND 10)`.
6. **Проверить в браузере**: вход → вкладка «📝 Отметки» → выбрать класс и предмет → поставить отметку 1…10. Обновить страницу — отметка должна остаться (значит, пишется в базу, а не в браузер).

> Пароль и e-mail пользователей скриптом не создаются: сначала зарегистрируйтесь на сайте, потом запускайте `promote_teacher.sql`.

## Что внутри

| Файл | Что делает |
| --- | --- |
| `apply_all.sql` | **быстрый путь**: все шаги 00–05 + демо-данные в одном файле (≈89 КБ) |
| `migrations/20260101000000_00_extensions_and_types.sql` | расширения (`pgcrypto`) и ENUM: `user_role`, `attendance_status`, `grade_kind`, `homework_status` |
| `migrations/20260101000001_01_core_tables.sql` | 15 таблиц: `schools, profiles, terms, classes, subjects, class_subjects, students, parent_students, schedule, lessons, grades, attendance, homework, homework_statuses, announcements` + индексы |
| `migrations/20260101000002_02_functions_and_triggers.sql` | 22 функции и триггеры: автосоздание профиля (`handle_new_user`), `updated_at`, четверть по дате оценки, подсчёт посещаемости |
| `migrations/20260101000003_03_rls_policies.sql` | 51 политика RLS: ученик видит только себя, оценку ставит учитель-предметник класса или админ |
| `migrations/20260101000004_04_views.sql` | 5 представлений: `v_student_diary`, `v_student_subject_averages`, `v_class_roster`, `v_week_schedule`, `v_student_homework` |
| `seed.sql` | демо-данные: школа, 4 четверти 2025/2026, 15 предметов, **36 классов** 3А…11Г с кодами приглашения (7A2025, 11G2025 …) |
| `promote_teacher.sql` | назначение роли `teacher` (по метаданным регистрации, без ввода e-mail; умеет обходить защитный триггер `profiles`) + назначение учителя на классы и предметы (`class_subjects`) |
| `migrations/20260101000005_05_classes_and_grades_scale.sql` | классы 3А…11Г (36 штук) и **10-балльная шкала** оценок (`grades_value_check`: 1…10) + уникальный ключ отметки для upsert |

Собрать `apply_all.sql` заново после правки любого файла: `npm run build:sql`, проверить всё: `npm run check:sql`.

## Способ 1 — одним файлом (быстро)

1. Supabase → проект → **SQL Editor** → **New query**.
2. Открыть [apply_all.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/apply_all.sql) → **Ctrl+A**, **Ctrl+C**.
3. Вставить в SQL Editor → **Run**. Ожидается «Success. No rows returned».

## Способ 2 — по шагам (если хотите видеть каждый шаг)

Запускать **строго по порядку**, каждый файл отдельным запросом:

1. [00_extensions_and_types.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/migrations/20260101000000_00_extensions_and_types.sql)
2. [01_core_tables.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/migrations/20260101000001_01_core_tables.sql)
3. [02_functions_and_triggers.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/migrations/20260101000002_02_functions_and_triggers.sql)
4. [03_rls_policies.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/migrations/20260101000003_03_rls_policies.sql)
5. [04_views.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/migrations/20260101000004_04_views.sql)
6. [05_classes_and_grades_scale.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/migrations/20260101000005_05_classes_and_grades_scale.sql) — классы 3А…11Г и 10-балльная шкала
7. [seed.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/seed.sql)
8. [promote_teacher.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/promote_teacher.sql) — уже после регистрации в приложении

## Проверка

```sql
select table_name from information_schema.tables where table_schema = 'public' order by 1; -- 15 таблиц + 5 v_*
select count(*) from public.subjects;      -- 15 предметов
select count(*) from public.classes;       -- 36 классов (3А…11Г)
select name, invite_code from public.classes order by grade_level, name;
select count(*) from public.schools;

-- 10-балльная шкала
select pg_get_constraintdef(oid) from pg_constraint where conname = 'grades_value_check';
-- ожидаем: CHECK (value BETWEEN 1 AND 10)
```

## Роль «Учитель»

В базе роль хранится **строчными** буквами: `teacher` (ENUM `user_role`: `admin`, `teacher`, `student`, `parent`).
Триггер `handle_new_user()` при регистрации уважает только `student` и `parent`, поэтому учителя назначают вручную:

1. Открыть [promote_teacher.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/promote_teacher.sql) и запустить целиком в **SQL Editor** — правки внутри файла не нужны.
   Скрипт сам находит пользователей, которые регистрировались как учитель (в метаданных `role = teacher`/`учитель`),
   а если таких нет — назначает `teacher` самому новому аккаунту; в конце печатает проверочную таблицу.

> **Почему нельзя просто `update public.profiles set role = ...` и почему не работает Table Editor.**
> В схеме есть триггер `trg_profiles_protect_fields` (`before update on public.profiles`), который разрешает менять
> `role`/`is_active` только администратору (`public.is_admin()`). И в SQL Editor, и у запросов панели нет JWT →
> `auth.uid()` = NULL → любая попытка заканчивается ошибкой
> `P0001: Менять роль или активность профиля может только администратор`.
> Поэтому `promote_teacher.sql` на время смены роли отключает триггер и включает обратно. Вручную это выглядит так:
>
> ```sql
> alter table public.profiles disable trigger trg_profiles_protect_fields;
> update public.profiles set role = 'teacher', updated_at = now()
>  where id = (select id from auth.users where email = 'кто-то@example.com');
> alter table public.profiles enable trigger trg_profiles_protect_fields;
> ```
>
> Роль в `auth.users.raw_user_meta_data` (`{"role":"teacher"}`) меняется и через интерфейс
> **Authentication → Users**, но она лишь вспомогательная: настоящая роль — в `public.profiles`.

Приложение понимает и `teacher`, и `Teacher`, и `Учитель` (нормализация роли в `src/context/AuthContext.jsx`).

### Почему учителю мало роли в `profiles`

RLS пускает учителя в класс только если он «ведёт» его: строки в `public.class_subjects` или `classes.class_teacher_id`.
Скрипт `promote_teacher.sql` (шаг 4) назначает каждого `teacher` на **все предметы всех 36 классов** — тогда доступна любая параллель.
Нужен только один класс — допишите в его `WHERE` условие `and c.name = '7А'`.
Администратору назначения не нужны: `public.is_admin()` открывает всё в школе.

## Оценки, классы и данные

С версии с 10-балльной шкалой приложение **читает и пишет данные прямо в Supabase** (файл `src/lib/schoolData.js`),
`localStorage` больше не используется. Что где лежит:

| Что | Таблица / представление |
| --- | --- |
| Состав класса (ФИО, номер карты) | `students` + `profiles`, читается через `v_class_roster` |
| Отметка в клетке дневника | `grades` (`value` 1…10, `kind = 'current'`), ключ — ученик + предмет + дата + вид (`uq_grades_student_subject_date_kind`) |
| «Н» (не был на уроке) | `attendance` (`status = 'absent'`, `lesson_number = 1` — отметка на день) |
| Средний балл по предметам | `v_student_subject_averages` |
| Список классов 3А…11Г и коды приглашения | `classes` (`name`, `invite_code`) |
| Привязка ученика к классу | RPC `public.join_class('7A2025')` — вызывается при регистрации и из блока «Присоединиться к классу» |

Особенности шкалы и «Н»:

* отметки — целые 1…10; средние считаются по числовым отметкам, «Н» в средний балл не входит;
* «Н» в дневнике хранится как пропуск на **день** (в базе посещаемость поурочная, а клетка дневника — «день по предмету»);
  если в клетке стоит отметка, она показывается вместо «Н»; очистка клетки («—») убирает и отметку, и «Н» дня;
* в журнале `classes` учитель видит код класса (например `7A2025`) и передаёт его ученикам.
