# Showcase sanitization policy

## Public-safe by default

- Use domain names, not internal GUIDs or credentials.
- Round or describe scale semantically unless an exact number proves a capability.
- Use synthetic or masked examples for business records.
- Keep raw SQL, connection details, employee/customer identifiers, and private URLs out.
- Link to local canonical paths, not confidential cloud exports.

## Keep exact in protected evidence

- live object IDs;
- exact row counts and timestamps;
- audit/run identifiers;
- source-system identifiers;
- private screenshots and deployment records.

## Every status must say what it proves

`object`, `definition`, `runtime`, `data freshness`, `DQ`, `permission`, and
`visual/channel` verification are different claims. Passing one does not prove
the others.
