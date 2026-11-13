-- depends_on: {{ ref('customer_reach') }}
-- No dimension: the grand total, which the view has no row for.
{{ exasol_semantic_views.query(
     model='esv_it_sales', object='CUSTOMER_REACH',
     metrics=['avg_order_value', 'largest_order']) }}
