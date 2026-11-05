-- The body splitter: quotes, doubled quotes, quoted identifiers and both
-- comment forms. Returns a row for each case that splits wrongly.
{%- set cases = [
  ("A; B", ["A", "B"]),
  ("A 'x;y'; B", ["A 'x;y'", "B"]),
  ("A 'it''s;'; B", ["A 'it''s;'", "B"]),
  ('A "a;b"; B', ['A "a;b"', "B"]),
  ("A -- c;d\n; B", ["A", "B"]),
  ("A /* c;d */ X; B", ["A  X", "B"]),
  ("-- only a comment;\n", []),
  ("A;;B;", ["A", "B"]),
] -%}
{%- set failures = [] -%}
{%- for text, expected in cases -%}
  {%- set got = exasol_semantic_views.split_statements(text) | map('trim') | list -%}
  {%- if got != expected -%}{%- do failures.append(loop.index) -%}{%- endif -%}
{%- endfor %}
SELECT case_number FROM (
  SELECT 0 AS case_number FROM DUAL
  {%- for n in failures %} UNION ALL SELECT {{ n }} FROM DUAL{% endfor %}
) WHERE case_number > 0
