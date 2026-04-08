---
name: security
description: Scan code for security vulnerabilities using pattern matching and logic review. Report only actionable issues with severity, exact locations, and fix direction.
---

# Security Scan

## Goal
Identify real security risks in changed code with precise locations and minimal noise. Two-pass approach: fast pattern scan, then logic review.

## Scope & attribution
- "Current change" = `git diff HEAD` (staged + unstaged). On a feature branch, also consider `git diff <base>...HEAD`.
- Scan changed files first. When a data flow chain (source → sink) crosses file boundaries, follow imports at least one level deep to trace the flow.
- Do not scan the entire project unless explicitly requested.
- Pre-existing issues outside the current change → report separately, do not fix.

## Pass 1 — Pattern scan

Grep changed files for known dangerous patterns. This is fast and catches the obvious cases.

**Secrets:**

| Pattern | What it catches |
|---|---|
| `(?i)(api[_-]?key\|secret\|token\|password\|credential\|auth\|bearer\|client[_-]?secret)\s*[:=]\s*["'][^"']{8,}` | Hardcoded secrets in assignments |
| `(?i)-----BEGIN (RSA\|EC\|DSA\|OPENSSH) PRIVATE KEY` | Private keys in source |
| `(?i)(aws_access_key_id\|aws_secret_access_key)\s*=` | AWS credentials |
| `ghp_[a-zA-Z0-9]{36}\|github_pat_` | GitHub tokens |
| `sk-[a-zA-Z0-9]{20,}` | OpenAI / Stripe secret keys |
| `(?i)basic\s+[A-Za-z0-9+/=]{20,}` | Hardcoded Basic auth headers |

**Injection sinks:**

