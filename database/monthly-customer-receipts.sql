-- Summaries, not a second cash receipt ledger. Amounts use sale/activation month.
create function public.jk_monthly_customer_receipts(p_month date) returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 if p_month is null then raise exception '판매월을 선택해 주세요.';end if;
 return (
 select jsonb_build_object(
  'cash',coalesce(sum(greatest(coalesce(cash_received,0)-coalesce(card_received_amount,0),0)) filter(where cash_receipt_method in ('현금','현금+카드')),0),
  'bank',coalesce(sum(greatest(coalesce(cash_received,0)-coalesce(card_received_amount,0),0)) filter(where cash_receipt_method in ('계좌','계좌+카드')),0),
  'unclassified',coalesce(sum(greatest(coalesce(cash_received,0)-coalesce(card_received_amount,0),0)) filter(where cash_receipt_method is null),0),
  'card_charged',coalesce(sum(card_received_amount),0),
  'vendor_signed',coalesce(sum(coalesce(base_rebate,0)-coalesce(cash_sale_amount,0)),0),
  'final_margin',coalesce(sum(final_margin),0),
  'count',count(*)
 ) from public.jk_sales_ledger
 where activation_date>=date_trunc('month',p_month) and activation_date<date_trunc('month',p_month)+interval '1 month'
 );
end $$;
revoke all on function public.jk_monthly_customer_receipts(date) from public,anon;
grant execute on function public.jk_monthly_customer_receipts(date) to authenticated;
notify pgrst,'reload schema';
