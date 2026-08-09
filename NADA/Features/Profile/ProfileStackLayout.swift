import Foundation

/// Shared Discover / Preview vertical order for photos + Bits.
///
/// Full stack (6 photos, 3 Bits):
/// name → photo → bit → essentials → photo → photo → bit → photo → bit → photo → photo
enum ProfileStackLayout {
    enum Slot: Equatable {
        case photo
        case bit
    }

    /// After the first photo + first Bit + essentials card.
    static let tailPattern: [Slot] = [
        .photo, .photo, .bit, .photo, .bit, .photo, .photo
    ]

    /// Builds the post-essentials sequence from remaining photos/Bits (already dropped index 0).
    static func tailBlocks<Photo, Bit>(
        photos: [Photo],
        bits: [Bit]
    ) -> [(photo: Photo?, bit: Bit?)] {
        var remainingPhotos = photos
        var remainingBits = bits
        var blocks: [(Photo?, Bit?)] = []

        for slot in tailPattern {
            switch slot {
            case .photo:
                if !remainingPhotos.isEmpty {
                    blocks.append((remainingPhotos.removeFirst(), nil))
                }
            case .bit:
                if !remainingBits.isEmpty {
                    blocks.append((nil, remainingBits.removeFirst()))
                }
            }
        }

        // Leftovers if counts diverge from the 6 + 3 ideal.
        while !remainingPhotos.isEmpty {
            blocks.append((remainingPhotos.removeFirst(), nil))
        }
        while !remainingBits.isEmpty {
            blocks.append((nil, remainingBits.removeFirst()))
        }

        return blocks
    }
}
