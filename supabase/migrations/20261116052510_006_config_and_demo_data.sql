-- ID formats exactly as the ERP builds them today. next_value = last number issued.
insert into public.id_counters (prefix, next_value, pad) values
  ('PT', 3, 4), ('CUS', 2, 3), ('SUP', 2, 3), ('ST', 4, 3), ('PO', 2, 4), ('POI', 3, 4),
  ('RM', 0, 4), ('BOM', 0, 3), ('STK', 0, 4), ('DWG', 0, 3), ('RTG', 0, 4), ('INV', 0, 4),
  ('TL', 0, 4), ('REJ', 0, 4), ('SHP', 1042, 4), ('EMP', 0, 3), ('LV', 0, 4);

-- Real configuration from build v35
insert into public.role_permissions (role, area, allowed)
select r.key, a.key, a.value::boolean
from jsonb_each('{"admin":{"poinbox":true,"proddash":true,"prodqueue":true,"qc":true,"rminv":true,"fgtools":true,"procurement":true,"inward":true,"productdata":true,"adminhub":true,"history":true,"failinsights":true},"ppc":{"poinbox":true,"proddash":true,"prodqueue":true,"qc":true,"rminv":true,"fgtools":true,"procurement":true,"inward":false,"productdata":true,"adminhub":false,"history":true,"failinsights":true},"prodmgr":{"poinbox":true,"proddash":true,"prodqueue":true,"qc":true,"rminv":false,"fgtools":true,"procurement":false,"inward":false,"productdata":true,"adminhub":false,"history":true,"failinsights":true},"staff":{"poinbox":false,"proddash":true,"prodqueue":true,"qc":false,"rminv":false,"fgtools":false,"procurement":false,"inward":false,"productdata":false,"adminhub":false,"history":false,"failinsights":false},"store":{"poinbox":false,"proddash":false,"prodqueue":false,"qc":false,"rminv":true,"fgtools":true,"procurement":true,"inward":true,"productdata":false,"adminhub":false,"history":false,"failinsights":false},"purchase":{"poinbox":false,"proddash":false,"prodqueue":false,"qc":false,"rminv":true,"fgtools":true,"procurement":true,"inward":true,"productdata":false,"adminhub":false,"history":false,"failinsights":false},"qi":{"poinbox":false,"proddash":false,"prodqueue":false,"qc":true,"rminv":false,"fgtools":false,"procurement":false,"inward":false,"productdata":false,"adminhub":false,"history":false,"failinsights":true},"dispatch":{"poinbox":false,"proddash":true,"prodqueue":false,"qc":false,"rminv":false,"fgtools":false,"procurement":false,"inward":false,"productdata":false,"adminhub":false,"history":true,"failinsights":false}}'::jsonb) r,
     jsonb_each_text(r.value) a;

insert into public.stages_master (id, name, category, can_qc_after, sort_order)
select s->>'id', s->>'name', s->>'category', (s->>'canQCAfter')::boolean, ord::int
from jsonb_array_elements('[{"id":"STG-001","name":"Raw material inward","category":"rm","canQCAfter":true},{"id":"STG-002","name":"Cutting","category":"machining","canQCAfter":true},{"id":"STG-003","name":"CNC machining","category":"machining","canQCAfter":true},{"id":"STG-004","name":"VMC machining","category":"machining","canQCAfter":true},{"id":"STG-005","name":"Laser cutting","category":"machining","canQCAfter":true},{"id":"STG-006","name":"Grinding","category":"machining","canQCAfter":true},{"id":"STG-007","name":"Bending","category":"machining","canQCAfter":true},{"id":"STG-008","name":"Heat treatment","category":"outsource","canQCAfter":true},{"id":"STG-009","name":"Plating / Coating","category":"outsource","canQCAfter":true},{"id":"STG-010","name":"Threading","category":"machining","canQCAfter":true},{"id":"STG-011","name":"Welding","category":"machining","canQCAfter":true},{"id":"STG-012","name":"Assembly","category":"machining","canQCAfter":true}]'::jsonb) with ordinality as t(s, ord);

insert into public.company_settings (id, name, short_name, tagline, address, brand_color)
values (1, 'Suru Industries', 'S', 'Precision Manufacturing', 'Malegaon MIDC, Sinnar, Nashik, Maharashtra - 422103', '#F5C518');

-- Demo data (replace with real data after go-live)
insert into public.staff (id, name, role, stages, active) values
  ('ST-001', 'Demo Staff 1', 'admin',   '{}', true),
  ('ST-002', 'Demo Staff 2', 'prodmgr', '{}', true),
  ('ST-003', 'Demo Staff 3', 'staff',   '{"Cutting","CNC machining"}', true),
  ('ST-004', 'Demo Staff 4', 'qi',      '{}', true);

insert into public.customers (id, name, contact, terms, active) values
  ('CUS-001', 'Demo Customer 1', 'Demo Contact 1', 'Net 30 days', true),
  ('CUS-002', 'Demo Customer 2', 'Demo Contact 2', 'Net 45 days', true);

insert into public.suppliers (id, code, name, contact, city, materials, terms, lead_days, active) values
  ('SUP-001', 'SUP-DEMO-001', 'Demo Supplier 1', 'Demo Contact 1', 'Nashik', 'EN8, SS316', 'Net 30 days', 7, true),
  ('SUP-002', 'SUP-DEMO-002', 'Demo Supplier 2', 'Demo Contact 2', 'Pune', 'SS316L, Duplex', 'Net 45 days', 10, true);

insert into public.products (id, part_no, name, material, type, uom, status) values
  ('PT-0001', 'DEMO-PRD-001', 'Demo Product 1', 'SS316', 'single', 'Nos', 'active'),
  ('PT-0002', 'DEMO-PRD-002', 'Demo Product 2', 'EN8',   'single', 'Nos', 'active'),
  ('PT-0003', 'DEMO-PRD-003', 'Demo Product 3', 'SS316', 'single', 'Nos', 'active');

insert into public.purchase_orders (id, po_no, customer_id, customer_name, po_date, due_date, source, status) values
  ('PO-0001', 'DEMO-PO-001', 'CUS-001', 'Demo Customer 1', date '2026-11-16', date '2026-12-15', 'manual', 'pending'),
  ('PO-0002', 'DEMO-PO-002', 'CUS-002', 'Demo Customer 2', date '2026-11-16', date '2026-12-31', 'manual', 'pending');

insert into public.po_items (id, po_id, line_no, item_code, material, description, qty, unit, delivery_date, status) values
  ('POI-0001', 'PO-0001', 1, 'DEMO-PRD-001', 'SS316', 'Demo Product 1', 10, 'PCS', date '2026-12-15', 'pending'),
  ('POI-0002', 'PO-0001', 2, 'DEMO-PRD-002', 'EN8',   'Demo Product 2', 5,  'PCS', date '2026-12-15', 'pending'),
  ('POI-0003', 'PO-0002', 1, 'DEMO-PRD-003', 'SS316', 'Demo Product 3', 20, 'PCS', date '2026-12-31', 'pending');
