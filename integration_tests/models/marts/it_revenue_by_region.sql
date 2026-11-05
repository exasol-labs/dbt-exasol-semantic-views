-- depends_on: {{ ref('esv_it_sales') }}
{{ exasol_semantic_views.query(
     model='esv_it_sales', object='ORDERS',
     metrics=['total_revenue', 'order_count'], dimensions=['customer_region']) }}
