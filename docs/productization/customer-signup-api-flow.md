# Customer Signup API Flow

## Scopo
Permettere la creazione iniziale del record cliente dal portale / landing page.

## Endpoint
- GET /api/v1/customer-onboarding/health
- POST /api/v1/customer-onboarding/signup

## Cosa fa il signup
1. crea il record in gb_customer_companies
2. genera tenant_code se non passato
3. imposta onboarding_status=signup_started
4. salva portal_user_email
5. assegna una release iniziale di default

## Step successivi
- creazione utente auth reale
- raccolta dati billing / Stripe
- assegnazione release
- preparazione bundle
- installazione locale
