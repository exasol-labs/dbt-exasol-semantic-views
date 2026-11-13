-- depends_on: {{ ref('orders_by_region') }}
-- By region alone: coarser than the view, which is by region and status.
{{ exasol_semantic_views.query(
     model='esv_it_sales', object='ORDERS_BY_REGION',
     metrics=['total_revenue', 'order_count', 'customers'], dimensions=['customer_region']) }}
