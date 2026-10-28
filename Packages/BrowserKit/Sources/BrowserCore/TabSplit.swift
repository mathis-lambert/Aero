import CoreGraphics
import Foundation

/// Up to four open tabs shown side by side in one entry of the sidebar (docs/SPLIT_VIEW.md). Each pane is a tab of its
/// own, with its page, history and title; the split only says where each shows.
public struct TabSplit: Identifiable, Equatable, Sendable {
    public static let maximumPanes = 4

    public let id: UUID
    public package(set) var spaceID: UUID
    public package(set) var root: SplitNode

    package init(id: UUID = UUID(), spaceID: UUID, root: SplitNode) {
        self.id = id
        self.spaceID = spaceID
        self.root = root
    }

    /// The panes' tabs, in reading order: leading to trailing, top to bottom.
    public var tabIDs: [UUID] { root.tabIDs }
}

/// Side by side, or one above the other.
public enum SplitAxis: String, Sendable {
    case horizontal, vertical
}

/// Where a pane goes beside another.
public enum SplitEdge: Sendable, CaseIterable {
    case leading, trailing, top, bottom

    var axis: SplitAxis { self == .leading || self == .trailing ? .horizontal : .vertical }
    /// The new pane comes first along the axis.
    var leads: Bool { self == .leading || self == .top }
}

