import CJavaScriptCore

extension String {
    /// Copies an engine string, which is UTF-16.
    init(_ string: JSStringRef) {
        let characters = UnsafeBufferPointer(start: JSStringGetCharactersPtr(string), count: JSStringGetLength(string))
        self = String(decoding: characters, as: UTF16.self)
    }

    /// Takes ownership of an engine string, where there is one.
    init?(consuming string: JSStringRef?) {
        guard let string else { return nil }
        defer { JSStringRelease(string) }
        self.init(string)
    }

    /// Lends the string to the engine for one call.
    func withJSString<Result>(_ body: (JSStringRef) throws -> Result) rethrows -> Result {
        let characters = Array(utf16)
        let string: JSStringRef = JSStringCreateWithCharacters(characters, characters.count)
        defer { JSStringRelease(string) }
        return try body(string)
    }
}
