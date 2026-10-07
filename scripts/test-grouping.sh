#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/grouping-check
swiftc Sources/BlogAssistant/VisitGrouping.swift Tests/BlogAssistantTests/VisitGroupingTests.swift -o .build/grouping-check/tests
.build/grouping-check/tests
swiftc Sources/BlogAssistant/VisitNameStore.swift Tests/VisitNameStoreChecks.swift -o .build/grouping-check/name-tests
.build/grouping-check/name-tests
swiftc Sources/BlogAssistant/VisitGroupStore.swift Tests/VisitGroupStoreChecks.swift -o .build/grouping-check/group-tests
.build/grouping-check/group-tests
swiftc Sources/BlogAssistant/ReviewStore.swift Tests/ReviewStoreChecks.swift -o .build/grouping-check/review-tests
.build/grouping-check/review-tests
swiftc Sources/BlogAssistant/ReferenceStore.swift Tests/ReferenceStoreChecks.swift -o .build/grouping-check/reference-tests
.build/grouping-check/reference-tests
swiftc Sources/BlogAssistant/ReviewStore.swift Sources/BlogAssistant/ReferenceStore.swift Sources/BlogAssistant/DraftPhotos.swift Sources/BlogAssistant/DraftPrompt.swift Sources/BlogAssistant/DraftStore.swift Sources/BlogAssistant/NaverPostPacket.swift Tests/DraftChecks.swift -o .build/grouping-check/draft-tests
.build/grouping-check/draft-tests
swiftc Sources/BlogAssistant/ReviewStore.swift Sources/BlogAssistant/DraftPhotos.swift Sources/BlogAssistant/NaverPostPacket.swift Sources/BlogAssistant/BridgeConfiguration.swift Sources/BlogAssistant/BridgeHTTP.swift Sources/BlogAssistant/NaverBridge.swift Tests/BridgeChecks.swift -o .build/grouping-check/bridge-tests
.build/grouping-check/bridge-tests
