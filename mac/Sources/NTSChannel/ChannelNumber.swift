/// A channel that exists. Where a value has to name a channel and nothing else,
/// this is the type, so a 3 is turned away where it is parsed rather than
/// leaving a view with an empty grid and no reason why.
///
/// It prints as its number, so `"NTS \(number)"` reads the same as it did when
/// this was an `Int`.
public enum ChannelNumber: Int, CaseIterable, CustomStringConvertible, Sendable {
    case one = 1, two = 2

    public var description: String { String(rawValue) }
}
