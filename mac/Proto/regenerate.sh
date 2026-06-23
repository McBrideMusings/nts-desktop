#!/usr/bin/env bash
# Regenerate the Firestore protobuf + gRPC Swift code from the vendored protos.
#
# Vendored protos under mac/Proto/google are the official googleapis Firestore v1
# tree (plus its transitive google/{api,rpc,type} imports). We only generate Swift
# for the messages/services we actually use; google/api/* are option-only imports
# (HTTP annotations) so they're parsed but not turned into Swift types. Well-known
# types (google/protobuf/*) come from the SwiftProtobuf runtime library.
#
# Requires: protoc, protoc-gen-swift (brew: swift-protobuf),
#           protoc-gen-grpc-swift (brew: protoc-gen-grpc-swift, binary is `-2`).
set -euo pipefail

cd "$(dirname "$0")/.."                     # -> mac/
OUT="Sources/NTSFirestore/Generated"
GRPC_PLUGIN="$(brew --prefix)/Cellar/protoc-gen-grpc-swift/2.4.0/bin/protoc-gen-grpc-swift-2"

MSGS=(
  google/firestore/v1/firestore.proto
  google/firestore/v1/common.proto
  google/firestore/v1/document.proto
  google/firestore/v1/query.proto
  google/firestore/v1/write.proto
  google/firestore/v1/aggregation_result.proto
  google/firestore/v1/bloom_filter.proto
  google/firestore/v1/explain_stats.proto
  google/firestore/v1/pipeline.proto
  google/firestore/v1/query_profile.proto
  google/rpc/status.proto
  google/type/latlng.proto
)

rm -f "$OUT"/*.swift

protoc -I Proto -I "$(brew --prefix)/include" \
  --plugin=protoc-gen-swift="$(brew --prefix)/bin/protoc-gen-swift" \
  --swift_out="$OUT" \
  --swift_opt=Visibility=Public,FileNaming=PathToUnderscores \
  "${MSGS[@]}"

protoc -I Proto -I "$(brew --prefix)/include" \
  --plugin=protoc-gen-grpc-swift="$GRPC_PLUGIN" \
  --grpc-swift_out="$OUT" \
  --grpc-swift_opt=Visibility=Public,Client=true,Server=false,FileNaming=PathToUnderscores \
  google/firestore/v1/firestore.proto

echo "Regenerated $(ls "$OUT"/*.swift | wc -l | tr -d ' ') files in $OUT"
