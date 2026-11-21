import CJavaScriptCore

/// A global object and the scripts that run against it.
public final class JSContext: @unchecked Sendable {
    public let virtualMachine: JSVirtualMachine
    let reference: JSGlobalContextRef

    public init(virtualMachine: JSVirtualMachine = JSVirtualMachine()) {
        self.virtualMachine = virtualMachine
        reference = JSGlobalContextCreateInGroup(virtualMachine.reference, nil)
    }

    deinit {
        JSGlobalContextRelease(reference)
    }

    /// The name a debugger shows for the context.
    public var name: String? {
        get { String(consuming: JSGlobalContextCopyName(reference)) }
        set {
            guard let newValue else { return JSGlobalContextSetName(reference, nil) }
            newValue.withJSString { JSGlobalContextSetName(reference, $0) }
        }
    }

    public var globalObject: JSValue {
        JSValue(context: self, reference: JSContextGetGlobalObject(reference))
    }

    /// Runs a script and returns its completion value.
    ///
    /// - Parameters:
    ///   - sourceURL: The name errors and stack traces give the script.
    ///   - line: The number of the script's first line in that source.
    /// - Throws: `JSError` for a syntax error or an uncaught exception.
    @discardableResult
    public func evaluateScript(_ script: String, sourceURL: String? = nil, line: Int = 1) throws -> JSValue {
        let result: JSValueRef? = try script.withJSString { script in
            guard let sourceURL else {
                return try check { JSEvaluateScript(reference, script, nil, nil, Int32(line), $0) }
            }
            return try sourceURL.withJSString { sourceURL in
                try check { JSEvaluateScript(reference, script, nil, sourceURL, Int32(line), $0) }
            }
        }
        guard let result else { return JSValue(undefinedIn: self) }
        return JSValue(context: self, reference: result)
    }

    /// Parses a script without running it.
    ///
    /// - Throws: `JSError` for a syntax error.
    public func checkSyntax(_ script: String, sourceURL: String? = nil, line: Int = 1) throws {
        try script.withJSString { script in
            guard let sourceURL else {
                _ = try check { JSCheckScriptSyntax(reference, script, nil, Int32(line), $0) }
                return
            }
            try sourceURL.withJSString { sourceURL in
                _ = try check { JSCheckScriptSyntax(reference, script, sourceURL, Int32(line), $0) }
            }
        }
    }

    /// A property of the global object, which is a global variable.
    public subscript(name: String) -> JSValue {
        get { globalObject[name] }
        set { globalObject[name] = newValue }
    }

    /// Collects what is unreachable now, where the engine would otherwise
    /// wait.
    public func collectGarbage() {
        JSGarbageCollect(reference)
    }
}