/// A split's layout: a pane, or a stack of parts side by side or one above the other, each a share of the stack's
/// length. A stack holds two parts or more and never holds a stack along its own axis: three panes in a row are one
/// stack of three. A pane goes beside another by joining its stack, all parts then sharing it equally, or by making a
/// stack of the two across it; a pane that goes gives its share to the others.
public indirect enum SplitNode: Equatable, Sendable {
    case pane(UUID)
    case stack(SplitAxis, [SplitPart])

    /// No part is ever smaller than this share of its stack.
    public static let minimumShare = 0.15

    public var tabIDs: [UUID] {
        switch self {
        case .pane(let id): [id]
        case .stack(_, let parts): parts.flatMap(\.node.tabIDs)
        }
    }

    /// The layout with `tab` beside `target`; `nil` without `target`.
    public func inserting(_ tab: UUID, beside target: UUID, at edge: SplitEdge) -> SplitNode? {
        switch self {
        case .pane(let id):
            guard id == target else { return nil }
            let pair = edge.leads ? [SplitNode.pane(tab), self] : [self, .pane(tab)]
            return .stack(edge.axis, pair.map { SplitPart(node: $0, share: 0.5) })
        case .stack(let axis, var parts):
            guard let index = parts.firstIndex(where: { $0.node.tabIDs.contains(target) }) else { return nil }
            if axis == edge.axis, parts[index].node == .pane(target) {
                parts.insert(SplitPart(node: .pane(tab), share: 0), at: edge.leads ? index : index + 1)
                return .stack(axis, parts.map { SplitPart(node: $0.node, share: 1 / Double(parts.count)) })
            }
            guard let node = parts[index].node.inserting(tab, beside: target, at: edge) else { return nil }
            parts[index].node = node
            return .stack(axis, parts)
        }
    }

    /// The layout with `tab` along `edge` of the whole of it: the last part of a stack along that axis, all its parts
    /// then sharing it equally, or one half of a stack of the two.
    public func inserting(_ tab: UUID, at edge: SplitEdge) -> SplitNode {
        if case .stack(let axis, var parts) = self, axis == edge.axis {
            parts.insert(SplitPart(node: .pane(tab), share: 0), at: edge.leads ? 0 : parts.endIndex)
            return .stack(axis, parts.map { SplitPart(node: $0.node, share: 1 / Double(parts.count)) })
        }
        let pair = edge.leads ? [SplitNode.pane(tab), self] : [self, .pane(tab)]
        return .stack(edge.axis, pair.map { SplitPart(node: $0, share: 0.5) })
    }

    /// The layout without `tab`, the others taking its share; `nil` when nothing is left.
    public func removing(_ tab: UUID) -> SplitNode? {
        switch self {
        case .pane(let id): return id == tab ? nil : self
        case .stack(let axis, let parts):
            // A stack left along this one's axis gives its parts to it.
            let kept = parts.flatMap { part -> [SplitPart] in
                switch part.node.removing(tab) {
                case nil: []
                case .stack(axis, let inner)?: inner.map { SplitPart(node: $0.node, share: $0.share * part.share) }
                case let node?: [SplitPart(node: node, share: part.share)]
                }
            }
            guard kept.count > 1 else { return kept.first?.node }
            let total = kept.reduce(0) { $0 + $1.share }
            let shared = kept.map { SplitPart(node: $0.node, share: $0.share / total) }
            // Parts given by a stack along this one's axis may come in below the minimum: then all share it equally.
            guard shared.allSatisfy({ $0.share >= Self.minimumShare }) else { return SplitNode.stack(axis, shared).equalized }
            return .stack(axis, shared)
        }
    }

    /// The same layout over other tabs.
    func mapping(_ transform: (UUID) -> UUID) -> SplitNode {
        switch self {
        case .pane(let id): .pane(transform(id))
        case .stack(let axis, let parts): .stack(axis, parts.map { SplitPart(node: $0.node.mapping(transform), share: $0.share) })
        }
    }

    /// The layout with `divider` at `boundary`, the share of its stack before it, kept from squeezing either neighbor away.
    public func resizing(_ divider: SplitDivider.Place, to boundary: Double) -> SplitNode {
        guard case .stack(let axis, var parts) = self else { return self }
        if let step = divider.path.first {
            guard parts.indices.contains(step) else { return self }
            parts[step].node = parts[step].node.resizing(SplitDivider.Place(path: Array(divider.path.dropFirst()), index: divider.index), to: boundary)
            return .stack(axis, parts)
        }
        let index = divider.index
        guard boundary.isFinite, index >= 0, parts.indices.contains(index + 1) else { return self }
        let start = parts[..<index].reduce(0) { $0 + $1.share }
        let pair = parts[index].share + parts[index + 1].share
        let first = min(max(boundary - start, Self.minimumShare), pair - Self.minimumShare)
        parts[index].share = first
        parts[index + 1].share = pair - first
        return .stack(axis, parts)
    }

    /// Every part of every stack the same size.
    public var equalized: SplitNode {
        switch self {
        case .pane: self
        case .stack(let axis, let parts): .stack(axis, parts.map { SplitPart(node: $0.node.equalized, share: 1 / Double(parts.count)) })
        }
    }

    /// Each pane's frame in `rect`, with `gap` between neighbors.
    public func frames(in rect: CGRect, gap: CGFloat) -> [UUID: CGRect] {
        switch self {
        case .pane(let id): return [id: rect]
        case .stack(let axis, let parts):
            let rects = Self.lay(parts, along: axis, in: rect, gap: gap)
            return zip(parts, rects).reduce(into: [:]) { frames, part in frames.merge(part.0.node.frames(in: part.1, gap: gap)) { $1 } }
        }
    }

    /// The pane at `point` and its side nearest to it: where a pane dropped there goes.
    public func destination(at point: CGPoint, in rect: CGRect, gap: CGFloat) -> SplitDestination? {
        guard let (pane, frame) = frames(in: rect, gap: gap).first(where: { $0.value.contains(point) }), frame.width > 0, frame.height > 0
        else { return nil }
        let x = (point.x - frame.minX) / frame.width, y = (point.y - frame.minY) / frame.height
        let distances: [(SplitEdge, CGFloat)] = [(.leading, x), (.trailing, 1 - x), (.top, y), (.bottom, 1 - y)]
        return distances.min { $0.1 < $1.1 }.map { SplitDestination(pane: pane, edge: $0.0) }
    }

    /// Each divider, with the stack it divides and the gap it stands in.
    public func dividers(in rect: CGRect, gap: CGFloat, at path: [Int] = []) -> [SplitDivider] {
        guard case .stack(let axis, let parts) = self else { return [] }
        let rects = Self.lay(parts, along: axis, in: rect, gap: gap)
        let own = rects.indices.dropLast().map { index in
            let line = axis == .horizontal
                ? CGRect(x: rects[index].maxX, y: rect.minY, width: gap, height: rect.height)
                : CGRect(x: rect.minX, y: rects[index].maxY, width: rect.width, height: gap)
            return SplitDivider(place: SplitDivider.Place(path: path, index: index), axis: axis, area: rect, parts: parts.count, line: line)
        }
        return own + parts.indices.flatMap { parts[$0].node.dividers(in: rects[$0], gap: gap, at: path + [$0]) }
    }

    /// The parts' rectangles along `axis`, `gap` apart, filling `rect` to the point.
    private static func lay(_ parts: [SplitPart], along axis: SplitAxis, in rect: CGRect, gap: CGFloat) -> [CGRect] {
        let length = axis == .horizontal ? rect.width : rect.height
        let available = max(0, length - gap * CGFloat(parts.count - 1))
        var boundaries: [CGFloat] = [0], total = 0.0
        for part in parts.dropLast() {
            total += part.share
            boundaries.append((available * total).rounded())
        }
        boundaries.append(available)
        return parts.indices.map { index in
            let start = boundaries[index] + gap * CGFloat(index), size = boundaries[index + 1] - boundaries[index]
            return axis == .horizontal
                ? CGRect(x: rect.minX + start, y: rect.minY, width: size, height: rect.height)
                : CGRect(x: rect.minX, y: rect.minY + start, width: rect.width, height: size)
        }
    }

    /// Shares in bounds, stacks of two parts or more never along their parent's axis, and no tab twice.
    var isValid: Bool {
        let ids = tabIDs
        return Set(ids).count == ids.count && isWellFormed
    }

    private var isWellFormed: Bool {
        guard case .stack(let axis, let parts) = self else { return true }
        let total = parts.reduce(0) { $0 + $1.share }
        return parts.count >= 2 && abs(total - 1) < 0.000_001 && parts.allSatisfy { part in
            if case .stack(axis, _) = part.node { return false }
            return part.share.isFinite && part.share >= Self.minimumShare - 0.000_001 && part.node.isWellFormed
        }
    }
}

