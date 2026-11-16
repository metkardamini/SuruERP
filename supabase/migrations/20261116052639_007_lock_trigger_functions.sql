revoke all on function public.provision_staff_from_employee() from public, anon, authenticated;
revoke all on function public.set_row_meta() from public, anon, authenticated;
comment on table public.id_counters is 'Server-side ID counters. RLS on with no policies by design: reachable only through public.next_id().';
