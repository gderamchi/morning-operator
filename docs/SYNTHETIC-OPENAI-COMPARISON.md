# Explicit synthetic OCR comparison

`SyntheticOpenAIComparisonTests` is an optional diagnostic for the owner's explicit consent to compare only the invented OCR texts from the compact French test movie with OpenAI. It does not enable remote inference in the app.

The test accepts one frozen extraction report by its SHA-256, verifies its synthetic acquisition and movie fingerprint, and replays its existing OCR through ordinary evidence preparation, the existing OpenAI route and native proposal validation. It reads no movie, audio, personal data or expected routine. The expected oracle is never sent. Each outgoing prompt, schema, endpoint, model, instructions and request options must match the prepared request exactly. The existing model is `gpt-5-mini-2025-08-07`, with `store: false`, strict structured output and no redirects.

Both `MO_RUN_OPENAI_SYNTHETIC_COMPARISON=1` and `MO_OPENAI_SYNTHETIC_TEXT_CONSENT=1` are required. `MO_OPENAI_SYNTHETIC_INPUT` and `MO_OPENAI_SYNTHETIC_OUTPUT` must be absolute JSON paths inside this checkout's private `work/` directory. The output must not already exist. `MO_OPENAI_SYNTHETIC_KEY_FILE` must reference an owner-only regular file outside Git; credentials live in ephemeral memory only and are never included in logs or reports. Do not put a key in a shell argument or commit one.

The private report records the exact input and instruction hashes, actual HTTP attempt/return counts, status codes, elapsed time, sanitized failure category and validated proposal. It is explicitly an OCR replay, not a fresh extraction/classification, full movie-pipeline result, learned personal routine or MORE acceptance result. A proposed draft remains synthetic and unapproved, with no target, automation or Keep authority.

The always-local egress guard test verifies rejection of changed source text, instructions, storage options, unexpected data, schema, endpoint and method. The optional live test is disabled in normal package and CI runs.
