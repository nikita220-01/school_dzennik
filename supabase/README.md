# База данных Supabase — как применить

Все SQL-файлы лежат в репозитории: `nikita220-01/school_dzennik` → папка `supabase`.
Локально (на этом компьютере): `C:\Users\DIGITAL-PC\.cline\school_dzennik\supabase`.

## Что внутри

| Файл | Что делает |
| --- | --- |
| `apply_all.sql` | **быстрый путь**: все шаги 00–04 + демо-данные в одном файле (77 КБ) |
| `migrations/20260101000000_00_extensions_and_types.sql` | расширения (`pgcrypto`) и ENUM: `user_role`, `attendance_status`, `grade_kind`, `homework_status` |
| `migrations/20260101000001_01_core_tables.sql` | 15 таблиц: `schools, profiles, terms, classes, subjects, class_subjects, students, parent_students, schedule, lessons, grades, attendance, homework, homework_statuses, announcements` + индексы |
| `migrations/20260101000002_02_functions_and_triggers.sql` | 22 функции и триггеры: автосоздание профиля (`handle_new_user`), `updated_at`, четверть по дате оценки, подсчёт посещаемости |
| `migrations/20260101000003_03_rls_policies.sql` | 51 политика RLS: ученик видит только себя, оценку ставит учитель-предметник класса или админ |
| `migrations/20260101000004_04_views.sql` | 5 представлений: `v_student_diary`, `v_student_subject_averages`, `v_class_roster`, `v_week_schedule`, `v_student_homework` |
| `seed.sql` | демо-данные: школа, четверти 2025/2026, 11 предметов, класс 7А |
| `promote_teacher.sql` | назначение роли `teacher` конкретному пользователю по e-mail |

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
6. [seed.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/seed.sql)

## Проверка

```sql
select table_name from information_schema.tables where table_schema = 'public' order by 1; -- 15 таблиц + 5 v_*
select count(*) from public.subjects;      -- предметы
select name, grade_level from public.classes; -- 7А
select count(*) from public.schools;
```

## Роль «Учитель»

В базе роль хранится **строчными** буквами: `teacher` (ENUM `user_role`: `admin`, `teacher`, `student`, `parent`).
Триггер `handle_new_user()` при регистрации уважает только `student` и `parent`, поэтому учителя назначают вручную:

1. Открыть [promote_teacher.sql](https://raw.githubusercontent.com/nikita220-01/school_dzennik/main/supabase/promote_teacher.sql), заменить `teacher@example.com` на свой e-mail (**3 места**), запустить в SQL Editor.
2. Или через интерфейс: **Authentication → Users** → пользователь → Raw user meta data → `{"role":"teacher"}` → Save, плюс **Table Editor → profiles** → `role = teacher`.

Приложение понимает и `teacher`, и `Teacher`, и `Учитель` (нормализация роли в `src/context/AuthContext.jsx`).

## Важно про оценки

SQL-схема готова, но экран «Отметки» пока читает данные из `localStorage`
(демо-режим, работает без базы). Чтобы оценки стали общими для всех устройств,
нужно переключить `src/lib/schoolData.js` на таблицы `grades` (значения 5/4/3/2),
`attendance` (статус `absent` для «Н») и `students` (состав класса).
