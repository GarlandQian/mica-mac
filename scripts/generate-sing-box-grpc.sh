#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
proto_path="Sources/MicaCore/Protocols/SingBox/started_service.proto"
output_path="Sources/MicaCore/Protocols/SingBox/Generated"
scratch_path="tmp/codex/singbox-codegen"

cd "$repo_root"
mkdir -p "$output_path" "$scratch_path"

swift package \
  --scratch-path "$scratch_path" \
  --allow-writing-to-package-directory \
  generate-grpc-code-from-protos \
  --output-path "$output_path" \
  -- "$proto_path"
