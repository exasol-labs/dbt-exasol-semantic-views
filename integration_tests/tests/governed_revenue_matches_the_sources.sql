-- The governed answers equal the same numbers computed by hand from the seeds.
WITH expected AS (
  SELECT c.region,
         SUM(o.net_amount) AS total_revenue,
         COUNT(o.net_amount) AS order_count,
         SUM(CASE WHEN o.order_status = 'delivered' THEN o.net_amount END) AS delivered_revenue
  FROM {{ ref('it_orders') }} o
  JOIN {{ ref('it_customers') }} c ON c.customer_key = o.customer_key
  GROUP BY c.region
)
SELECT e.region
FROM expected e
LEFT JOIN {{ ref('it_revenue_by_region') }} r ON r.customer_region = e.region
LEFT JOIN {{ ref('it_delivered_by_region') }} d ON d.customer_region = e.region
WHERE r.total_revenue IS NULL OR r.total_revenue <> e.total_revenue
   OR r.order_count <> e.order_count
   OR d.delivered_revenue IS NULL OR d.delivered_revenue <> e.delivered_revenue
