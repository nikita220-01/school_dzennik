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
