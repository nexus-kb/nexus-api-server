# Nexus KB

A Linux kernel development knowledge base built with Swift, Vapor, Postgres,
and a SolidJS web interface.

## Backend

```bash
swift build
swift run
swift test
```

The Vapor application requires the existing Postgres environment variables.
It serves the production web interface from `Public/` at
`http://127.0.0.1:8080/`.

## Web interface

Install the frontend dependencies once:

```bash
cd WebUI
pnpm install
```

For frontend development, run Vapor in one terminal and Vite in another:

```bash
# Terminal 1, from the repository root
swift run

# Terminal 2
cd WebUI
pnpm dev
```

Vite proxies `/api` requests to Vapor at `http://127.0.0.1:8080`.

Generate the production assets served by Vapor:

```bash
cd WebUI
pnpm build
```

The build replaces `Public/index.html` and `Public/assets/`. These generated
files are committed so a checkout can serve the web interface without running
the frontend toolchain.

## Tests

```bash
swift test

cd WebUI
pnpm test
```

The frontend can also be type-checked independently with `pnpm check`.