| Language | Patterns to grep |
|---|---|
| SQL (any) | String concatenation or interpolation adjacent to `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `WHERE` — e.g. `f"SELECT.*{`, `` `SELECT.*${` ``, `"SELECT" + `, `format("SELECT` |
| Node/TS | `eval(`, `Function(`, `child_process.exec(`, `child_process.execSync(`, `vm.runInNewContext(` |
| Python | `eval(`, `exec(`, `os.system(`, `subprocess.*shell=True`, `__import__(` |
| Go | `exec.Command(` with variable args, `db.Query(` with `fmt.Sprintf` |
| PHP | `eval(`, `exec(`, `system(`, `passthru(`, `shell_exec(`, `preg_replace` with `e` modifier |
| Java | `Runtime.exec(`, `ProcessBuilder` with unsanitized input, `Statement.execute(` (vs `PreparedStatement`) |
| Ruby | `eval(`, `system(`, `` `...#{` `` (backtick interpolation), `send(` with user input |
| .NET | `Process.Start(`, `SqlCommand` with string concat |
| NoSQL (Mongo) | Query objects built from user input — e.g. `{ field: req.query.x }`, `$ne`, `$gt`, `$regex` operators from request data |

**SSRF — dynamic outbound URLs:**

| Language | Patterns to grep |
|---|---|
| Node/TS | `fetch(`, `axios(`, `axios.get(`, `got(`, `http.request(`, `https.request(` with non-literal URL |
| Python | `requests.get(`, `requests.post(`, `urllib.request.urlopen(`, `httpx.get(` with non-literal URL |
| Go | `http.Get(`, `http.Post(`, `http.NewRequest(` with non-literal URL |
| PHP | `curl_setopt(` with `CURLOPT_URL`, `file_get_contents(` with non-literal URL |
| Java | `HttpClient`, `URL(`, `HttpURLConnection` with non-literal URL |
| Ruby | `Net::HTTP`, `open-uri`, `HTTParty` with non-literal URL |

Only flag when the URL argument is a variable, concatenation, or interpolation — not a static string literal. In Pass 2, verify that dynamic URLs are validated against an allowlist and block internal targets: `localhost`, `127.0.0.1`, `::1`, `::ffff:127.0.0.1`, `0.0.0.0`, `169.254.169.254` (cloud metadata), and private IP ranges (`10.x`, `172.16-31.x`, `192.168.x`).

**Mass assignment:**

| Framework | Patterns to grep |
|---|---|
| Node/TS | `Model.create(req.body)`, `db.update(req.body)`, `Object.assign(model, req.body)`, spread into DB call `...req.body` |
| Python | `Model(**request.data)`, `serializer.save()` without explicit `fields`, `Model.objects.create(**request.POST)` |
| Ruby/Rails | `Model.new(params)`, `Model.create(params)`, `update(params)` without `permit` |
| PHP/Laravel | `Model::create($request->all())`, `->fill($request->all())` without `$fillable` |

**JWT misuse:**

| Pattern | What it catches |
|---|---|
| `jwt.decode(` without corresponding `jwt.verify(` | Token decoded but not verified |
| `algorithms: ["none"]` or `algorithm.*none` | Algorithm none attack |
| `jwt.decode(.*verify=False` | Python explicit skip verification |

**Dangerous DOM / output APIs:**

| Framework | Patterns |
|---|---|
| Browser JS | `innerHTML`, `outerHTML`, `document.write(`, `insertAdjacentHTML(` |
| React | `dangerouslySetInnerHTML`, JSX spread of user input (`{...userInput}` into DOM element) |
| Angular | `bypassSecurityTrust*` |
| Vue | `v-html` |
| Server HTML | Template rendering without auto-escaping (`\|safe`, `{% autoescape off %}`, `{!! !!}`) |

**Path traversal:**

| Pattern | What it catches |
|---|---|
| `path.join(` or `os.path.join(` with user-controlled segments without validation | Directory traversal |
| `fs.readFile\|open(` with request param in path | Arbitrary file read |
| `../` in string literals near file operations | Hardcoded traversal |

In Pass 2, verify path traversal defenses are complete: `path.join` alone is insufficient — check that the resolved path is validated against a base directory (e.g. `resolvedPath.startsWith(baseDir)`).

## Pass 2 — Logic review

Read each changed function, endpoint, or handler. Trace data flow manually.

**For each changed code path, answer:**

1. **Input sources** — Where does external data enter? (request params, headers, body, cookies, file uploads, URL path segments, environment variables set by users, database values that originated from user input)
2. **Sink reachability** — Does any input reach a dangerous sink (DB query, shell command, file system, HTTP response body, redirect URL, deserialization) without sanitization or parameterization? For NoSQL: can user-controlled objects or operators (`$ne`, `$gt`, `$regex`) reach query filters?
3. **Auth & access control:**
   - New or modified endpoints: is there an authorization check? Does it verify the acting user owns the resource (no IDOR)?
   - State-changing operations (POST/PUT/DELETE): is CSRF protection present where expected?
   - Does the endpoint expose data beyond what the caller needs?
   - JWT handling: are tokens verified (not just decoded)? Is the algorithm enforced? Are expiration (`exp`), issuer (`iss`), and audience (`aud`) checked where applicable?
   - Mass assignment: is request body mapped directly to a model without field allowlisting? Can user-controlled input modify sensitive fields (`role`, `isAdmin`, `permissions`, `balance`, `email_verified`)?
4. **Data exposure:**
   - Does the response include fields that should be excluded (passwords, tokens, internal IDs, stack traces)?
   - Are errors returned to the client with internal details?
   - Is sensitive data written to logs? Specifically: tokens, passwords, session IDs, PII (email, SSN, credit card numbers).
   - Are debug-level logs (`console.log`, `logging.debug`, `log.Debug`) guarded by environment or log-level checks, or could they leak sensitive data in production?
5. **External calls:**
   - SSRF: are outbound URLs validated against an allowlist? Are internal targets blocked (`localhost`, `127.0.0.1`, `169.254.169.254`, private IP ranges)?
   - Open redirect: are redirects constrained to same-origin or an allowlist? Watch for `res.redirect(req.query.url)`, `redirect(userInput)`, `Location` header set from user input.
   - Are webhooks verified (signature, shared secret)?
6. **Cryptography:**
   - Use of broken algorithms (MD5/SHA1 for security, ECB mode, DES)?
   - Hardcoded IVs or salts?
   - Custom crypto implementations instead of standard libraries?
7. **Deserialization:**
   - `pickle.loads`, `yaml.load` (without `SafeLoader`), Java `ObjectInputStream`, `unserialize()` (PHP) with untrusted data?
8. **Template injection:**
   - Is user input rendered directly in a server-side template engine (Jinja2, Twig, Thymeleaf, ERB, Pug) without escaping or sandboxing? E.g. `Template(userInput).render()`, `render_template_string(userInput)`.

## Severity criteria

| Severity | Criteria | Examples |
|---|---|---|
| **Critical** | User input reaches a dangerous sink with no sanitization; secrets in source code | Raw SQL concat with request param; hardcoded API key; `eval(req.body)` |
| **High** | Sanitization present but bypassable; missing auth on state-changing endpoints; missing rate limiting on auth endpoints (login, password reset, OTP) | Allow-list with regex bypass; no auth middleware on DELETE endpoint; SSRF with partial URL validation; brute-force login with no throttling |
| **Medium** | Defense-in-depth gaps; exploitable only with additional conditions | Missing CSP headers; overly broad CORS (`*`); verbose error messages in production config |
| **Low** | Hygiene issues; no direct exploitability | Weak hash for non-security purpose; unnecessary crypto imports; HTTP used in non-sensitive internal calls |

## Fix policy
- **Secrets**: never auto-fix. Report only. Removal from source is not enough — git history retains them. Note that key rotation and history rewrite are needed.
- **Injection / auth**: fix if the fix is a single-site change (swap string concat for parameterized query, add auth middleware call, add input validation). Report if the fix requires architectural change (e.g. redesigning an auth model).
- **Unclear security intent**: if the fix could change auth or access control behavior in ways that aren't obviously correct, report — do not auto-fix.
- **Code you changed** → fix.
- **Code you didn't change** → report, do not fix.
- **Never weaken existing security controls** (remove auth checks, disable CSRF, broaden CORS) to make code work.
- If unsure whether a finding is real or a false positive, report it with the uncertainty noted — do not suppress.

## Reporting

Format each finding as:

```
**[SEVERITY]** `file:line` — description
  Fix: fix direction
```

Group by severity, Critical first. Example:

```
**[Critical]** `src/api/users.ts:42` — SQL query built with string interpolation from `req.query.id`
  Fix: use parameterized query via `db.query("SELECT ... WHERE id = $1", [id])`

**[High]** `src/api/admin.ts:15` — DELETE /admin/users/:id has no authorization middleware
  Fix: add `requireRole('admin')` middleware before handler
```

If no issues found → output: `No security issues found in the current change.`

If pre-existing issues found outside the change:

```
**Pre-existing (not introduced by this change):**
**[High]** `src/legacy/auth.ts:88` — session token stored in localStorage
  Fix: migrate to httpOnly cookie (separate task)
```

## Constraints
- No full project audits unless explicitly requested
- No dependency installation
- No large rewrites
- Do not run external security tools — that is outside this skill's scope
- Do not suppress findings to reduce noise — report everything real, let the user triage
