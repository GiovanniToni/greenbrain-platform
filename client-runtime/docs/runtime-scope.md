# Runtime Scope

## Development / master platform
- repository: greenbrain-platform
- database: Supabase (current master/dev)
- purpose: development, analytics, fixes, evolution

## Client runtime
- repository subtree: client-runtime
- database: local PostgreSQL at customer site
- purpose: installable runtime for customer environments

## Separation principle
The dev/master platform and the customer runtime must remain logically separated,
even when they temporarily share parts of the same monorepo.
