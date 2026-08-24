#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
input_directory="${1:-$repository_root/Tools/TransitSeedBuilder/Resources/Json}"
output_directory="${2:-$repository_root/TRoutes/TRoutes/Resources/TransitSeed}"
builder="$TMPDIR/troutes-transit-seed-builder"

sources=(
  "$repository_root/Tools/TransitSeedBuilder/main.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/TransitDataVersion.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/TransitSeedManifest.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/Form/TransitType.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/SwiftDataModels/TransitStation.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/SwiftDataModels/TransitPlatform.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/SwiftDataModels/TransitPattern.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/SwiftDataModels/TransitEdge.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/SwiftDataModels/TransitReferenceImportMetadata.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/SwiftDataModels/JSON/JsonBuilderStation.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/SwiftDataModels/JSON/JsonBuilderPlatform.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/SwiftDataModels/JSON/JsonBuilderPattern.swift"
  "$repository_root/TRoutes/TRoutes/DataModels/SwiftDataModels/JSON/JsonBuilderSequenceEdge.swift"
)

xcrun swiftc \
  -module-name TRoutes \
  -parse-as-library \
  -swift-version 6 \
  -O \
  "${sources[@]}" \
  -o "$builder"

"$builder" "$input_directory" "$output_directory"