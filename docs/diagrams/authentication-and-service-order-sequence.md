# Sequence diagrams: authentication + service order

Required by the Tech Challenge brief as a distinct artifact from the
component diagrams already in each repo's README (`## Architecture`) —
those show *topology*, these show *the order things happen in*.

Two flows, and they're deliberately connected: the second diagram reuses
the token issued by the first, at the `accept`/`reject` step, to show
where the CPF-based login actually gets consumed downstream rather than
treating it as an isolated feature.

## 1. Customer authentication via CPF

The only flow that touches the API Gateway and the `lambda-auth` function.

```mermaid
sequenceDiagram
    autonumber
    actor Customer
    participant GW as API Gateway<br/>(this repo, terraform/gateway)
    participant L as Lambda: customer-login<br/>(auto-repair-shop-lambda-auth)
    participant SM as Secrets Manager
    participant DB as RDS PostgreSQL<br/>(auto-repair-shop-infra-db)

    Customer->>GW: POST /auth/customer-login<br/>{ "cpf": "..." }
    GW->>L: AWS_PROXY invoke

    opt cold start only
        L->>SM: GetSecretValue(APP_SECRET_ID)
        SM-->>L: { jwt_secret, postgres_password }
    end

    L->>DB: SELECT user_id FROM customer WHERE cpf = $1

    alt CPF not found
        DB-->>L: no rows
        L-->>GW: 404 { "errors": ["customer not found"] }
        GW-->>Customer: 404
    else CPF found
        DB-->>L: user_id
        L->>DB: SELECT role.name<br/>FROM user_role JOIN role<br/>WHERE user_role.user_id = $1
        DB-->>L: roles[]
        L->>L: sign JWT (HS256)<br/>claims: user_id, roles, exp
        L-->>GW: 200 { token, expires_in }
        GW-->>Customer: 200 { token, expires_in }
    end
```

## 2. Opening a service order, through to customer approval

Service orders are opened by staff, not customers — `POST /service-order`
requires an **attendant** role, so this flow starts with the app's own
email/password login, not the CPF one. The CPF-issued token from diagram 1
re-enters the picture at step 9, when the customer acts on the order.

```mermaid
sequenceDiagram
    autonumber
    actor Attendant
    actor Customer
    participant GW as API Gateway
    participant App as auto-repair-shop<br/>(EKS)
    participant DB as RDS PostgreSQL

    Attendant->>App: POST /v1/auth/login<br/>{ email, password }
    App->>DB: verify user + password hash
    DB-->>App: user_id, roles [ATTENDANT]
    App-->>Attendant: 200 { token }

    Attendant->>App: POST /v1/service-order<br/>Authorization: Bearer <attendant token><br/>{ client, vehicle }
    App->>DB: INSERT service_order (status = RECEIVED)
    DB-->>App: id
    App-->>Attendant: 201 { id, status: RECEIVED }

    Note over Attendant,App: mechanic diagnoses, adds works/supplies,<br/>then sends it for customer approval
    Attendant->>App: PUT /service-order/{id}/send
    App->>DB: UPDATE status = AWAITING_APPROVAL
    App-->>Attendant: 204

    Note over Customer,GW: Customer authenticates via CPF —<br/>see diagram 1. Reuses that token below.
    Customer->>GW: PUT /service-order/{id}/accept<br/>Authorization: Bearer <CPF-issued token>
    GW->>App: HTTP_PROXY forward (path/method/headers unchanged)
    App->>App: middleware verifies JWT (HS256, same secret<br/>as the lambda) — role must be CUSTOMER
    App->>DB: UPDATE service_order<br/>SET status = IN_PROGRESS<br/>WHERE id = $1 AND customer.user_id = $token.user_id
    DB-->>App: ok
    App-->>GW: 204
    GW-->>Customer: 204
```

## Notes

- The app's auth middleware makes **no extra DB call** to validate a
  token — it trusts the JWT payload entirely, whether that token came
  from the Lambda or from the app's own `/v1/auth/login`. Same secret,
  same claim shape, so both are interchangeable from the middleware's
  point of view (see [auto-repair-shop-lambda-auth's
  README](https://github.com/POS-FIAP-15SOAT-TEAM-DARK-MODE/auto-repair-shop-lambda-auth#request--response)
  for the byte-compatibility note).
- `accept`/`reject` scope by `customer.user_id` — this is the reason the
  lambda still does a minimal DB lookup instead of skipping the database
  entirely (see
  [auto-repair-shop-lambda-auth's ADR 0002](https://github.com/POS-FIAP-15SOAT-TEAM-DARK-MODE/auto-repair-shop-lambda-auth/blob/develop/docs/adr/0002-token-issuance-only-scope.md)).
