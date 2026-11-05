-- depends_on: {{ ref('esv_it_sales') }}
{{ exasol_semantic_views.compile_sql(
     "SELECT customer_region, delivered_revenue FROM ESV_IT_SALES.ORDERS GROUP BY customer_region") }}
