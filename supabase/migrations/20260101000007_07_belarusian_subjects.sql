-- =============================================================================
--  Школьный дневник — шаг 07. Предметы: белорусский язык и белорусская литература
--
--  Добавляет два предмета в школьный список (seed.sql делает то же самое при
--  первой установке). Дополнительно выдаёт эти предметы всем учителям, чтобы
--  они сразу могли ставить по ним отметки (RLS: нужен доступ в class_subjects).
--
--  КАК ЗАПУСКАТЬ: Supabase → SQL Editor → New query → вставить целиком → Run.
--  Файл идемпотентный: повторный запуск безопасен.
-- =============================================================================

insert into public.subjects (school_id, name, short_name, color)
select sc.id, v.name, v.short_name, v.color
  from (select id from public.schools order by created_at limit 1) sc
 cross join (values
   ('Белорусский язык',       'Бел. яз.',  '#dc2626'),
   ('Белорусская литература', 'Бел. л-ра', '#b91c1c')
 ) as v (name, short_name, color)
on conflict (school_id, name) do nothing;

-- Учителям — доступ к новым предметам во всех классах (как в promote_teacher.sql)
insert into public.class_subjects (class_id, subject_id, teacher_id)
select c.id, s.id, p.id
  from public.profiles p
 cross join public.classes c
 cross join public.subjects s
 where p.role = 'teacher'
   and s.name in ('Белорусский язык', 'Белорусская литература')
on conflict (class_id, subject_id) do update
  set teacher_id = excluded.teacher_id;

-- Проверка: список предметов и их количество
select count(*) as subjects_total from public.subjects;

select name, short_name from public.subjects order by name;