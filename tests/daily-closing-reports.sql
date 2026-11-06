begin;
do $$declare s uuid:=gen_random_uuid();o uuid:=gen_random_uuid();m uuid:=gen_random_uuid();begin
 insert into auth.users(id,email,email_confirmed_at) values(s,s||'@example.invalid',now()),(o,o||'@example.invalid',now()),(m,m||'@example.invalid',now());
 insert into jk_document_private.access_requests(user_id,email,display_name,status) values(s,s||'@example.invalid','SYNTHETIC REPORT STAFF','approved'),(o,o||'@example.invalid','SYNTHETIC OTHER STAFF','approved'),(m,m||'@example.invalid','SYNTHETIC REPORT MANAGER','approved');
 insert into jk_document_private.business_managers(user_id,email) values(m,m||'@example.invalid');
 perform set_config('test.report_staff',s::text,true);perform set_config('test.report_other',o::text,true);perform set_config('test.report_manager',m::text,true);
 perform set_config('request.jwt.claim.sub',s::text,true);perform set_config('request.jwt.claims',json_build_object('sub',s,'is_anonymous',false)::text,true);
end$$;
set local role authenticated;
do $$declare d date:=(now() at time zone 'Asia/Seoul')::date;b jsonb;r jsonb;begin
 b:=jsonb_build_object('visit',2,'phone',3,'online',1,'flyers',100,'reels_filmed',2,'reels_uploaded',1,'completed','SYNTHETIC completed','tomorrow','SYNTHETIC tomorrow','shared','SYNTHETIC shared','followups',jsonb_build_array(jsonb_build_object('customer','SYNTHETIC A','content','기기변경','pending','색상 안내','contact_at',to_char(d+1,'YYYY-MM-DD')||'T11:00')));
 perform set_config('test.report_body',b::text,true);
 r:=public.jk_daily_report_data(d);if not exists(select 1 from jsonb_array_elements(r->'roster') x where x->>'author_id'=current_setting('test.report_staff')) then raise exception 'FAIL approved roster';end if;
 r:=public.jk_save_daily_report(d,b,'draft',0);if r->>'report_status'<>'draft' or (r->>'version')::int<>1 then raise exception 'FAIL draft save';end if;
 if public.jk_save_daily_report(d,b,'draft',0)->>'version'<>'1' then raise exception 'FAIL idempotent retry';end if;
 r:=public.jk_save_daily_report(d,b,'submitted',1);if r->>'report_status'<>'submitted' or r->>'submitted_at' is null then raise exception 'FAIL submit';end if;
 begin perform public.jk_save_daily_report(d,b||'{"completed":"STALE"}', 'submitted',1);raise exception 'FAIL stale overwrite';exception when serialization_failure then null;end;
 begin perform public.jk_save_daily_report(d,b,'submitted',0,current_setting('test.report_other')::uuid);raise exception 'FAIL other author spoof';exception when insufficient_privilege then null;end;
 begin perform public.jk_save_daily_report(d,b||'{"visit":-1}','draft',2);raise exception 'FAIL negative count';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.jk_save_daily_report(d,b||'{"author_name":"SPOOF"}','draft',2);raise exception 'FAIL extra field';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.jk_save_daily_report(d,b||'{"completed":""}','submitted',2);raise exception 'FAIL empty submit';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.jk_save_daily_report(d+1,b,'draft',0);raise exception 'FAIL future report';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.jk_save_daily_report(d,b||'{"followups":[{"customer":"A","content":"","pending":"","contact_at":""}]}','submitted',2);raise exception 'FAIL incomplete followup';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform 1 from jk_document_private.daily_reports;raise exception 'FAIL direct table read';exception when insufficient_privilege then null;end;
 begin perform jk_document_private.daily_report_roster();raise exception 'FAIL direct roster read';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$begin perform set_config('request.jwt.claim.sub',current_setting('test.report_other'),true);perform set_config('request.jwt.claims',json_build_object('sub',current_setting('test.report_other'),'is_anonymous',false)::text,true);end$$;
set local role authenticated;
do $$declare r jsonb;d date:=(now() at time zone 'Asia/Seoul')::date;begin
 r:=public.jk_daily_report_data(d);if not exists(select 1 from jsonb_array_elements(r->'reports') x where x->>'author_id'=current_setting('test.report_staff') and x->>'report_status'='submitted') then raise exception 'FAIL shared team read';end if;
 perform public.jk_save_daily_report(d-1,current_setting('test.report_body')::jsonb,'submitted',0);
end$$;
reset role;
do $$begin perform set_config('request.jwt.claim.sub',current_setting('test.report_manager'),true);perform set_config('request.jwt.claims',json_build_object('sub',current_setting('test.report_manager'),'is_anonymous',false)::text,true);end$$;
set local role authenticated;
do $$declare r jsonb;d date:=(now() at time zone 'Asia/Seoul')::date;begin
 r:=public.jk_save_daily_report(d,current_setting('test.report_body')::jsonb||'{"shared":"MANAGER EDIT"}','submitted',2,current_setting('test.report_staff')::uuid);
 if r->>'author_id'<>current_setting('test.report_staff') or r->>'updated_by'<>current_setting('test.report_manager') or r->'body'->>'shared'<>'MANAGER EDIT' then raise exception 'FAIL manager edit identity';end if;
end$$;
reset role;
update jk_document_private.access_requests set status='revoked' where user_id=current_setting('test.report_manager')::uuid;
set local role authenticated;
do $$begin
 begin perform public.jk_daily_report_data(current_date);raise exception 'FAIL revoked read';exception when insufficient_privilege then null;end;
 begin perform public.jk_save_daily_report(current_date,current_setting('test.report_body')::jsonb,'draft',0);raise exception 'FAIL revoked write';exception when insufficient_privilege then null;end;
end$$;
reset role;
set local role anon;
do $$begin begin perform public.jk_daily_report_data(current_date);raise exception 'FAIL anonymous read';exception when insufficient_privilege then null;end;end$$;
reset role;
rollback;
select 'PASS: approved shared reads, own daily draft/submission, retries, optimistic conflict, manager edit, date history, strict validation, no raw table access, revoked/anonymous denial; synthetic fixtures rolled back' result;
