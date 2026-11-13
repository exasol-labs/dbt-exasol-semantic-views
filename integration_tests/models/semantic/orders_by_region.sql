-- Adopted as semantic view ORDERS_BY_REGION by the post-hook in dbt_project.yml.
select
    o.region                                                           as customer_region,
    o.order_status,
    sum(o.net_amount)                                                  as total_revenue,
    sum(case when o.order_status = 'delivered' then o.net_amount end)  as delivered_revenue,
    count(o.net_amount)                                                as order_count,
    count(distinct o.customer_key)                                     as customers
from {{ ref('it_orders_wide') }} o
group by o.region, o.order_status
