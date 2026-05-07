select 'gb_customer_companies.runtime_connection_status' as check_name,
       exists (
         select 1 from information_schema.columns
         where table_schema='public'
           and table_name='gb_customer_companies'
           and column_name='runtime_connection_status'
       ) as ok
union all
select 'greenbrain_runtime_connections.installation_id',
       exists (
         select 1 from information_schema.columns
         where table_schema='public'
           and table_name='greenbrain_runtime_connections'
           and column_name='installation_id'
       )
union all
select 'gb_customer_runtime_installations',
       exists (
         select 1 from information_schema.tables
         where table_schema='public'
           and table_name='gb_customer_runtime_installations'
       )
union all
select 'gb_customer_runtime_provisioning_tokens',
       exists (
         select 1 from information_schema.tables
         where table_schema='public'
           and table_name='gb_customer_runtime_provisioning_tokens'
       );