/// A side of a pane, where another goes.
public struct SplitDestination: Equatable, Sendable {
    public let pane: UUID
    public let edge: SplitEdge
}

/// A part of a stack: a pane or a stack across it, and its share of the stack's length.
public struct SplitPart: Equatable, Sendable {
    public var node: SplitNode
    public var share: Double

    public init(node: SplitNode, share: Double) {
        self.node = node
        self.share = share
    }
}

/// The gap between two parts of a stack.
public struct SplitDivider: Hashable, Sendable {
    /// The stack, by the parts taken from the root to reach it, and the part the divider follows.
    public struct Place: Hashable, Sendable {
        public let path: [Int]
        public let index: Int

        public init(path: [Int], index: Int) {
            self.path = path
            self.index = index
        }
    }

    public let place: Place
    public let axis: SplitAxis
    /// The stack's rectangle, which its boundaries are shares of, and how many parts it has.
    public let area: CGRect
    public let parts: Int
    /// The gap it stands in.
    public let line: CGRect

    /// The share of the stack before the divider when it stands at `point`, along its axis.
    public func boundary(at point: CGPoint, gap: CGFloat) -> Double {
        let length = (axis == .horizontal ? area.width : area.height) - gap * CGFloat(parts - 1)
        guard length > 0 else { return 0.5 }
        let offset = (axis == .horizontal ? point.x - area.minX : point.y - area.minY) - gap * CGFloat(place.index) - gap / 2
        return Double(offset / length)
    }
}

extension SplitNode: Codable {
    private enum Keys: String, CodingKey { case tab, axis, parts }
    private enum PartKeys: String, CodingKey { case node, share }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        if let tab = try container.decodeIfPresent(UUID.self, forKey: .tab) {
            self = .pane(tab)
            return
        }
        guard let axis = SplitAxis(rawValue: try container.decode(String.self, forKey: .axis)) else {
            throw DecodingError.dataCorruptedError(forKey: .axis, in: container, debugDescription: "Unknown split axis")
        }
        var list = try container.nestedUnkeyedContainer(forKey: .parts)
        var parts: [SplitPart] = []
        while !list.isAtEnd {
            let part = try list.nestedContainer(keyedBy: PartKeys.self)
            parts.append(SplitPart(node: try part.decode(SplitNode.self, forKey: .node), share: try part.decode(Double.self, forKey: .share)))
        }
        self = .stack(axis, parts)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .pane(let id): try container.encode(id, forKey: .tab)
        case .stack(let axis, let parts):
            try container.encode(axis.rawValue, forKey: .axis)
            var list = container.nestedUnkeyedContainer(forKey: .parts)
            for part in parts {
                var entry = list.nestedContainer(keyedBy: PartKeys.self)
                try entry.encode(part.node, forKey: .node)
                try entry.encode(part.share, forKey: .share)
            }
        }
    }
}
