select order_key, customer_key, order_status, net_amount from {{ ref('it_orders') }}
