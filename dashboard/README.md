# PolyMint ledger dashboard

A web dashboard over the public `plastic_transactions` ledger, for DWCC operators and auditors:

- what was recovered: summary, per-day or per-week chart, and mix by material;
- which batches **need review**, each with its reason (low AI confidence, or the collector overrode the AI);
- the **scale proof** behind every credit (PoPP timeline, readings hashed, hash chain);
- filters (period, material, verification, search), sorting, and CSV export.

It reads Firestore directly and is read-only; the ledger rules forbid client writes. Data updates live.

## Run locally

```bash
cd dashboard && python3 -m http.server 8765
# open http://localhost:8765            live ledger
# open http://localhost:8765/#preview   sample records in the current schema
```

`#preview` loads `preview-records.json` instead of Firestore, so the review and scale-proof views
can be checked before real batches exist.

## Deploy

`firebase.json` serves this folder with Firebase Hosting:

```bash
firebase deploy --only hosting
```

## Data notes

- Records from older app versions don't store how the material was verified ("Not recorded"), and
  they have no scale proof.
- Records with a `demo_seed` field were seeded for a demo and are **hidden by default**. Tick
  "Include demo records" to see them. The app can't delete them because the ledger is
  append-only, so remove them in the Firebase console if they should go.
