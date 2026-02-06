# CPR Position Decoding for Beast Provider

**Date:** 2025-02-06
**Status:** Approved

## Problem

The Beast provider receives raw ADS-B messages but doesn't decode aircraft positions. CPR (Compact Position Reporting) encoding requires either two messages (even + odd) or a reference position to decode latitude/longitude. Currently all Beast aircraft are filtered out because they have no position.

## Solution

Implement both global and local CPR decoding in `BeastProvider`.

### Data Structures

```swift
/// Stores a CPR position message for later decoding
struct CPRFrame {
    let isOdd: Bool           // F flag: false=even, true=odd
    let latCPR: Int           // 17-bit encoded latitude (0-131071)
    let lonCPR: Int           // 17-bit encoded longitude (0-131071)
    let altitude: Int?        // Altitude from same message
    let timestamp: Date       // When received (for 10-second validity check)
}

/// Per-aircraft CPR state for position decoding
struct CPRState {
    var evenFrame: CPRFrame?
    var oddFrame: CPRFrame?
    var lastDecodedPosition: Coordinate?
}
```

### Decoding Priority

1. **Global decode** - If both even and odd frames exist within 10 seconds
2. **Local decode** - Using `lastDecodedPosition` from previous global decode
3. **Local decode** - Using `referenceLocation` (receiver position) as fallback

### Algorithm

**Global decoding** uses both frame types to compute position without prior knowledge:
- Compute latitude index j from both frames
- Compute candidate latitudes for even/odd
- Verify zone consistency (NL values must match)
- Compute longitude using most recent frame

**Local decoding** uses a reference position to resolve ambiguity with single frame:
- Find nearest latitude zone to reference
- Compute latitude from CPR value
- Similar process for longitude

**NL (Number of Longitude zones)** is a precomputed lookup table with 59 latitude thresholds.

### Integration

Modify `BeastProvider.parseAirbornePosition()` to:
1. Extract F flag, latCPR, lonCPR from message
2. Store frame in per-aircraft CPRState
3. Attempt global decode if both frames available
4. Fall back to local decode with reference position
5. Update aircraft position on success

### Cleanup

- Remove CPR state when aircraft removed from cache
- Clear all CPR state on disconnect
- Expire frames older than 60 seconds

## Files Modified

- `Sources/Providers/BeastProvider.swift` - Add CPR decoding logic
- `Sources/Providers/ProviderManager.swift` - Pass reference location to Beast providers

## References

- [Mode-S.org CPR Guide](https://mode-s.org/1090mhz/content/ads-b/3-airborne-position.html)
- [ADS-B Position Decoding](http://www.lll.lu/~edward/edward/adsb/DecodingADSBposition.html)
- [NASA CPR Formal Analysis](https://shemesh.larc.nasa.gov/fm/CPR/)
