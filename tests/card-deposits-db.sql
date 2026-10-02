-- Synthetic fixtures only; isolated local validation database. No production writes.
begin;
insert into auth.users(id) values('00000000-0000-4000-8000-000000000001');
insert into public.admin_users(user_id,name) values('00000000-0000-4000-8000-000000000001','검증 관리자');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
insert into public.jk_internal_items(item_key,category,title,source_month,direction,amount,due_date,note)
values('manual:company-card:test','manual','현대카드 단말기 대금 · 테스트 고객',date_trunc('month',current_date),'out',319000,current_date+30,E'JK_COMPANY_CARD_V1\n{"version":1,"customer_name":"테스트 고객","card_name":"현대카드","charged_on":"2026-10-02"}');
insert into public.jk_internal_items(item_key,category,title,source_month,direction,amount,due_date)
values('vendor:test','vendor','테스트 거래처 · 테스트 판매분',date_trunc('month',current_date)-interval '1 month','in',1000000,current_date);
do $$declare p uuid;q uuid;req uuid:=gen_random_uuid();d jsonb;n bigint;failed boolean:=false;begin
 select count(*) into n from public.jk_sales_ledger;
 p:=public.jk_internal_record_payment('manual:company-card:test',100000,current_date,req,'계좌',true,'이미 납부');
 q:=public.jk_internal_record_payment('manual:company-card:test',100000,current_date,req,'계좌',true,'이미 납부');
 if p<>q or (select count(*) from public.jk_internal_payments where item_key='manual:company-card:test')<>1 then raise exception 'duplicate card payment';end if;
 begin update public.jk_internal_items set amount=90000 where item_key='manual:company-card:test';exception when others then failed:=true;end;
 if not failed then raise exception 'paid amount guard missing';end if;
 perform public.jk_internal_record_payment('vendor:test',400000,current_date,gen_random_uuid(),'계좌',true,'과거 입금');
 d:=public.jk_internal_settlement_data(date_trunc('month',current_date)::date,current_date);
 if not exists(select 1 from jsonb_array_elements(d->'items') x where x->>'item_key'='manual:company-card:test' and left(x->>'note',length('JK_COMPANY_CARD_V1')+1)='JK_COMPANY_CARD_V1'||chr(10)) then raise exception 'card metadata round trip failed';end if;
 if (select count(*) from public.jk_sales_ledger)<>n then raise exception 'ledger unexpectedly changed';end if;
 if (select sum(amount) from public.jk_internal_payments where item_key='vendor:test' and not voided)<>400000 then raise exception 'deposit not recorded';end if;
 perform public.jk_internal_void_payment(p,'검증 취소');
 if exists(select 1 from public.jk_internal_payments where id=p and not voided) then raise exception 'void failed';end if;
end $$;
rollback;
