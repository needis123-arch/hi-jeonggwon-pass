-- Synthetic amounts only; every write is rolled back.
begin;
do $$begin perform set_config('request.jwt.claims',jsonb_build_object('sub',(select user_id from public.admin_users limit 1),'role','authenticated')::text,true);end$$;
set local role authenticated;
do $$
declare k text:='test:'||gen_random_uuid(); req uuid:=gen_random_uuid(); p uuid; t uuid; data jsonb; r jsonb; today date:=(now() at time zone 'Asia/Seoul')::date; month date:=date_trunc('month',today)::date; ik text; lk text; vendor text:='TEST'||gen_random_uuid();
begin
 insert into public.jk_internal_items(item_key,category,title,source_month,direction,amount,due_date) values(k,'payroll','SYNTHETIC payroll',month,'out',1000000,today);
 p:=public.jk_internal_record_payroll(k,400000,12000,1200,today,req,'계좌',true,'SYNTHETIC');
 if public.jk_internal_record_payroll(k,400000,12000,1200,today,req)<>p then raise exception 'FAILED payroll idempotency';end if;
 if (select amount from public.jk_internal_payments where id=p)<>386800 or (select gross_amount from public.jk_internal_payments where id=p)<>400000 then raise exception 'FAILED gross/net payroll';end if;
 begin perform public.jk_internal_record_payroll(k,600001,18000,1800,today,gen_random_uuid());raise exception 'FAILED payroll overpay';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 begin update public.jk_internal_items set amount=399999 where item_key=k;raise exception 'FAILED gross lower than paid';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 begin perform public.jk_internal_record_payment(k,1,today,gen_random_uuid());raise exception 'FAILED legacy payroll path';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 data:=public.jk_internal_settlement_data(month,today);
 ik:='withholding:'||p::text||':income';lk:='withholding:'||p::text||':local';
 select value into r from jsonb_array_elements(data->'items') where value->>'item_key'=ik;
 if (r->>'amount')::bigint<>12000 or (r->>'due_date')::date<>(month+interval '1 month 9 days')::date or not(r->'basis'->>'withholding')::boolean then raise exception 'FAILED withholding generation';end if;
 insert into public.jk_internal_items(item_key,category,title,source_month,direction,amount,due_date,origin_payment_id) values(ik,'tax','SYNTHETIC income tax',month,'out',12000,today,p);
 begin update public.jk_internal_items set amount=12001 where item_key=ik;raise exception 'FAILED withholding mutation';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 begin update public.jk_internal_items set excluded=true where item_key=ik;raise exception 'FAILED active withholding exclusion';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 t:=public.jk_internal_record_payment(ik,12000,today,gen_random_uuid());
 begin perform public.jk_internal_void_payment(p,'SYNTHETIC');raise exception 'FAILED payroll reversal after tax paid';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 perform public.jk_internal_void_payment(t,'SYNTHETIC');perform public.jk_internal_void_payment(p,'SYNTHETIC');perform public.jk_internal_void_payment(p,'SYNTHETIC retry');
 if not(select excluded from public.jk_internal_items where item_key=ik) then raise exception 'FAILED void tax obligation';end if;
 data:=public.jk_internal_settlement_data(month,today);
 if exists(select 1 from jsonb_array_elements(data->'items') a where a->>'item_key'=lk) then raise exception 'FAILED void generated tax persists';end if;
 update public.jk_internal_items set payroll_tax_mode='none' where item_key=k;
 begin perform public.jk_internal_record_payroll(k,1000000,30000,3000,today,gen_random_uuid());raise exception 'FAILED none mode deductions';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 perform public.jk_internal_record_payroll(k,1000000,0,0,today,gen_random_uuid());
 insert into public.jk_internal_tax_invoices(invoice_date,kind,vendor,supply_amount,vat_amount,creditable,source_item_key,settlement_sales_month,invoice_number,evidence_type) values(today,'purchase',vendor,1000,100,true,k,month,'SYNTHETIC-001','tax_invoice');
 begin insert into public.jk_internal_tax_invoices(invoice_date,kind,vendor,supply_amount,vat_amount,invoice_number) values(today,'purchase',vendor,1000,100,'SYNTHETIC-001');raise exception 'FAILED duplicate invoice';exception when unique_violation then null;end;
 begin insert into public.jk_internal_tax_invoices(invoice_date,kind,vendor,supply_amount,vat_amount,creditable,evidence_type) values(today,'purchase',vendor,1000,100,true,'receipt');raise exception 'FAILED receipt credit eligibility';exception when check_violation then null;end;
 insert into public.jk_internal_vendor_checks(vendor_item_key,source_month,file_name,sheet_name,sign,statement_signed,ledger_signed,result) values(k,month,'SYNTHETIC.xlsx','정산',-1,1000,900,'{"rows":[],"summary":{"difference":100}}');
 data:=public.jk_internal_settlement_data(month,today);
 if not exists(select 1 from jsonb_array_elements(data->'vendor_checks') c where c->>'vendor_item_key'=k) then raise exception 'FAILED check persistence';end if;
end $$;
reset role;
do $$begin
 if has_function_privilege('anon','public.jk_internal_record_payroll(text,bigint,bigint,bigint,date,uuid,text,boolean,text)','execute') then raise exception 'FAILED anon payroll execute';end if;
 if has_table_privilege('anon','public.jk_internal_vendor_checks','select') or has_table_privilege('anon','public.jk_internal_payroll_reports','select') then raise exception 'FAILED anon finance tables';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000009","role":"authenticated"}',true);
do $$begin
 if exists(select 1 from public.jk_internal_vendor_checks) or exists(select 1 from public.jk_internal_payroll_reports) then raise exception 'FAILED nonadmin isolation';end if;
 begin perform public.jk_internal_record_payroll('none',100,3,0,current_date,gen_random_uuid());raise exception 'FAILED nonadmin RPC';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
end $$;
reset role;
rollback;
select 'PASS: gross/net/partial/idempotent payroll, withholding liability/due/reversal, old API guard, invoice uniqueness/eligibility, Excel report storage, admin-only isolation; all fixtures rolled back' result;
