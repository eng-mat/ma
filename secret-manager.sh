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
