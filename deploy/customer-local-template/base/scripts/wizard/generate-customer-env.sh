#!/bin/bash
OVERLAY_ENV="overlay/env/customer-local.env"
mkdir -p "$(dirname "$OVERLAY_ENV")"

read -p "Enter customer email: " CUSTOMER_EMAIL
read -sp "Enter customer password: " CUSTOMER_PASSWORD
echo
PASSWORD_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'$CUSTOMER_PASSWORD', bcrypt.gensalt()).decode())")
JWT_SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
TENANT_CODE="${CUSTOMER_EMAIL%@*}"
cat > "$OVERLAY_ENV" <<EOL
LOCAL_CUSTOMER_EMAIL=$CUSTOMER_EMAIL
LOCAL_CUSTOMER_PASSWORD_HASH=$PASSWORD_HASH
LOCAL_CUSTOMER_TENANT_CODE=$TENANT_CODE
JWT_SECRET=$JWT_SECRET
POSTGRES_DB=customer_local_db
POSTGRES_USER=customer_local_user
POSTGRES_PASSWORD=customer_local_pass
EOL
echo "Overlay env creato in $OVERLAY_ENV"
