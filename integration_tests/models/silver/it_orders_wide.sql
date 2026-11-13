-- The wide mart the semantic views read: joining is dbt's job, so each
-- semantic view is one table.
select o.order_key, o.customer_key, c.region, o.order_status, o.net_amount
from {{ ref('it_orders_silver') }} o
join {{ ref('it_customers_silver') }} c on c.customer_key = o.customer_key
