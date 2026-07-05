# ADR-001: No Upgradeability for BovineTracking (v1)

**Status:** Accepted  
**Date:** 2026-07-05  
**Decision Makers:** ranch_ledger team  
**Context:** R-08 (EIP-7201), R-12 (Rural Credit Vault)

---

## Summary

BovineTracking v1 will **not** be upgradeable via UUPS proxy. The contract is deployed as a standalone, immutable implementation. Future bug fixes or feature additions require:
1. A new contract deployment (v2)
2. Data migration from v1 to v2
3. Deprecation of the old v1 address

## Motivation

The initial roadmap considered UUPS upgradeability for BovineTracking to enable:
- Quick bug fixes without full redeployment
- Seamless integration with future lending vault (R-12)
- Flexibility for regulatory changes (EUDR, SISBOV)

However, after analysis, we determined that **upgradeability introduces more risk than it solves** for this specific use case.

## Decision

### Why NOT UUPS?

1. **Regulatory Compliance:** Brazilian agribusiness requires immutable audit trails. An upgradeable contract creates uncertainty about which version processed a given transaction.

2. **Data Integrity:** The 100-agent demo proves the current implementation works correctly. Upgrading risks breaking the proven data model.

3. **Migration Complexity:** Migrating 100+ agents to a new contract requires coordinated action, potentially excluding ranchers without technical expertise.

4. **Security Surface:** UUPS proxies add complexity (storage layout, initialization, access control) that increases attack surface for a contract handling real cattle data.

5. **Cost vs Benefit:** The gas savings from upgradeability (~0.001 MATIC per tx) don't justify the operational overhead and security risks.

### What We're Doing Instead

1. **Immutable v1:** Deploy BovineTracking as a standalone, immutable contract
2. **Versioned Data Model:** Use EIP-7201 namespaced storage (R-08) to prepare for future migrations if needed
3. **Clear Migration Path:** Document migration procedures in `docs/MIGRATION_GUIDE.md`
4. **Monitoring & Alerts:** Set up on-chain monitoring to detect issues early

## Consequences

### Positive
- ✅ Simpler security model (no proxy, no initialization risks)
- ✅ Immutable audit trail for regulatory compliance
- ✅ No coordination overhead for upgrades
- ✅ Lower gas costs (no proxy indirection)
- ✅ Clearer ownership and responsibility

### Negative
- ❌ Bug fixes require full redeployment + migration
- ❌ Feature additions require new contract deployment
- ❌ Users must be informed of new contract addresses
- ❌ Legacy data remains on old contract address

## Migration Strategy (If Needed in Future)

If a critical bug or regulatory change requires migration:

1. **Deploy v2** with the fix/feature using EIP-7201 storage layout
2. **Announce migration window** (30 days minimum)
3. **Provide migration tooling** (`migrate.sh` script for bulk data transfer)
4. **Monitor adoption** and send reminders to inactive agents
5. **Deprecate v1** after 90 days with clear documentation

## Related Items

- R-08: EIP-7201 namespaced storage (implementation guide created, not applied to v1)
- R-12: Rural Credit Vault (will use its own upgradeable contract if needed)
- R-03: Polygon Amoy deployment (v1 deployed as immutable)

## Open Questions

1. **Should we revisit this decision for v2?** Only if a critical bug emerges that cannot be worked around in the current data model.

2. **What about the lending vault (R-12)?** The RanchLendingVault contract can use UUPS independently, as it's a separate concern with different upgrade requirements.

3. **How do we handle EUDR regulatory changes?** If EUDR mandates new fields or logic, we'll deploy v2 and provide migration tooling rather than upgrading v1.

## References

- [EIP-7201: Namespaced Storage Slots](https://eips.ethereum.org/EIPS/eip-7201)
- [OpenZeppelin UUPS Proxy Pattern](https://docs.openzeppelin.com/contracts/5.x/api/proxy#UUPSUpgradeable)
- [Brazilian SISBOV Regulations](https://www.gov.br/agricultura/assuntos/sisbov)

---

**Last Updated:** 2026-07-05  
**Review Date:** Quarterly or upon critical bug report
