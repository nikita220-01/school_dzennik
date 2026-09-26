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
