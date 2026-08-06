import Foundation

/// Minimal read-only analog of `serde_json::Value` for the ways the Rust code
/// navigates gh / plugin JSON output: chained `.get(key)`, `.as_str()`,
/// `.as_bool()`, `.as_array()`. Backed by Foundation's JSONSerialization.
struct JSON {
    let raw: Any?

    init(_ raw: Any?) { self.raw = raw }

    /// Parse bytes as JSON (objects, arrays, or fragments). Returns nil on
    /// invalid input.
    static func parse(_ data: Data) -> JSON? {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return JSON(obj)
    }

    static func parse(_ string: String) -> JSON? {
        parse(Data(string.utf8))
    }

    /// Object member access; yields a JSON wrapping nil if absent or not an
    /// object. Analog of `serde_json::Value::get`.
    subscript(_ key: String) -> JSON {
        JSON((raw as? [String: Any])?[key])
    }

    var string: String? { raw as? String }

    /// Bool, being careful not to coerce JSON numbers. JSONSerialization maps
    /// booleans to NSNumber, so verify the underlying type is Bool.
    var bool: Bool? {
        guard let n = raw as? NSNumber else { return raw as? Bool }
        return CFGetTypeID(n) == CFBooleanGetTypeID() ? n.boolValue : nil
    }

    var array: [JSON]? { (raw as? [Any])?.map(JSON.init) }

    /// True when this node holds any value (present, possibly null-bearing).
    var exists: Bool { raw != nil }
}
