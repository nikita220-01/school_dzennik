-- =============================================================================
--  11. ПОСЕЩАЕМОСТЬ: ПРИЧИНЫ ОТСУТСТВИЯ ОТ РОДИТЕЛЯ
--
--  Вкладка «Посещаемость»: родитель привязанного ребёнка (parent_students)
--  указывает причину его отсутствия. Раньше attendance могли менять только
--  учитель класса и админ — расширяем на родителей.
--  Идемпотентно: повторный запуск безопасен.
-- =============================================================================

drop policy if exists attendance_insert on public.attendance;
create policy attendance_insert on public.attendance
  for insert to authenticated
  with check (
    public.is_admin()
    or public.teaches_class(class_id)
    or exists (
      select 1 from public.parent_students ps
      where ps.parent_id = auth.uid()
        and ps.student_id = attendance.student_id
    )
  );

drop policy if exists attendance_update on public.attendance;
create policy attendance_update on public.attendance
  for update to authenticated
  using (
    public.is_admin()
    or public.teaches_class(class_id)
    or exists (
      select 1 from public.parent_students ps
      where ps.parent_id = auth.uid()
        and ps.student_id = attendance.student_id
    )
  )
  with check (
    public.is_admin()
    or public.teaches_class(class_id)
    or exists (
      select 1 from public.parent_students ps
      where ps.parent_id = auth.uid()
        and ps.student_id = attendance.student_id
    )
  );