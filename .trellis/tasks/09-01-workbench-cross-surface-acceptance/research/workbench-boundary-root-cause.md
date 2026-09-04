# Bug Analysis: Workbench Invalidation, Accessibility, And Command Boundaries

## Bayesian Assessment

### Priors

| Hypothesis | Prior | Reasoning |
| --- | ---: | --- |
| H1: Cross-layer ownership was underspecified | 35% | UI, projection, observation, and AppModel all participated in the reported symptoms. |
| H2: Change propagation missed sibling surfaces | 30% | Workbench has several data browsers and command-bearing control families with similar shapes. |
| H3: Tests covered values but not invalidation/runtime behavior | 25% | Equality tests can pass while SwiftUI or AppKit still performs expensive work. |
| H4: One isolated rendering defect caused the symptoms | 10% | The screenshots suggested layout defects, but not the CPU and stale-command findings. |

### Discriminating Evidence And Posterior

- Runtime samples showed AppKit materializing offscreen native Table cells after
  an accessibility query. This strongly supports H1/H3 over an isolated visual
  defect.
- `withObservationTracking` fired when an aggregate catalog property changed
  even though its nested revision value stayed equal. This supports H1/H3 and
  disproves the assumption that `.task(id:)` equality prevents body
  invalidation.
- A same-controller generation-A command scope was rejected only after scope
  became part of the retained handler/API boundary. This supports H1/H2; exact
  target resolution alone could not distinguish identical generation-B data.
- Fresh independent review found the Logs Picker and two local Proxy AX effects
  after the first scope pass. This is direct evidence for H2.
- Source verification, 412-test full regression, a fresh 167-test checker pass,
  and two deterministic 30-case Release reports reduce the probability of a
  remaining broad implementation defect, but cannot replace the pending runtime
  AX repeat.

Posterior assessment: H1 42%, H2 33%, H3 23%, H4 2%. Confidence is high (94%)
that the durable root is boundary ownership plus propagation/test gaps, rather
than one renderer or one controller backend.

## Bug Analysis: Workbench Boundary Drift

### 1. Root Cause Category

- **Category**: B - Cross-Layer Contract
- **Specific Cause**: Semantic change domains, bounded accessibility payloads,
  and retained command identity were not explicit at every boundary. Aggregate
  observable state, native AX traversal, and invocation-time session lookup
  therefore performed work or accepted intent outside the originating domain.
- **Contributing Category**: C - Change Propagation Failure. Initial repairs did
  not cover every Table/Proxy/Logs sibling or every local side effect.
- **Contributing Category**: D - Test Coverage Gap. Value equality and pure
  projection tests did not initially observe Swift Observation invalidation,
  owner replacement, or same-controller generation replacement.
- **Contributing Category**: E - Implicit Assumption. The implementation assumed
  native Table AX virtualization, nested revision equality, and current
  AppModel identity were sufficient boundaries.

### 2. Why Fixes Failed

1. **Surface layout fixes**: constraining individual summary rows treated the
   visible empty area, but the shared scaffold still offered flexible vertical
   space to supplementary chrome.
2. **Direct Table accessibility replacement**: bounding replacement rows did
   not prevent AppKit from first walking the hidden native `NSTableView` cell
   hierarchy. The semantic host had to be detached from the Table and driven by
   a pure bounded payload.
3. **Request equality only**: equal `.task(id:)` requests avoided task restart,
   but reading the aggregate catalog still invalidated the SwiftUI body. A
   standalone observable structure/metrics token was required.
4. **Current target resolution only**: exact rules/members prevented stale
   entity mutation, but identical data in generation B still matched an intent
   retained from A. The originating identity had to become a required command
   input.
5. **First scope inventory**: Configuration, Rules, and remote Proxy AX effects
   were fixed, but fresh review found the Logs Picker plus Proxy AX group
   toggle/Locate Current. The propagation inventory initially classified local
   workspace effects as harmless even though they could corrupt new-generation
   UI state.

### 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
| --- | --- | --- | --- |
| P0 | Architecture | Split rules/providers catalogs and publish connection structure/metrics through standalone scalar tokens. | DONE |
| P0 | Compile-time | Require `LiveCommandScope` on AppModel APIs reached by retained edit/entity handlers; provide no unscoped overload. | DONE |
| P0 | Architecture | Hide native Table AX and render one detached/equatable host from a pure maximum-32-row payload. | DONE |
| P0 | Test coverage | Track Observation invalidation, same-ID/new-generation commands, owner tokens, exact targets, and bounded AX traversal. | DONE |
| P1 | Code review | Source verifier inventories every data browser and all six effectful Proxy AX callbacks, plus Logs/Configuration/Rules scope capture. | DONE |
| P1 | Documentation | Update Workbench, live-session, and cross-layer contracts with signatures, matrices, examples, and anti-patterns. | DONE |
| P1 | Runtime | Repeat read-only populated Connections/Overview AX capture and verify CPU recovery without controller commands. | TODO - requires explicit runtime permission |

### 4. Systematic Expansion

- **Similar Issues**: Any new Binding, inspector action, confirmation, AX action,
  or delayed projection can repeat the same error if it reads current identity
  instead of retaining its source scope. Any nested revision in an observable
  aggregate can create hidden invalidation.
- **Design Improvement**: Make semantic domains explicit in types: per-domain
  catalogs/tokens, immutable request values, pure bounded AX payloads, command
  scopes, owner IDs, and exact-current-target resolvers.
- **Process Improvement**: Audit by complete sibling inventory, then require a
  fresh checker to look for omitted UI and local-state effects. Compare two
  Release reports by case/fixture/checksum before accepting hot-path changes.
- **Knowledge Gap**: Swift Observation tracks stored-property access rather than
  nested equality, and AppKit may traverse a native Table before honoring an
  attached accessibility replacement. Both facts must be considered in future
  performance reviews.

### 5. Knowledge Capture

- [x] Updated `.trellis/spec/frontend/workbench-ui-contract.md` with detached
      bounded AX and narrow Overview observation contracts.
- [x] Updated `.trellis/spec/frontend/live-session-controller-contract.md` with
      catalog/token publication, command ownership, and exact targeting; split
      the seven-section retained-handler rules into the indexed
      `.trellis/spec/frontend/live-command-scope-contract.md` so task context is
      not truncated at the 32 KiB injection limit.
- [x] Updated `.trellis/spec/guides/cross-layer-thinking-guide.md` with retained
      intent and standalone observation-token checks.
- [x] Kept the issue record in the active `09-01` task and its research files.
- [x] Checked template synchronization: this repository has no
      `src/templates/markdown/spec/` tree, so there is no template target to
      update; `.trellis/.template-hashes.json` is metadata, not a spec template.
- [ ] Obtain explicit permission, then complete the runtime AX acceptance repeat
      before archiving the task.
