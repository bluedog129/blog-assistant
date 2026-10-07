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
