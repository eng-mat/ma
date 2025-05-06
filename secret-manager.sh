create secretes.


echo -n "your-infoblox-username" | gcloud secrets create infoblox-username \
  --replication-policy=user-managed \
  --locations=us-central1 \
  --data-file=- \
  --kms-key=projects/my-project/locations/us-central1/keyRings/my-keyring/cryptoKeys/my-key


echo -n "your-infoblox-password" | gcloud secrets create infoblox-password \
  --replication-policy=user-managed \
  --locations=us-central1 \
  --data-file=- \
  --kms-key=projects/my-project/locations/us-central1/keyRings/my-keyring/cryptoKeys/my-key



  gcloud secrets create "username" \
    --replication="user-managed" \
    --locations="us-west2" \
    --data-file="username.txt" \
    --kms-key="projects/YOUR_PROJECT_ID/locations/us-west2/keyRings/YOUR_KEYRING/cryptoKeys/YOUR_KEY_NAME"

gcloud secrets create "password" \
    --replication="user-managed" \
    --locations="us-west2" \
    --data-file="password.txt" \
    --kms-key="projects/YOUR_PROJECT_ID/locations/us-west2/keyRings/YOUR_KEYRING/cryptoKeys/YOUR_KEY_NAME"
