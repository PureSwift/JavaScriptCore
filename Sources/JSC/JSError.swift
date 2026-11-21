import CJavaScriptCore

/// A value JavaScript threw.
public struct JSError: Error, CustomStringConvertible {
    /// What was thrown: usually an `Error` object, but any value can be.
    public let value: JSValue

    public init(_ value: JSValue) {
        self.value = value
    }

    /// The error's `message`, or the value as text when it has none.
    public var message: String {
        let message = value.isObject ? value["message"] : value
        return message.isUndefined ? value.toString() : message.toString()
    }

    /// The error's `name`, such as `TypeError`.
    public var name: String? {
        guard value.isObject else { return nil }
        let name = value["name"]
        return name.isUndefined ? nil : name.toString()
    }

    /// The line the error was thrown from, where the engine recorded one.
    public var line: Int? {
        guard value.isObject else { return nil }
        let line = value["line"]
        return line.isNumber ? Int(line.toInt32()) : nil
    }

    /// The call stack at the throw, where the engine recorded one.
    public var stack: String? {
        guard value.isObject else { return nil }
        let stack = value["stack"]
        return stack.isString ? stack.toString() : nil
    }

    public var description: String { value.toString() }
}

extension JSContext {
    /// Runs one engine call, and throws what it reports as an exception.
    func check<Result>(_ body: (UnsafeMutablePointer<JSValueRef?>) -> Result) throws -> Result {
        var exception: JSValueRef?
        let result = body(&exception)
        if let exception { throw JSError(JSValue(context: self, reference: exception)) }
        return result
    }
}
