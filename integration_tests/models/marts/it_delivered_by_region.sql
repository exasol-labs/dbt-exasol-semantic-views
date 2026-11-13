-- depends_on: {{ ref('orders_by_region') }}
{{ exasol_semantic_views.compile_sql(
     "SELECT customer_region, delivered_revenue FROM SEMANTIC_ESV_IT_SALES.ORDERS_BY_REGION"
     ~ " GROUP BY customer_region") }}
