-- =============================================================================
--  12. ПОСЕЩАЕМОСТЬ: ПРИЧИНУ ОТСУТСТВИЯ МЕНЯЕТ ТОЛЬКО РОДИТЕЛЬ ИЛИ АДМИН
--
--  Вкладка «Посещаемость»: причины отсутствия заполняют родители, учитель и
--  администрация могут только просматривать их. При этом таблица attendance
--  общая — учитель ставит «Н» в журнале «Отметки» через ту же таблицу
--  (status='absent'), поэтому Row-Level Security (уровень строк) тут не поможет.
--
--  Ограничение делаем на уровне столбцов через BEFORE-триггер:
--    * админ (is_admin) и родитель ребёнка (owns_student) — без ограничений;
--    * учителю (и всем прочим ролям) можно ставить/менять status
--      (present / absent / late — например «Н»), но НЕЛЬЗЯ:
--        – заполнять или менять столбец reason,
--        – выставлять уважительный статус status = 'excused'.
--
--  service_role и seed (auth.uid() is null) триггер пропускает без проверок.
--  Идемпотентно: повторный запуск безопасен (create or replace / drop if exists).
-- =============================================================================

create or replace function public.guard_attendance_reason()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Серверная вставка (service_role / seed), админ и родитель ребёнка — без ограничений
  if auth.uid() is null
     or public.is_admin()
     or public.owns_student(new.student_id) then
    return new;
  end if;

  -- Учителю (и прочим) нельзя указывать причину и ставить «уважительный» статус
  if new.status = 'excused'
     or (tg_op = 'UPDATE' and new.reason is distinct from old.reason)
     or (tg_op = 'INSERT' and new.reason is not null) then
    raise exception 'Причину отсутствия может указать только родитель ребёнка или администрация'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function public.guard_attendance_reason() is
  'Посещаемость: причину (reason) и статус excused меняет только админ или родитель ребёнка; учитель ставит только absent/present/late';

drop trigger if exists attendance_guard_reason on public.attendance;
create trigger attendance_guard_reason
  before insert or update on public.attendance
  for each row execute function public.guard_attendance_reason();
