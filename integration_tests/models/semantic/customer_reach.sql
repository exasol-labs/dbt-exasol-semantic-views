-- A second view over the same table, written as most dbt models are: no
-- alias, bare columns, GROUP BY position. It shares customer_region with
-- orders_by_region.
select region as customer_region, avg(net_amount) as avg_order_value,
       max(net_amount) as largest_order
from {{ ref('it_orders_wide') }}
group by 1
